# Planerka: flagship UI and AI workflow revision

Date: 2026-10-08. Repository: `d3c0r1x/planerka`, branch `develop`.

## Authorized scope

Implement the user's latest requested redesign on top of the approved local-only Android planner. Keep dark mode primary, preserve existing functions and data, keep personal seed data private, and require explicit approval before AI writes task changes. AI must remain on-device; model weights stay outside the APK.

## Product outcomes

- Premium-feeling dark interface with richer accent colors, layered/gradient cards, visible progress pills, expressive icon treatments and tactile press states.
- Home includes one-tap Inbox entry, today's plan, model installation/download status, and primary goal with task-derived progress.
- Swipe between the four main destinations while keeping bottom navigation in sync.
- Add/edit deadlines and reminders reliably; overdue and upcoming states are clear.
- AI helps classify Inbox, decompose the primary goal into task drafts, and propose a deadline-aware daily schedule. It never persists a suggestion until the user selects and confirms it.
- Large model downloads continue after the model screen closes and while the app is backgrounded, expose visible progress/notification controls, resume after process recreation, verify pinned SHA-256, and never load a partial file.
- Build, install and exercise core user flows on an API 28+ Android emulator. Verify local inference with the actual pinned GGUF when network and emulator resources permit; record latency, memory and any failure honestly.

## Goals and acceptance

### R1 — Home shell and flagship visual system

- Replace plain home hero with a layered dashboard: date/greeting, primary-goal progress, deadline/AI status pills, quick Inbox entry, daily progress and colorful actions.
- Add reusable press-feedback, gradient surface and progress-pill components; preserve accessibility and contrast.
- Use a swipeable `PageView` for Сегодня, Inbox, Фокус and Прогресс; tap navigation remains synchronized and nested horizontal content remains usable.
- Tests cover Inbox quick capture, horizontal tab changes, selected nav state and dashboard empty/loading/goal states.

### R2 — Primary goal and task-derived progress

- Let user choose one existing goal as primary.
- Calculate progress from completed versus active tasks attached to goal-linked projects; do not silently treat manual unit progress as task progress.
- Add on-device AI goal decomposition as a validated draft. Show generated steps, allow individual selection, create/link tasks only after explicit confirm.
- Closing the preview or selecting nothing leaves SQLite unchanged. Tests cover empty goal, progress boundaries, stale goal and transaction rollback.

### R3 — Deadline-aware planning and Inbox AI

- Keep existing deadline scheduling and local notifications, add polished deadline/reminder entry points from task create/edit/triage flows, and surface overdue/next-deadline cards on Home.
- Add deterministic urgency scoring using due date and task state; use it to order planner suggestions before asking local AI to explain or refine them.
- Add AI Inbox classification as a reviewable draft (quick, schedule, project, delete); validate proposed IDs/categories and require per-item user confirmation.
- Tests cover date/time zones, overdue ordering, exact-alarm fallback, invalid AI output, selected-only apply and no-write cancel.

### R4 — Background model transfer and global model status

- Integrate native background downloading for the approved URL and private `.part` destination; preserve pause/resume and process-death recovery.
- Show persistent OS progress notification and app-wide model banner/status. Allow open/download/resume from Home. Keep hash verification and atomic install as mandatory gates.
- Test adapter/state restoration, retries, pause/resume, digest mismatch, verified reuse and app-wide banner states. Run a real emulator download and hash check.

### R5 — Emulator end-to-end, release and publication

- Install on API 28+ emulator with a compatible ABI; exercise quick Inbox add, swipe navigation, goal selection, AI goal plan confirmation/cancel, deadline scheduling/notification, background download/reopen, model integrity and one Russian inference.
- Run full `flutter analyze`, all tests, release build, APK content/signature/permissions inspection and privacy/history review.
- Publish only safe code/docs. Keep local model, personal seed and personal APK out of GitHub. Copy final installable APK to the user's Planerka folder and record SHA-256.

## Execution rules

- Work one goal at a time: RED, implement, focused tests, full regression where needed, verify, commit, update `.agent/PROGRESS.md`.
- Preserve schema where possible. Any migration must retain task, reminder, goal and game data and update backup import/export coverage.
- If actual model inference fails on emulator, perform structured diagnosis before changing runtime, and distinguish native bridge success from model-quality success.
- Do not claim device readiness until a compatible emulator run proves the relevant flows.

## Environment baseline

- Last verified full regression: 81 tests pass; `flutter analyze` clean; release arm64 APK built. Re-run baseline before first implementation edits.
- Current running emulator: API 25 x86_64; incompatible with current minSdk 28. Install/create an API 35 x86_64 emulator for app and inference testing; physical target phone is not connected.
- Current Git state before this plan: clean, `develop` synchronized with `origin/develop` at `8068d16`.

## Status update 2026-10-08
- R1/R2 complete and published. R3/R4 implementation GREEN in working tree; regression 92 PASS and analyzer clean. R5 API35 smoke test passed for launch, Home model banner and swipe to Inbox; real model inference/download and final release artifact verification remain.
