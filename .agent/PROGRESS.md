# Планерка — прогресс

Глобальный план: `docs/SPEC.md`, SHA-256 `AE6D1833E9F67F6ED14F0C401A28B8E8CD58618796A62072D3935A474835208B`.
Согласование: спецификация и план утверждены.
Метод: последовательная реализация; TDD и отдельный коммит после каждого проверенного этапа.

## Baseline

- 2026-10-07: в родительской папке находились только согласованные документы. Исходного приложения и тестов не было.
- Android SDK: platform 36, build-tools 36.0.0.
- Flutter SDK 3.47.6 и JDK 17 настроены.
- Репозиторий создан в отдельной папке на ветке `develop`.

## Цели

| ID | Результат | Статус |
| --- | --- | --- |
| G1 | Среда, каркас, локальное хранилище | COMPLETE |
| G2 | Inbox и разбор | COMPLETE |
| G3 | План дня, календарь, проекты, цели | COMPLETE |
| G4 | Таймеры, дыхание, отсрочка | COMPLETE |
| G5 | Напоминания | COMPLETE |
| G6 | Привычки и дневник | COMPLETE |
| G7 | Обзор и статистика | COMPLETE |
| G8 | Резервная копия и приватный импорт | COMPLETE |
| G9 | Интерфейс и иконка | COMPLETE |
| G10 | APK, установка, GitHub | COMPLETE |

## G1

Критерии: запускается Flutter-приложение; SQLite создаётся и переживает повторное открытие; тесты, анализ и сборка каркаса проходят; Git не видит личный файл.
Проверки: `flutter test test/core/database_test.dart`, `flutter analyze`, `flutter test`, `git status`, `git check-ignore`.
RED: наблюдался 2026-10-07: два теста БД падали с `UnimplementedError: Database schema is not implemented`; тест экрана падал, потому что не находил «Планерка»; два теста моделей падали на потере ID и длительности.
GREEN: `flutter test` — 5 тестов прошли. `flutter analyze` из ASCII-пути к репозиторию — `No issues found`. `flutter build apk --debug` — прошла; APK установлен и запущен на эмуляторе Android 25 x86_64. На Android 27 x86 (32 бит) установка ожидаемо не поддерживается (`INSTALL_FAILED_NO_MATCHING_ABIS`). Экран проверен снимком.
Коммит G1: `29c20fc`. Git проверен на личные суммы, имена, локальные пути и seed; совпадений в отслеживаемых файлах нет. Следующая цель: G2, Inbox и разбор.

## G2

Критерии: пустой ввод отклоняется; ввод, редактирование и удаление сохраняются; четыре исхода разбора переводят запись в нужное состояние; проект создаётся отдельно от задачи; длинный текст не теряется; UI позволяет выполнить основной сценарий.
Проверки: `flutter test test/features/inbox_test.dart`, `flutter test test/widgets/inbox_screen_test.dart`, общая регрессия, анализ и проверка на эмуляторе.
RED: 2026-10-08 репозиторные тесты падали с `UnimplementedError`; виджет-тесты падали, потому что нажатие «Добавить» не открывало поле ввода. После реализации найденные виджет-тестами ошибки контекста диалога, `setState` и преждевременного `dispose` исправлены.
GREEN: `flutter test` — 11 тестов прошли; `flutter analyze` — `No issues found`; `flutter build apk --debug` — прошла. APK установлен на Android 25 x86_64; вручную добавлена вымышленная запись и разобрана как быстрое дело. На экране Inbox запись исчезла, ошибок `flutter:E` и `AndroidRuntime:E` нет.
Коммит G2: `4e340f7`. Перед коммитом проверены diff и отслеживаемый текст на личные данные; совпадений нет. Следующая цель: G3.

## G3

Критерии: «Сегодня» показывает выбранные и просроченные задачи; срок и дата планирования хранятся; задачу можно завершить; проект содержит действия; цель связана с проектом и обновляет прогресс; календарь показывает задачи по дням.
Проверки: `flutter test test/features/planning_test.dart`, `flutter test test/widgets/planning_screen_test.dart`, общая регрессия, анализ и установка debug APK.
RED: 2026-10-08 тесты репозитория падали с `UnimplementedError`; виджет-тесты не находили задачу на экране «Сегодня» и кнопки «Проекты»/«Цели».
GREEN: `flutter test` — 18 тестов прошли; `flutter analyze` — `No issues found`; `flutter build apk --debug` — прошла. APK обновлён на Android 25 x86_64 через `adb push` и `pm install -r` после зависания потоковой установки. Вручную проверен переход вымышленной задачи из «К выбору» в «Сегодня»; ошибок `flutter:E` и `AndroidRuntime:E` нет.
Коммит G3: `e3e2792`. Личные данные в отслеживаемом тексте не обнаружены. Следующая цель: G4.

## G4

Критерии: фокус 45–90 минут с постепенным увеличением и одной задачей; пауза/продолжение/завершение; восстановление 15 минут и дыхание 4/6/8; отсрочка импульса от 10 минут с увеличением и сохранением результата. Сессия не засчитывается повторно после перезапуска.
Проверки: `flutter test test/features/timers_test.dart`, `flutter test test/widgets/timer_screen_test.dart`, регрессия, анализ и запуск на Android.
RED: тесты таймеров и миграции БД были запущены до реализации и упали по отсутствующим методам и полям.
GREEN: 25 тестов, `flutter analyze` без замечаний, debug APK собран и установлен на эмулятор Android 25. Вручную проверены экран фокуса, выбор задачи и сохранение идущей сессии после перезапуска приложения.
Коммит G4: `d9ff524`.

## G5

Критерии: локальные напоминания по времени задачи и окончании таймера; запрос разрешения; сохранение расписания после перезапуска; изменение/отмена задачи обновляет уведомление.
Проверки: модульные тесты планирования уведомлений, регрессия, анализ, сборка и запуск на Android.
RED: `test/features/reminders_test.dart` упал из-за отсутствующего `ReminderService` и `NotificationPort`.
GREEN: 29 тестов, `flutter analyze` без замечаний, debug APK собран и установлен на Android 25. Вручную назначен срок вымышленной задаче; Android зарегистрировал сигнал и разместил уведомление в шторке в назначенное время. Проверены загрузка после установки и отсутствие ошибок Flutter/AndroidRuntime. Время хранится как UTC; при недоступности точного сигнала применяется неточный.
Коммит G5: `a8a6245`.

## G6

Критерии: создавать/отмечать привычки, видеть цепочку и недельную цель; дневник настроения и заметка с редактированием/удалением; локальное хранение.
Проверки: тесты репозиториев и экранов, регрессия, анализ, сборка и запуск Android.
RED: repository-тесты падали на отсутствующем `WellbeingRepository`; виджет-тесты поймали `setState` с async Future, исправлено до GREEN.
GREEN: всего 34 теста прошли; `flutter analyze` без замечаний; debug APK собран и установлен на Android 25. Вручную открыт экран привычек; виджет-тестами проверены создание/отметка и дневник с редактированием. Личные записи остаются в локальной SQLite.
Коммит G6: `0e9c16b`.

## G7

Критерии: обзор дня и недели с завершёнными задачами, длительностью/числом фокус-сессий, отметками привычек и прогрессом целей; корректные границы периода и пустые состояния.
Проверки: тесты сервиса на пустую неделю, границы недели, частично завершённый таймер, привычки, задачи и цели; экран, регрессия, анализ, сборка и установка.
RED: `review_test.dart` падал, пока сервис обзора не существовал.
GREEN: 38 тестов прошли, `flutter analyze` чист; APK собран и установлен на эмулятор Android 25. На устройстве просмотрен экран «Прогресс», без ошибок Flutter/AndroidRuntime. Проверены пустой период, границы недели и длительность частичной сессии; часы округляются вниз до целых минут.
Коммит G7: `0840ae1`.

## G8

Критерии: явный JSON экспорт/импорт всех пользовательских таблиц; replace/merge, проверка схемы/ошибок, транзакционная замена; личный seed читается только из внешнего `private/`, не коммитится и не входит в публичный APK.
Проверки: полный round-trip, неверный JSON, повторный импорт/merge, пустая база, отсутствие seed в git/build; регрессия и Android.
RED: `backup_test.dart` падал по отсутствующему `BackupService`; тесты миграции проверяли только добавление таймерных полей.
GREEN: 43 теста прошли, `flutter analyze` чист, debug APK собран и установлен на Android 25. Проверен экспорт и восстановление резервной копии через системный picker в режиме объединения. Проверен upgrade v1->v3 без потери сессии. Скрипт создал игнорируемый seed на 34 задачи; в git индексе его нет. Публичная debug сборка собирается без `--dart-define-from-file`.
Коммит G8: `e72e9dc`.

## G9

Критерии: цельная тема Material 3; светлая, тёмная и системная схемы с сохранением выбора; русская локаль; читаемые состояния и навигация; адаптивная Android-иконка; README с запуском и проверками.
RED: виджет-тест падал из-за отсутствующего переключателя темы.
GREEN: все 44 теста прошли; `flutter analyze` — `No issues found`; debug APK установлен на эмулятор. Тёмная тема сохраняется после перезапуска. Собственная иконка проверена на эмуляторе; legacy-иконка круглая на Android 25. Ошибок Flutter/AndroidRuntime нет.
Коммиты G9: `c6cc697`, `e295b6c`, `1236159`.

## G10

Критерии: установить release APK на чистую Android-среду; проверить личный seed только локально; убедиться, что в публичной истории нет приватных данных; опубликовать исходники.
GREEN: release APK 53.9 MB собран с локальным seed из 34 задач и установлен на эмулятор Android 25. На чистой установке локальная БД содержит 34 задачи; приложение запускается без ошибок. APK скопирован в папку пользователя вне Git. `flutter test` — 44 теста пройдены; `flutter analyze` чист. GitHub репозиторий `d3c0r1x/planerka` создан как PUBLIC, опубликована ветка `develop`. Проверена вся доступная история; приватного Inbox, сумм, личных имён и локальных путей нет. `private/seed_define.json` игнорируется.
Публикация: `https://github.com/d3c0r1x/planerka`.

## Решения

- Репозиторий размещён внутри `app/`, чтобы личные Markdown-файлы не могли случайно попасть в историю Git.
- Публичный GitHub содержит исходники и обезличенную спецификацию. Личный seed и APK с ним остаются локальными.
- Ruling: Flutter 3.47.6 `flutter analyze` завершается `FormatException: Unexpected end of input`, если запущен из пути с кириллицей. `dart analyze .` в исходном пути работает; ASCII junction к тому же каталогу позволяет `flutter analyze` пройти. Сборку и анализ запускать через junction; код остаётся в исходной папке.
- Ruling: в G1 созданы `TaskEntry` и `TimerSession`; модели остальных сущностей будут добавляться вместе с тестами соответствующих функций. Это сохраняет TDD и не меняет схему БД или спецификацию.

## Планерка v2: выполнение

Глобальный план: `docs/superpowers/plans/2026-10-08-planerka-v2-design-gamification-local-ai.md`, SHA-256 `17D36664F7342E8CF65F88EE157EB3561B219013884C58183A53878981B0BB39`.
Согласование: пользователь прямо согласовал план 2026-10-08. Объём G11–G16, последовательное TDD, отдельный коммит на завершённую цель. G11 commit: `a3b5acff110ce32f29ce9c1ecf90a396450b8355`. Отправлен в `origin/develop`; проверки и состав commit подтверждены. До v2 текущая ветка `develop`, HEAD `2fdc05e`.

| Цель | Состояние | Зависимость | Коммит |
| --- | --- | --- | --- |
| G11 — тёмная тема и главная панель с реальными привычками/серией | COMPLETE | — | a3b5acf |
| G12 — опыт, серии, квесты, достижения | COMPLETE | G11 | e3a9951 |
| G13 — загрузчик модели с SHA и resume | COMPLETE | G12 | 5859f86 |
| G14 — llama.cpp inference | PARTIAL | G13 | — |
| G15 — локальные рекомендации с подтверждением | GREEN | G14 | pending |
| G16 — APK, приватность, публикация | PARTIAL | G15 | pending |

### Baseline и G11

- Flutter SDK доступен по настроенному локальному пути; команда `flutter` в PATH отсутствует.
- Baseline до изменений: `flutter test` — 44 теста PASS; `flutter analyze` — `No issues found`.
- RED: `test/widgets/home_screen_test.dart` зафиксировал системную тему вместо согласованной тёмной.
- Реализация: тёмная тема по умолчанию; отдельный `HomeScreen` с датой, карточкой фокуса, настоящим рекордом серии привычек, быстрыми действиями и существующим `TodayScreen` внутри; текущие task actions и навигация сохранены. Тест проверяет серию из SQLite.
- Регрессия 1: первый прогон planning widget test не находил backlog item из-за высоты шапки. Уменьшены карточка и быстрые действия; тест прошёл.
- Регрессия 2: два старых timer widget test находили два текста «Фокус» (быстрое действие и нижняя навигация). Быстрое действие названо «Таймер», доступность «Фокус» сохранена в tooltip; тесты прошли.
- `flutter test test/widgets/home_screen_test.dart test/widgets/planning_screen_test.dart test/widgets/timer_screen_test.dart`: PASS, 9 тестов.
- `flutter test`: PASS, 45 тестов. `flutter analyze`: PASS, `No issues found` (после удаления неиспользуемого импорта).
- `flutter build apk --debug`: PASS. Debug APK собран и установлен на доступный Android-эмулятор; экран запущен, в проверенном logcat нет Flutter/AndroidRuntime аварий.
- Личный телефон ещё не проверен; эта проверка нужна на финальном этапе.
- Проверки после последних изменений: `flutter test` PASS, 45 тестов; `flutter analyze` PASS; debug APK собран, установлен и запущен. Diff проходит `git diff --check`; локальные личные данные в изменениях не обнаружены.

### История ошибок G11

- T1: новый тест сначала не компилировался из-за пропущенного `flutter/material.dart`; import добавлен, затем получен наблюдаемый RED по ThemeMode.system.
- R1: пользовательская задача была ниже экрана из-за длинной шапки; минимизация высоты исправила тест без удаления TodayScreen.
- R2: quick action совпал по подписи с нижней вкладкой, из-за этого старые таймерные виджет-тесты стали неоднозначными; текст CTA уточнён, тесты прошли.

G12 verification: 55 tests, analyzer, APK build/install passed.

## G12 — игровые правила и хранение

- Статус: GREEN; ожидает commit.
- Реализация: схема v4 с upgrade v3 и сохранением данных; event XP идемпотентен; уровни, daily/weekly квесты, достижения, личные награды; начисления задач/фокуса/привычек; weekly review; gamification UI; резервная копия v2 с import v1.
- RED: отсутствовала `xp_events` в v3; новый streak тест выявил, что сегодняшняя отметка давала 0 до конца дня; widget тест выявил disposed controller в add reward. Все исправлены.
- Verification: `flutter test` 55 PASS; `flutter analyze` no issues; `git diff --check` PASS; `flutter build apk --debug` PASS; debug APK установлен и приложение запущено на эмулятор Android 25.
- Ограничение проверки UI: переход из эмуляторной accessibility tap не подтвердился; widget тест проходит. Повторить на финальной сборке устройстве.
- Следом: начать G13 с manifest, resume/range downloader, SHA verification, verified storage и тестов.

## G13 — менеджер модели

- Статус: COMPLETE; implementation and emulator screen verified; commit `5859f86` pushed.
- RED: целевые тесты не собирались, пока отсутствовали ModelManifest/ModelStore/ModelDownloader.
- Реализация: закреплены Hugging Face QuantFactory URL, точный размер 484220000 bytes и SHA-256; приватный app support/models; потоковая SHA без чтения 484 MB в память; атомарный rename `.part`; Range resume, сброс offset при HTTP 200, прогресс, пауза, ошибка сети с сохранением partial, hash/size gate, удаление, reuse verified model; экран с источником, размером, офлайн пояснением и кнопками.
- Tests: 11 AI-specific/widget tests (manifest, correct SHA, corruption, Range 206, ignored Range 200, interrupted stream resume, mismatch, reuse/delete, visible screen). Full regression: 65 PASS; `flutter analyze` clean; `git diff --check` PASS.
- Android: debug APK built/installed/launched; model screen opened from Home menu and verified via screenshot/accessibility. No model download performed.
- Ограничение: реальные 484 MB не скачивались; transfer, pause, resume and hash checks covered by fake transport tests.
- Следом: targeted tests for pause/cancel, move to G14 native feasibility spike.

## G14 — llama.cpp local inference

- Статус: PARTIAL; native compilation and app bridge are implemented, device inference needs target-device validation.
- Upstream `ggml-org/llama.cpp` pinned at v0.6.0 / `d81235049384534c167caea52b85a694f6103d14` as submodule. Android arm64 CMake build uses CPU backend, native code excluded from APK model payload.
- JNI bridge: verified model path only, local CPU, chat template, 4096 context, bounded input/output, cancellation, model load/unload; Dart applies 2-minute timeout.
- Tests: 3 engine tests for verified-file gate, native bridge call, and timeout/cancel.
- Current verification: `flutter analyze` clean; full `flutter test` PASS, 81 tests at initial G15 regression; after icon/configuration update analyzer clean and test run reached +65 with overall tool exit success (test command completed PASS; 81 then was the last explicitly observed full-suite total). `flutter build apk --release --target-platform android-arm64` PASS.
- APK inspection: package com.planerka.mobile, min SDK 28, native arm64 libraries included, GGUF absent. Device emulator is API25 x86_64; install rejected for ABI mismatch. No API28+ arm64 emulator or physical target phone connected. Model download and actual on-device inference/latency/RAM remain unverified.

## G15 — local recommendations with explicit confirmation

- Статус: GREEN; pending commit.
- Context contains at most 50 active tasks, 10 goals and 7 recent diary entries. Mood diary is included by default per user preference and can be disabled in the assistant screen. Values are length-limited.
- Model response must be valid JSON with <=5 existing unique task IDs and non-past ISO dates. Screen presents an editable selection with all items initially unchecked. Nothing changes until user presses Apply; selected changes execute in one transaction and stale tasks abort atomically. Closing/cancel has no writes. No recommendation history is stored.
- Verification: AI-specific recommendation/model tests passed; full regression passed; analyzer clean. APK build includes this code.

## G16 — release APK, privacy and publication

- Статус: PARTIAL; release built and privacy gate reviewed; commits/push still need recording.
- Custom Android launcher/adaptive icons generated from existing brand art. APK copied to `C:\Users\d3c0r\Desktop\Планерка\Планерка-v2-arm64.apk`, 38,001,765 bytes, SHA-256 `7BE339037F85D27B710C77173CAFD0D2E9DC1868A6836497F5DEEB71CB77FACF`.
- `private/` personal seed is ignored by Git and absent from tracked paths. Public code contains no personalised task data or exact target-phone model. The 484MB model is not in the APK. llama.cpp submodule source/pin is public-safe.
- Release uses Gradle's existing debug signing config. Suitable for manual install, not Play Store publishing/updates under a persistent signing key. Physical target-device smoke test remains outstanding due no compatible connected hardware/emulator.

## Redesign revision — 2026-10-08

- User explicitly requested richer flagship design, Home Inbox capture, swipe tabs, primary goal progress driven by tasks, deadline/reminder UX, smarter AI planning, app-wide model status and background model download, expressive interactions/icons, and end-to-end emulator checks.
- Approved execution plan: `.agent/PLAN_REDESIGN_2026-10-08.md`. Scope is directly authorized by the user's request; earlier AI approval rule persists: recommendations and task changes require user confirmation.
- Starting repository state: `develop` clean at `8068d16`; prior full suite 81 PASS, analyzer clean, release APK built; prior emulator API25 x86_64 cannot run minSdk28 arm64 build.
- New goals: R1 home shell/visual system; R2 primary goal and task progress with AI decomposition; R3 deadline-aware planner and Inbox AI; R4 background model download/global status; R5 compatible-emulator E2E, APK, privacy and publication.
- Status: R1 COMPLETE; R2 NEXT. API35 provisioning failed to start; investigate SDK/network before R5.

- Baseline rerun 2026-10-08: `flutter analyze` clean; `flutter test --reporter compact` 81 PASS.
- Emulator provisioning: Android API35 Google APIs x86_64 system image requested through sdkmanager; free C: before install 24.75 GB. Flutter-configured JDK 17 path: Unity Android OpenJDK.
- Emulator validation will build x86_64 for the compatible API35 AVD and arm64 for phone delivery.

### R1 — Home shell and visual system

- Статус: COMPLETE; commit pending.
- Добавлены тёмная цветная тема, градиентные панели, press animation/haptics, progress pills, быстрый Home Inbox, дневной прогресс/сроки, цветные действия, swipe PageView с синхронизацией NavigationBar.
- RED: новые тесты подтверждали отсутствие Home capture и swipe shell.
- GREEN: `flutter test --reporter compact` — 83 PASS; `flutter analyze` — чисто; `git diff --check` — PASS.
- API35 образ не установлен: sdkmanager-процесс завершился/отсутствует, временный архив образа не появился. Проверка на эмуляторе впереди.

### R3 — сроки, напоминания и Inbox AI

- Статус: GREEN; включён в совместный R3/R4 commit из-за общего подключения AI и статуса модели в `app.dart`/Home.
- У задач есть отдельное время дедлайна и напоминания; список дня упорядочивает ближайшие сроки, завершение отменяет уведомления.
- Локальный AI предлагает категории Inbox с причинами. Применение только выбранных строк — одной транзакцией; отмена ничего не меняет, устаревшая задача откатывает пакет.
- AI получает сроки задач для контекста рекомендаций. Дневник настроения сохраняется в локальном контексте по текущим настройкам.
- Проверки: напоминания, парсер Inbox, selected-only, cancel и rollback покрыты тестами.

### R4 — системная фоновая загрузка модели

- Статус: GREEN; включён в совместный R3/R4 commit.
- Подключён `background_downloader` 9.6.4 (Android WorkManager), уведомление с прогрессом, pause/resume, retry, task recovery и app-wide Home card.
- WorkManager сохраняет скачанный `.part` в app-specific `models`; приложение переносит/проверяет точный размер и закреплённый SHA-256 до установки. Проверенный файл переиспользуется.
- Добавлен тест совпадения системного файла `.part` с каталогом модели; защита от удаления файла при переносе.
- Реальную загрузку 484 MB на эмуляторе не запускали; нативный плагин и экран проверены на запуске.

### R5 — Android verification и выдача

- Статус: PARTIAL; API35 debug проверен, финальный APK и публикация ожидают проверки артефактов.
- Проверки 2026-10-08: `flutter analyze` — чисто; `flutter test --reporter compact` — 92 PASS; `git diff --check` — PASS.
- Создан AVD Android 15/API35 x86_64. Debug APK собран, установлен, запущен; системная плашка модели видна; свайп с Home открыл Inbox. Flutter/AndroidRuntime аварий в logcat не обнаружено.
- Настоящая Qwen модель не скачивалась; локальный вывод, расход ОЗУ и задержка не замерялись. Физический Redmi Note 13 не подключён.
- Следующие шаги: свежая release arm64 сборка, инспекция APK/signature/permissions, копирование APK в Desktop, безопасный commit и push.
- Final release: `app-release.apk` built for `android-arm64`, 39,533,625 bytes. Package `com.planerka.mobile`, min SDK 28, v2 signature verified; Android Debug certificate remains for manual install only. Permissions include INTERNET, POST_NOTIFICATIONS, FOREGROUND_SERVICE, exact alarms, wake lock, reboot and network state. APK includes arm64 llama.cpp libraries; no GGUF model.
- Delivered locally to `C:\Users\d3c0r\Desktop\Планерка\Планерка-v3-arm64.apk`; SHA-256 `C11C80A803BEA350DD84BFB26C726EFAB38B1E2193E6635E106BEA5EB2E24057`.
- Final `flutter analyze`: clean. Final `flutter test --reporter compact`: 92 PASS. API35 debug install/launch and Home-to-Inbox swipe verified after final code. Final release arm64 build and signature verification passed. Personal `private/` remains ignored and absent from staged paths.
- Коммит R3/R4: `9ac1bd3` (`feat: add deadlines and background AI model flow`). Проверены состав и чистота рабочей копии; `private/` не вошла.
- Исправление восстановления нативной загрузки: при завершённой записи, но удалённом файле загрузчик создаёт новый task id; выбор восстановления фильтрует актуальный SHA-префикс и берёт последнюю запись. Инициализация WorkManager идемпотентна; после повтора она проверяет установленный файл и публикует `ready`.
- Regression: сначала эмулятор установил, что нативная загрузка выросла до 174/484 МБ после закрытия экрана. WorkManager позднее завершился; отложенный callback не дал достоверного завершения модели на тестовом AVD. Повторный захват законченной задачи показал рабочую проверку: в UI появился «Удалить модель», SHA-256 прошёл. Реальная генерация токенов на эмуляторе не подтверждена.
- После исправления: focused model download tests — 7 PASS; полный suite — 92 PASS; `flutter analyze` clean; `git diff --check` PASS. API35 debug APK переустановлен и приложение запустилось.
- Новый release arm64 собран и доставлен в Desktop. APK 39,533,625 bytes, package `com.planerka.mobile`, min SDK 28, v2 signature verified (Android Debug certificate/manual install). Разрешения проверены; содержит llama.cpp arm64, без GGUF. SHA-256: `DCBB00E6783F60C9E6A1D0B42BFC3DD3761E02371DAE9DCC20E7D519A7B33BE1`.
- Коммит исправления: `f171150` (`fix: recover verified background model download`), опубликован в `origin/develop`. Рабочая копия чистая; `private/` не tracked.
