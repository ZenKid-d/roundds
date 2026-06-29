/// Результат резолва играбельного потока для трека.
/// URL у YouTube/SoundCloud временный — поэтому держим срок жизни,
/// чтобы плеер мог сделать пере-резолв при истечении.
class PlayableStream {
  final Uri uri;
  final Map<String, String>? headers;
  final DateTime? expiresAt;

  const PlayableStream({
    required this.uri,
    this.headers,
    this.expiresAt,
  });

  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);
}
