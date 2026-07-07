/// Настройки Premium/Boosty. Значения-плейсхолдеры — замени на свои.
library;

/// Ссылка на твою страницу Boosty (кнопка «Оформить на Boosty»).
/// ЗАМЕНИ на реальный адрес, напр. https://boosty.to/roundds.
const String kBoostyUrl = 'https://boosty.to/your-page';

/// Текст цены на экране Premium. ЗАМЕНИ при необходимости.
const String kPremiumPriceLabel = '199 ₽ / месяц';

/// Длительность подписки по одному коду (дней) — для справки и генератора кодов.
const int kSubscriptionDays = 30;

/// Публичный ключ проекта (Ed25519, 32 байта, base64url без паддинга).
/// Приватный ключ хранится ТОЛЬКО у тебя (см. tool/README.md).
/// Чтобы выпустить свою пару ключей — запусти `dart run tool/premium_keygen.dart`
/// и вставь сюда напечатанный публичный ключ.
const String kPremiumPublicKey = '2xCe3CBI2TWKki1AaKc8rjUmOxmphaSCm1GAd_l9CXM';
