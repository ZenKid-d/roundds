import 'package:dio/dio.dart';

/// Перевод строк текста на русский (бесплатный публичный эндпоинт Google, без
/// ключа). Результаты кэшируются в памяти.
class TranslationService {
  TranslationService(this._dio);
  final Dio _dio;
  final Map<String, String> _cache = {};

  Future<String?> toRussian(String text) async {
    final t = text.trim();
    if (t.isEmpty) return null;
    final cached = _cache[t];
    if (cached != null) return cached;
    try {
      final r = await _dio.get(
        'https://translate.googleapis.com/translate_a/single',
        queryParameters: {
          'client': 'gtx',
          'sl': 'auto',
          'tl': 'ru',
          'dt': 't',
          'q': t,
        },
      );
      final data = r.data;
      final sb = StringBuffer();
      for (final seg in (data[0] as List)) {
        sb.write((seg as List)[0]);
      }
      final out = sb.toString().trim();
      _cache[t] = out;
      return out;
    } catch (_) {
      return null;
    }
  }
}
