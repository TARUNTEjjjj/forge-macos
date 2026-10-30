# Forge Mac working conventions

- Use only the owner's GitHub account `TARUNTEjjjj`. Check authentication before remote writes.
- Keep this repository private unless the owner explicitly requests a visibility change.
- Build meaningful functionality with accurate commit messages and tests for real failure cases. The owner chooses each day's focus; do not manufacture activity.
- Keep the native curriculum, notes, and journal available offline. Online labs use a separate WebKit window and separate website storage.
- Run `scripts/test.sh` and `scripts/swift-command.sh run ForgeMac --check-native` for persistence/editor changes. Run `scripts/build-app.sh debug` for native changes.
- Preserve user progress on load/write failures. Never silently overwrite invalid data or discard failed editor drafts.
- Do not commit build products, credentials, Apple certificates/profiles, or learner data.
- A local ad-hoc app is not a Mac App Store release. Record actual validation and remaining release steps in `docs/mac-app-store.md`.
