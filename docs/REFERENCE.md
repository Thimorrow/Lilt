# Design reference and attribution

The original [Lilt study](https://vayun.net/studies/lilt/) was created by [Vayun Godara](https://github.com/vayungodara). It was inspected on October 30, 2026. Current attribution and licence details are in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).

The local interface adapts the study's notch structure, SVG icons, cover artwork, font and CSS motion. The study uses silent example tracks and a filename preview; this app adds native player controls and local file references. The original study's files include:

- https://vayun.net/studies/lilt/lilt.css
- https://vayun.net/studies/lilt/lilt.js
- https://vayun.net/studies/lilt/fonts/familjen-grotesk.woff2

## Original motion reference

The original browser study used a 520 ms piecewise-linear shape transition, delayed content transitions and independent tab selection motion. These observations describe the source study, not a guarantee that every current Lilt interaction has the same timing. The app's current tab and swipe behavior evolved with user feedback. Keyboard navigation and reduced-motion settings use immediate transitions.

## Native adaptation

AppKit places the panel at the screen edge using the detected display geometry. `NSPrefersDisplaySafeAreaCompatibilityMode` is disabled for the app; see [Apple's documentation](https://developer.apple.com/documentation/bundleresources/information-property-list/nsprefersdisplaysafeareacompatibilitymode). The app uses true black and a compact height based on the physical notch where screen information is available.

Focus works independently; the optional Brain.fm integration controls the installed app rather than asking for its login. Current behavior and test boundaries are described in [README.md](../README.md) and [STATUS.md](../STATUS.md). Diagnostic files under `docs/evidence/` are local and are not distributed with the repository.

The app code and adaptations are MIT licensed with the permission recorded in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md). This does not relicense the original website or other work by its author. Familjen Grotesk remains under SIL OFL 1.1.
