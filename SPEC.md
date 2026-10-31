# Lilt specification

Lilt is a local macOS app for music, focus and files at the screen edge. It adapts [Vayun Godara's Lilt study](https://vayun.net/studies/lilt/) while retaining the notch geometry and motion where applicable. [STATUS.md](STATUS.md) records test evidence and open limits. Earlier requirements and decisions remain in the Git history.

## Current behavior

### Music

- Spotify and Apple Music connect directly without Meld or Android. Read metadata and confirm playback commands against the selected player. Polling and source selection must not start music or request permission.
- Meld is an optional local integration. Its Android bridge targets the configured Meld emulator and the unique Meld media session. Show disconnected, loading, empty and error states; never invent track metadata or a successful command.
- Do not use global media keys, store account credentials or allow stale responses from a previous source to overwrite current state.

### Focus

- The standalone timer must work without Brain.fm. Work and break intervals are optional; the next phase starts only after explicit confirmation. Do not start music during a break or after a restart.
- Brain.fm is optional. When enabled, use the installed app and explicitly authorized Accessibility access. Confirm the selected activity and playback before changing the associated timer state. Show uncertain states and errors.
- Store native timer state and deadlines. Restore the state after restart without inventing unobserved playback. Keep timer expiry visible within Lilt and do not bring another app to the foreground.

### Shelf

- A scrollable list displays readable names and small image previews. More than 24 entries are supported. Text and controls must stay outside the physical notch.
- Support single and multiple selection by mouse and keyboard. Provide contextual preview, open, Finder, sharing, group drag and removal actions. Removing or expiring a reference never moves or deletes the original file.
- New references receive the current short retention period, initially seven days. Explicitly keeping an item longer starts the current long period, initially 30 days. Changing a default does not alter existing deadlines. References created before expiry was introduced remain until removed.
- Acceptance requires isolated files, scrolling beyond 24 entries, selection and actions, retention changes, expiry and restart. Compare originals before and after. Report native drag/sharing and human design review separately.

### Settings and display

- Settings open from the gear, menu or ⌘,. Persist confirmed player source, focus defaults, optional Brain.fm, Shelf retention and display choice. Retain the current settings redesign, keyboard access and reduced-motion behavior.
- Automatic display selection prefers a physical notch, then the main display. If an explicitly selected display disconnects, temporarily fall back and restore the selection when it returns.
- Keep the selected compact view across open and close. A running or completed focus session must not replace an explicitly selected Music or Shelf view. Empty panel areas, outside clicks and Escape close the panel; interactive controls stay usable.
- Compact and expanded layouts must accommodate different notch dimensions. If screen data is missing or implausible, avoid placing text behind the physical notch. Hardware checks are separate from geometry tests.

### Interaction and motion

- Trackpad swipes move between neighboring views. Preserve vertical Shelf scrolling, horizontal scrollable content, file drag, clicks and keyboard navigation. Do not wrap at either end. Respect the system scroll direction and reduced motion.
- During a swipe, current and neighboring views follow a shared position. A short gesture returns to its starting view; direction changes and interruption must not jump. The tab indicator follows that position.
- Existing click-driven tab transitions remain interruptible. Keyboard navigation and reduced motion switch immediately. Preserve the existing shape animation, black background and Play alignment between Music and Focus.
- Dropdowns use an interruptible scale and opacity transition anchored at the trigger. Opening uses 200 ms and `cubic-bezier(.23,1,.32,1)`; closing uses 150 ms and `ease-in`. The menu becomes inaccessible immediately on close. Keyboard and reduced-motion paths switch directly.

## Verification

- Run Swift and Node behavior tests, shell syntax checks, a release build and signature verification.
- Check rendered UI states in an isolated WKWebView with test data. Distinguish simulated players, real player control, hardware tests and human design acceptance.
- Exercise real Spotify and Apple Music commands separately. Verify Brain.fm start, pause, resume, reset and restoration only when explicitly authorized.
- Check Shelf selection, Quick Look, Finder, expiry, restart, group drag and sharing using test files. An AirDrop test needs a receiving device.
- Test trackpad gestures, both macOS scroll directions, different MacBook notches and external displays on actual hardware. Record unavailable devices as open limits.

## Attribution and boundaries

The app code and published adaptations use the MIT licence. Credit Vayun Godara's original study and preserve the Familjen Grotesk OFL 1.1 licence. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). No account credentials, signing keys, diagnostic captures or user data belong in the repository.
