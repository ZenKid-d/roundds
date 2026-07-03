# Настройка входа Google для импорта лайков YouTube Music

Импорт лайкнутых треков использует **официальный YouTube Data API v3** и вход
через Google (OAuth). Чтобы вход заработал, нужно один раз создать OAuth-клиент
в Google Cloud — приложение подхватит его по package name + SHA-1.

## Шаги (≈10 минут)

1. Открой **Google Cloud Console** → https://console.cloud.google.com/ →
   создай проект (или выбери существующий).
2. **APIs & Services → Library** → найди **YouTube Data API v3** → **Enable**.
3. **APIs & Services → OAuth consent screen**:
   - User type: **External** → Create.
   - Заполни название приложения и свою почту.
   - На шаге **Test users** добавь **свой** Google-аккаунт (пока проект в
     статусе Testing, входить может только он).
   - Scopes можно не добавлять — приложение запросит `youtube.readonly` само.
4. **APIs & Services → Credentials → Create Credentials → OAuth client ID**:
   - Application type: **Android**
   - Package name: `com.roundds.roundds`
   - SHA-1: `6B:FB:0F:90:79:77:6F:AD:A9:A3:C9:26:DB:E2:B0:27:28:7E:04:2E`
   - Create.

Готово. Никакой `google-services.json` не нужен — `google_sign_in` находит клиент
по совпадению package + SHA-1.

## Как пользоваться
Медиатека → значок импорта → **«Лайки YouTube Music (вход Google)»** → выбери свой
аккаунт → появится плейлист **«YouTube — Мне понравилось»**.

## Если вход проходит, но API отвечает 403/ошибкой доступа
В некоторых конфигурациях Android-клиента не хватает — добавь ещё один
**OAuth client ID типа Web application** (в том же проекте) и скажи мне его
Client ID: пропишу его как `serverClientId` в коде.

## Важно про подпись
Релизы теперь подписываются **выделенным release-ключом** (`roundds-release.jks`,
см. [RELEASING.md](RELEASING.md)), а не debug-ключом. В OAuth-клиент Android
нужно добавить SHA-1 этого ключа:
```
45:F4:2C:F9:56:37:D1:6B:06:DA:CC:C6:7D:AD:ED:0D:1E:79:9E:C0
```
Старый debug-SHA-1 (`6B:FB:0F:90:79:77:6F:AD:A9:A3:C9:26:DB:E2:B0:27:28:7E:04:2E`)
можно оставить — он всё ещё нужен для локальных debug-сборок (`flutter run`).
В один OAuth-клиент можно добавить оба отпечатка.
