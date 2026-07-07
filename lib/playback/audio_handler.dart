import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/aggregator.dart';
import '../domain/models/playable_stream.dart';
import '../domain/models/source_type.dart';
import '../domain/models/track.dart';

enum LoopMode { off, all, one }

/// Аудио-хендлер поверх audio_service: владеет плеером, очередью и эквалайзером,
/// отдаёт состояние в уведомление/локскрин и принимает оттуда команды.
class RoundsAudioHandler extends BaseAudioHandler {
  RoundsAudioHandler(this._aggregator) {
    // Маппим события в состояние вручную (не .pipe), чтобы ловить ошибки
    // воспроизведения и не рвать поток состояния при сбое источника.
    _player.playbackEventStream.listen(
      (event) => playbackState.add(_transformEvent(event)),
      onError: _onPlaybackError,
    );
    _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) _onComplete();
    });
    // Бесшовный режим: реагируем на переход плеера на следующий элемент.
    _player.currentIndexStream.listen(_onGaplessIndex);
  }

  final Aggregator _aggregator;
  final Random _rng = Random();

  final AndroidEqualizer _equalizer = AndroidEqualizer();
  final AndroidLoudnessEnhancer _loudness = AndroidLoudnessEnhancer();
  late final AudioPlayer _player = AudioPlayer(
    audioPipeline:
        AudioPipeline(androidAudioEffects: [_loudness, _equalizer]),
  );

  AndroidEqualizer get equalizer => _equalizer;

  // Нормализация громкости: поднимаем тихие треки к целевой громкости
  // (LoudnessEnhancer с компрессией — не даёт клиппинга).
  bool _normalize = false;
  bool get normalize => _normalize;
  Future<void> setNormalize(bool on) async {
    _normalize = on;
    try {
      await _loudness.setTargetGain(on ? 5.0 : 0.0);
      await _loudness.setEnabled(on);
    } catch (_) {/* платформа может не поддерживать */}
    _notify();
  }

  /// Локальный путь к скачанному треку (оффлайн). Ставится из main().
  String? Function(String uid)? localFileResolver;

  final List<Track> _queue = [];
  int _index = -1;
  bool _loading = false;
  String? _error;
  bool _shuffle = false;
  LoopMode _repeat = LoopMode.off;

  // Радио: бесконечный микс, докручивается похожими.
  bool radioMode = false;
  Future<List<Track>> Function(Track seed)? radioExtender;

  // Кроссфейд-лайт: плавное затухание в конце и появление в начале трека.
  bool _crossfade = false;
  Timer? _fadeTimer;
  int _fadeMs = 700; // длительность затухания, настраивается

  // Пауза после текущего трека (таймер сна «до конца трека»).
  bool sleepAfterTrack = false;

  // Бесшовное воспроизведение (эксперим.): ConcatenatingAudioSource с окном
  // [текущий, следующий]. По умолчанию выключено — обычный путь не меняется.
  bool _gapless = false;
  ConcatenatingAudioSource? _concat;
  int? _gaplessNext; // логический индекс буферизованного следующего

  bool get gapless => _gapless;
  Future<void> setGapless(bool on) async {
    if (_gapless == on) return;
    _gapless = on;
    _notify();
    if (current != null) await _load(); // применить к текущему треку
  }

  // Предзагрузка следующего трека.
  String? _preUid;
  PlayableStream? _preStream;

  // Авто-восстановление при обрыве протухшего потока во время игры.
  bool _recovering = false;
  int _recoverAttempts = 0;
  String? _recoverUid;

  // «Продолжить с места»: очередь+индекс+позицию храним в prefs, восстанавливаем
  // на старте (на паузе). Позицию сохраняем периодически, пока играет.
  SharedPreferences? _sessionPrefs;
  Timer? _sessionTimer;

  void bindSession(SharedPreferences prefs) {
    _sessionPrefs = prefs;
    _sessionTimer?.cancel();
    // Позицию тикаем часто (дёшево — один int), а тяжёлую сериализацию очереди
    // делаем только при смене трека/паузе (_saveSession).
    _sessionTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_player.playing) _savePosition();
    });
  }

  void _savePosition() {
    final prefs = _sessionPrefs;
    if (prefs == null || current == null || _queue.isEmpty) return;
    prefs.setInt('last_position_ms', _player.position.inMilliseconds);
  }

  void _saveSession() {
    final prefs = _sessionPrefs;
    final cur = current;
    if (prefs == null || cur == null || _queue.isEmpty) return;
    try {
      prefs.setString(
        'last_session',
        jsonEncode({
          'tracks': _queue.map((t) => t.toJson()).toList(),
          'index': _index,
        }),
      );
      prefs.setInt('last_position_ms', _player.position.inMilliseconds);
    } catch (_) {}
  }

  /// Восстанавливает прошлую сессию: ставит очередь и грузит текущий трек на
  /// паузе с сохранённой позиции. Резолв потока — в фоне (не блокирует старт).
  Future<void> restoreSession(
      List<Track> queue, int index, Duration position) async {
    if (queue.isEmpty || index < 0 || index >= queue.length) return;
    if (_queue.isNotEmpty) return; // уже что-то играем — не перетираем
    _queue
      ..clear()
      ..addAll(queue);
    _index = index;
    _notify();
    await _loadPaused(position);
  }

  Future<void> _loadPaused(Duration at) async {
    final track = current;
    if (track == null) return;
    _loading = true;
    _notify();
    mediaItem.add(_toMediaItem(track));
    try {
      final local = localFileResolver?.call(track.uid);
      final AudioSource src;
      if (local != null) {
        src = AudioSource.uri(Uri.file(local));
      } else {
        final stream = await _aggregator.resolveStreamWithFallback(track);
        src = AudioSource.uri(stream.uri, headers: stream.headers);
      }
      // initialPosition — стартовая позиция без play(): трек ждёт на паузе.
      await _player.setAudioSource(src, initialPosition: at);
    } catch (_) {
      // Не смогли восстановить поток — трек остаётся в очереди, сыграет по тапу.
    } finally {
      _loading = false;
      _notify();
    }
  }

  void Function()? onUiChanged;
  void _notify() => onUiChanged?.call();

  /// Вызывается при старте нового трека (для скробблинга Last.fm).
  void Function(Track track)? onTrackStarted;

  AudioPlayer get player => _player;
  int? get androidAudioSessionId => _player.androidAudioSessionId;
  List<Track> get trackQueue => List.unmodifiable(_queue);
  Track? get current =>
      (_index >= 0 && _index < _queue.length) ? _queue[_index] : null;
  bool get isLoading => _loading;
  String? get error => _error;
  bool get isShuffle => _shuffle;
  LoopMode get repeatMode => _repeat;

  void toggleShuffle() {
    _shuffle = !_shuffle;
    _resyncGaplessNext();
    _notify();
  }

  void cycleRepeat() {
    _repeat = LoopMode.values[(_repeat.index + 1) % LoopMode.values.length];
    _resyncGaplessNext();
    _notify();
  }

  double get speed => _player.speed;
  @override
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
    _notify();
  }

  /// Громкость плеера (0..1) — используется плавным затуханием таймера сна.
  Future<void> setVolume(double v) => _player.setVolume(v.clamp(0.0, 1.0));

  bool get crossfade => _crossfade;
  void setCrossfade(bool on) {
    _crossfade = on;
    _fadeTimer?.cancel();
    if (on) {
      _fadeTimer = Timer.periodic(
          const Duration(milliseconds: 120), (_) => _fadeTick());
    } else {
      _fadeTimer = null;
      _player.setVolume(1);
    }
    _notify();
  }

  /// Длительность затухания кроссфейда, сек (0.3–6.0).
  double get crossfadeSeconds => _fadeMs / 1000.0;
  void setCrossfadeSeconds(double seconds) {
    _fadeMs = (seconds.clamp(0.3, 6.0) * 1000).round();
    _notify();
  }

  /// Пропуск тишины в треке (Android).
  bool _skipSilence = false;
  bool get skipSilence => _skipSilence;
  Future<void> setSkipSilence(bool on) async {
    _skipSilence = on;
    try {
      await _player.setSkipSilenceEnabled(on);
    } catch (_) {/* платформа может не поддерживать */}
    _notify();
  }

  void _fadeTick() {
    final posMs = _player.position.inMilliseconds;
    final durMs = _player.duration?.inMilliseconds ?? 0;
    var v = 1.0;
    if (posMs < _fadeMs) v = (posMs / _fadeMs).clamp(0.0, 1.0);
    if (durMs > 0) {
      final rem = durMs - posMs;
      if (rem < _fadeMs) {
        final vo = (rem / _fadeMs).clamp(0.0, 1.0);
        if (vo < v) v = vo;
      }
    }
    _player.setVolume(v);
  }

  Future<void> playTrack(Track track, {List<Track>? queue}) async {
    radioMode = false;
    if (queue != null) {
      _queue
        ..clear()
        ..addAll(queue);
      _index = _queue.indexOf(track);
      if (_index < 0) {
        _queue.insert(0, track);
        _index = 0;
      }
    } else {
      final existing = _queue.indexOf(track);
      if (existing >= 0) {
        _index = existing;
      } else {
        _queue.add(track);
        _index = _queue.length - 1;
      }
    }
    await _load();
  }

  Future<void> _load() async {
    final track = current;
    if (track == null) return;
    if (_gapless) {
      await _loadGapless(track);
      return;
    }
    _loading = true;
    _error = null;
    _notify();
    mediaItem.add(_toMediaItem(track));
    onTrackStarted?.call(track);
    // До 2 попыток: 1-я может взять предзагруженную ссылку, 2-я — свежий резолв
    // (истёкшая/битая ссылка, временный сбой источника).
    Object? lastErr;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        if (attempt > 0) {
          // Сброс возможно-залипшего состояния плеера после сбоя соединения.
          try {
            await _player.stop();
          } catch (_) {}
        }
        final local = localFileResolver?.call(track.uid);
        if (local != null) {
          await _player.setAudioSource(AudioSource.uri(Uri.file(local)));
        } else {
          PlayableStream stream;
          if (attempt == 0 &&
              _preUid == track.uid &&
              _preStream != null &&
              !_preStream!.isExpired) {
            stream = _preStream!;
          } else {
            stream = await _aggregator.resolveStreamWithFallback(track);
          }
          _preUid = null;
          _preStream = null;
          await _player.setAudioSource(
            AudioSource.uri(stream.uri, headers: stream.headers),
          );
        }
        _player.play();
        _error = null;
        lastErr = null;
        _saveSession(); // запомнить трек/очередь для «продолжить с места»
        unawaited(_preloadNext());
        unawaited(_maybeExtendRadio());
        break;
      } catch (e) {
        lastErr = e;
        if (attempt == 0) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }
    if (lastErr != null) {
      _error = 'Не удалось воспроизвести трек — источник недоступен. '
          'Нажмите «Повтор» или попробуйте другой источник.';
    }
    _loading = false;
    _notify();
  }

  /// Повторная попытка воспроизвести текущий трек.
  Future<void> retry() {
    _recoverUid = null; // ручной повтор — сбросить бюджет авто-восстановления
    final t = current;
    if (t != null) _aggregator.evictStreamCache(t); // свежий резолв, не из кэша
    return _load();
  }

  /// Ошибка воспроизведения от плеера (напр. истёкшая ссылка на поток посреди
  /// трека). Пытаемся прозрачно перерезолвить и продолжить с той же позиции,
  /// не дёргая пользователя ручным «Повтором».
  void _onPlaybackError(Object e, StackTrace st) {
    if (e is PlayerInterruptedException) return; // прерывание аудиофокуса — не наш случай
    unawaited(_tryAutoRecover());
  }

  Future<void> _tryAutoRecover() async {
    final track = current;
    if (track == null || _recovering || _loading) return;
    // Оффлайн-файлы не протухают — их не перерезолвим.
    if (localFileResolver?.call(track.uid) != null) return;
    // Бюджет попыток — на трек, чтобы не зациклиться на битом источнике.
    if (_recoverUid != track.uid) {
      _recoverUid = track.uid;
      _recoverAttempts = 0;
    }
    if (_recoverAttempts >= 3) return;
    _recoverAttempts++;
    _recovering = true;
    final pos = _player.position; // вернёмся на то же место после перерезолва
    _preUid = null; // возможно-протухшая предзагрузка больше не годится
    _preStream = null;
    _aggregator.evictStreamCache(track); // не отдать битую ссылку из кэша
    try {
      try {
        await _player.stop(); // сбросить возможно-залипшее состояние плеера
      } catch (_) {}
      await _load();
      if (_error == null && pos > Duration.zero) {
        try {
          await _player.seek(pos);
        } catch (_) {}
      }
    } finally {
      _recovering = false;
    }
  }

  /// Запуск радио: очередь из похожих, дальше докручивается на лету.
  Future<void> playRadio(Track seed, List<Track> queue) async {
    radioMode = true;
    _queue
      ..clear()
      ..addAll(queue);
    _index = _queue.indexOf(seed);
    if (_index < 0) {
      _queue.insert(0, seed);
      _index = 0;
    }
    await _load();
  }

  Future<void> _maybeExtendRadio() async {
    if (!radioMode || radioExtender == null) return;
    if (_index < _queue.length - 2) return;
    final seed = current;
    if (seed == null) return;
    try {
      final more = await radioExtender!(seed);
      final have = _queue.map((t) => t.uid).toSet();
      _queue.addAll(more.where((t) => !have.contains(t.uid)));
      _notify();
    } catch (_) {}
  }

  /// Заранее резолвит ссылку следующего трека (только при выключенном shuffle).
  Future<void> _preloadNext() async {
    if (_shuffle) return;
    final ni = _index + 1;
    if (ni >= _queue.length) return;
    final next = _queue[ni];
    if (localFileResolver?.call(next.uid) != null) return;
    if (_preUid == next.uid) return;
    try {
      final s = await _aggregator.resolveStreamWithFallback(next);
      _preUid = next.uid;
      _preStream = s;
    } catch (_) {/* не критично */}
  }

  // --- Бесшовное воспроизведение (эксперим.) ---

  Future<AudioSource> _sourceForTrack(Track t) async {
    final local = localFileResolver?.call(t.uid);
    if (local != null) return AudioSource.uri(Uri.file(local));
    final s = await _aggregator.resolveStreamWithFallback(t);
    return AudioSource.uri(s.uri, headers: s.headers);
  }

  Future<void> _loadGapless(Track track) async {
    _loading = true;
    _error = null;
    _notify();
    mediaItem.add(_toMediaItem(track));
    onTrackStarted?.call(track);
    // До 2 попыток: при обрыве соединения делаем свежий резолв и сброс плеера,
    // чтобы не залипнуть с ошибкой (иначе приходилось перезапускать приложение).
    Object? lastErr;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        if (attempt > 0) {
          _preUid = null;
          _preStream = null;
          _aggregator.evictStreamCache(track);
          try {
            await _player.stop();
          } catch (_) {}
        }
        final src = await _sourceForTrack(track);
        final concat = ConcatenatingAudioSource(children: [src]);
        _concat = concat;
        _gaplessNext = null;
        await _player.setAudioSource(concat);
        _player.play();
        _error = null;
        lastErr = null;
        _saveSession();
        unawaited(_maybeExtendRadio());
        unawaited(_appendNextGapless());
        break;
      } catch (e) {
        lastErr = e;
        if (attempt == 0) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }
    if (lastErr != null) {
      _error = 'Не удалось воспроизвести трек — источник недоступен. '
          'Нажмите «Повтор» или переключите трек.';
    }
    _loading = false;
    _notify();
  }

  /// Следующий логический индекс с учётом repeat/shuffle/radio; null — конец.
  int? _nextIndex() {
    if (_queue.isEmpty) return null;
    if (_repeat == LoopMode.one) return _index; // бесшовный повтор одного
    int next;
    if (_shuffle && _queue.length > 1) {
      final curArtist = current?.artist.toLowerCase();
      next = _index;
      for (var attempt = 0; attempt < 6; attempt++) {
        var n = _rng.nextInt(_queue.length - 1);
        if (n >= _index) n += 1;
        next = n;
        if (curArtist == null ||
            _queue[n].artist.toLowerCase() != curArtist) {
          break;
        }
      }
    } else {
      next = _index + 1;
    }
    if (next >= _queue.length) {
      if (_repeat == LoopMode.all) {
        next = 0;
      } else {
        return null;
      }
    }
    return next;
  }

  /// Догружает следующий трек в конец окна (буферизуется для бесшовности).
  Future<void> _appendNextGapless() async {
    final concat = _concat;
    if (!_gapless || concat == null) return;
    if (sleepAfterTrack) return; // уснуть после текущего — не докладываем
    if (concat.length > 1) return; // уже буферизован
    final ni = _nextIndex();
    if (ni == null) {
      _gaplessNext = null;
      return;
    }
    try {
      final src = await _sourceForTrack(_queue[ni]);
      if (!_gapless || _concat != concat || concat.length > 1) return;
      await concat.add(src);
      _gaplessNext = ni;
    } catch (_) {/* не критично — доиграет и остановится */}
  }

  /// Плеер бесшовно перешёл на следующий элемент окна.
  void _onGaplessIndex(int? idx) {
    if (!_gapless || _concat == null || idx == null || idx <= 0) return;
    final ni = _gaplessNext;
    if (ni != null) _index = ni;
    _gaplessNext = null;
    final cur = current;
    if (cur != null) {
      mediaItem.add(_toMediaItem(cur));
      onTrackStarted?.call(cur);
    }
    _notify();
    final concat = _concat!;
    final removeCount = idx.clamp(0, concat.length - 1);
    Future(() async {
      try {
        for (var i = 0; i < removeCount; i++) {
          await concat.removeAt(0);
        }
      } catch (_) {}
      await _maybeExtendRadio();
      await _appendNextGapless();
    });
  }

  /// Сбрасывает буферизованный «следующий» после изменений очереди.
  void _resyncGaplessNext() {
    final concat = _concat;
    if (!_gapless || concat == null) return;
    Future(() async {
      try {
        while (concat.length > 1) {
          await concat.removeAt(concat.length - 1);
        }
      } catch (_) {}
      _gaplessNext = null;
      await _appendNextGapless();
    });
  }

  MediaItem _toMediaItem(Track t) => MediaItem(
        id: t.uid,
        title: t.title,
        artist: t.artist,
        album: t.source.label,
        artUri: t.artworkUrl != null ? Uri.tryParse(t.artworkUrl!) : null,
        duration: t.duration,
      );

  void addToQueue(Track t) {
    _queue.add(t);
    _resyncGaplessNext();
    _notify();
  }

  /// Recs v2: заменяет «хвост» очереди новыми треками, сохраняя текущий и
  /// следующий (который мог быть предзагружен/буферизован). Волна зовёт это
  /// при real-time адаптации после скипа.
  void replaceUpcoming(List<Track> tail) {
    if (_queue.isEmpty || tail.isEmpty) return;
    final keepEnd = (_index + 2).clamp(0, _queue.length);
    final head = _queue.sublist(0, keepEnd);
    final headUids = head.map((t) => t.uid).toSet();
    _queue
      ..clear()
      ..addAll(head)
      ..addAll(tail.where((t) => !headUids.contains(t.uid)));
    _resyncGaplessNext();
    _notify();
  }

  /// Вставляет трек сразу после текущего («играть следующим»).
  void playNextInQueue(Track t) {
    final at = (_index >= 0 ? _index + 1 : _queue.length)
        .clamp(0, _queue.length);
    _queue.insert(at, t);
    _resyncGaplessNext();
    _notify();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final t = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, t);
    if (_index == oldIndex) _index = newIndex;
    _resyncGaplessNext();
    _notify();
  }

  Future<void> _onComplete() async {
    // Таймер сна «до конца трека»: останавливаемся, а не переходим дальше.
    if (sleepAfterTrack) {
      sleepAfterTrack = false;
      _notify();
      await _player.pause();
      return;
    }
    await _advance(auto: true);
  }

  Future<void> _advance({required bool auto}) async {
    if (_queue.isEmpty) return;
    if (auto && _repeat == LoopMode.one) {
      await _load();
      return;
    }
    int next;
    if (_shuffle && _queue.length > 1) {
      // Умное перемешивание: избегаем того же артиста подряд, если можно.
      final curArtist = current?.artist.toLowerCase();
      next = _index;
      for (var attempt = 0; attempt < 6; attempt++) {
        var n = _rng.nextInt(_queue.length - 1);
        if (n >= _index) n += 1;
        next = n;
        if (curArtist == null ||
            _queue[n].artist.toLowerCase() != curArtist) {
          break;
        }
      }
    } else {
      next = _index + 1;
    }
    if (next >= _queue.length) {
      if (_repeat == LoopMode.all) {
        next = 0;
      } else {
        return;
      }
    }
    _index = next;
    await _load();
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() async {
    await _player.pause();
    _saveSession(); // зафиксировать позицию на паузе для «продолжить с места»
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _advance(auto: false);

  @override
  Future<void> skipToPrevious() async {
    if (_player.position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }
    if (_index > 0) {
      _index--;
      await _load();
    }
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _index >= 0 ? _index : null,
    );
  }
}
