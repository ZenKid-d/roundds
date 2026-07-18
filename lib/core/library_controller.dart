import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/playlist.dart';
import '../domain/models/track.dart';
import 'diagnostics.dart';

/// Локальная медиатека: история прослушивания и пользовательские плейлисты.
/// Хранится в SharedPreferences как JSON (без codegen).
class LibraryController extends ChangeNotifier {
  LibraryController(this._prefs) {
    _load();
  }

  final SharedPreferences _prefs;

  /// Сколько последних треков держим в истории прослушивания. Старые
  /// вытесняются (FIFO) — история нужна для «недавнее», а не как архив.
  static const int maxHistory = 50;

  final List<Track> _history = [];
  final List<PlaylistX> _playlists = [];
  final List<Track> _liked = [];
  final Map<String, Track> _statTrack = {};
  final Map<String, int> _statCount = {};
  final Set<String> _blacklist = {}; // артисты в нижнем регистре
  int _totalListenedMs = 0;

  // Кэш отсортированных топов — пересортировка по всем прослушанным трекам
  // дорогая, а статы меняются редко (на проигрывание). Сбрасываем при мутации.
  List<MapEntry<Track, int>>? _topTracksCache;
  List<MapEntry<String, int>>? _topArtistsCache;
  void _invalidateStatCaches() {
    _topTracksCache = null;
    _topArtistsCache = null;
  }

  /// Вызывается при добавлении лайка (для авто-скачивания). Ставится в провайдере.
  void Function(Track track)? onTrackLiked;

  List<Track> get history => List.unmodifiable(_history);
  List<PlaylistX> get playlists => List.unmodifiable(_playlists);
  List<Track> get liked => List.unmodifiable(_liked);

  // --- Подписки на артистов ---
  final List<String> _followed = []; // отображаемые имена, новые сверху
  List<String> get followedArtists => List.unmodifiable(_followed);
  bool isFollowing(String artist) =>
      _followed.any((e) => e.toLowerCase() == artist.toLowerCase());
  Future<void> toggleFollow(String artist) async {
    final a = artist.trim();
    if (a.isEmpty) return;
    if (isFollowing(a)) {
      _followed.removeWhere((e) => e.toLowerCase() == a.toLowerCase());
    } else {
      _followed.insert(0, a);
    }
    await _prefs.setStringList('followed_artists', _followed);
    notifyListeners();
  }

  // --- Чёрный список артистов ---
  List<String> get blacklistedArtists => _blacklist.toList()..sort();
  bool isArtistBlacklisted(String artist) =>
      _blacklist.contains(artist.toLowerCase());
  Future<void> blacklistArtist(String artist) async {
    if (artist.trim().isEmpty) return;
    _blacklist.add(artist.toLowerCase());
    await _prefs
        .setStringList('blacklist_artists', _blacklist.toList());
    notifyListeners();
  }

  Future<void> unblacklistArtist(String artist) async {
    _blacklist.remove(artist.toLowerCase());
    await _prefs
        .setStringList('blacklist_artists', _blacklist.toList());
    notifyListeners();
  }

  /// Безопасный поиск плейлиста по id. Возвращает null, если плейлиста нет —
  /// например, когда его успели удалить между открытием меню и тапом по
  /// действию (гонка UI). Все мутации плейлиста идут через этот метод и
  /// молча no-op, чтобы не бросать StateError в рантайме.
  PlaylistX? _findById(String id) {
    for (final p in _playlists) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Убирает дубликаты треков в плейлисте (по uid и по «артист — название»).
  /// Возвращает число удалённых дубликатов (0, если плейлист уже удалён).
  Future<int> removeDuplicates(String playlistId) async {
    final pl = _findById(playlistId);
    if (pl == null) return 0;
    final seenUid = <String>{};
    final seenName = <String>{};
    final before = pl.tracks.length;
    pl.tracks.retainWhere((t) {
      final nameKey = '${t.artist.toLowerCase()}—${t.title.toLowerCase()}';
      final dupUid = !seenUid.add(t.uid);
      final dupName = !seenName.add(nameKey);
      return !(dupUid || dupName);
    });
    await _persistPlaylists();
    notifyListeners();
    return before - pl.tracks.length;
  }

  void _load() {
    final h = _prefs.getString('history');
    if (h != null) {
      _history
        ..clear()
        ..addAll((jsonDecode(h) as List)
            .map((e) => Track.fromJson((e as Map).cast<String, dynamic>())));
    }
    final p = _prefs.getString('playlists');
    if (p != null) {
      _playlists
        ..clear()
        ..addAll((jsonDecode(p) as List)
            .map((e) => PlaylistX.fromJson((e as Map).cast<String, dynamic>())));
    }
    final l = _prefs.getString('liked');
    if (l != null) {
      _liked
        ..clear()
        ..addAll((jsonDecode(l) as List)
            .map((e) => Track.fromJson((e as Map).cast<String, dynamic>())));
    }
    _blacklist
      ..clear()
      ..addAll(_prefs.getStringList('blacklist_artists') ?? const []);
    _followed
      ..clear()
      ..addAll(_prefs.getStringList('followed_artists') ?? const []);
    final s = _prefs.getString('stats');
    if (s != null) {
      for (final e in (jsonDecode(s) as List)) {
        final m = (e as Map).cast<String, dynamic>();
        final t = Track.fromJson((m['track'] as Map).cast<String, dynamic>());
        _statTrack[t.uid] = t;
        _statCount[t.uid] = m['count'] as int;
      }
      _invalidateStatCaches();
    }
    // Суммарное время прослушивания. Если ещё не считалось — разовая оценка
    // из истории (кол-во прослушиваний × длительность трека).
    _totalListenedMs = _prefs.getInt('listened_ms') ?? -1;
    if (_totalListenedMs < 0) {
      var est = 0;
      for (final t in _statTrack.values) {
        final d = t.duration;
        if (d != null) est += d.inMilliseconds * (_statCount[t.uid] ?? 0);
      }
      _totalListenedMs = est;
      _prefs.setInt('listened_ms', _totalListenedMs);
    }
    notifyListeners();
  }

  Duration get totalListened => Duration(milliseconds: _totalListenedMs);
  int get uniqueTracks => _statTrack.length;
  int get uniqueArtists =>
      _statTrack.values.map((t) => t.artist).toSet().length;

  Future<void> addListened(int ms) async {
    if (ms <= 0) return;
    _totalListenedMs += ms;
    await _prefs.setInt('listened_ms', _totalListenedMs);
    notifyListeners();
  }

  /// Топ треков по числу прослушиваний.
  List<MapEntry<Track, int>> topTracks({int limit = 50}) {
    final all = _topTracksCache ??= (_statTrack.values
        .map((t) => MapEntry(t, _statCount[t.uid] ?? 0))
        .toList()
      ..sort((a, b) => b.value - a.value));
    return all.take(limit).toList();
  }

  /// Топ артистов по суммарному числу прослушиваний.
  List<MapEntry<String, int>> topArtists({int limit = 20}) {
    final all = _topArtistsCache ??= (() {
      final byArtist = <String, int>{};
      for (final t in _statTrack.values) {
        byArtist[t.artist] =
            (byArtist[t.artist] ?? 0) + (_statCount[t.uid] ?? 0);
      }
      return byArtist.entries.toList()..sort((a, b) => b.value - a.value);
    })();
    return all.take(limit).toList();
  }

  int get totalPlays =>
      _statCount.values.fold(0, (sum, c) => sum + c);

  Future<void> _persistStats() => _prefs.setString(
        'stats',
        jsonEncode(_statTrack.values
            .map((t) => {'track': t.toJson(), 'count': _statCount[t.uid]})
            .toList()),
      );

  bool isLiked(Track t) => _liked.any((e) => e.uid == t.uid);

  Future<void> addManyToLiked(List<Track> tracks) async {
    for (final t in tracks) {
      if (!_liked.any((x) => x.uid == t.uid)) _liked.insert(0, t);
    }
    await _prefs.setString(
        'liked', jsonEncode(_liked.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  Future<void> toggleLike(Track t) async {
    if (isLiked(t)) {
      _liked.removeWhere((e) => e.uid == t.uid);
    } else {
      _liked.insert(0, t);
      onTrackLiked?.call(t); // авто-скачивание, если включено
    }
    await _prefs.setString(
        'liked', jsonEncode(_liked.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  Future<void> pushHistory(Track t) async {
    _history.removeWhere((e) => e.uid == t.uid);
    _history.insert(0, t);
    if (_history.length > maxHistory) {
      _history.removeRange(maxHistory, _history.length);
    }
    _statTrack[t.uid] = t;
    _statCount[t.uid] = (_statCount[t.uid] ?? 0) + 1;
    _invalidateStatCaches();
    await _persistHistory();
    await _persistStats();
    notifyListeners();
  }

  Future<PlaylistX> createPlaylist(String name) async {
    final pl = PlaylistX(
      id: 'pl_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
    );
    _playlists.add(pl);
    await _persistPlaylists();
    notifyListeners();
    return pl;
  }

  Future<PlaylistX> importPlaylist(String name, List<Track> tracks) async {
    final pl = PlaylistX(
      id: 'pl_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      tracks: List.of(tracks),
    );
    _playlists.add(pl);
    await _persistPlaylists();
    notifyListeners();
    return pl;
  }

  Future<void> renamePlaylist(String id, String name) async {
    final pl = _findById(id);
    if (pl == null) return;
    pl.name = name;
    await _persistPlaylists();
    notifyListeners();
  }

  Future<void> deletePlaylist(String id) async {
    _playlists.removeWhere((e) => e.id == id);
    await _persistPlaylists();
    notifyListeners();
  }

  Future<void> addToPlaylist(String id, Track t) async {
    final pl = _findById(id);
    if (pl == null) return;
    if (!pl.tracks.any((e) => e.uid == t.uid)) {
      pl.tracks.add(t);
      await _persistPlaylists();
      notifyListeners();
    }
  }

  Future<void> removeFromPlaylist(String id, Track t) async {
    final pl = _findById(id);
    if (pl == null) return;
    pl.tracks.removeWhere((e) => e.uid == t.uid);
    await _persistPlaylists();
    notifyListeners();
  }

  /// Полный экспорт библиотеки (плейлисты, лайки, история, статистика).
  Map<String, dynamic> exportData() => {
        'version': 1,
        'playlists': _playlists.map((e) => e.toJson()).toList(),
        'liked': _liked.map((e) => e.toJson()).toList(),
        'history': _history.map((e) => e.toJson()).toList(),
        'stats': _statTrack.values
            .map((t) => {'track': t.toJson(), 'count': _statCount[t.uid]})
            .toList(),
      };

  /// Импорт (слияние) библиотеки из бэкапа.
  ///
  /// Битые записи (отсутствует id, не тот тип) пропускаем, а не роняем весь
  /// импорт — так частично повреждённый бэкап восстановит что сможет. Причина
  /// каждого пропуска пишется в диагностику.
  Future<void> importData(Map<String, dynamic> data) async {
    var skipped = 0;
    for (final e in (data['playlists'] as List? ?? [])) {
      try {
        final pl = PlaylistX.fromJson((e as Map).cast<String, dynamic>());
        if (!_playlists.any((p) => p.id == pl.id)) _playlists.add(pl);
      } catch (err) {
        skipped++;
        Diagnostics.instance.warn('library', 'Импорт: битый плейлист пропущен: $err');
      }
    }
    for (final e in (data['liked'] as List? ?? [])) {
      try {
        final t = Track.fromJson((e as Map).cast<String, dynamic>());
        if (!_liked.any((x) => x.uid == t.uid)) _liked.insert(0, t);
      } catch (err) {
        skipped++;
        Diagnostics.instance.warn('library', 'Импорт: битый лайк пропущен: $err');
      }
    }
    for (final e in (data['stats'] as List? ?? [])) {
      try {
        final m = (e as Map).cast<String, dynamic>();
        final t = Track.fromJson((m['track'] as Map).cast<String, dynamic>());
        final c = (m['count'] as num?)?.toInt() ?? 0;
        _statTrack[t.uid] = t;
        _statCount[t.uid] = (_statCount[t.uid] ?? 0) + c;
      } catch (err) {
        skipped++;
        Diagnostics.instance.warn('library', 'Импорт: битая запись stats пропущена: $err');
      }
    }
    if (skipped > 0) {
      Diagnostics.instance
          .warn('library', 'Импорт завершён, пропущено битых записей: $skipped');
    }
    _invalidateStatCaches();
    await _persistPlaylists();
    await _prefs.setString(
        'liked', jsonEncode(_liked.map((e) => e.toJson()).toList()));
    await _persistStats();
    notifyListeners();
  }

  Future<void> _persistHistory() => _prefs.setString(
      'history', jsonEncode(_history.map((e) => e.toJson()).toList()));

  Future<void> _persistPlaylists() => _prefs.setString(
      'playlists', jsonEncode(_playlists.map((e) => e.toJson()).toList()));
}
