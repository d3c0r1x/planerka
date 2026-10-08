# G31 — Flagship UI refresh

## Global constraints

- Preserve all existing task, calendar, goal, focus, Inbox, and progress behavior.
- Keep black as the default background and use vivid, restrained accents.
- Put the main goal and its progress first on Home.
- Keep quick capture one tap away, retain swipe navigation, and keep the center action colorful and round.
- Use meaningful progress visuals, expressive icons, short motion, and touch feedback.
- Keep contrast, semantics, and layouts usable on narrow Android screens.
- Do not add personal task data, private schedules, credentials, model files, or user paths to code or tests.
- Follow RED-GREEN: add a behavior or accessibility test, observe its expected failure, then implement the minimum change.

## Task 1 — Theme and app shell

Refresh `lib/core/app_theme.dart` and the app shell/bottom navigation in `lib/app.dart`. Keep public theme APIs backward compatible. Add focused tests in `test/widgets/flagship_navigation_test.dart` for black default theme, central capture action, selected navigation, and swipe behavior.

## Task 2 — Home, Today, and Calendar

Refresh `lib/features/home/home_screen.dart`, `lib/features/planning/today_screen.dart`, and `lib/features/planning/calendar_screen.dart`.

- Put Home content in one coherent scroll and keep the main goal, Inbox capture, and Today visible early.
- Show honest completion progress with a clear numerator/total. Do not label selected dates or backlog as completed work.
- Reduce crowded task-row actions to one primary action plus an accessible secondary menu.
- Use a compact branded month grid with task, deadline, and shift markers plus a selected-day summary.
- Keep the swipe regression test representative of a real Android drag with multiple pointer events after Home gains vertical scrolling.
- Refresh calendar markers after shift overrides or future-cycle adjustments through a UI callback; keep shift calculations and persistence unchanged.
- Show a retryable unavailable state when month marker loading fails; never announce unknown task counts as zero.
- Preserve task completion, deadlines, shift setup, overnight shift details, and calendar interactions.
- Update widget tests, including a narrow-screen overflow check.

## Task 3 — Inbox and Goals

Refresh `lib/features/inbox/inbox_screen.dart` and `lib/features/goals/goals_screen.dart`.

- Give Inbox one-tap capture and visible triage categories; show the unsorted count.
- Make one primary goal the visual hero with task fraction, percent, and next action. Keep other primary goals easy to scan.
- Keep manual/AI triage, goal links, approval, edit, date/time, and missing-model actions available.
- Update widget tests, including a narrow-screen overflow check.

## Task 4 — Focus and Progress

Refresh `lib/features/timers/focus_screen.dart` and `lib/features/review/progress_screen.dart`.

- Make the timer the visual anchor with radial progress, selected task, and one primary control. Give recovery and breathing their own secondary card.
- Show completion, focus, and habit progress with clear period context and comparisons backed by existing data.
- Preserve session modes, pause/resume/finish, task selection, breathing, day/week selection, and existing metrics.
- Update widget tests, including a narrow-screen overflow check.

## Completion checks

- Focused tests for each task pass, with the new test observed failing before its UI change.
- `flutter test` passes; `flutter analyze` reports no issues.
- Android release build succeeds.
- Inspect the running app on a dedicated API 35 emulator and capture Home, Inbox, Focus, and Goals screens.
- Review the final diff for privacy and file ownership before commit.
