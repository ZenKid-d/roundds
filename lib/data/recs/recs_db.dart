import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Recs v2 — SQLite-хранилище: event log, дизлайки, cooldown, кэши похожести и
/// дневных плейлистов, снапшот профиля. Миграции — onCreate/onUpgrade.
class RecsDb {
  RecsDb._(this.db);
  final Database db;

  static const int schemaVersion = 1;

  static Future<RecsDb> open() async {
    try {
      final base = await getDatabasesPath();
      return RecsDb._(await _openAt(p.join(base, 'recs.db')));
    } catch (_) {
      // Фолбэк: in-memory — recs не персистит, но приложение не падает на старте.
      return RecsDb._(await _openAt(inMemoryDatabasePath));
    }
  }

  static Future<Database> _openAt(String path) => openDatabase(
        path,
        version: schemaVersion,
        onCreate: _create,
        onUpgrade: _upgrade,
      );

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE events(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        track_key TEXT NOT NULL,
        source TEXT,
        artist TEXT,
        title TEXT,
        ts INTEGER NOT NULL,
        dur_ms INTEGER,
        played_ms INTEGER,
        kind TEXT NOT NULL
      )''');
    await db.execute('CREATE INDEX ix_events_ts ON events(ts)');
    await db.execute('CREATE INDEX ix_events_track ON events(track_key)');

    await db.execute('''
      CREATE TABLE dislikes(
        track_key TEXT PRIMARY KEY,
        artist TEXT,
        title TEXT,
        source TEXT,
        track_json TEXT,
        ts INTEGER NOT NULL
      )''');

    await db.execute('''
      CREATE TABLE cooldowns(
        track_key TEXT PRIMARY KEY,
        last_played_ts INTEGER NOT NULL
      )''');

    await db.execute('''
      CREATE TABLE similar_cache(
        cache_key TEXT PRIMARY KEY,
        payload TEXT NOT NULL,
        fetched_ts INTEGER NOT NULL
      )''');

    await db.execute('''
      CREATE TABLE daily_cache(
        kind TEXT NOT NULL,
        day TEXT NOT NULL,
        payload TEXT NOT NULL,
        PRIMARY KEY(kind, day)
      )''');

    await db.execute('''
      CREATE TABLE profile_snapshot(
        id INTEGER PRIMARY KEY CHECK(id = 1),
        payload TEXT NOT NULL,
        updated_ts INTEGER NOT NULL
      )''');
  }

  // Будущие версии схемы: switch по [from]. v1 — начальная, миграций пока нет.
  static Future<void> _upgrade(Database db, int from, int to) async {}
}
