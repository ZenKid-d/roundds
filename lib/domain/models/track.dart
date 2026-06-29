import 'source_type.dart';

/// Универсальное представление трека из любого источника.
class Track {
  /// Идентификатор внутри источника (videoId, soundcloud id, yandex trackId).
  final String id;
  final String title;
  final String artist;
  final String? album;
  final String? artworkUrl;
  final Duration? duration;
  final SourceType source;

  /// Сырые данные источника, нужные для резолва потока
  /// (например, transcodings у SoundCloud, albumId у Яндекса).
  final Map<String, dynamic> extra;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.source,
    this.album,
    this.artworkUrl,
    this.duration,
    this.extra = const {},
  });

  /// Глобально уникальный ключ (источник + id) — для очереди, истории, плейлистов.
  String get uid => '${source.id}:$id';

  Track copyWith({String? artworkUrl, Duration? duration}) => Track(
        id: id,
        title: title,
        artist: artist,
        source: source,
        album: album,
        artworkUrl: artworkUrl ?? this.artworkUrl,
        duration: duration ?? this.duration,
        extra: extra,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'artworkUrl': artworkUrl,
        'durationMs': duration?.inMilliseconds,
        'source': source.id,
        'extra': extra,
      };

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        artist: j['artist'] as String? ?? '',
        album: j['album'] as String?,
        artworkUrl: j['artworkUrl'] as String?,
        duration: j['durationMs'] != null
            ? Duration(milliseconds: j['durationMs'] as int)
            : null,
        source: SourceTypeX.fromId(j['source'] as String? ?? 'youtube'),
        extra: (j['extra'] as Map?)?.cast<String, dynamic>() ?? const {},
      );

  @override
  bool operator ==(Object other) => other is Track && other.uid == uid;

  @override
  int get hashCode => uid.hashCode;
}
