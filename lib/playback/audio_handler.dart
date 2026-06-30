import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../data/aggregator.dart';
import '../domain/models/source_type.dart';
import '../domain/models/track.dart';

enum LoopMode { off, all, one }

/// Аудио-хендлер поверх audio_service: владеет плеером и очередью, отдаёт
/// состояние в системное уведомление / на локскрин и принимает оттуда команды.
class RoundsAudioHandler extends BaseAudioHandler {
  RoundsAudioHandler(this._aggregator) {
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);
    _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) _onComplete();
    });
  }

  final Aggregator _aggregator;
  final AudioPlayer _player = AudioPlayer();
  final Random _rng = Random();

  /// Возвращает локальный путь к скачанному треку (если есть) — для оффлайна.
  /// Устанавливается из main().
  String? Function(String uid)? localFileResolver;

  final List<Track> _queue = [];
  int _index = -1;
  bool _loading = false;
  String? _error;
  bool _shuffle = false;
  LoopMode _repeat = LoopMode.off;

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

  Future<void> playTrack(Track track, {List<Track>? queue}) async {
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
        // Оффлайн — играем скачанный файл.
        await _player.setAudioSource(AudioSource.uri(Uri.file(local)));
      } else {
        final stream = await _aggregator.resolveStreamWithFallback(track);
        await _player.setAudioSource(
          AudioSource.uri(stream.uri, headers: stream.headers),
        );
      }
      _player.play();
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      _notify();
    }
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

  // --- навигация по очереди ---

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
        return; // конец очереди
      }
    }
    _index = next;
    await _load();
  }

  // --- команды из системного UI / приложения ---

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
