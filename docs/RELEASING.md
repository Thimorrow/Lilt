# Releasing a macOS beta

The download is an explicitly unnotarized beta. An Apple Development certificate is not a Developer ID certificate. A notarized release requires a Developer ID certificate, appropriate hardened runtime settings and Apple notarization to be set up separately.

## Build the package

On a Mac with Xcode, use a clean, committed source checkout:

```sh
./scripts/package-release.sh 0.1.0-beta.2
```

The script exports the current Git commit to a separate build directory. It does not replace the running development app or its signature. It builds a universal arm64/x86_64 app without the Android bridge or a developer certificate. The release bundle ID is `io.github.thimorrow.Lilt`; local development builds default to `local.lilt.preview`.

The output is `build/releases/VERSION/`, containing a DMG, ZIP, `RELEASE-INFO.txt` with the source commit and `SHA256SUMS.txt`. The beta suffix is part of the package version; the app version is numeric, for example 0.1.0 with build 2. Existing packages are not overwritten. The script accepts only `MAJOR.MINOR.PATCH-beta.N` so an unnotarized package cannot accidentally be labelled stable.

## Verify before publishing

- Pass Swift and Node tests and GitHub CI for the source commit.
- Verify the DMG with `hdiutil verify` and check both CPU architectures with `lipo`.
- Mount the DMG read-only, copy the app to an isolated installation directory, and verify its signature and bundled licences. Unpack the ZIP separately and compare the app.
- Launch the extracted app with isolated diagnostic data. Do not stop a user's existing instance; account for bundle-ID collisions. A second process that immediately exits is not proof of a successful launch.
- Describe Gatekeeper's response honestly. Do not call the beta notarized or disable system-wide protections.
- Check the checksums and source commit against the release tag. Do not upload build caches, user data, credentials or diagnostic captures.

## Publish on GitHub

Commit and push the authorized source, and wait for CI. Create a new tag `vVERSION` at the exact source commit recorded in the package. Publish the four files as a GitHub **prerelease**; do not overwrite existing tags or assets. Include installation instructions, the lack of notarization and concrete testing limitations. Download the published files again and compare them against `SHA256SUMS.txt`.

See [INSTALL-BETA.txt](INSTALL-BETA.txt), [Apple's app-opening guidance](https://support.apple.com/en-us/102445) and [Apple's notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
