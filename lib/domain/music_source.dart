import 'models/track.dart';
import 'models/playable_stream.dart';
import 'models/source_type.dart';

/// Общий контракт для всех источников музыки.
/// Каждый коннектор (YouTube/SoundCloud/Яндекс) реализует его, а агрегатор
/// сводит их в единый поиск и ленту.
abstract class MusicSource {
  SourceType get type;

  /// Готов ли источник к работе (например, у Яндекса есть ли токен).
  Future<bool> get isReady;

  /// Поиск треков по запросу.
  Future<List<Track>> search(String query, {int limit = 20});

  /// Лента/подборка для главного экрана (charts / новинки / популярное).
  Future<List<Track>> feed({int limit = 20});

  /// Получить играбельный поток для трека (вызывается перед воспроизведением).
  Future<PlayableStream> resolveStream(Track track);
}

/// Исключение источника с человекочитаемой причиной (показываем в UI).
class SourceException implements Exception {
  final SourceType source;
  final String message;
  SourceException(this.source, this.message);

  @override
  String toString() => '${source.label}: $message';
}
