# Feature plan and acceptance checks

This document records the agreed direction for Shelf, focus intervals, display support and trackpad navigation. Parts are implemented in the working tree. [STATUS.md](../STATUS.md) records the evidence and remaining checks; [SPEC.md](../SPEC.md) contains the project specification and its historical decisions.

## Notification banners (experimental infrastructure; capture gated)

Show notifications as temporary banners in the notch, without a notification history. Reuse Lilt's existing opening and closing animation unchanged. The separate liquid/resistance animation experiment was rejected and closed; do not integrate its motion controllers.

The working tree now implements a default-off opt-in, explicit Accessibility settings action, honest capture status, synthetic Preview, typed ephemeral native owner and a transient banner inside the existing shell. No persistent notification tab or history is added. Arrival never activates a source or makes the panel key. A tab/shortcut takes ownership; expiry is identity-guarded and cannot intentionally close a user-owned panel.

Receiving other apps' notifications remains blocked, not proven implemented. Static Notification Center metadata confirms only `com.apple.notificationcenterui`, not a transient-banner hierarchy or identifiers distinct from history. The production adapter therefore checks nonprompting trust on one serial background queue and returns permission-needed or unsupported/unverified without reading AX windows, children or text. The bounded metadata-first classifier uses explicitly fictional injected fixtures only. No fixture identifier is shipped as a macOS profile.

The remaining feasibility gate is a reviewed, version-specific public AX layout that positively distinguishes a transient banner from Notification Center history before any content read. A future public AX reader must enforce the declared window/node/depth/string, per-message timeout and total elapsed budgets, followed by separately authorized controlled live checks, baseline/no-replay checks, permission revocation, sleep/session and lock-screen checks. The current session/sleep hooks do not prove complete lock safety. Synthetic UI and parser tests are not live notification evidence.

## Notch sizes and trackpad navigation

Lilt should keep content outside the physical camera notch on MacBooks with different notch sizes. When screen data is missing or implausible, the app should choose a safe fallback. Check both compact and open states, long text and several notch dimensions. Tests using modelled geometry do not replace checks on different MacBook models.

A horizontal trackpad swipe switches between Music, Focus and Shelf. Click and keyboard navigation remain available. Gestures should respect macOS scrolling direction and must not interfere with horizontal scrolling or file drag. Verify both directions, every tab transition and reduced motion on an actual Magic Trackpad. AppKit's scroll events do not by themselves prove the number of fingers.

## Shelf

Shelf is a local collection of file references. Users can select one or more files, preview or open an individual item, show it in Finder, drag the selection out or use the macOS sharing menu. Removing a reference never deletes or moves the original file.

The current direction is a scrollable list with readable names and small previews. It must handle empty, missing, duplicate-name and large collections. New references receive the short retention period; explicitly extending an item starts its long period at that moment. Changing a default affects future decisions, not existing deadlines. Legacy references without a deadline remain until removed.

Acceptance needs isolated files and a comparison of originals before and after actions. Check mouse and keyboard selection, persistence across restart, expiry, missing files, Quick Look, Finder, shared dragging and sharing. A complete AirDrop check needs a receiving device. Record rendered UI checks and human design review separately.

## Focus intervals

The standalone timer can use a sequence of work and break phases. Users choose the durations before starting; the next phase requires an explicit action. Breaks do not start music automatically. Brain.fm remains optional and must not block the standalone timer.

Check phase changes, pause, resume, cancellation and restoration. Verify the compact view and keyboard controls in the rendered app. Keep simulated-player evidence separate from tests against an actual Brain.fm installation.

## Displays without a physical notch

A small area at the top of a display without a notch provides access to Music, Focus and Shelf. Users can choose a display in settings. The automatic selection prefers a physical notch, then the main display. If a selected display disconnects, Lilt temporarily falls back and can return to it after reconnection.

Check opening and closing, all tabs, display switching, disconnection, reconnection, fullscreen behavior and menu-bar overlap on actual displays. Record unavailable hardware as an open test limit.
