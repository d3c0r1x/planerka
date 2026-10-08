# Планерка — прогресс

Глобальный план: `docs/SPEC.md`, SHA-256 `B37B06074A444ED1921D6B75F2E63F2AF28647658E3F230FE82CE6B98031D2D2`.
Согласование: спецификация подтверждена пользователем 2026-10-08; план G17–G29 подтверждён ранее данным пользователем разрешением «Подтверждаю, делай»; реализация идёт последовательно.
Метод: последовательная реализация; plan-driven TDD и отдельный коммит после каждого проверенного этапа.

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

## R6 — Inbox workflow, goal links and black background

- Статус: GREEN; release APKs built and x86_64 install/launch verified; commit and push pending.
- Quick Inbox triage schedules task for today, rolls unfinished items to current day at app launch/resume, then queues two-hour reminders for remaining daytime slots. Completion cancels reminders.
- Planned triage requests date and time; quick items appear in Today's plan. Projects now show parent tasks and allow child tasks without requiring a linked project record.
- Goal links support multiple primary goals; AI proposes task-goal links for user confirmation. Goal progress draws from linked task/project work.
- Main dark surface and Android system navigation bar use black. Background picker lives in Settings, copies image into app support storage, and applies translucent shells.
- Replace backup retains private seed import marker to avoid reimporting seed rows.
- RED/GREEN: new reminders rollover/cadence, task children, durable background, and revised planning tests added. Focused tests passed. Full `flutter test --reporter expanded`: 97 PASS. `flutter analyze`: No issues. `git diff --check`: PASS.
- Release `android-arm64` APK copied to `C:\Users\d3c0r\Desktop\Планерка\Ритм-дня-arm64.apk`, 41,156,403 bytes, SHA-256 `EFD6012013C1172826D4F17F5EF8DF5958DDA0382A6095E46AAAEEDD2CF8C7E4`.
- Release `android-x64` APK copied to `C:\Users\d3c0r\Desktop\Планерка\Ритм-дня-emulator-x64.apk`, 41,156,403 bytes, SHA-256 `29FB57F24EC20049F31CF677ACEC8E6F2AD42CF4E6562E76F25900464F334EF1`.
- Emulator `emulator-5556` is API35 x86_64. ARM64 install attempt failed by ABI mismatch, then x86_64 release installed successfully and app process launched. Existing logcat contained an older ARM64 mismatch before successful install; no fresh failure was observed after relaunch.
- Personal `private/seed_define.json` remains ignored and absent from tracked files. Real-device Redmi Note 13 inference/background reminder behavior remains unverified.

## Расширение v2 — цели G17–G29

- Состояние: `IN_PROGRESS`; спека и план подтверждены, этапы выполняются по очереди.
- Baseline G17 до новых функций: Flutter 3.47.6 / Dart 3.13.5; `flutter analyze` clean; `flutter test --reporter compact` — 97 PASS; debug APK собран.
- G17–G19 завершены и отправлены; G20 реализован и проходит полную локальную регрессию.
- Очередь: G17–G26 завершены; G27 виджет/статистика; G28 интерфейс; G29 APK/GitHub.
- Формула штрафов и недельной надёжности утверждена пользователем и будет реализована в G26: 100 очков, −10 за подтверждённый штраф, максимум 3 штрафа в неделю, завершённый восстановительный шаг снимает один штраф; XP и уровни не уменьшаются.

### G17 — baseline перед расширением

- Статус: COMPLETE; baseline снят до продуктовых изменений на `b609b26439f8b2150a205d6388196dfe1d09af9c`.
- Flutter SDK найден по `android/local.properties`: `C:\Users\d3c0r\Documents\Codex\tools\flutter`; Flutter 3.47.6, Dart 3.13.5.
- `flutter test --reporter compact`: 97 PASS. `flutter analyze`: No issues found. `flutter build apk --debug`: успешно, `build/app/outputs/flutter-apk/app-debug.apk`.
- Ранее отмеченные 81/97 тестов были до этого baseline; актуальный результат — 97 PASS.
- `git diff --check`: PASS. Следующая цель: G18.

### G18 — экран целей и центральный Inbox-ввод

- Статус: GREEN.
- `PlanningRepository.goalTaskProgress` объединяет прямые связи задач и шаги проекта, считает каждую задачу один раз; пустая цель даёт 0/0.
- На карточке главной цели появился линейный progress bar; экран «Цели» показывает все цели, прогресс шагов и понятное состояние для цели без шагов. Сохранено подтверждение пользователем выбранных AI-шагов.
- В центре нижней навигации добавлена круглая цветная кнопка. Она открывает быстрый ввод и сохраняет только в Inbox, не переключая вкладку. Inbox regression tests переведены на новый поток.
- RED зафиксирован отсутствием метода, индикатора и центральной кнопки. GREEN: focused tests прошли; полный `flutter test --reporter compact` — 102 PASS; `flutter analyze` — No issues found; `git diff --check` — PASS.
- API 35 x86_64: debug APK собран, установлен, процесс запущен. На устройстве центральная кнопка открыла быстрый ввод, тестовая запись появилась в Inbox; экран целей открылся и показал пустое состояние.
- Изменены только код и synthetic тесты; личные файлы и данные в Git не добавлялись. Следующая цель: G19, чистый расчёт восьмидневного графика.

### G19 — чистый расчёт восьмидневного цикла смен

- Статус: GREEN.
- Добавлены типы фаз, команд/руководителей, настроек, статуса дня, исключений и отметки посещения.
- Калькулятор использует календарные даты и floor-modulo; положительное смещение двигает команду вперёд по фазам. Восемь фаз: день, день, предночной отдых, ночь, ночь, восстановление, выходной, выходной. Смещения команд 0/2/4/6.
- Блоки времени используют местные значения: день 08:00–20:00 и дорога 07:00–21:30; ночь 20:00–08:00 следующего дня и дорога 19:00–09:30.
- RED: тесты не собирались из-за отсутствующих типов и калькулятора. GREEN: `shift_cycle_test.dart` — 7 PASS; полный `flutter test --reporter compact` — 109 PASS; `flutter analyze` — No issues found; `git diff --check` — PASS.
- Покрыты все фазы, смещения, дата до якоря, високосный день, переход года, ночной интервал и исключение правой границы диапазона. Следующая цель: G20, миграция SQLite v6→v7 и репозиторий.

### G20 — SQLite и репозиторий четырёх смен

- Статус: GREEN.
- Схема SQLite поднята с v6 до v7; добавлены команды, настройки, исключения дат, изменения цикла и посещаемость с foreign keys, checks и индексами.
- `ShiftRepository` сохраняет четыре команды и настройки одной транзакцией; проверяет ID/смещения; сохраняет прежние записи при обновлении команды; календарь применяет последний сдвиг, исключение даты, ночные интервалы и дорогу.
- Миграция fixture v6 сохранила задачу, цель, запись дневника и XP. Обновлён регрессионный v3 fixture для последовательного перехода к v7.
- RED: тесты выявили отсутствие repository и таблиц; при полной регрессии выявлено устаревшее ожидание `user_version=6` и неверная downgrade fixture — оба исправлены.
- GREEN: focused database/repository/cycle tests — 18 PASS; полный `flutter test --reporter compact` — 117 PASS; `flutter analyze` — No issues found; `git diff --check` — PASS.
- Следующая цель: G21, мастер четырёх смен и календарь на API 35.

### G21 — мастер настройки и календарь смен

- Статус: COMPLETE.
- Добавлен мастер с опорной датой/командой, четырьмя названиями и руководителями, выбором посещаемых смен, палитрой цветов и настройкой дороги/напоминания; восьмидневный предпросмотр показывает чередование команд.
- Календарь открывает настройку, показывает цвет команды, фазу, руководителя и временные блоки дороги/смены, включая переход ночи на следующий день. Есть отметка посещения, исключение или корректировка одной даты и сдвиг цикла для будущих дат.
- RED: widget-тесты проверили создание конфигурации, циклическое смещение опорной смены, предпросмотр, цвета, посещаемость, изменение отдельной даты, сдвиг будущего графика и ночное окончание. Во время написания тестов исправлены ожидания порядка команд (репозиторий сортирует по фазовому смещению) и прокрутка ленивого списка.
- GREEN: G21 tests — 8 PASS; полный `flutter test --reporter compact` — 125 PASS; `flutter analyze` — No issues found; `git diff --check` — PASS. Debug APK android-x64 собран, установлен и запущен на API35 x86_64. Календарь и мастер настройки открыты на эмуляторе; личные данные в настройку не вводились.
- Следующая цель: G23, общий локальный/облачный AI router с явным согласием.

### G22 — режим сна, повторы и сменные уведомления

- Статус: COMPLETE.
- Режим сна сохраняется в app metadata и виден в меню «Ещё» на главной. При включении очищает очередь уведомлений; при выключении сохраняет время пробуждения, быстрые задачи возобновляют повторы через 2 часа. Быстрые задачи переносятся на текущую календарную дату при запуске; сигналы не группируются в backlog.
- Удалена прежняя граница напоминаний 20:00; повторы идут каждые два часа в пределах текущего локального календарного дня, ночной период не порождает ранний повтор на следующий день.
- Календарь смен планирует уведомление перед блоком дороги с настроенным lead time; учитывает посещаемую смену, отмену даты и уже отмеченную посещаемость. Ночные даты используют рассчитанный блок дороги.
- Android-уведомления задач имеют действия «Выполнено» и «Перенести на 2 часа». Обработчик принимает только известные действия, повторно проверяет существование и статус задачи, затем обновляет данные и очередь.
- RED/GREEN: тесты режима сна, отключения и возобновления повторов, сменного напоминания перед дорогой, отмены после отметки посещения и действий уведомления. Полный `flutter test --reporter expanded` — 130 PASS; `flutter analyze` — No issues found; `git diff --check` — PASS.
- Debug APK android-x64 собран, установлен на API35 x86_64; force-stop и повторный запуск прошли без свежих ошибок AndroidRuntime. Уведомления после физического перезапуска эмулятора отдельно не проверены; алгоритм и обработчики покрыты тестами.

### G23 — локальный/облачный AI router и согласие на контекст

- Статус: GREEN.
- Добавлены локальный/cloud router без fallback, HTTPS-only OpenAI-compatible endpoint, отдельное согласие на передачу полей и защищённое хранилище API key через `flutter_secure_storage`. Ключ не сохраняется в SQLite/логах; дневник выключен по умолчанию.
- AI settings доступны с экрана модели. AI-действия Inbox/целей ведут на восстановление модели или настройки при соответствующих ошибках; не показывают сырой `StateError`.
- RED/GREEN: unit-тесты local/cloud routing, блокировки без согласия, отсутствия ключа в SQLite, diary opt-in и восстановления обеих AI-точек. AI-focused tests — 40 PASS; полный `flutter test --reporter expanded` — 137 PASS; `flutter analyze` — чисто; `git diff --check` — PASS.
- API 35 x86_64: экран настроек открыт на эмуляторе; просмотрено окно перечисления передаваемых полей; отказ оставил согласие выключенным. Не вводились endpoint/API key и сетевой вызов не выполнялся. Локальный инференс не проверен: модель не установлена.
- Debug APK установлен и запущен. Следующая цель: G24, временные блоки и планирование с учётом смен.

### G24 — временные блоки и планирование с учётом смен

- Статус: GREEN.
- SQLite поднята с v7 до v8; `scheduled_at` и `estimated_minutes` отделены от `due_at`. Миграции v7→v8 и v6→v8 сохраняют сроки и существующие данные.
- В плане дня можно назначить/изменить дату, время и длительность блока, убрать время; дедлайн показывается отдельно. Календарь показывает временной блок и срок независимо.
- AI-контекст включает выбранные смены с дорогой, существующие временные блоки, длительности, дедлайны, цели и разрешённый дневник настроения. Проверка отклоняет прошлые слоты, пересечения, неизвестные задачи, некорректную длительность и выход за срок; перед применением проверяет актуальные данные повторно.
- RED: новые тесты не компилировались без методов планирования и типизированных busy blocks. GREEN: миграции, дедлайн без потери, сохранение/сброс блока, свободные/занятые AI-слоты, актуальность preview и существующая сменная регрессия покрыты тестами.
- `flutter test --reporter compact` — 142 PASS; `flutter analyze` — No issues found; `git diff --check` — PASS.
- Debug APK android-x64 собран, установлен и запущен на API35 x86_64. Вручную создал синтетическую задачу, назначил пятницу 09:00 на 30 минут; календарь показал блок отдельно. В свежем logcat ошибок Flutter/AndroidRuntime нет.
- Следующая цель: G25, интервью после пропущенной задачи.

### G25 — интервью после пропуска задачи

- Статус: COMPLETE; commit `58983ad` (`feat: review missed tasks with AI`).
- AI-интервью задаёт 2–4 вопроса по одному; ответы остаются в памяти экрана. Причину можно исправить в preview; доступны объяснение и варианты переноса, разбиения, срока или снятия задачи.
- Изменение задачи требует явного подтверждения и применяется один раз. Отмена сохраняет исходные данные. Для avoidable delay предусмотрена отдельная кнопка подтверждения штрафа; остальные категории не запускают штраф.
- Отсутствующая модель открывает экран локальной модели; AI settings остаются доступны для облачной конфигурации. Экран не показывает сырые StateError.
- Добавлен navigator key после обнаружения отсутствующего Navigator в callback-контексте.
- Повторная проверка блокирует пересечения смен/дороги и задач; при анализе и применении сравнивается свежий снимок срока и расписания, чтобы отклонить устаревший preview.
- RED/GREEN: AI review unit tests — 13 PASS; полный `flutter test --reporter expanded` — 166 PASS; `flutter analyze` — No issues found; `git diff --check` — PASS.
- API 35 x86_64: synthetic overdue task показала кнопку «Разобрать пропуск»; переход открыл экран разбора, затем «Установить модель» открыл экран загрузки и проверки SHA. Свежих Flutter/AndroidRuntime ошибок нет. Реальный разговор с Qwen не выполнен: модель не установлена.
- Экран передаёт штраф только при выбранной и подтверждённой причине; G26 callback записывает подтверждённый штраф.
- Commit: `58983ad`.

### G26 — подтверждаемая система штрафов без потери прогресса

- Статус: COMPLETE; commit `6d22712` (`feat: add confirmed accountability tracking`), опубликован в `origin/develop`.
- Добавлены SQLite v9 accountability journal, сервис proposal/confirm, недельные 100 баллов, −10 за штраф, лимит три события и восстановление на 10 баллов.
- Причины кроме avoidable delay отклоняются; отключённая система не выдаёт предложение. Повторный ID/task-week-cause идемпотентен. XP и уровни не меняются.
- Экран показывает недельную надёжность, лимит, историю, переключатель и выбор использованного восстановительного шага.
- Backup JSON сохраняет журнал и настройку ответственности; импорт старого v2 сохраняет локальную настройку.
- G25 callback подключён: только отдельное подтверждение в разборе записывает штраф.
- G26 review findings закрыты: та же восстановительная задача не используется повторно, настройка ответственности сохраняется в backup, route ошибки проверяются в app widget test.
- Verification: accountability/gamification/database/backup widget suites pass; полный `flutter test --reporter expanded` — 168 PASS; `flutter analyze` — No issues found; `git diff --check` — PASS.
- API35 x86_64: v8 DB обновилась до v9 при запуске. Вкладка прогресса открывает экран игрового прогресса, на экране видны надёжность 100 и переключатель. Свежих Flutter/AndroidRuntime ошибок нет.
- Commit: `6d22712`.
- Следующая цель: G27, Android-виджет и статистика смен/ответственности.

### G27 — Android-widget and shift stats

- Status: GREEN; commit after G28 regression to keep goal history clear.
- Added widget snapshot for primary goal, progress, up to three tasks and next selected shift. Widget sync persists data and updates Android AppWidget.
- Native widget shows dark progress card, task taps use cold-start deep links, revalidate status and avoid duplicate XP.
- Progress now reports attended/missed shifts per selected period and weekly reliability. Mood does not affect score.
- RED/GREEN: widget snapshot/sync + review + planning suites: 18 PASS. lutter analyze clean; git diff --check PASS.
- Full test suite attempted three times. Parallel suite hit Windows Dart OOM. Sequential suite hangs in existing pumpAndSettle widget tests for Inbox, focus, goals and flagship navigation. Full regression gate remains blocked.
- API35 emulator-5556: debug APK built, installed and launched; receiver registered. Synthetic cold-start task link completed task. Repeated tap kept same completed_at and XP event count 1. Launcher card visual not verified because no widget instance was pinned.
- Build report in ndroid/build/ excluded from Git after build produced untracked Gradle diagnostic.
- Next: G28 visual polish.

### G27 follow-up — cold start and end-to-end regression

- HomeWidget.initiallyLaunchedFromHomeWidget() called without a platform channel in Flutter tests and kept startup async work pending. Startup now probes the widget channel and returns safely when unavailable.
- Widget updates are decoupled from reminder callback; widget refresh runs on app resume, task capture and completion.
- RED: lagship_navigation_test timed out in pumpAndSettle before guard. GREEN: flagship navigation — 5 PASS; goals screen — 2 PASS; full lutter test --concurrency=1 --reporter compact — 178 PASS; lutter analyze clean.
- Debug APK rebuilt and reinstalled API35. Receiver query found com.planerka.mobile/.PlannerWidgetProvider; app relaunched successfully.
- Follow-up commit recorded separately after G27 main commit.

### G28 — visual polish and branding

- Status: GREEN; commit after release smoke and final repository audit.
- Updated application and widget labels to Ритм дня; aapt confirms application-label Ритм дня. Existing launcher assets are colorful adaptive PNG icons and remain unchanged.
- Dark theme uses black main surface, colored accent palette and progress cards. Home, Inbox, focus, goals and navigation flows passed focused UI suites (15 PASS); goal screen 2 PASS.
- API35 x86_64: app launch checked with system font scales 1.0 and 1.3; no crash observed. Release APK installs successfully on API35 emulator.
- Full lutter test --concurrency=1 --reporter compact: 178 PASS; lutter analyze: clean.
- UI audit of every screen/large-font screenshot and pinned widget placement not completed; emulator automation verified startup/provider and deep link, not pixel layout.
- G28 minimum covered for app label/theme/UI suite; detailed visual screenshots remain a limitation.
- Next: G29 final delivery audit.

### G29 — final Android delivery audit

- Status: PARTIAL; APK and source checks pass; cannot call delivery complete because current signing key is Debug and physical Redmi Note 13 / launcher visual / every integration screen not verified.
- Full lutter test --concurrency=1 --reporter compact: 178 PASS. lutter analyze: clean. Focused widget+review+planning: 18 PASS; final widget/navigation focused: 13 PASS. git diff --check: clean.
- API35 x86_64 debug installed, receiver registered; cold-start task completion and duplicate prevention verified. Release arm64 APK installed and started. Font scales 1.0 and 1.3 app launch verified.
- Release APK: C:\Users\d3c0r\Desktop\Планерка\Ритм-дня-arm64.apk; 41,195,766 bytes; package com.planerka.mobile; min SDK 28, target SDK 36; ARM64 llama native library; no GGUF or seed entries found. SHA-256 A8AE7E8084EC71B46FDE0A0F8FD8A0DA95B8BC562A1405C5F032E67FEB9E5B65.
- Signature verified with APK v2 but certificate is Android Debug (f57d3dc1de2817b369f4553628215ef65359c4f016a6c85ef1ae5870be4425a). APK is suitable for manual install/testing only, not Play Store. No user release key was available; do not use debug cert for public release.
- Manifest label now Ритм дня; G28 commit d74b88f pushed before final APK. G27 commits 79c024, 155fbde, 8e07632 pushed. Existing private directory remains ignored; worktree clean.
- Redmi Note 13 physical device unavailable: NOT_RUN. Airplane mode and visual widget placement not exercised. Cloud is disabled unless configured and agreed, existing tests cover no-consent route.
- Do not create GitHub Release until proper release signing key and full smoke scenario are available. Source commits pushed to develop.

### G29 — повторный финальный аудит (продолжение)

- Исправлена очистка завершённой background_downloader передачи: после установленной модели удалённая/перемещённая временная задача не блокирует повторную загрузку; при retry создаётся новый task ID и очищается stale record.
- Qwen3 `/no_think` и очистка `<think>` проверены тестами; полный набор тестов выполнялся после этих исправлений (ожидается финальный итог процесса).
- API35 x86_64: повторная загрузка фактически стартовала, прогресс показал 136/484 МБ; SHA-256 проверка завершилась, экран предложил открыть помощника. Передача/установка модели больше не теряется после старого complete-task.
- Ветка локальной подписи подготовлена: отдельный release keystore и key.properties локальны и игнорируются Git; `docs/ANDROID_RELEASE.md` описывает сборку. Публичная публикация APK пока запрещена до финального сборочного/подписного/приватностного аудита и реального упражнения помощника.
- Ограничение среды: параллельная Gradle/Dart нагрузка привела к Windows VirtualAlloc 1455 и Gradle daemon с Xmx8G; сборку следует повторить с одним ABI за раз после остановки собственных тестовых Flutter процессов.
# Планерка — прогресс

Глобальный план: `docs/SPEC.md`, SHA-256 `B37B06074A444ED1921D6B75F2E63F2AF28647658E3F230FE82CE6B98031D2D2`.
Согласование: спецификация подтверждена пользователем 2026-10-08; план G17–G29 подтверждён ранее данным пользователем разрешением «Подтверждаю, делай»; реализация идёт последовательно.
Метод: последовательная реализация; plan-driven TDD и отдельный коммит после каждого проверенного этапа.

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

## R6 — Inbox workflow, goal links and black background

- Статус: GREEN; release APKs built and x86_64 install/launch verified; commit and push pending.
- Quick Inbox triage schedules task for today, rolls unfinished items to current day at app launch/resume, then queues two-hour reminders for remaining daytime slots. Completion cancels reminders.
- Planned triage requests date and time; quick items appear in Today's plan. Projects now show parent tasks and allow child tasks without requiring a linked project record.
- Goal links support multiple primary goals; AI proposes task-goal links for user confirmation. Goal progress draws from linked task/project work.
- Main dark surface and Android system navigation bar use black. Background picker lives in Settings, copies image into app support storage, and applies translucent shells.
- Replace backup retains private seed import marker to avoid reimporting seed rows.
- RED/GREEN: new reminders rollover/cadence, task children, durable background, and revised planning tests added. Focused tests passed. Full `flutter test --reporter expanded`: 97 PASS. `flutter analyze`: No issues. `git diff --check`: PASS.
- Release `android-arm64` APK copied to `C:\Users\d3c0r\Desktop\Планерка\Ритм-дня-arm64.apk`, 41,156,403 bytes, SHA-256 `EFD6012013C1172826D4F17F5EF8DF5958DDA0382A6095E46AAAEEDD2CF8C7E4`.
- Release `android-x64` APK copied to `C:\Users\d3c0r\Desktop\Планерка\Ритм-дня-emulator-x64.apk`, 41,156,403 bytes, SHA-256 `29FB57F24EC20049F31CF677ACEC8E6F2AD42CF4E6562E76F25900464F334EF1`.
- Emulator `emulator-5556` is API35 x86_64. ARM64 install attempt failed by ABI mismatch, then x86_64 release installed successfully and app process launched. Existing logcat contained an older ARM64 mismatch before successful install; no fresh failure was observed after relaunch.
- Personal `private/seed_define.json` remains ignored and absent from tracked files. Real-device Redmi Note 13 inference/background reminder behavior remains unverified.

## Расширение v2 — цели G17–G29

- Состояние: `IN_PROGRESS`; спека и план подтверждены, этапы выполняются по очереди.
- Baseline G17 до новых функций: Flutter 3.47.6 / Dart 3.13.5; `flutter analyze` clean; `flutter test --reporter compact` — 97 PASS; debug APK собран.
- G17–G19 завершены и отправлены; G20 реализован и проходит полную локальную регрессию.
- Очередь: G17–G26 завершены; G27 виджет/статистика; G28 интерфейс; G29 APK/GitHub.
- Формула штрафов и недельной надёжности утверждена пользователем и будет реализована в G26: 100 очков, −10 за подтверждённый штраф, максимум 3 штрафа в неделю, завершённый восстановительный шаг снимает один штраф; XP и уровни не уменьшаются.

### G17 — baseline перед расширением

- Статус: COMPLETE; baseline снят до продуктовых изменений на `b609b26439f8b2150a205d6388196dfe1d09af9c`.
- Flutter SDK найден по `android/local.properties`: `C:\Users\d3c0r\Documents\Codex\tools\flutter`; Flutter 3.47.6, Dart 3.13.5.
- `flutter test --reporter compact`: 97 PASS. `flutter analyze`: No issues found. `flutter build apk --debug`: успешно, `build/app/outputs/flutter-apk/app-debug.apk`.
- Ранее отмеченные 81/97 тестов были до этого baseline; актуальный результат — 97 PASS.
- `git diff --check`: PASS. Следующая цель: G18.

### G18 — экран целей и центральный Inbox-ввод

- Статус: GREEN.
- `PlanningRepository.goalTaskProgress` объединяет прямые связи задач и шаги проекта, считает каждую задачу один раз; пустая цель даёт 0/0.
- На карточке главной цели появился линейный progress bar; экран «Цели» показывает все цели, прогресс шагов и понятное состояние для цели без шагов. Сохранено подтверждение пользователем выбранных AI-шагов.
- В центре нижней навигации добавлена круглая цветная кнопка. Она открывает быстрый ввод и сохраняет только в Inbox, не переключая вкладку. Inbox regression tests переведены на новый поток.
- RED зафиксирован отсутствием метода, индикатора и центральной кнопки. GREEN: focused tests прошли; полный `flutter test --reporter compact` — 102 PASS; `flutter analyze` — No issues found; `git diff --check` — PASS.
- API 35 x86_64: debug APK собран, установлен, процесс запущен. На устройстве центральная кнопка открыла быстрый ввод, тестовая запись появилась в Inbox; экран целей открылся и показал пустое состояние.
- Изменены только код и synthetic тесты; личные файлы и данные в Git не добавлялись. Следующая цель: G19, чистый расчёт восьмидневного графика.

### G19 — чистый расчёт восьмидневного цикла смен

- Статус: GREEN.
- Добавлены типы фаз, команд/руководителей, настроек, статуса дня, исключений и отметки посещения.
- Калькулятор использует календарные даты и floor-modulo; положительное смещение двигает команду вперёд по фазам. Восемь фаз: день, день, предночной отдых, ночь, ночь, восстановление, выходной, выходной. Смещения команд 0/2/4/6.
- Блоки времени используют местные значения: день 08:00–20:00 и дорога 07:00–21:30; ночь 20:00–08:00 следующего дня и дорога 19:00–09:30.
- RED: тесты не собирались из-за отсутствующих типов и калькулятора. GREEN: `shift_cycle_test.dart` — 7 PASS; полный `flutter test --reporter compact` — 109 PASS; `flutter analyze` — No issues found; `git diff --check` — PASS.
- Покрыты все фазы, смещения, дата до якоря, високосный день, переход года, ночной интервал и исключение правой границы диапазона. Следующая цель: G20, миграция SQLite v6→v7 и репозиторий.

### G20 — SQLite и репозиторий четырёх смен

- Статус: GREEN.
- Схема SQLite поднята с v6 до v7; добавлены команды, настройки, исключения дат, изменения цикла и посещаемость с foreign keys, checks и индексами.
- `ShiftRepository` сохраняет четыре команды и настройки одной транзакцией; проверяет ID/смещения; сохраняет прежние записи при обновлении команды; календарь применяет последний сдвиг, исключение даты, ночные интервалы и дорогу.
- Миграция fixture v6 сохранила задачу, цель, запись дневника и XP. Обновлён регрессионный v3 fixture для последовательного перехода к v7.
- RED: тесты выявили отсутствие repository и таблиц; при полной регрессии выявлено устаревшее ожидание `user_version=6` и неверная downgrade fixture — оба исправлены.
- GREEN: focused database/repository/cycle tests — 18 PASS; полный `flutter test --reporter compact` — 117 PASS; `flutter analyze` — No issues found; `git diff --check` — PASS.
- Следующая цель: G21, мастер четырёх смен и календарь на API 35.

### G21 — мастер настройки и календарь смен

- Статус: COMPLETE.
- Добавлен мастер с опорной датой/командой, четырьмя названиями и руководителями, выбором посещаемых смен, палитрой цветов и настройкой дороги/напоминания; восьмидневный предпросмотр показывает чередование команд.
- Календарь открывает настройку, показывает цвет команды, фазу, руководителя и временные блоки дороги/смены, включая переход ночи на следующий день. Есть отметка посещения, исключение или корректировка одной даты и сдвиг цикла для будущих дат.
- RED: widget-тесты проверили создание конфигурации, циклическое смещение опорной смены, предпросмотр, цвета, посещаемость, изменение отдельной даты, сдвиг будущего графика и ночное окончание. Во время написания тестов исправлены ожидания порядка команд (репозиторий сортирует по фазовому смещению) и прокрутка ленивого списка.
- GREEN: G21 tests — 8 PASS; полный `flutter test --reporter compact` — 125 PASS; `flutter analyze` — No issues found; `git diff --check` — PASS. Debug APK android-x64 собран, установлен и запущен на API35 x86_64. Календарь и мастер настройки открыты на эмуляторе; личные данные в настройку не вводились.
- Следующая цель: G23, общий локальный/облачный AI router с явным согласием.

### G22 — режим сна, повторы и сменные уведомления

- Статус: COMPLETE.
- Режим сна сохраняется в app metadata и виден в меню «Ещё» на главной. При включении очищает очередь уведомлений; при выключении сохраняет время пробуждения, быстрые задачи возобновляют повторы через 2 часа. Быстрые задачи переносятся на текущую календарную дату при запуске; сигналы не группируются в backlog.
- Удалена прежняя граница напоминаний 20:00; повторы идут каждые два часа в пределах текущего локального календарного дня, ночной период не порождает ранний повтор на следующий день.
- Календарь смен планирует уведомление перед блоком дороги с настроенным lead time; учитывает посещаемую смену, отмену даты и уже отмеченную посещаемость. Ночные даты используют рассчитанный блок дороги.
- Android-уведомления задач имеют действия «Выполнено» и «Перенести на 2 часа». Обработчик принимает только известные действия, повторно проверяет существование и статус задачи, затем обновляет данные и очередь.
- RED/GREEN: тесты режима сна, отключения и возобновления повторов, сменного напоминания перед дорогой, отмены после отметки посещения и действий уведомления. Полный `flutter test --reporter expanded` — 130 PASS; `flutter analyze` — No issues found; `git diff --check` — PASS.
- Debug APK android-x64 собран, установлен на API35 x86_64; force-stop и повторный запуск прошли без свежих ошибок AndroidRuntime. Уведомления после физического перезапуска эмулятора отдельно не проверены; алгоритм и обработчики покрыты тестами.

### G23 — локальный/облачный AI router и согласие на контекст

- Статус: GREEN.
- Добавлены локальный/cloud router без fallback, HTTPS-only OpenAI-compatible endpoint, отдельное согласие на передачу полей и защищённое хранилище API key через `flutter_secure_storage`. Ключ не сохраняется в SQLite/логах; дневник выключен по умолчанию.
- AI settings доступны с экрана модели. AI-действия Inbox/целей ведут на восстановление модели или настройки при соответствующих ошибках; не показывают сырой `StateError`.
- RED/GREEN: unit-тесты local/cloud routing, блокировки без согласия, отсутствия ключа в SQLite, diary opt-in и восстановления обеих AI-точек. AI-focused tests — 40 PASS; полный `flutter test --reporter expanded` — 137 PASS; `flutter analyze` — чисто; `git diff --check` — PASS.
- API 35 x86_64: экран настроек открыт на эмуляторе; просмотрено окно перечисления передаваемых полей; отказ оставил согласие выключенным. Не вводились endpoint/API key и сетевой вызов не выполнялся. Локальный инференс не проверен: модель не установлена.
- Debug APK установлен и запущен. Следующая цель: G24, временные блоки и планирование с учётом смен.

### G24 — временные блоки и планирование с учётом смен

- Статус: GREEN.
- SQLite поднята с v7 до v8; `scheduled_at` и `estimated_minutes` отделены от `due_at`. Миграции v7→v8 и v6→v8 сохраняют сроки и существующие данные.
- В плане дня можно назначить/изменить дату, время и длительность блока, убрать время; дедлайн показывается отдельно. Календарь показывает временной блок и срок независимо.
- AI-контекст включает выбранные смены с дорогой, существующие временные блоки, длительности, дедлайны, цели и разрешённый дневник настроения. Проверка отклоняет прошлые слоты, пересечения, неизвестные задачи, некорректную длительность и выход за срок; перед применением проверяет актуальные данные повторно.
- RED: новые тесты не компилировались без методов планирования и типизированных busy blocks. GREEN: миграции, дедлайн без потери, сохранение/сброс блока, свободные/занятые AI-слоты, актуальность preview и существующая сменная регрессия покрыты тестами.
- `flutter test --reporter compact` — 142 PASS; `flutter analyze` — No issues found; `git diff --check` — PASS.
- Debug APK android-x64 собран, установлен и запущен на API35 x86_64. Вручную создал синтетическую задачу, назначил пятницу 09:00 на 30 минут; календарь показал блок отдельно. В свежем logcat ошибок Flutter/AndroidRuntime нет.
- Следующая цель: G25, интервью после пропущенной задачи.

### G25 — интервью после пропуска задачи

- Статус: COMPLETE; commit `58983ad` (`feat: review missed tasks with AI`).
- AI-интервью задаёт 2–4 вопроса по одному; ответы остаются в памяти экрана. Причину можно исправить в preview; доступны объяснение и варианты переноса, разбиения, срока или снятия задачи.
- Изменение задачи требует явного подтверждения и применяется один раз. Отмена сохраняет исходные данные. Для avoidable delay предусмотрена отдельная кнопка подтверждения штрафа; остальные категории не запускают штраф.
- Отсутствующая модель открывает экран локальной модели; AI settings остаются доступны для облачной конфигурации. Экран не показывает сырые StateError.
- Добавлен navigator key после обнаружения отсутствующего Navigator в callback-контексте.
- Повторная проверка блокирует пересечения смен/дороги и задач; при анализе и применении сравнивается свежий снимок срока и расписания, чтобы отклонить устаревший preview.
- RED/GREEN: AI review unit tests — 13 PASS; полный `flutter test --reporter expanded` — 166 PASS; `flutter analyze` — No issues found; `git diff --check` — PASS.
- API 35 x86_64: synthetic overdue task показала кнопку «Разобрать пропуск»; переход открыл экран разбора, затем «Установить модель» открыл экран загрузки и проверки SHA. Свежих Flutter/AndroidRuntime ошибок нет. Реальный разговор с Qwen не выполнен: модель не установлена.
- Экран передаёт штраф только при выбранной и подтверждённой причине; G26 callback записывает подтверждённый штраф.
- Commit: `58983ad`.

### G26 — подтверждаемая система штрафов без потери прогресса

- Статус: COMPLETE; commit `6d22712` (`feat: add confirmed accountability tracking`), опубликован в `origin/develop`.
- Добавлены SQLite v9 accountability journal, сервис proposal/confirm, недельные 100 баллов, −10 за штраф, лимит три события и восстановление на 10 баллов.
- Причины кроме avoidable delay отклоняются; отключённая система не выдаёт предложение. Повторный ID/task-week-cause идемпотентен. XP и уровни не меняются.
- Экран показывает недельную надёжность, лимит, историю, переключатель и выбор использованного восстановительного шага.
- Backup JSON сохраняет журнал и настройку ответственности; импорт старого v2 сохраняет локальную настройку.
- G25 callback подключён: только отдельное подтверждение в разборе записывает штраф.
- G26 review findings закрыты: та же восстановительная задача не используется повторно, настройка ответственности сохраняется в backup, route ошибки проверяются в app widget test.
- Verification: accountability/gamification/database/backup widget suites pass; полный `flutter test --reporter expanded` — 168 PASS; `flutter analyze` — No issues found; `git diff --check` — PASS.
- API35 x86_64: v8 DB обновилась до v9 при запуске. Вкладка прогресса открывает экран игрового прогресса, на экране видны надёжность 100 и переключатель. Свежих Flutter/AndroidRuntime ошибок нет.
- Commit: `6d22712`.
- Следующая цель: G27, Android-виджет и статистика смен/ответственности.

### G27 — Android-widget and shift stats

- Status: GREEN; commit after G28 regression to keep goal history clear.
- Added widget snapshot for primary goal, progress, up to three tasks and next selected shift. Widget sync persists data and updates Android AppWidget.
- Native widget shows dark progress card, task taps use cold-start deep links, revalidate status and avoid duplicate XP.
- Progress now reports attended/missed shifts per selected period and weekly reliability. Mood does not affect score.
- RED/GREEN: widget snapshot/sync + review + planning suites: 18 PASS. lutter analyze clean; git diff --check PASS.
- Full test suite attempted three times. Parallel suite hit Windows Dart OOM. Sequential suite hangs in existing pumpAndSettle widget tests for Inbox, focus, goals and flagship navigation. Full regression gate remains blocked.
- API35 emulator-5556: debug APK built, installed and launched; receiver registered. Synthetic cold-start task link completed task. Repeated tap kept same completed_at and XP event count 1. Launcher card visual not verified because no widget instance was pinned.
- Build report in ndroid/build/ excluded from Git after build produced untracked Gradle diagnostic.
- Next: G28 visual polish.

### G27 follow-up — cold start and end-to-end regression

- HomeWidget.initiallyLaunchedFromHomeWidget() called without a platform channel in Flutter tests and kept startup async work pending. Startup now probes the widget channel and returns safely when unavailable.
- Widget updates are decoupled from reminder callback; widget refresh runs on app resume, task capture and completion.
- RED: lagship_navigation_test timed out in pumpAndSettle before guard. GREEN: flagship navigation — 5 PASS; goals screen — 2 PASS; full lutter test --concurrency=1 --reporter compact — 178 PASS; lutter analyze clean.
- Debug APK rebuilt and reinstalled API35. Receiver query found com.planerka.mobile/.PlannerWidgetProvider; app relaunched successfully.
- Follow-up commit recorded separately after G27 main commit.

### G28 — visual polish and branding

- Status: GREEN; commit after release smoke and final repository audit.
- Updated application and widget labels to Ритм дня; aapt confirms application-label Ритм дня. Existing launcher assets are colorful adaptive PNG icons and remain unchanged.
- Dark theme uses black main surface, colored accent palette and progress cards. Home, Inbox, focus, goals and navigation flows passed focused UI suites (15 PASS); goal screen 2 PASS.
- API35 x86_64: app launch checked with system font scales 1.0 and 1.3; no crash observed. Release APK installs successfully on API35 emulator.
- Full lutter test --concurrency=1 --reporter compact: 178 PASS; lutter analyze: clean.
- UI audit of every screen/large-font screenshot and pinned widget placement not completed; emulator automation verified startup/provider and deep link, not pixel layout.
- G28 minimum covered for app label/theme/UI suite; detailed visual screenshots remain a limitation.
- Next: G29 final delivery audit.

### G29 — final Android delivery audit

- Status: PARTIAL; APK and source checks pass; cannot call delivery complete because current signing key is Debug and physical Redmi Note 13 / launcher visual / every integration screen not verified.
- Full lutter test --concurrency=1 --reporter compact: 178 PASS. lutter analyze: clean. Focused widget+review+planning: 18 PASS; final widget/navigation focused: 13 PASS. git diff --check: clean.
- API35 x86_64 debug installed, receiver registered; cold-start task completion and duplicate prevention verified. Release arm64 APK installed and started. Font scales 1.0 and 1.3 app launch verified.
- Release APK: C:\Users\d3c0r\Desktop\Планерка\Ритм-дня-arm64.apk; 41,195,766 bytes; package com.planerka.mobile; min SDK 28, target SDK 36; ARM64 llama native library; no GGUF or seed entries found. SHA-256 A8AE7E8084EC71B46FDE0A0F8FD8A0DA95B8BC562A1405C5F032E67FEB9E5B65.
- Signature verified with APK v2 but certificate is Android Debug (f57d3dc1de2817b369f4553628215ef65359c4f016a6c85ef1ae5870be4425a). APK is suitable for manual install/testing only, not Play Store. No user release key was available; do not use debug cert for public release.
- Manifest label now Ритм дня; G28 commit d74b88f pushed before final APK. G27 commits 79c024, 155fbde, 8e07632 pushed. Existing private directory remains ignored; worktree clean.
- Redmi Note 13 physical device unavailable: NOT_RUN. Airplane mode and visual widget placement not exercised. Cloud is disabled unless configured and agreed, existing tests cover no-consent route.
- Do not create GitHub Release until proper release signing key and full smoke scenario are available. Source commits pushed to develop.

### G29 — повторный финальный аудит (продолжение)

- Исправлена очистка завершённой background_downloader передачи: после установленной модели удалённая/перемещённая временная задача не блокирует повторную загрузку; при retry создаётся новый task ID и очищается stale record.
- Qwen3 `/no_think` и очистка `<think>` проверены тестами; полный `flutter test --concurrency=1 --reporter compact` — 181 PASS; `flutter analyze` — clean.
- API35 x86_64: повторная загрузка показала 136/484 МБ; SHA-256 завершилась успешно, экран предложил открыть помощника. Свежий x86_64 APK установлен поверх существующего и запущен, ошибок AndroidRuntime/Flutter в logcat нет. После этой финальной переустановки повторный ответ помощника пока не запускался.
- Ветка локальной подписи подготовлена: отдельный release keystore и key.properties локальны и игнорируются Git; `docs/ANDROID_RELEASE.md` описывает сборку. ARM64 30,266,922 bytes и x86_64 32,200,434 bytes APK пересобраны; обе подписи v2 проверены, сертификат SHA-256 `9df296187ee915a0a9fcc333aa7560dbec9e0d6086723d4da372540904346a6e`. Файлы: `C:\Users\d3c0r\Desktop\Планерка\Ритм-дня-arm64.apk` SHA-256 `E7299D7335EEE15CA07ADDC14908FCF12FC91C9D2394C63DB31CFC5B0768D2E5`; `C:\Users\d3c0r\Desktop\Планерка\Ритм-дня-emulator-x64.apk` SHA-256 `2F6532026DE8309F414CD53C454C2B76C447D250EC784C302FE34D3B7EA8D188`. APK package `com.planerka.mobile`, version `1.0.0`, min SDK 28, target SDK 36; GGUF/partial/seed entries absent. Commit `a91868c` pushed to `origin/develop`; worktree clean. Публичный GitHub Release не создан: после последней сборки нужен один проверочный ответ помощника; физический Redmi Note 13 недоступен.
- Ограничение среды: параллельная Gradle/Dart нагрузка привела к Windows VirtualAlloc 1455 и Gradle daemon с Xmx8G; сборку следует повторить с одним ABI за раз после остановки собственных тестовых Flutter процессов.

