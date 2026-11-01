# Contributing to Lilt

Small, focused contributions are welcome. Please discuss larger changes in an [issue](https://github.com/Thimorrow/Lilt/issues) first. Preserve the existing interaction design, accessibility and local data handling.

## Set up

You need macOS 15 or later, Xcode/Swift and Node.js. CI uses Node.js 24. Android is needed only for the optional Meld integration.

```sh
git clone https://github.com/Thimorrow/Lilt.git
cd Lilt
LILT_BUILD_MELD=0 LILT_SIGN_IDENTITY=- ./scripts/build-app.sh
open build/Lilt.app
```

The command uses an ad-hoc signature and does not require an Apple developer account. macOS permissions may need to be granted again after rebuilding. If you depend on existing permissions, retain the app's working development identity. This local build is not a notarized release.

## Optional Meld integration

Meld is a separately configured local Android integration and is not included in the beta download. Spotify, Apple Music, standalone Focus and Shelf do not require it.

Building the bridge requires Android SDK platform 34, build tools 36.0.0 and a JDK. It targets only the specifically configured local Meld emulator, not other Android devices. See [Meld control](docs/BRIDGE.md#meld-control) for the required emulator configuration and bridge behavior.

## Verify changes

```sh
swift test
node --test scripts/test-ui.mjs scripts/test-focus.mjs scripts/test-settings.mjs
bash -n scripts/build-app.sh scripts/build-meld-bridge.sh
git diff --check
```

CI runs automated tests, builds without Android, checks bundled licences and scans Git history for secrets. These checks do not replace testing the app, real players or hardware.

Use `--ui-test-dir` or a separate `--data-dir` for repeatable tests. Diagnostic and smoke modes suppress real player control unless an explicit live flag is supplied. Do not stop an existing user instance to run a test. Diagnostic captures can contain private filenames, paths or track information; keep them out of Git. The diagnostic interface is described in [docs/BRIDGE.md](docs/BRIDGE.md).

## Pull requests

- Explain the problem, the resulting behavior and how you tested it.
- Add tests for meaningful changes in behavior. Operate visible changes in the app and call out missing live or hardware checks.
- Do not commit credentials, signing keys, account data, diagnostic captures or build output.
- Contributions use the MIT licence. Preserve third-party licences and [credits](THIRD_PARTY_NOTICES.md).

Report security issues privately as described in [SECURITY.md](SECURITY.md).
