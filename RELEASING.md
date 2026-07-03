# Roundds — выпуск релизов (CI)

Сборка и публикация APK автоматизированы через GitHub Actions
([.github/workflows/release.yml](.github/workflows/release.yml)). Workflow
собирает release-APK, подписывает его **тем же debug-ключом**, что и локально,
и публикует релиз в публичный репозиторий **`ZenKid-d/roundds-releases`** —
оттуда приложение забирает обновления
([update_service.dart](lib/core/update_service.dart)).

## Разовая настройка (секреты)

Settings → Secrets and variables → Actions → **New repository secret**:

### 1. `ANDROID_DEBUG_KEYSTORE_BASE64`
База64 твоего локального debug-ключа. Именно он даёт SHA-1
`6B:FB:0F:90:…`, зарегистрированный в Google Cloud для входа, и позволяет
обновлениям вставать поверх уже установленных копий.

```bash
base64 -w0 ~/.android/debug.keystore        # Linux
base64 -i ~/.android/debug.keystore | tr -d '\n'   # macOS
```
Скопируй вывод целиком в значение секрета.

> ⚠️ Debug-ключ — не «безопасный» ключ подписи, но проект и так подписывался
> им (см. `android/app/build.gradle.kts`, `signingConfigs.getByName("debug")`).
> Сохраняем как есть, чтобы не ломать вход Google и цепочку обновлений.

### 2. `RELEASES_TOKEN`
Fine-grained Personal Access Token с доступом к репозиторию
`ZenKid-d/roundds-releases` и правом **Contents: Read and write**
(GitHub → Settings → Developer settings → Fine-grained tokens). Обычный
`GITHUB_TOKEN` не годится — он не может писать в другой репозиторий.

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
