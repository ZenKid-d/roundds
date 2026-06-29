import 'track.dart';

/// Локальный плейлист пользователя (хранится на устройстве).
class PlaylistX {
  final String id;
  String name;
  final List<Track> tracks;

  PlaylistX({
    required this.id,
    required this.name,
    List<Track>? tracks,
  }) : tracks = tracks ?? [];

  Track? get cover => tracks.isNotEmpty ? tracks.first : null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'tracks': tracks.map((t) => t.toJson()).toList(),
      };

  factory PlaylistX.fromJson(Map<String, dynamic> j) => PlaylistX(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Без названия',
        tracks: (j['tracks'] as List? ?? [])
            .map((e) => Track.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}
