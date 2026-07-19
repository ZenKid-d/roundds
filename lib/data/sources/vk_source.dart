import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/diagnostics.dart';
import '../../domain/constants.dart';
import '../../domain/models/artist_profile.dart';
import '../../domain/models/playable_stream.dart';
import '../../domain/models/source_type.dart';
import '../../domain/models/track.dart';
import '../../domain/music_source.dart';

/// Источник VK Музыка поверх официального `api.vk.com` (метод `audio.*`).
/// Аудио играет ВНУТРИ нашего плеера (VK отдаёт HLS `index.m3u8`, играбельный
/// в ExoPlayer, либо прямой mp3).
///
/// ⚠️ Аудио-API у VK официально не открыт: непустые ссылки на поток отдаются
/// только по токену «доверенного» клиента (напр. Kate Mobile / VK Android).
/// Нарушает ToS VK, есть риск ограничения аккаунта — как и у Яндекса.
/// `api.vk.com` — российский хост, обычно достижим, когда SoundCloud/YouTube
/// заблокированы на уровне DNS.
class VkSource implements MusicSource {
  VkSource(this._dio, {String? token}) : _token = _clean(token);

  final Dio _dio;
  String? _token;

  /// Токен из копипаста часто приходит с пробелами/переводом строки; если их не
  /// срезать, Dio закодирует их в access_token (%0A) → VK отвечает HTTP 400.
  static String? _clean(String? t) {
    final v = t?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  static const _base = 'https://api.vk.com/method';
  static const _apiVersion = '5.131';

  // ВАЖНО: методы audio.* у VK доступны только с User-Agent «доверенного»
  // клиента. Kate Mobile (client_id=2685278) был отрезан от аудио-API VK
  // примерно в мае 2026 — audio.search стал отвечать error_code=3 «Unknown
  // method passed» для ЛЮБОГО токена, выпущенного под этот client_id, вне
  // зависимости от UA запроса. Официальное Android-приложение VK
  // (client_id=2274003) на момент этого фикса ещё работает — используем его
  // UA. Токен тоже должен быть выпущен под client_id=2274003 (см. описание в
  // Настройках), иначе смена одного UA не поможет.
  //
  // Побочный эффект: этот клиент отдаёт ссылки на поток в виде HLS
  // `.m3u8` вместо прямых `.mp3` — ExoPlayer (используется в проигрывателе)
  // их поддерживает нативно, так что resolveStream ничего менять не должен.
  static const _ua =
      'VKAndroidApp/4.13.1-1206 (Android 4.4.3; SDK 19; armeabi; ; ru)';

  @override
  SourceType get type => SourceType.vk;

  void setToken(String? token) => _token = _clean(token);

  @override
  Future<bool> get isReady async => _token != null && _token!.isNotEmpty;

  Options get _opts => Options(headers: const {'User-Agent': _ua});

  Map<String, dynamic> _params([Map<String, dynamic> extra = const {}]) => {
        'access_token': _token,
        'v': _apiVersion,
        ...extra,
      };

  /// Разбирает ответ VK: при ошибке кидает [SourceException] с текстом от VK.
  Map<String, dynamic> _unwrap(dynamic data) {
    final map = (data as Map).cast<String, dynamic>();
    final err = map['error'];
    if (err is Map) {
      // error_code=3 «Unknown method passed» на audio.* — это не опечатка в
      // имени метода (он существует), а признак того, что VK отрезал именно
      // ЭТОТ client_id/токен от аудио-API целиком (так было с Kate Mobile в
      // мае 2026). Обычное «неверный токен» здесь вводит в заблуждение.
      if (err['error_code'] == 3) {
        throw SourceException(type,
            'VK закрыл доступ к музыке для этого токена — сгенерируйте новый '
            'через официальное приложение VK (см. Настройки)');
      }
      throw SourceException(
          type, 'VK: ${err['error_msg'] ?? err['error_code'] ?? 'ошибка'}');
    }
    return map;
  }

  /// Внятное описание сбоя для диагностики. VK часто возвращает причину в ТЕЛЕ
  /// ответа даже при HTTP-ошибке (400/403), а generic-текст Dio её прячет —
  /// вытаскиваем `error_msg`/`error_code`, иначе показываем статус и тело.
  static String _describe(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      dynamic body = data;
      if (body is String && body.isNotEmpty) {
        try {
          body = jsonDecode(body);
        } catch (_) {/* оставляем строкой */}
      }
      if (body is Map && body['error'] is Map) {
        final err = body['error'] as Map;
        return 'VK ${err['error_code']}: ${err['error_msg'] ?? 'ошибка'}';
      }
      final code = e.response?.statusCode;
      if (code != null) {
        final b = (body ?? e.message)?.toString() ?? '';
        return 'HTTP $code: ${b.length > 200 ? '${b.substring(0, 200)}…' : b}';
      }
      return e.message ?? e.type.name;
    }
    return '$e';
  }

  @override
  bool get supportsPaging => true;

  @override
  Future<List<Track>> search(String query, {int limit = 20, int page = 0}) async {
    _requireToken();
    try {
      final r = await _dio.get('$_base/audio.search',
          queryParameters: _params({
            'q': query,
            'count': limit,
            if (page > 0) 'offset': page * limit,
          }),
          options: _opts);
      final items = (_unwrap(r.data)['response']?['items'] as List? ?? []);
      return items
          .whereType<Map>()
          .map((e) => toTrack(e.cast<String, dynamic>()))
          .whereType<Track>()
          .toList();
    } on SourceException {
      rethrow;
    } catch (e) {
      final why = _describe(e);
      Diagnostics.instance.error('vk.search', '«$query»: $why');
      throw SourceException(type, 'ошибка поиска ($why)');
    }
  }

  @override
  Future<List<Track>> feed({int limit = 20}) async {
    _requireToken();
    // «Лента» — популярное. Метод устаревающий; при ошибке — фолбэк на поиск.
    try {
      final r = await _dio.get('$_base/audio.getPopular',
          queryParameters: _params({'count': limit}), options: _opts);
      final resp = _unwrap(r.data)['response'];
      final items = resp is List ? resp : (resp?['items'] as List? ?? []);
      return items
          .whereType<Map>()
          .map((e) => toTrack(e.cast<String, dynamic>()))
          .whereType<Track>()
          .toList();
    } catch (e) {
      Diagnostics.instance
          .warn('vk.feed', 'getPopular: ${_describe(e)} — фолбэк на поиск');
      return search('популярное', limit: limit);
    }
  }

  @override
  Future<PlayableStream> resolveStream(Track track) async {
    _requireToken();
    // Ссылки VK на поток живут ~30 мин, а сохранённый (лайкнутый) трек может
    // играться позже — поэтому берём СВЕЖУЮ ссылку через audio.getById по id
    // вида «owner_id_id» (это и есть наш track.id). Кэш из extra — фолбэк, если
    // запрос не прошёл.
    var url = '';
    try {
      final r = await _dio
          .get('$_base/audio.getById',
              queryParameters: _params({'audios': track.id}), options: _opts)
          .timeout(const Duration(seconds: 12));
      final items = (_unwrap(r.data)['response'] as List? ?? []);
      if (items.isNotEmpty) {
        url = (items.first as Map)['url'] as String? ?? '';
      }
    } catch (e) {
      Diagnostics.instance.warn(
          'vk.resolve', '${track.id} getById: ${_describe(e)} — пробуем кэш');
    }
    if (url.isEmpty) url = (track.extra['url'] as String?) ?? '';
    if (url.isEmpty) {
      Diagnostics.instance
          .error('vk.resolve', '${track.id} «${track.title}»: пустой url');
      throw SourceException(
        type,
        'поток недоступен — нужен токен доверенного клиента VK (напр. Kate Mobile).',
      );
    }
    return PlayableStream(
      uri: Uri.parse(url),
      expiresAt: DateTime.now().add(defaultStreamExpiry),
    );
  }

  // Нативной загрузки нет — грузим по resolveStream-URL (см. DownloadsController).
  @override
  Future<bool> downloadTo(Track track, String path,
          {void Function(int received, int total)? onProgress}) async =>
      false;

  @visibleForTesting
  static Track? toTrack(Map<String, dynamic> j) {
    final ownerId = j['owner_id'];
    final id = j['id'];
    if (id == null) return null;
    final thumb = (j['album'] as Map?)?['thumb'] as Map?;
    final art = (thumb?['photo_600'] ?? thumb?['photo_300'] ?? thumb?['photo_135'])
        as String?;
    final dur = j['duration'];
    return Track(
      id: ownerId != null ? '${ownerId}_$id' : '$id',
      title: j['title'] as String? ?? 'Без названия',
      artist: j['artist'] as String? ?? 'VK Музыка',
      artworkUrl: art,
      duration: dur is int ? Duration(seconds: dur) : null,
      source: SourceType.vk,
      extra: {
        'url': j['url'] as String? ?? '',
        // Владелец записи (пользователь/паблик, кто загрузил трек) — нужен
        // для artistProfile(). НЕ обязательно сам артист, см. isRecordOwner.
        if (ownerId != null) 'ownerId': ownerId,
      },
    );
  }

  /// Профиль владельца записи (аватар/подписчики/описание) по `owner_id`
  /// трека — положительный id значит пользователя (`users.get`), отрицательный
  /// — паблик/группу (`groups.getById`). VK не имеет отдельной сущности
  /// «артист» для музыки — owner_id это тот, кто ЗАГРУЗИЛ трек, поэтому
  /// результат всегда помечен [ArtistProfile.isRecordOwner] = true; вызывающий
  /// код обязан честно показать это как «владелец записи», а не выдавать за
  /// подтверждённый профиль исполнителя.
  Future<ArtistProfile?> artistProfile(Track seed) async {
    final rawOwnerId = seed.extra['ownerId'];
    if (rawOwnerId == null || _token == null || _token!.isEmpty) return null;
    final ownerId =
        rawOwnerId is int ? rawOwnerId : int.tryParse('$rawOwnerId');
    if (ownerId == null) return null;
    try {
      return ownerId < 0
          ? await _groupProfile(-ownerId, seed)
          : await _userProfile(ownerId, seed);
    } catch (e) {
      Diagnostics.instance
          .warn('vk.artistProfile', '$ownerId: ${_describe(e)}');
      return null;
    }
  }

  Future<ArtistProfile?> _groupProfile(int groupId, Track seed) async {
    final r = await _dio.get('$_base/groups.getById',
        queryParameters: _params({
          'group_ids': '$groupId',
          'fields': 'description,members_count,cover',
        }),
        options: _opts);
    final items = (_unwrap(r.data)['response'] as List? ?? []);
    if (items.isEmpty) return null;
    final g = (items.first as Map);
    final coverImages = (g['cover'] as Map?)?['images'] as List?;
    final cover = (coverImages != null && coverImages.isNotEmpty)
        ? (coverImages.last as Map)['url'] as String?
        : null;
    final desc = (g['description'] as String?)?.trim();
    return ArtistProfile(
      name: g['name'] as String? ?? seed.artist,
      source: SourceType.vk,
      avatarUrl: g['photo_200'] as String?,
      bannerUrl: cover,
      bio: (desc == null || desc.isEmpty) ? null : desc,
      followers: (g['members_count'] as num?)?.toInt(),
      isRecordOwner: true,
    );
  }

  Future<ArtistProfile?> _userProfile(int userId, Track seed) async {
    final r = await _dio.get('$_base/users.get',
        queryParameters: _params({
          'user_ids': '$userId',
          'fields': 'photo_200,followers_count,about',
        }),
        options: _opts);
    final items = (_unwrap(r.data)['response'] as List? ?? []);
    if (items.isEmpty) return null;
    final u = (items.first as Map);
    final name = [u['first_name'], u['last_name']]
        .whereType<String>()
        .join(' ')
        .trim();
    final about = (u['about'] as String?)?.trim();
    return ArtistProfile(
      name: name.isEmpty ? seed.artist : name,
      source: SourceType.vk,
      avatarUrl: u['photo_200'] as String?,
      bio: (about == null || about.isEmpty) ? null : about,
      followers: (u['followers_count'] as num?)?.toInt(),
      isRecordOwner: true,
    );
  }

  void _requireToken() {
    if (_token == null || _token!.isEmpty) {
      throw SourceException(type, 'не задан токен (укажите в Настройках)');
    }
  }
}
