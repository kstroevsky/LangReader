# Architecture Completion Tasks

- [x] Move proven presentation-only types and their tests from Core to App; split mixed web-presentation and reading-position ownership.
- [x] Add deterministic semantic-placement enforcement for Core.
- [x] Introduce typed navigation, viewport-anchor, continuous-scroll, zoom, and focus capabilities with contract tests.
- [ ] Continue migrating native access in independently green feature slices. The first slice removed navigation, zoom, and document-agent prompt orchestration from the allowlist (41 to 38 files).
- [x] Move the persisted PDF vocabulary occurrence model and stable-key/dedup save planning into Core with focused tests. PDF selection geometry and asynchronous discovery remain at the platform edge.
- [x] Extract and test document-agent request identity, continuation, auxiliary-task, and independent-cancellation ownership. Retrieval and evidence rendering remain with their existing feature collaborators.
- [ ] Replace the migration allowlist with path-based enforcement only after all feature/controller entries are gone.
- [x] Complete broad deterministic verification and development app assembly; use GUI/performance capture only when a change creates a measurement gap and the required session/fixtures are available.

Stop any task whose only outcome is moving code, renaming files, or adding a forwarding abstraction without removing debt or improving testability.

## Verification (2026-08-13)

- `./scripts/check.sh --no-build`: passed, including strict Swift 6 build, 52 SwiftPM tests (one optional fixture skipped), all 280 legacy logic tests, architecture checks, and performance-capture validator tests.
- `./scripts/build_app.sh`: built, signed, and validated the development app bundle.
- Strict bundled-runtime packaging remains environment-blocked because the configured local Piper/Kokoro/Supertonic artifacts are absent; no check was weakened.
- GUI smoke and live performance capture were not run: this migration added no measurement-infrastructure gap, and those checks require a suitably permissioned GUI session and representative private fixtures.
