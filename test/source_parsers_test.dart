import 'package:flutter_test/flutter_test.dart';
import 'package:roundds/core/net/doh_resolver.dart';
import 'package:roundds/data/sources/soundcloud_source.dart';
import 'package:roundds/data/sources/vk_source.dart';
import 'package:roundds/data/sources/yandex_source.dart';
import 'package:roundds/data/sources/youtube_music_source.dart';
import 'package:roundds/domain/models/source_type.dart';
import 'package:roundds/domain/models/track.dart';

/// Тесты парсеров источников на зафиксированных фрагментах ответов.
///
/// Это самый хрупкий код проекта: он разбирает неофициальные схемы
/// YouTube/SoundCloud/Яндекса, которые меняются без предупреждения. Фикстуры
/// ниже — минимальные срезы реальных структур; если сервис сменит разметку,
/// упавший тест укажет, какой именно парсер надо чинить (а не «молча пусто»).
void main() {
  group('YoutubeMusicSource.parseClockDuration', () {
    test('mm:ss', () {
      expect(YoutubeMusicSource.parseClockDuration('3:05'),
          const Duration(seconds: 185));
    });
    test('hh:mm:ss', () {
      expect(YoutubeMusicSource.parseClockDuration('1:02:07'),
          const Duration(seconds: 3727));
    });
    test('null → null', () {
      expect(YoutubeMusicSource.parseClockDuration(null), isNull);
    });
    test('мусор → null', () {
      expect(YoutubeMusicSource.parseClockDuration('abc'), isNull);
      expect(YoutubeMusicSource.parseClockDuration('12345'), isNull);
      expect(YoutubeMusicSource.parseClockDuration('LIVE'), isNull);
    });
  });

  group('YoutubeMusicSource.isMusicUploader', () {
    test('«- Topic» и VEVO → музыка (регистр не важен)', () {
      expect(YoutubeMusicSource.isMusicUploader('Some Artist - Topic'), isTrue);
      expect(YoutubeMusicSource.isMusicUploader('some artist - topic'), isTrue);
      expect(YoutubeMusicSource.isMusicUploader('ArtistVEVO'), isTrue);
      expect(YoutubeMusicSource.isMusicUploader('EminemVEVO'), isTrue);
    });
    test('обычный канал / пусто / null → не музыка', () {
      expect(YoutubeMusicSource.isMusicUploader('Some Channel'), isFalse);
      expect(YoutubeMusicSource.isMusicUploader('Топ 10 приколов'), isFalse);
      expect(YoutubeMusicSource.isMusicUploader(''), isFalse);
      expect(YoutubeMusicSource.isMusicUploader(null), isFalse);
    });
  });

  group('YoutubeMusicSource.dig', () {
    final data = {
      'a': [
        {'b': 42}
      ]
    };
    test('навигация по картам и спискам', () {
      expect(YoutubeMusicSource.dig(data, ['a', 0, 'b']), 42);
    });
    test('выход за границы списка → null', () {
      expect(YoutubeMusicSource.dig(data, ['a', 9, 'b']), isNull);
    });
    test('ключ в не-карте → null', () {
      expect(YoutubeMusicSource.dig(data, ['a', 0, 'b', 'c']), isNull);
    });
  });

  group('YoutubeMusicSource.extractJson', () {
    test('достаёт объект после маркера', () {
      const html = 'foo var ytInitialData = {"a":1,"b":{"c":2}}; bar';
      final j = YoutubeMusicSource.extractJson(html, 'ytInitialData');
      expect(j['a'], 1);
      expect((j['b'] as Map)['c'], 2);
    });
    test('игнорирует скобки внутри строк', () {
      const html = 'x = {"t":"a}b{","n":3}';
      final j = YoutubeMusicSource.extractJson(html, 'x =');
      expect(j['t'], 'a}b{');
      expect(j['n'], 3);
    });
    test('маркер не найден → пусто', () {
      expect(YoutubeMusicSource.extractJson('nothing here', 'ytInitialData'),
          isEmpty);
    });
  });

  group('YoutubeMusicSource.mrlirToTrack (YT Music «Songs»)', () {
    Map<String, dynamic> renderer() => {
          'playlistItemData': {'videoId': 'vid12345678'},
          'flexColumns': [
            {
              'musicResponsiveListItemFlexColumnRenderer': {
                'text': {
                  'runs': [
                    {'text': 'Song Title'}
                  ]
                }
              }
            },
            {
              'musicResponsiveListItemFlexColumnRenderer': {
                'text': {
                  'runs': [
                    {'text': 'Artist Name'},
                    {'text': '3:05'},
                  ]
                }
              }
            },
          ],
          'thumbnail': {
            'musicThumbnailRenderer': {
              'thumbnail': {
                'thumbnails': [
                  {'url': 'https://lh3.googleusercontent.com/x=w60-h60'}
                ]
              }
            }
          },
        };

    test('happy path: id/title/artist/duration/квадратная обложка', () {
      final t = YoutubeMusicSource.mrlirToTrack(renderer())!;
      expect(t.id, 'vid12345678');
      expect(t.title, 'Song Title');
      expect(t.artist, 'Artist Name');
      expect(t.duration, const Duration(seconds: 185));
      // Размер обложки нормализуется к w720-h720.
      expect(t.artworkUrl, contains('w720-h720'));
    });

    test('нет videoId → null', () {
      final r = renderer()..remove('playlistItemData');
      expect(YoutubeMusicSource.mrlirToTrack(r), isNull);
    });

    // Когда фильтр «Songs» пуст, поиск повторяется БЕЗ него, и подпись ряда
    // выглядит иначе: «Video • Канал • 3.2M views • 6:07». Первый ран — тип, а
    // не артист; счётчик просмотров — не артист.
    test('нефильтрованный ряд-видео: тип отбрасывается, артист = канал', () {
      final r = {
        'playlistItemData': {'videoId': 'vidUnfilt01'},
        'flexColumns': [
          {
            'musicResponsiveListItemFlexColumnRenderer': {
              'text': {
                'runs': [
                  {'text': 'Arctic Monkeys - R U Mine?'}
                ]
              }
            }
          },
          {
            'musicResponsiveListItemFlexColumnRenderer': {
              'text': {
                'runs': [
                  {'text': 'Video'},
                  {'text': ' • '},
                  {'text': 'Domino Recording Co'},
                  {'text': ' • '},
                  {'text': '78M views'},
                  {'text': ' • '},
                  {'text': '3:44'},
                ]
              }
            }
          },
        ],
      };
      final t = YoutubeMusicSource.mrlirToTrack(r)!;
      expect(t.artist, 'Domino Recording Co');
      expect(t.artist, isNot('Video'));
      expect(t.duration, const Duration(seconds: 224));
    });

    test('эпизод подкаста (с videoId) отсекается по типу → null', () {
      final r = {
        'playlistItemData': {'videoId': 'episodeVid1'},
        'flexColumns': [
          {
            'musicResponsiveListItemFlexColumnRenderer': {
              'text': {
                'runs': [
                  {'text': 'Some Podcast Episode'}
                ]
              }
            }
          },
          {
            'musicResponsiveListItemFlexColumnRenderer': {
              'text': {
                'runs': [
                  {'text': 'Episode'},
                  {'text': ' • '},
                  {'text': 'Jun 28'},
                ]
              }
            }
          },
        ],
      };
      expect(YoutubeMusicSource.mrlirToTrack(r), isNull);
    });
  });

  group('YoutubeMusicSource.cardShelfToTrack (Top result)', () {
    test('официальный трек из карточки: id/title/artist/duration', () {
      final t = YoutubeMusicSource.cardShelfToTrack({
        'thumbnail': {
          'musicThumbnailRenderer': {
            'thumbnail': {
              'thumbnails': [
                {'url': 'https://i.ytimg.com/vi/VQH8ZTgna3Q/hqdefault.jpg'}
              ]
            }
          }
        },
        'title': {
          'runs': [
            {
              'text': 'R U Mine?',
              'navigationEndpoint': {
                'watchEndpoint': {'videoId': 'VQH8ZTgna3Q'}
              }
            }
          ]
        },
        'subtitle': {
          'runs': [
            {'text': 'Video'},
            {'text': ' • '},
            {'text': 'Arctic Monkeys'},
            {'text': ' • '},
            {'text': '224M views'},
            {'text': ' • '},
            {'text': '3:44'},
          ]
        },
      })!;
      expect(t.id, 'VQH8ZTgna3Q');
      expect(t.title, 'R U Mine?');
      expect(t.artist, 'Arctic Monkeys');
      expect(t.duration, const Duration(seconds: 224));
    });

    test('нет videoId в title → null', () {
      expect(
          YoutubeMusicSource.cardShelfToTrack({
            'title': {
              'runs': [
                {'text': 'No Endpoint'}
              ]
            }
          }),
          isNull);
    });
  });

  group('YoutubeMusicSource.metaFromRuns', () {
    test('формат «Songs» (без типа): артист + длительность', () {
      final m = YoutubeMusicSource.metaFromRuns([
        {'text': 'Arctic Monkeys'},
        {'text': ' • '},
        {'text': 'AM'},
        {'text': ' • '},
        {'text': '3:44'},
      ]);
      expect(m.type, isNull);
      expect(m.artist, 'Arctic Monkeys');
      expect(m.duration, const Duration(seconds: 224));
    });
    test('пустой ряд → артист YouTube, длительность null', () {
      final m = YoutubeMusicSource.metaFromRuns(const []);
      expect(m.artist, 'YouTube');
      expect(m.duration, isNull);
    });
  });

  group('YoutubeMusicSource.panelToTrack (радио/next)', () {
    test('happy path + снятие « - Topic»', () {
      final t = YoutubeMusicSource.panelToTrack({
        'videoId': 'radio123',
        'title': {
          'runs': [
            {'text': 'Radio Track'}
          ]
        },
        'longBylineText': {
          'runs': [
            {'text': 'The Band - Topic'}
          ]
        },
        'lengthText': {
          'runs': [
            {'text': '2:00'}
          ]
        },
      })!;
      expect(t.id, 'radio123');
      expect(t.title, 'Radio Track');
      expect(t.artist, 'The Band');
      expect(t.duration, const Duration(seconds: 120));
    });
  });

  group('YoutubeMusicSource.lockupToTrack + collect (импорт плейлиста)', () {
    Map<String, dynamic> lockup(String id, String title) => {
          'contentId': id,
          'metadata': {
            'lockupMetadataViewModel': {
              'title': {'content': title},
              'metadata': {
                'contentMetadataViewModel': {
                  'metadataRows': [
                    {
                      'metadataParts': [
                        {
                          'text': {'content': 'Playlist Artist'}
                        }
                      ]
                    }
                  ]
                }
              }
            }
          },
          'contentImage': {
            'thumbnailViewModel': {
              'overlays': [
                {
                  'thumbnailBottomOverlayViewModel': {
                    'badges': [
                      {
                        'thumbnailBadgeViewModel': {'text': '3:00'}
                      }
                    ]
                  }
                }
              ]
            }
          },
        };

    test('lockupToTrack разбирает карточку видео', () {
      final t = YoutubeMusicSource.lockupToTrack(lockup('plvid1', 'Song A'))!;
      expect(t.id, 'plvid1');
      expect(t.title, 'Song A');
      expect(t.artist, 'Playlist Artist');
      expect(t.duration, const Duration(seconds: 180));
    });

    test('collect собирает треки и достаёт continuation-токен', () {
      final node = {
        'items': [
          {
            'lockupViewModel': {
              'contentType': 'LOCKUP_CONTENT_TYPE_VIDEO',
              ...lockup('plvid1', 'Song A'),
            }
          },
          {
            'lockupViewModel': {
              'contentType': 'LOCKUP_CONTENT_TYPE_VIDEO',
              ...lockup('plvid2', 'Song B'),
            }
          },
        ],
        'continuations': {
          'continuationCommand': {'token': 'NEXT_PAGE'}
        },
      };
      final out = <Track>[];
      final token = YoutubeMusicSource.collect(node, out, <String>{});
      expect(out.map((t) => t.id).toList(), ['plvid1', 'plvid2']);
      expect(token, 'NEXT_PAGE');
    });

    test('collect дедуплицирует по seen', () {
      final node = {
        'lockupViewModel': {
          'contentType': 'LOCKUP_CONTENT_TYPE_VIDEO',
          ...lockup('dup', 'X'),
        }
      };
      final out = <Track>[];
      final seen = <String>{'dup'};
      YoutubeMusicSource.collect(node, out, seen);
      expect(out, isEmpty);
    });
  });

  group('SoundcloudSource.toTrack', () {
    Map<String, dynamic> raw() => {
          'kind': 'track',
          'id': 12345,
          'title': 'SC Song',
          'user': {'username': 'DJ Test'},
          'artwork_url': 'https://i1.sndcdn.com/artworks-abc-large.jpg',
          'duration': 210000,
          'media': {
            'transcodings': [
              {
                'url': 'https://api/transcode',
                'format': {'protocol': 'progressive'}
              }
            ]
          },
        };

    test('happy path + апскейл обложки + transcodings в extra', () {
      final t = SoundcloudSource.toTrack(raw())!;
      expect(t.id, '12345');
      expect(t.title, 'SC Song');
      expect(t.artist, 'DJ Test');
      expect(t.duration, const Duration(milliseconds: 210000));
      expect(t.artworkUrl, contains('-t500x500'));
      expect((t.extra['transcodings'] as List), hasLength(1));
      expect(t.source, SourceType.soundcloud);
    });

    test('kind != track → null', () {
      final r = raw()..['kind'] = 'playlist';
      expect(SoundcloudSource.toTrack(r), isNull);
    });

    test('без title/user — дефолты', () {
      final t = SoundcloudSource.toTrack({'id': 1, 'kind': 'track'})!;
      expect(t.title, 'Без названия');
      expect(t.artist, 'SoundCloud');
    });
  });

  group('DohResolver.parseAnswers (DoH JSON)', () {
    test('берёт только A-records (type 1), сохраняя порядок', () {
      final ips = DohResolver.parseAnswers({
        'Answer': [
          {'type': 5, 'data': 'cname.example.com'}, // CNAME — отбрасываем
          {'type': 1, 'data': '104.18.0.1'},
          {'type': 1, 'data': '104.18.0.2'},
          {'type': 1, 'data': 'not-an-ip'}, // мусор — отбрасываем
        ]
      });
      expect(ips, ['104.18.0.1', '104.18.0.2']);
    });

    test('нет Answer / не карта → пусто', () {
      expect(DohResolver.parseAnswers({'Status': 0}), isEmpty);
      expect(DohResolver.parseAnswers('nope'), isEmpty);
      expect(DohResolver.parseAnswers(null), isEmpty);
    });
  });

  group('VkSource.toTrack', () {
    Map<String, dynamic> raw() => {
          'id': 456,
          'owner_id': -123,
          'artist': 'Crystal Castles',
          'title': 'Untrust Us',
          'duration': 185,
          'url': 'https://vk.com/stream/index.m3u8?ts=1',
          'album': {
            'thumb': {
              'photo_300': 'https://sun.vk/300.jpg',
              'photo_600': 'https://sun.vk/600.jpg',
            }
          },
        };

    test('happy path: id=owner_id_id, длительность в секундах, обложка, url в extra',
        () {
      final t = VkSource.toTrack(raw())!;
      expect(t.id, '-123_456');
      expect(t.title, 'Untrust Us');
      expect(t.artist, 'Crystal Castles');
      expect(t.duration, const Duration(seconds: 185));
      expect(t.artworkUrl, 'https://sun.vk/600.jpg');
      expect(t.extra['url'], 'https://vk.com/stream/index.m3u8?ts=1');
      expect(t.source, SourceType.vk);
    });

    test('без id → null', () {
      final r = raw()..remove('id');
      expect(VkSource.toTrack(r), isNull);
    });

    test('без artist/title/url — дефолты и пустой url', () {
      final t = VkSource.toTrack({'id': 1, 'owner_id': 2})!;
      expect(t.id, '2_1');
      expect(t.title, 'Без названия');
      expect(t.artist, 'VK Музыка');
      expect(t.extra['url'], '');
      expect(t.artworkUrl, isNull);
    });
  });

  group('YandexSource.toTrack', () {
    test('happy path: артисты через запятую, обложка, альбом', () {
      final t = YandexSource.toTrack({
        'id': 777,
        'title': 'Ya Song',
        'artists': [
          {'name': 'A1'},
          {'name': 'A2'},
        ],
        'albums': [
          {'title': 'Alb', 'coverUri': 'avatars.yandex.net/get/%%'}
        ],
        'durationMs': 180000,
      });
      expect(t.id, '777');
      expect(t.artist, 'A1, A2');
      expect(t.album, 'Alb');
      expect(t.artworkUrl, 'https://avatars.yandex.net/get/400x400');
      expect(t.duration, const Duration(milliseconds: 180000));
      expect(t.source, SourceType.yandex);
    });

    test('без артистов → дефолт', () {
      final t = YandexSource.toTrack({'id': 1, 'title': 'x', 'artists': []});
      expect(t.artist, 'Яндекс Музыка');
    });

    test('albumId кладётся в extra (для страницы альбома)', () {
      final t = YandexSource.toTrack({
        'id': 1,
        'title': 'x',
        'albums': [
          {'id': 555, 'title': 'Alb'}
        ],
      });
      expect(t.extra['albumId'], '555');
    });

    test('без альбома — extra пустой', () {
      final t = YandexSource.toTrack({'id': 1, 'title': 'x'});
      expect(t.extra['albumId'], isNull);
    });
  });

  group('YandexSource.albumTracksFromResult (треклист альбома)', () {
    test('собирает треки из всех томов плоско, по порядку', () {
      final tracks = YandexSource.albumTracksFromResult({
        'title': 'Some Album',
        'volumes': [
          [
            {'id': 1, 'title': 'A'},
            {'id': 2, 'title': 'B'},
          ],
          [
            {'id': 3, 'title': 'C'},
          ],
        ],
      });
      expect(tracks.map((t) => t.id).toList(), ['1', '2', '3']);
      expect(tracks.map((t) => t.title).toList(), ['A', 'B', 'C']);
    });

    test('нет volumes → пусто', () {
      expect(YandexSource.albumTracksFromResult({'title': 'x'}), isEmpty);
      expect(YandexSource.albumTracksFromResult(null), isEmpty);
    });
  });

  group('YandexSource — подпись потока (самая хрупкая часть)', () {
    test('tag извлекает содержимое XML-тега', () {
      const xml = '<root><host>s1.host</host><path>/get</path></root>';
      expect(YandexSource.tag(xml, 'host'), 's1.host');
      expect(YandexSource.tag(xml, 'path'), '/get');
      expect(YandexSource.tag(xml, 'missing'), '');
    });

    test('buildStreamUrl собирает подписанную mp3-ссылку по известной схеме', () {
      final url = YandexSource.buildStreamUrl(
        host: 'h',
        path: '/abc',
        ts: '111',
        s: 'xyz',
      );
      // md5('XGRlBW9FXlekgbPrRHuSiA' + 'abc' + 'xyz') — зафиксировано.
      expect(url,
          'https://h/get-mp3/f9a64526668963e5f6bcfca5348fed38/111/abc');
    });
  });
}
