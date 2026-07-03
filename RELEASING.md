# Roundds — выпуск релизов (CI)

Сборка и публикация APK автоматизированы через GitHub Actions
([.github/workflows/release.yml](.github/workflows/release.yml)). Workflow
собирает release-APK, подписывает его **выделенным release-ключом**
(`roundds-release.jks`) и публикует релиз в публичный репозиторий
**`ZenKid-d/roundds-releases`** — оттуда приложение забирает обновления
([update_service.dart](lib/core/update_service.dart)).

Подпись читается из `android/key.properties` (в гит не коммитится — см.
`.gitignore`). Если файла нет, release подпишется debug-ключом, чтобы
локальный `flutter run --release` работал без ключа.

## ⚠️ Разовая миграция подписи (важно!)

Проект перешёл со старого debug-ключа на новый release-ключ. Последствия:

1. **Google Cloud.** Новый SHA-1 нужно добавить в OAuth-клиент Android
   (иначе вход через Google для импорта лайков YT перестанет работать):
   ```
   45:F4:2C:F9:56:37:D1:6B:06:DA:CC:C6:7D:AD:ED:0D:1E:79:9E:C0
   ```
   Google Cloud Console → APIs & Services → Credentials → OAuth client
   (Android, package `com.roundds.roundds`) → добавить этот SHA-1
   (старый `6B:FB:…` можно оставить или удалить). См.
   [GOOGLE_OAUTH_SETUP.md](GOOGLE_OAUTH_SETUP.md).
2. **Установленные копии.** APK, подписанный новым ключом, **не встанет
   поверх** старой установки (конфликт подписи) — нужна разовая
   переустановка приложения. Дальше обновления снова бесшовные.

Файлы ключа лежат вне репозитория:
`~/roundds-release.jks` и `~/roundds-release.jks.base64`.
**Забэкапь их и пароль в надёжное место** — потеря ключа = снова миграция.

## Разовая настройка (секреты GitHub)

Settings → Secrets and variables → Actions → **New repository secret**:

| Секрет | Значение |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | содержимое `~/roundds-release.jks.base64` (одной строкой) |
| `ANDROID_KEYSTORE_PASSWORD` | пароль хранилища |
| `ANDROID_KEY_ALIAS` | `roundds` |
| `ANDROID_KEY_PASSWORD` | пароль ключа (совпадает с паролем хранилища) |
| `RELEASES_TOKEN` | fine-grained PAT с **Contents: write** на `ZenKid-d/roundds-releases` |

`RELEASES_TOKEN` создаётся в GitHub → Settings → Developer settings →
Fine-grained tokens (обычный `GITHUB_TOKEN` в чужой репозиторий писать не
может).

> Пароль и base64 были показаны при генерации ключа. Если потерял — можно
> перевыпустить ключ (`keytool -genkeypair …`), но тогда снова миграция
> подписи (см. выше).

## Как выпустить релиз

### Вариант A — по тегу (обычный путь)
```bash
# при желании синхронно поднять версию в pubspec.yaml (необязательно —
# workflow всё равно проставит versionName из тега через --build-name)
git tag v1.5.1
git push origin v1.5.1
```
Пуш тега `vX.Y.Z` запускает сборку и публикацию.

### Вариант B — вручную
Actions → **Release** → **Run workflow** → ввести версию `1.5.1` → Run.

## Что делает workflow
1. Ставит Java 17 + Flutter, восстанавливает debug-ключ из секрета.
2. `flutter pub get` + `flutter analyze --no-fatal-infos` (гейт качества —
   релиз не соберётся при ошибках/предупреждениях анализатора).
3. `flutter build apk --release` с `versionName` из тега и `versionCode`,
   вычисленным из semver (`major*10000 + minor*100 + patch`) — монотонно
   растёт, так что Android принимает обновление.
4. Публикует релиз в `roundds-releases` с ассетом `roundds-<version>.apk` и
   changelog из коммитов с предыдущего тега.

## Заметки
- **Версия в теге = версия в APK.** `--build-name` берётся из тега, поэтому
  тег `v1.5.1` гарантированно даёт APK с `versionName 1.5.1` — приложение не
  зациклится на «доступно обновление».
- Flutter в CI запинен на `3.44.4` (как в [SETUP.md](SETUP.md)). Если версия
  недоступна — поменяй `flutter-version` в workflow или переключи на
  `channel: stable`.
- Отдельного CI на каждый push нет по решению — анализ выполняется внутри
  релиз-джобы перед сборкой.
