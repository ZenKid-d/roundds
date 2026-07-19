import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roundds/data/aggregator.dart';
import 'package:roundds/data/sources/soundcloud_source.dart';
import 'package:roundds/domain/models/source_type.dart';
import 'package:roundds/domain/models/track.dart';
import 'package:roundds/domain/music_source.dart';

/// [SoundcloudSource.goPlusMarker] и [Aggregator.isGoPlusErr] — ранняя детекция
/// пейволла Go+: при отсутствии потока родной источник кидает SourceException со
/// стабильным маркером, агрегатор опознаёт его и идёт в кросс-источник тише
/// (info вместо warn). Тестируем контракт маркера без сети — Dio не нужен, т.к.
/// логика пейволла выведена в чистые функции ([isPaywallStatus], [isGoPlusErr]).
void main() {
  group('SoundcloudSource.goPlusMarker', () {
    test('маркер — непустая строка со стабильным префиксом SC_GO_PLUS', () {
      // Префикс — контракт с агрегатором; текст после двоеточия может меняться.
      expect(SoundcloudSource.goPlusMarker, contains('SC_GO_PLUS'));
      expect(SoundcloudSource.goPlusMarker.split(':').first, 'SC_GO_PLUS');
    });
  });

  group('SoundcloudSource.isPaywallStatus', () {
    test('401/403 от SoundCloud → true (контент за пейволлом)', () {
      final e401 = DioException(
        requestOptions: RequestOptions(path: '/tracks/1'),
        response: Response(
          requestOptions: RequestOptions(path: '/tracks/1'),
          statusCode: 401,
        ),
      );
      final e403 = DioException(
        requestOptions: RequestOptions(path: '/tracks/1'),
        response: Response(
          requestOptions: RequestOptions(path: '/tracks/1'),
          statusCode: 403,
        ),
      );
      expect(SoundcloudSource.isPaywallStatus(e401), isTrue);
      expect(SoundcloudSource.isPaywallStatus(e403), isTrue);
    });

    test('404/500/таймаут → false (не пейволл, а иная ошибка)', () {
      final e404 = DioException(
        requestOptions: RequestOptions(path: '/tracks/1'),
        response: Response(
          requestOptions: RequestOptions(path: '/tracks/1'),
          statusCode: 404,
        ),
      );
      final e500 = DioException(
        requestOptions: RequestOptions(path: '/tracks/1'),
        response: Response(
          requestOptions: RequestOptions(path: '/tracks/1'),
          statusCode: 500,
        ),
      );
      final eTimeout = DioException(
        requestOptions: RequestOptions(path: '/tracks/1'),
        type: DioExceptionType.connectionTimeout,
      );
      expect(SoundcloudSource.isPaywallStatus(e404), isFalse);
      expect(SoundcloudSource.isPaywallStatus(e500), isFalse);
      expect(SoundcloudSource.isPaywallStatus(eTimeout), isFalse);
    });

    test('не DioException → false', () {
      expect(SoundcloudSource.isPaywallStatus(Exception('что угодно')), isFalse);
    });
  });

  group('Aggregator.isGoPlusErr', () {
    const scTrack = Track(
      id: '123',
      title: 'Go+ Exclusive',
      artist: 'Artist',
      source: SourceType.soundcloud,
    );

    test('SourceException с маркером Go+ → true', () {
      final err = SourceException(
        scTrack.source,
        SoundcloudSource.goPlusMarker,
      );
      expect(Aggregator.isGoPlusErr(err), isTrue);
    });

    test('SourceException без маркера (иной сбой SC) → false', () {
      final err = SourceException(scTrack.source, 'нет играбельного транскодинга');
      expect(Aggregator.isGoPlusErr(err), isFalse);
    });

    test('обычное Exception без маркера → false', () {
      expect(Aggregator.isGoPlusErr(Exception('network error')), isFalse);
    });

    test('строка с маркером в произвольном исключении → true', () {
      // Маркер может всплыть в toString() вложенной ошибки — опознаём по
      // стабильному префиксу, где бы он ни оказался.
      expect(
        Aggregator.isGoPlusErr(
          Exception('упало: ${SoundcloudSource.goPlusMarker}'),
        ),
        isTrue,
      );
    });
  });
}
