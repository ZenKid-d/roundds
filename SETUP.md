# Roundds — сборка и запуск

Roundds — Android-приложение (Flutter): единый плеер, который проигрывает музыку
из **YouTube Music**, **SoundCloud** и **Яндекс Музыки** ВНУТРИ собственного
плеера, без официальных API.

> ⚠️ **Важно.** Воспроизведение использует неофициальные методы извлечения. Это
> нарушает правила (ToS) этих сервисов и авторские права, может ломаться при их
> обновлениях, а токен Яндекса несёт риск блокировки аккаунта. Приложение **не для
> Google Play** (только установка APK). Ответственность за использование — на вас.

## Текущее состояние (уже сделано)
- ✅ Flutter 3.44.4 установлен в `C:\src\flutter` и добавлен в `PATH`.
- ✅ `flutter doctor` — окружение в порядке, лицензии Android приняты.
- ✅ Платформенная часть `android/` сгенерирована (applicationId `com.roundds.roundds`),
  `AndroidManifest.xml` пропатчен под фоновый плеер (`just_audio_background`).
- ✅ `flutter pub get` выполнен, `flutter analyze` — **без ошибок**.
- ✅ Собран debug-APK: `build/app/outputs/flutter-apk/app-debug.apk`.

## Как запустить
Нужен **Android-таргет** (на машине сейчас только Windows/браузеры — на них это
приложение не идёт, оно под Android).

### Вариант A — физический телефон (рекомендуется для музыки)
1. На телефоне: «Настройки → Для разработчиков → Отладка по USB».
2. Подключить кабелем, разрешить отладку.
3. ```powershell
   flutter devices          # должен появиться телефон
   flutter run              # запуск debug на телефон
   ```
   Либо просто установить готовый APK:
   ```powershell
   flutter install
   # или вручную: adb install build\app\outputs\flutter-apk\app-debug.apk
   ```

### Вариант B — эмулятор
Нужен системный образ AVD (сейчас не установлен):
```powershell
& "$env:LOCALAPPDATA\Android\Sdk\cmdline-tools\latest\bin\sdkmanager.bat" "system-images;android-35;google_apis;x86_64"
& "$env:LOCALAPPDATA\Android\Sdk\cmdline-tools\latest\bin\avdmanager.bat" create avd -n roundds -k "system-images;android-35;google_apis;x86_64" -d pixel_7
flutter emulators --launch roundds
flutter run
```
(требуется аппаратная виртуализация — Hyper-V/WHPX или Intel HAXM.)

## Сборка release-APK
```powershell
flutter build apk --release
# результат: build/app/outputs/flutter-apk/app-release.apk
```

## Подключение источников (в приложении → Настройки)
- **YouTube Music** — работает сразу, ключи не нужны.
- **SoundCloud** — `client_id` определяется автоматически; если перестанет играть,
  в Настройках кнопка «Обновить».
- **Яндекс Музыка** — вставить OAuth-токен аккаунта (Настройки → Яндекс Музыка).
  Токен хранится в защищённом хранилище устройства.

## Проверка (acceptance)
- Открывается главная, боковое меню (☰), лента скроллится.
- Поиск → трек YouTube/SoundCloud **играет внутри приложения**, в фоне, с
  уведомлением; винил крутится и реагирует на паузу; акцент меняется под обложку.
- Очередь и плейлисты создаются и переживают перезапуск.

## Известные хрупкости
- YouTube/SoundCloud: ссылки на поток временные. Если ссылка истекает во время
  игры, плеер сам перерезолвит свежую и продолжит с той же позиции (до 3 попыток
  на трек); при полном отказе источника показывается «Повтор».
- Яндекс — самый хрупкий: при смене схемы подписи `download-info` резолв сломается.
- Шрифт Poppins подгружается через `google_fonts` в рантайме (нужен интернет при
  первом запуске).
