# Lilt

Lilt is a local macOS notch app. AppKit owns windows, permissions, storage and player control; bundled WKWebViews render the notch and settings. No remote website is loaded.

## Read first

- `README.md`: setup, features and diagnostic commands.
- `SPEC.md`: agreed behavior; historical sections are labelled.
- `STATUS.md`: recorded evidence and remaining limitations, not proof of current tests.
- `docs/BRIDGE.md`: native/web messages.
- `THIRD_PARTY_NOTICES.md`: design attribution and font licence.
- `docs/FEATURE-PLAN.md`: future work, not implemented functionality.

## Build and test

Requires macOS 15+, Xcode/Swift and Node.js. CI uses Node.js 24.

```sh
swift test
node --test scripts/test-ui.mjs scripts/test-focus.mjs scripts/test-settings.mjs
bash -n scripts/build-app.sh scripts/build-meld-bridge.sh
LILT_BUILD_MELD=0 LILT_SIGN_IDENTITY=- ./scripts/build-app.sh
codesign --verify --deep --strict build/Lilt.app
git diff --check
```

Android is optional. Do not require it for Spotify, Apple Music, independent Focus or Shelf. Do not replace a working development signature when a task depends on existing macOS permissions.

## Ownership and boundaries

- `Sources/Lilt/AppDelegate.swift`: lifecycle and bridge routing.
- `DirectMusicController.swift` / `MeldController.swift`: targeted player control and confirmed music state.
- `FocusSession.swift`: native focus state, deadlines and restoration.
- `SettingsStore.swift` / `SettingsWindowController.swift`: atomic settings and settings window.
- `ShelfStore.swift`: local references; removing an entry never deletes its original file.
- `Resources/Web/`: local interface, fonts and motion.
- `Tests/LiltTests/` and `scripts/test-*.mjs`: automated behavior checks.

Use native snapshots as the authority. Do not invent playback confirmation, start music during polling or source selection, or control another player through global media keys. Preserve validation, stale-response guards and optional Brain.fm behavior.

Keep changes small and follow the existing Swift/JavaScript style. Preserve geometry, reduced motion, accessible names, keyboard support and settings persistence. Check rendered behavior for UI changes and distinguish it from simulated or unit-test evidence.

## Test data and publishing

Use isolated fixtures and `--ui-test-dir` or `--data-dir`. Smoke/diagnostic modes suppress real players unless explicit live flags are supplied. Do not change real player state or request permissions as a side effect of routine automated checks. Do not stop an existing user instance to make a test pass.

Keep `docs/evidence/`, build outputs and credentials out of Git. Do not publish screenshots containing personal paths or music metadata. Keep MIT and third-party notices in generated app bundles. Commit, push, visibility changes and releases require the corresponding task authorization.
