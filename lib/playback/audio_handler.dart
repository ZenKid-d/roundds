import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../data/aggregator.dart';
import '../domain/models/playable_stream.dart';
import '../domain/models/source_type.dart';
import '../domain/models/track.dart';

enum LoopMode { off, all, one }

/// Аудио-хендлер поверх audio_service: владеет плеером, очередью и эквалайзером,
/// отдаёт состояние в уведомление/локскрин и принимает оттуда команды.
class RoundsAudioHandler extends BaseAudioHandler {
  RoundsAudioHandler(this._aggregator) {
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);
    _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) _onComplete();
    });
  }

  final Aggregator _aggregator;
  final Random _rng = Random();

  final AndroidEqualizer _equalizer = AndroidEqualizer();
  late final AudioPlayer _player = AudioPlayer(
    audioPipeline: AudioPipeline(androidAudioEffects: [_equalizer]),
  );

  AndroidEqualizer get equalizer => _equalizer;

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
  static const int _fadeMs = 700;

  // Предзагрузка следующего трека.
  String? _preUid;
  PlayableStream? _preStream;

  void Function()? onUiChanged;
  void _notify() => onUiChanged?.call();

  AudioPlayer get player => _player;
  List<Track> get trackQueue => List.unmodifiable(_queue);
  Track? get current =>
      (_index >= 0 && _index < _queue.length) ? _queue[_index] : null;
  bool get isLoading => _loading;
  String? get error => _error;
  bool get isShuffle => _shuffle;
  LoopMode get repeatMode => _repeat;

  void toggleShuffle() {
    _shuffle = !_shuffle;
    _notify();
  }

  void cycleRepeat() {
    _repeat = LoopMode.values[(_repeat.index + 1) % LoopMode.values.length];
    _notify();
  }

  double get speed => _player.speed;
  @override
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
    _notify();
  }

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
    _loading = true;
    _error = null;
    _notify();
    mediaItem.add(_toMediaItem(track));
    try {
      final local = localFileResolver?.call(track.uid);
      if (local != null) {
        await _player.setAudioSource(AudioSource.uri(Uri.file(local)));
      } else {
        PlayableStream stream;
        if (_preUid == track.uid &&
            _preStream != null &&
            !_preStream!.isExpired) {
          stream = _preStream!; // готовая ссылка из предзагрузки
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
      unawaited(_preloadNext());
      unawaited(_maybeExtendRadio());
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      _notify();
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
    _notify();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final t = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, t);
    if (_index == oldIndex) _index = newIndex;
    _notify();
  }

  Future<void> _onComplete() => _advance(auto: true);

  Future<void> _advance({required bool auto}) async {
    if (_queue.isEmpty) return;
    if (auto && _repeat == LoopMode.one) {
      await _load();
      return;
    }
    int next;
    if (_shuffle && _queue.length > 1) {
      next = _rng.nextInt(_queue.length - 1);
      if (next >= _index) next += 1;
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
  Future<void> pause() => _player.pause();

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
