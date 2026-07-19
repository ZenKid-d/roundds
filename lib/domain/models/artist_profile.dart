import 'source_type.dart';

/// Профиль исполнителя (аватар/баннер/био/подписчики), если источник умеет
/// его отдавать. Сейчас только SoundCloud — у остальных источников артист
/// в API это просто строка имени трека, без отдельного профиля.
class ArtistProfile {
  const ArtistProfile({
    required this.name,
    required this.source,
    this.avatarUrl,
    this.bannerUrl,
    this.bio,
    this.followers,
  });

  final String name;
  final SourceType source;
  final String? avatarUrl;
  final String? bannerUrl;
  final String? bio;
  final int? followers;
}
