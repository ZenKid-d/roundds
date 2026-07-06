import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:roundds/data/spotify_import.dart';

void main() {
  group('SpotifyImportService.extractId', () {
    test('из ссылки playlist', () {
      expect(
        SpotifyImportService.extractId(
            'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M'),
        '37i9dQZF1DXcBWIGoYBM5M',
      );
    });

    test('из ссылки с локалью и ?si', () {
      expect(
        SpotifyImportService.extractId(
            'https://open.spotify.com/intl-ru/album/4aawyAB9vmqN3uQ7FjRGTy?si=ab'),
        '4aawyAB9vmqN3uQ7FjRGTy',
      );
    });

    test('из uri', () {
      expect(
        SpotifyImportService.extractId(
            'spotify:playlist:37i9dQZF1DXcBWIGoYBM5M'),
        '37i9dQZF1DXcBWIGoYBM5M',
      );
    });

    test('голый id', () {
      expect(SpotifyImportService.extractId('37i9dQZF1DXcBWIGoYBM5M'),
          '37i9dQZF1DXcBWIGoYBM5M');
    });

    test('чужая ссылка → null', () {
      expect(SpotifyImportService.extractId('https://youtube.com/watch?v=abc'),
          isNull);
    });
  });

  group('SpotifyImportService.extractType', () {
    test('album', () {
      expect(SpotifyImportService.extractType('https://open.spotify.com/album/x'),
          'album');
    });
    test('playlist по умолчанию', () {
      expect(
          SpotifyImportService.extractType(
              'https://open.spotify.com/playlist/x'),
          'playlist');
    });
  });

  group('SpotifyImportService.parseEmbed', () {
    String htmlWith(Map<String, dynamic> entity) {
      final data = {
        'props': {
          'pageProps': {
            'state': {
              'data': {'entity': entity}
            }
          }
        }
      };
      return '<html><script id="__NEXT_DATA__" type="application/json">'
          '${jsonEncode(data)}</script></html>';
    }

    test('название + запросы «артист трек»', () {
      final html = htmlWith({
        'name': 'My Mix',
        'trackList': [
          {'title': 'Blinding Lights', 'subtitle': 'The Weeknd'},
          {'title': 'Levitating', 'subtitle': 'Dua Lipa, DaBaby'},
          {'title': 'Solo', 'subtitle': ''}, // без артиста — только название
        ],
      });
      final r = SpotifyImportService.parseEmbed(html);
      expect(r.name, 'My Mix');
      expect(r.queries, [
        'The Weeknd Blinding Lights',
        'Dua Lipa, DaBaby Levitating',
        'Solo',
      ]);
    });

    test('нет __NEXT_DATA__ → исключение', () {
      expect(() => SpotifyImportService.parseEmbed('<html></html>'),
          throwsA(isA<SpotifyImportException>()));
    });

    test('пустой трек-лист → исключение', () {
      expect(
        () => SpotifyImportService.parseEmbed(
            htmlWith({'name': 'x', 'trackList': const []})),
        throwsA(isA<SpotifyImportException>()),
      );
    });
  });
}
