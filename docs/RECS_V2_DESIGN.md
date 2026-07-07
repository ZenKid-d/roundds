# Recs v2 «Моя волна» — design-документ (Фаза 0)

Статус: **согласовано, идёт реализация по фазам.**

## Подтверждённые решения (Q&A)
- **Q1 — БД:** `sqflite` (миграции = onCreate/onUpgrade).
- **Q2 — Last.fm-ключ:** НЕ вшиваем. Last.fm-провайдер работает только если
  пользователь ввёл ключ; иначе граф похожести держат source/SC/YT-InnerTube/
  local-history провайдеры. Движок обязан быть сильным без Last.fm — это дефолт.
- **Q6 — Радио v1:** полностью заменяется движком волны (`radioFrom` + докрутка
  в `audio_handler` уходят).
- Q3 InnerTube — experimental за флагом. Q4 Премьера — отдельная под-фаза 5b.
  Q5 — экран «Моя волна». Q7 — переиспользуем TTL-кэш агрегатора.

---

## 0. Что уже есть в репозитории (факты)

- **Стек:** Flutter/Dart, Android-only. Riverpod (провайдеры в `lib/core/providers.dart`),
  go_router, `MusicSource` (YouTube/SoundCloud/Яндекс) + `Aggregator`
  (кросс-источниковый поиск/резолв, TTL-кэш ленты/поиска, `youtubeMatch`).
- **Хранение — НЕ БД.** `SharedPreferences` + JSON-строки (`library_controller`,
  `downloads_controller`), `flutter_secure_storage` (токены). Пакетов
  sqflite/drift/hive/isar **нет**.
- **Сигналы, которые уже логируются (в prefs, агрегированно, без событий):**
  - `library_controller`: `_liked` (лайки), `_history` (последние 50),
    `_statTrack`/`_statCount` (счётчики прослушиваний), `_blacklist` (артисты),
    `topTracks`/`topArtists` (мемоизированы).
  - `addListened(ms)` — суммарное время; вызывается из плеера.
- **Хуки плеера (`playback_controller.dart`)** — готовые точки для event log:
  - `onTrackStarted(track)` — старт трека.
  - `onListened(ms)` — накопленное реально-прослушанное время (флашится ~20с и на паузе).
  - `onScrobble(track, startedAtEpochSec)` + `shouldScrobble(durationMs, playedMs)` —
    уже считают «дослушал ли» по правилам Last.fm (½ или 4 мин).
  - Всё это уже сводится в `providers.dart` (`pc.onListened`, `pc.onNowPlaying`, …).
- **Recs v1 (`recommendation_service.dart`):** `similarTo(seed)` (source similar
  endpoints), `forYou({history, liked, topTracks, topArtists})` → список `RecoRow`
  (ряды на главной), `radioFrom(seed)` (радио-очередь). Ряды строятся прямо из
  сырых similar-эндпоинтов источников — **это и есть источник однообразия v1**.
- **Last.fm (`lastfm_service.dart`):** есть только `updateNowPlaying`/`scrobble`/
  `login`. **Нет** `getSimilar`/`getTopTags`/`getTopArtists`/`getTopTracks`. Ключ —
  **пользовательский** (`prefs['lastfm_key']`), задаётся ради скроббла; для юзеров
  без Last.fm его нет.
- **Лайк:** `toggleLike`/`isLiked`. **Дизлайка нет.** Контекстное меню трека —
  `track_menu.dart` (ListTile'ы). Полноэкранный плеер — `now_playing_screen.dart`
  (`_tools` — ряд кнопок: лайк/скачать/очередь/…).
- **Онбординга/first-run нет.**

---

## 1. Хранилище событий и данных v2 (ключевое решение — см. вопрос Q1)

ТЗ предполагает БД с миграциями. **Её нет.** prefs+JSON не годятся для event log
(тысячи событий, запросы по времени/агрегации, cooldown-выборки). Предлагаю:

**Добавить `sqflite` (+ хелпер миграций).** Лёгкий, нативный SQLite, честные
`onCreate`/`onUpgrade` (= «миграции» из ТЗ), запросы по индексам. Альтернатива —
`drift` (типобезопасно, кодоген) — тяжелее в сборку; `hive`/`isar` — NoSQL, хуже
под аналитические запросы cooldown/агрегации. **Рекомендую sqflite.**

Таблицы (v2 schema, `lib/data/recs/recs_db.dart`):

```sql
-- события воспроизведения (append-only)
events(id INTEGER PK, track_key TEXT, source TEXT, artist TEXT,
       title TEXT, ts INTEGER, dur_ms INTEGER, played_ms INTEGER,
       kind TEXT)            -- start|skip_hard|skip_soft|complete|like|dislike|repeat|queue
CREATE INDEX ix_events_ts ON events(ts);
CREATE INDEX ix_events_track ON events(track_key);

-- дизлайкнутые треки (hard-фильтр)
dislikes(track_key TEXT PK, artist TEXT, ts INTEGER)

-- cooldown: когда трек последний раз звучал в волне
cooldowns(track_key TEXT PK, last_played_ts INTEGER)

-- кэш похожести (Last.fm/SC/…): TTL ~7 дней
similar_cache(cache_key TEXT PK,  -- напр. 'lastfm:track_sim:artist|title'
              payload TEXT, fetched_ts INTEGER)

-- кэш дневных плейлистов
daily_cache(kind TEXT, day TEXT, payload TEXT, PRIMARY KEY(kind, day))

-- снапшот профиля вкуса (артисты/теги, long/short/neg) — денормализованный JSON
profile_snapshot(id INTEGER PK CHECK(id=1), payload TEXT, updated_ts INTEGER)
```

`track_key` — нормализованный ключ дедупа (см. §4), не `Track.uid` (uid источник-
специфичен; ключ должен объединять один трек с YTM и SC).

**Миграции лайков/истории/статов из prefs:** НЕ ломаем v1. `library_controller`
остаётся источником правды для лайков/истории/UI. Recs v2 при первом старте
**однократно импортирует** существующие prefs-данные в `events` (лайки → like-события,
статы → синтетические complete-события), дальше живёт своим event log. Prefs не
удаляем.

---

## 2. Что переиспользуем / добавляем / заменяем

| Область | v1 (есть) | v2 (действие) |
|---|---|---|
| Хранение сигналов | prefs-агрегаты | **+ sqflite event log** (не заменяет prefs) |
| Лайк | `toggleLike` | reuse + **логируем событие** |
| Дизлайк | — | **новый**: таблица + UI (плеер, меню) + экран в настройках |
| Профиль вкуса | `topArtists`/`topTracks` | **новый** `TasteProfile` (long/short/neg, затухание) |
| Кандидаты | `similarTo` (source) | **новый** `CandidateProvider`-интерфейс + реализации; source similar становится одним из провайдеров |
| Last.fm similar/tags | — | **добавить** методы + кэш в `similar_cache` |
| Скоринг/ранжирование | нет (сырые списки) | **новый** `Scorer` + `WaveRanker` (anti-repetition, дедуп, exploration) |
| Радио | `radioFrom` + докрутка в `audio_handler` | **заменяем** движком волны (буфер + real-time петля) |
| Ряды на главной | `forYou` → RecoRow | **переписать** поверх движка (§6), API `RecoRow` сохраняем |
| Дневные плейлисты | «Микс дня» ряд | **новый** генератор + `daily_cache` |
| Онбординг | — | **новый** flow |

Точка сбора событий: в `providers.dart`, где уже висят `pc.onListened`/
`pc.onTrackStarted`/`pc.onScrobble` — добавим `pc.onTrackEnded(track, playedMs, durMs)`
(или используем существующий finalize-момент) → `RecsEventLog.record(...)`.
Классификатор скипа переиспользует уже посчитанные `playedMs`/`durMs`.

---

## 3. Модели/провайдеры (Riverpod)

Новый слой `lib/data/recs/`:
- `recs_db.dart` — sqflite, схема, миграции.
- `event_log.dart` — `RecsEventLog` (record/query), классификатор сигналов (константы весов).
- `taste_profile.dart` — `TasteProfile` (artistWeights/tagWeights, long/short/neg,
  экспоненциальное затухание half-life 30д, инкрементальное обновление, снапшот).
- `candidates/` — `CandidateProvider` + `LastFmProvider`, `SoundCloudRelatedProvider`,
  `YtMusicRadioProvider` (experimental), `LocalHistoryProvider`, `YandexSimilarProvider` (опц.).
- `scorer.dart` — `score(t)` по формуле ТЗ (веса в константах).
- `dedup.dart` — нормализатор ключа + fuzzy (тестируемо).
- `wave_engine.dart` — буфер очереди, real-time петля, настройки характера.
- `daily_playlists.dart` — генератор дневных.
- `recs_providers.dart` — Riverpod-провайдеры, конфиг весов/настроек.

Тяжёлый скоринг (ранжирование большого пула кандидатов) — через `Isolate.run`
с копией профиля+кандидатов (данные простые: списки записей и weight-словари),
результат — отсортированные ключи. DB/сеть — на главном изолейте.

---

## 4. Дедуп (нормализатор ключа) — тестируемо

`normKey(artist, title)`:
- lowercase, trim, схлопнуть пробелы;
- вырезать `(feat. …)`, `(ft. …)`, `[…]`, `(…)`, суффиксы `remaster(ed)`, `live`,
  `radio edit`, годы `(2019)`;
- убрать диакритику/пунктуацию.
- Итог: `artist|title`. Fuzzy (Levenshtein/Jaccard по токенам) — для граничных
  случаев при сравнении кандидатов между собой.

---

## 5. Anti-repetition (лечим болезнь v1)

- **Cooldown:** трек не в волне N дней (default 7), кроме режима «Любимое».
- **Плотность артиста:** не чаще 1 раза в 5 позиций и ≤3 раз за сессию.
- **Дедуп кросс-источников** по `normKey` перед выдачей.
- **Exploration-слоты:** фикс-доля незнакомых артистов (2-hop граф), доля от настройки характера.

---

## 6. Фазы (как в ТЗ) — каждая = коммит, `flutter analyze` чистый

0. **(этот док)** research + design → подтверждение.
1. sqflite + миграции + event log + классификатор + **дизлайк** (UI плеер/меню +
   экран в настройках + hard-фильтр) + импорт prefs → events. Тесты: классификатор.
2. `TasteProfile` (long/short/neg, затухание) + `CandidateProvider`'ы +
   Last.fm similar/tags + `Scorer` + дедуп. Тесты: затухание, скоринг, дедуп, anti-rep.
3. Волна: буфер + real-time петля + настройки характера + UI (кнопка на главной).
4. Ряды на главной v2 (поверх движка, API `RecoRow`).
5. Дневные плейлисты (Плейлист дня, Дежавю; Премьера — см. Q4).
6. Онбординг (жанры → артисты → сид профиля; авто-сид из лайков YTM).
7. (v2.1, опц.) Настроения через Last.fm-теги.

---

## 7. Вопросы и противоречия с ТЗ (нужно согласовать до Фазы 1)

**Q1 (блокер). БД.** В проекте нет БД — только prefs/JSON. ТЗ говорит «в той же БД…
миграции». Предлагаю **добавить `sqflite`** (миграции = onUpgrade). Ок? Или
предпочитаешь `drift`/оставить всё на JSON-файлах (не рекомендую для event log)?

**Q2. Last.fm ключ.** Сейчас ключ — пользовательский (для скроббла) и есть не у
всех. Движок обязан работать без Last.fm-аккаунта, но `getSimilar`/`getTopTags` —
основной граф похожести. Нужен **дефолтный recs-ключ, вшитый в конфиг** (ты писал
«я его добавлю»). Подтверди: кладу `--dart-define=LASTFM_KEY=…` (или const в
`lib/core/config.dart`), отдельно от пользовательских скроббл-кредов. Без ключа —
graceful degradation (только source/SC/YT-провайдеры).

**Q3. YtMusicRadioProvider (InnerTube `next`).** youtube_explode этого не отдаёт;
делаю raw-dio-запрос в стиле InnerTune/ViMusic. Он хрупкий (внутренний API).
Подтверждаю статус **experimental** (за флагом, не блокирует остальные провайдеры) — ок?

**Q4. Премьера (новые релизы).** MusicBrainz (`/release?artist=…`, без ключа) даёт
даты релизов, но матчинг артистов и rate-limit (1 rps) — риск. Предлагаю: Премьеру
**вынести в отдельную под-фазу 5b**, а если MusicBrainz окажется ненадёжным —
отложить и сообщить. Ок так?

**Q5. Настройки характера/настроения — где в UI?** Новый экран «Моя волна» с
переключателями (Любимое/Незнакомое/Популярное + опц. настроение), или чипы на
главной над кнопкой волны? Предпочтение?

**Q6. Радио v1.** Заменяем `radioFrom`/докрутку в `audio_handler` движком волны
полностью, или волна — отдельная кнопка, а старое «радио по артисту/жанру» остаётся?
(Предлагаю: волна — новая сущность, старое радио пока живёт, помечаем как legacy.)

**Q7. Объём фичи vs текущий кэш.** У `Aggregator` уже есть TTL-кэш поиска/резолва —
переиспользую для резолва кандидатов в играбельные треки. Ок?

---

Подтверди Q1–Q7 (или поправь) — и я начинаю Фазу 1.
