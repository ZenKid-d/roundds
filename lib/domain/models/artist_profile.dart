import 'source_type.dart';

/// Профиль исполнителя (аватар/баннер/био/подписчики), если источник умеет
/// его отдавать. Умеют SoundCloud, YouTube Music и Яндекс Музыка — у VK
/// профиля артиста как сущности нет вовсе (см. [isRecordOwner]).
class ArtistProfile {
  const ArtistProfile({
    required this.name,
    required this.source,
    this.avatarUrl,
    this.bannerUrl,
    this.bio,
    this.followers,
    this.isRecordOwner = false,
  });

  final String name;
  final SourceType source;
  final String? avatarUrl;
  final String? bannerUrl;
  final String? bio;
  final int? followers;

  /// true у VK: `owner_id` трека — это тот, кто ЗАГРУЗИЛ запись (пользователь
  /// или паблик), а не обязательно официальный артист. Профиль показываем
  /// честно как «владелец записи», а не выдаём за подтверждённую страницу
  /// исполнителя (у VK такой сущности для музыки просто нет).
  final bool isRecordOwner;
}
