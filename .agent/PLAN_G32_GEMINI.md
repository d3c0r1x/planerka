# G32 — Gemini integration

**Status:** in progress
**Global contract:** `docs/SPEC.md` G23, extended by G32; user directly requested Gemini integration.
**Branch:** `codex/flagship-ui-refresh`

## Outcome

Add Gemini as a first-class cloud provider in «Ритм дня». Keep local AI as default. Keep all keys outside source, tests, assets, build inputs, APKs, and Git. Reuse the approved router, consent gate, and Android secure storage.

## Acceptance

1. Settings identify Gemini and provide an API-key field without logging or displaying saved key.
2. Model discovery calls the Gemini Models API with the key in a request header, filters to `generateContent`, and sends no personal planner context.
3. Choose `gemini-3.5-flash-lite` by default when the returned catalog contains it. Keep model override available.
4. Generation calls the official `generateContent` endpoint with HTTPS, bounded output tokens, and the existing cloud-consent gate.
5. Local mode remains default and does not call network. Cloud failure does not fall back silently.
6. Tests prove the REST request/response contract, model filtering, Gemini router selection, settings behavior, key storage boundary, and consent blocking.
7. Full Flutter tests, `flutter analyze`, Android API 35 install/launch, synthetic Gemini smoke, and APK key/model scan pass. The `.env` key is entered only into local secure storage for an emulator smoke and removed afterwards.

## Sequence

1. RED: REST request, response, model list/filter behavior.
2. GREEN: implement the native Gemini REST client with injectable HTTP transport/base URI.
3. RED: provider selection, recommended model, model discovery and consent behavior.
4. GREEN: wire router and settings screen; preserve generic OpenAI-compatible path.
5. Run targeted AI tests, then full regression and analysis.
6. Build/install Android APK, exercise settings/local mode, run one synthetic cloud request only after consent, remove emulator key.
7. Scan release artifact and Git diff for the key; commit only safe source/docs/tests. Keep `.agent/PROGRESS.md` local and uncommitted.

## Baseline

- API key successfully listed 45 models supporting `generateContent`; no key value was emitted.
- Recommended app model: `gemini-3.5-flash-lite`, available via the current API key.
- AI tests: 55 passed with `--concurrency=1`; default test worker previously exhausted Windows VM memory.
- Android manifest already includes `android.permission.INTERNET`.
