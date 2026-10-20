# CassettePlayer

Нативный аудиоплеер для macOS с интерфейсом кассетной деки.

## Возможности

- загрузка аудиофайлов и папок перетаскиванием;
- библиотека с просмотром папок и группировкой по исполнителям;
- плейлист, переходы между треками, перемешивание и режимы повтора;
- воспроизведение, пауза, стоп, перемотка и регулировка громкости;
- эквалайзер с сохранением настроек и визуальные индикаторы уровня;
- сменные кассеты и анимация катушек;
- управление медиаклавишами совместимых клавиатур.

Минимальная версия macOS — 13 Ventura.

## Сборка и запуск

1. Установите Xcode или Command Line Tools для Xcode.
2. В терминале перейдите в папку проекта.
3. Выполните `./build_app.sh`.
4. Запустите созданное приложение `CassettePlayer.app`.

Скрипт создаёт локальную ad hoc подпись. При первом запуске macOS может запросить подтверждение приложения. Для медиаклавиш разрешите CassettePlayer доступ в **Системные настройки → Конфиденциальность и безопасность → Мониторинг ввода** и **Универсальный доступ**.

## Добавление музыки

- Перетащите аудиофайл или папку с музыкой на окно плеера.
- Чтобы выбрать папку библиотеки и просматривать её содержимое, откройте панель библиотеки кнопкой в интерфейсе.
- Папка библиотеки и настройки эквалайзера сохраняются локально на этом Mac. Сам плейлист между запусками не сохраняется.

Поддерживаемые контейнеры и кодеки зависят от декодеров, доступных AVFoundation в установленной macOS.

## Перенос на другой Mac

Приложение можно скопировать на другой Mac, но локальные разрешения конфиденциальности и сохранённые настройки туда не переносятся. Из-за ad hoc подписи macOS может показать предупреждение при первом запуске. Для использования медиаклавиш на новом Mac нужно отдельно разрешить мониторинг ввода и Универсальный доступ. Для регулярного распространения приложения потребуется Developer ID подпись и нотарификация Apple.

## HM Remote (iPhone companion)

CassettePlayer now starts a local control API for the planned **HM Remote** iPhone app. Audio continues to play on the Mac; the phone only controls playback and reads track information.

- Bonjour service: `_hmremote._tcp`, advertised as `Mayak-233`
- HTTP port: `8765`
- `POST /api/pair` with JSON `{"code":"123456"}` returns an access token. The temporary six-digit pairing code is shown in the Mac menu bar under **HM Remote**.
- Authenticated `GET /api/state` returns the current track, artist, album, playback state, elapsed time and duration.
- Authenticated `GET /api/artwork` returns embedded artwork or the app's placeholder logo.
- Authenticated `POST /api/command` accepts `{"command":"playPause"}`, `{"command":"next"}`, `{"command":"previous"}`, or `{"command":"seek","seconds":42.5}`.
- Authenticated requests use `Authorization: Bearer <token>`.

The pairing code changes each time CassettePlayer starts. The paired access token is stored in the Mac user's preferences. Keep HM Remote on a trusted local network; the API is intended for local-network use only.
