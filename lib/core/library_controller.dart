import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/playlist.dart';
import '../domain/models/track.dart';

/// Локальная медиатека: история прослушивания и пользовательские плейлисты.
/// Хранится в SharedPreferences как JSON (без codegen).
class LibraryController extends ChangeNotifier {
  LibraryController(this._prefs) {
    _load();
  }

  final SharedPreferences _prefs;

  final List<Track> _history = [];
  final List<PlaylistX> _playlists = [];

  List<Track> get history => List.unmodifiable(_history);
  List<PlaylistX> get playlists => List.unmodifiable(_playlists);

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
    notifyListeners();
  }

  Future<void> pushHistory(Track t) async {
    _history.removeWhere((e) => e.uid == t.uid);
    _history.insert(0, t);
    if (_history.length > 50) _history.removeRange(50, _history.length);
    await _persistHistory();
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

  Future<void> renamePlaylist(String id, String name) async {
    final pl = _playlists.firstWhere((e) => e.id == id);
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
    final pl = _playlists.firstWhere((e) => e.id == id);
    if (!pl.tracks.any((e) => e.uid == t.uid)) {
      pl.tracks.add(t);
      await _persistPlaylists();
      notifyListeners();
    }
  }

  Future<void> removeFromPlaylist(String id, Track t) async {
    final pl = _playlists.firstWhere((e) => e.id == id);
    pl.tracks.removeWhere((e) => e.uid == t.uid);
    await _persistPlaylists();
    notifyListeners();
  }

  Future<void> _persistHistory() => _prefs.setString(
      'history', jsonEncode(_history.map((e) => e.toJson()).toList()));

  Future<void> _persistPlaylists() => _prefs.setString(
      'playlists', jsonEncode(_playlists.map((e) => e.toJson()).toList()));
}
