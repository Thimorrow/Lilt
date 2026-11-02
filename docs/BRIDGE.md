# Native/UI contract

The notch and settings are native SwiftUI views hosted by AppKit (`NotchHostView`, `SettingsWindowController`). No web content, WebKit or remote page is loaded. The message names below are kept from the former web bridge: native code still calls `send(method, value)`, which JSON round-trips the value into `NotchModel.receive` or `SettingsModel.receive`, and the views post the same validated dictionaries to `AppDelegate.handleNotchMessage` / `handleSettingsAction`. JSON round-tripping keeps the UI on plain, already validated values.

## Settings and direct players

The settings window hosts the native `SettingsView`, driven by `SettingsModel`. Its controls are keyboard reachable according to the macOS keyboard navigation setting. Settings opens through the Notch gear, menu, ⌘, or application reopen. Closing/folding the Notch does not close settings.

`SettingsModel` receives `receiveSnapshot` with `{musicSource,sourceName,brainFMEnabled,focusMinutes,focusActivity,shelfShortDays,shelfLongDays,displayID,focusSound,shortcutEnabled,openAtLogin,shortcutLabel,shortcutConflict,displays,displayUnavailable,musicBusy,focusLocked,providers,brainFM,error,saved}`. Source is `spotify`, `appleMusic` or `meld`; minutes is an integer from 1–180. The Shelf retention values are whole days from 1–3650. `openAtLogin` reflects macOS login items, not `settings.json`; a `settingsUpdate` with only `openAtLogin` registers or removes it. Diagnostic and smoke runs simulate it and never register the global shortcut. Provider entries have `{id,name,installed,running,availability,permission,message}`. `brainFM` has `installed` and `permission` booleans. `configure({reducedMotion})` disables all motion when requested; `inspect()` returns the model state for diagnostics.

Settings messages are `settingsReady`, `settingsUpdate {changes}`, `settingsClose`, `musicConnect`, `musicOpen`, `brainfmSettings` and `brainfm`. Only recognized settings fields and validated types cross the native boundary. Storage writes atomically to `settings.json` before runtime selection changes. A failed save keeps the last confirmed configuration. Music changes are refused while a transport command is pending. Focus defaults/integration changes are refused while a session is active or paused. Notch `focusConfigure` also updates saved defaults after an accepted native configuration.

The Notch receives `receiveSettingsSnapshot` and music snapshots additionally include `source` and `sourceName`. The selected tab is authoritative for both expanded and compact presentation. Running/paused/completed Focus does not override an explicitly selected Music or Shelf tab. Opening compact preserves the selected tab. Header, free inner surface, Escape and native outside clicks fold; interactive controls do not. There is no visible footer Fold button.

`DirectMusicController` uses a source enum and the installed app's scripting definition to send Apple Events only to the already running Spotify/Music PID. Polling never opens an app or prompts for Automation permission. `musicConnect` explicitly requests that permission on a background queue. `musicOpen` explicitly opens the selected app without a Play command. There is no OAuth, copied login, token, global media key or arbitrary app target. Commands compare fresh before/after observations and fail if playback or track change is unconfirmed. Source selection invalidates old reads and clears metadata; disconnected states clear stale artwork and controls.

Apple Music artwork is read natively; Spotify artwork is fetched only over HTTPS from `i.scdn.co`, without cookies/credentials/redirects and with bounded size/time. Both become at most 160px bounded JPEG data URIs before reaching the UI model. The Android bridge is optional at build/runtime for direct providers.

New installations default to Spotify with Brain.fm disabled. In independent mode, native Focus start/pause/resume/reset/finish never call the Brain.fm controller. A running deadline continues across restart; expired sessions remain completed. The persisted session records its integration mode. Legacy or mismatched active modes pause conservatively with an explicit message and do not read or modify music. When Brain.fm is enabled, the existing confirmed-playback lifecycle below applies.

Diagnostics may select `target: 'settings'`; `settingsSize: {width,height}` resizes only that window within bounded test dimensions. Diagnostic responses include actual settings frame/visibility/key state. `scripts/native-command.mjs DIRECTORY STEPS.json [EVIDENCE] [settings] [WIDTHxHEIGHT]` drives the existing isolated seam. With independent Focus, `testFocus` in diagnostic mode accepts only bounded `remaining` to check expiry; it cannot enable real playback. Normal app mode ignores that fixture.

`testPointer {phase:'down'|'up',x,y}` is accepted only in diagnostic mode. Finite coordinates must lie within the notch host view bounds. Native NSEvents are delivered exclusively to Lilt's own panel. They do not move the global mouse or address another application. Normal app mode ignores this fixture.

## Notification banners

Settings add `notificationBannersEnabled` (strict Boolean, persisted atomically, default false), `notificationCaptureStatus` (`disabled`, `diagnostic`, `suspended`, `permission`, `active`), `notificationCaptureMessage`, `slackStatus` (`off`, `connecting`, `connected`, `failed`) and `slackMessage`. `notificationPreview` creates synthetic text only; `notificationAccessibilitySettings` opens the Accessibility pane only on an explicit action with opt-in and never in diagnostic/smoke mode. No prompting AX trust API is called.

`receiveNotificationBanner({id,source,title,body,image?})` presents at most one banner while the panel is closed and no file chooser is active. Source/title/body are bounded to 80/160/360 characters, stripped of control characters and rendered as plain text. `image` is a PNG/JPEG data URI of at most 200 KB (avatar or app icon). `receiveNotificationBanner({id,clear:true})` clears only the matching banner. `notificationTakeover({id,open})` transfers ownership; the UI sends `notificationDismiss {id}` or `notificationTakeover {id}`. Banners expire after about eight seconds. Banners that cannot show yet wait in an in-memory queue of five for up to 120 seconds; disable, suspension and permission loss clear it. Arrival never activates a source or makes the panel key.

One main-run-loop 0.75-second tick drains the agent inbox, advances the queue and starts at most one serial background capture. Enable/resume establishes a baseline; ephemeral dedup keys (the banner's AX identifier, else its text) expire after 120 seconds with a 64-key maximum; generations reject stale completions.

**Other apps.** `NotificationCenterCapture` checks nonprompting `AXIsProcessTrusted` off the main thread, then walks only `com.apple.notificationcenterui` with a 40 ms AX messaging timeout. `NotificationClassifier` reads text only from an `AXGroup` whose subrole is `AXNotificationCenterBanner` or `AXNotificationCenterAlert`: `AXStaticText` children `title`/`subtitle`/`body`, and the sending app from the first comma-separated item of the group's description (description-only layouts fall back to `App, Title, Body`). Any `widget-editor-button` or `AXNotificationListItems` marker (history or widgets open) makes the scan return nothing. Limits: four windows, 200 nodes, depth ten, 24 strings, 512 characters, 150 ms. With Slack connected, captured banners from "Slack" are skipped.

**Slack.** `slackConnect {appToken,userToken}` accepts only `xapp-`/`xoxp-` tokens (ASCII letters, digits and dashes, at most 300 characters), stores them in the login Keychain (service "Lilt Slack") and opens Socket Mode (`auth.test`, `apps.connections.open`). Envelopes are acknowledged; `disconnect` opens a replacement socket; failures retry after 1–60 seconds; rejected tokens stop with `failed`. Only `message` events from someone else are shown: direct/group messages, or channel messages containing `<@me>`; edits and system subtypes are ignored. Names and 72 px avatars come from `users.info`, channel names from `conversations.info`, cached in memory. `slackDisconnect` stops the socket and deletes the Keychain item. `Lilt --slack-connect` reads the app-level and user token as two stdin lines, validates and saves them from Lilt's own signed binary (so the app reads them without a Keychain prompt) and exits 1 on invalid input; the running app picks them up on its next launch. `slackCreateApp` opens `api.slack.com/apps?new_app=1&manifest_json=…`. Isolated runs never touch the Keychain or network.

**Coding agents.** `Lilt --notify claude|codex [--data-dir DIR] [json]` runs without UI and always exits 0. Claude Code's Stop hook JSON arrives on stdin (`last_assistant_message`, else the transcript's last assistant text); Codex passes `agent-turn-complete` JSON as the last argument. `T3CODE_THREAD_ID` marks T3 Code. The command writes `{source,project,message,app,created}` to `<data dir>/inbox/<uuid>.json` via rename; the app reads up to five files per tick, deletes each, drops entries older than ten minutes or larger than 64 KB, and shows the icon of the bundle `app`. `scripts/agent-hook.sh` wraps the command for both agents, preserves a previous Codex notify chain and skips Lilt binaries without the `lilt-agent-inbox-` marker.

Only diagnostic `testNotification {source?,title?,body?,app?,clear?,expire?}` injects, clears or expires synthetic banners. Diagnostic/smoke mode bypasses capture and Slack. The notch `inspect()` includes only `notification {visible,hasText,hasImage}`; native diagnostic responses add `notificationCaptureStatus`, `notificationVisible`, `notificationPending`, `notificationGeneration`, `notificationPanelKey` and `notificationAcceptsKey`. Banner text and dedup keys never appear in diagnostics.

`scripts/check-native-notch.mjs DIRECTORY` covers queued presentation, the app picture, arrival focus, takeover and an agent inbox file. Swift tests cover the queue, image payload, classifier fixtures, Slack filtering/formatting/token validation and agent parsing. To preserve `build/Lilt.app`, build a separate bundle with `LILT_APP_DIR=/absolute/path/Other.app` and `LILT_BUNDLE_ID=...`, then launch it with `--ui-test-dir`.

## Native → UI

`NotchModel.receive(method, value)` accepts:

- `configure({hardwareWidth?,hardwareHeight?,reducedMotion?})` applies supplied geometry/accessibility values.
- `setOpen(boolean)`, `setView('music'|'focus'|'shelf')`.
- `setDragging(boolean)` displays the native file-drag target state.
- `swipeGesture(phase,dx,dy,accepted,x,y,inputTime?)` receives precise native scroll phases (`begin`, `change`, `end`, `cancel`). Deltas retain macOS scroll direction; x/y are top-left panel coordinates and `inputTime` is the native monotonic event time in seconds. `NotchHostView` forwards phases directly to `NotchModel.swipeGesture`. The strip follows the finger once per display frame (CADisplayLink), including the tab marker, and settles critically damped from its current position and measured input velocity. Direct diagnostic calls may omit time. Vertical/horizontal-scroll exclusions, file drag, cancellation and reduced motion remain enforced. This API does not confirm a physical finger count or hardware performance.
- `receiveMusicSnapshot({availability,id,title,artist,album,queueID,duration,elapsed,playing,buffering,speed,cover,canPlay,canPause,canNext,canPrevious,pending,error})` mirrors the native MusicCoordinator. Times are seconds. Availability is checking, ready, offline, empty, unavailable or disabled. Cover is a bounded JPEG data URI or null; pending is play, pause, next, previous or null; error is `{code,message}` or null.
- `receiveFocusSnapshot({activity,duration,remaining,deadline,phase,owned,restoring,pending,error})` accepts the native FocusCoordinator snapshot. Activity is `deepWork` or `lightWork`; duration/remaining are seconds; deadline is Unix milliseconds or null. Phase is idle, running, paused, completed, uncertain or checking. Pending is `{id,action}` or null; error is `{code,message,action}` or null.
- `receiveShelfSnapshot({items,message})` replaces the visible shelf from native storage. An item contains `{id,name,location,available,kind,expiresAt,retention,thumbnail?}`. The optional bounded image preview is a data URI; full paths and bookmark data never enter the UI model. The ID identifies a native stored entry.
- `inspect()` returns the UI model state for diagnostics. It is read-only and does not drive the native timer.

Native FocusCoordinator owns duration, activity, optional confirmed playback, wall-clock deadline, pending operation ID, storage and recovery. The UI has no independent focus timer, optimistic playback state or completion authority. Music only interpolates elapsed playback time between confirmed selected-player snapshots. It never selects a new track or declares playback on its own.

## UI → native

Every intent posts a dictionary through `NotchModel.post` to `AppDelegate.handleNotchMessage`:

- `ready`: configure geometry, deliver native stores and show the window.
- `openChanged {open}`: window state; `hitRect` supplies the actual shape for pointer passthrough.
- `chooseFiles`: native file picker. Actual file URLs are kept in ShelfStore.
- `focusConfigure {activity,minutes}`: native validation allows 1–180 integral minutes and known activities. Pending/running/restoring/uncertain sessions cannot be reconfigured.
- `musicAction {command:'play'|'pause'|'next'|'previous'}` requests an allowlisted targeted Meld operation; duplicate requests are suppressed until its result.
- `meldOpen` explicitly opens the configured local Meld launcher and, after validating the AVD, its Android activity. It is never invoked by polling.
- `focusAction {command:'start'|'pause'|'reset'|'finish'}`: serialized native operation. Start may select a requested activity. Other commands pause only the matching activity. Timer start/pause/completion requires confirmed results. Reset after a confirmed foreign activity only discards local ownership.
- `swipeHaptic`: one trackpad alignment tick when a live swipe crosses the commit threshold toward an existing neighbour page, or when the rubber band at the first or last page engages.
- `shelfAction {command,id?,ids?,x?,y?,width?,height?}`: command is refresh, clear, preview, open, reveal, remove, keep, share or drag. Native actions validate stored IDs and resolve bookmarks. Clear/remove never delete the original. Drag starts a native file-URL NSDraggingSession using a recent mouse event from Lilt's panel and advertises copy only. The file context menu is rendered inside the notch; only sharing opens the macOS sharing picker. Share coordinates are local UI points.
- `focusIntervalsConfigure {workMinutes,restMinutes}` configures a sequence; `focusIntervalsNext` explicitly starts its next phase. Native Focus remains the timer authority, and a break does not start Brain.fm.
- `brainfm`: explicitly open installed Brain.fm for user intervention.
- `brainfmSettings`: user-invoked macOS permission prompt/settings. Never grants access automatically.
- `quit`: terminate.

`NotchHostView` accepts real incoming file URLs from NSDraggingInfo. Outbound drags use native URL pasteboard items. Mouse-down capture is scoped to Lilt's own panel; no global input is synthesized for Shelf.

Local precise, phased horizontal scroll events are observed without being consumed. The UI excludes closed Notch, file drag, focus menus and horizontally scrollable content while vertical scrolling remains available. The native event cannot prove the number of fingers; actual trackpad behavior requires a separate hardware check.

## Persistence and lifecycle

Normal storage is `~/Library/Application Support/Lilt`. `--data-dir DIR` replaces it for isolated normal UI/connection/restart tests. Diagnostic runs otherwise use `--ui-test-dir DIR` → `DIR/data`; smoke storage is temporary.

Focus writes configured state and confirmed transitions atomically. A native 250 ms timer checks deadlines and publishes changing remaining seconds. When Brain.fm is enabled, read-only polling runs approximately every three seconds while Lilt owns a session, with wake rechecking. Unknown playback freezes the last confirmed remaining time and shows an error. After restart, checking is shown until a real matching observation. No music starts automatically. If a stored running session is now paused, the unknown off-app pause time is not invented: the last verified remaining time is preserved. A pending failed finish remains finish intent across restart.

Lilt cannot act while fully terminated. A restored expired session must first prove a matching player before requesting Pause. The native timer continues while merely folded. Completion stays inside Lilt and does not open the panel or activate another app.

Shelf stores stable IDs, bookmarks without implicit security grants, last resolved local URLs and fixed expiry dates. URLs are normalized for duplicate comparison. Original files are not copied, moved or deleted by adding/removing references or expiry. Entries remain scrollable/actionable beyond 24; unavailable entries remain removable. Legacy references without expiry are retained. Settings changes affect subsequently added or extended references only.

## Brain.fm control

Only bundle com.electron.brain.fm is targeted. Known activity Home buttons are `Go to Deep Work session` and `Go to Light Work session`. Switching a mismatched player starts with the exact START static-text navigation link; the nearest ancestor exposing the Accessibility Press action is invoked within a bounded parent search. Recognized player/Home buttons are focused and receive PID-directed Enter/Space, followed by stable rereads. No global media/keyboard/mouse events, synthesized mouse clicks, remote debugging, tokens or app-bundle changes.

Home can contain a still-playing miniplayer. Home and an open activity chooser never prove paused playback. Inspect is read-only. Pause refuses mismatched activities. Commands have a 16-second total deadline and bounded targeted attempts. Native pending IDs reject duplicate/stale responses; read polling cannot overwrite a pending user command.

## Meld control

The only target is ADB serial `emulator-5580` on local socket `tcp:localhost:5040`. Every operation verifies the AVD name is exactly `Meld`; a different device is rejected. The transport never selects a default/first device or dispatches global media keys. Only the MediaController whose package is exactly `com.meld.app` is used; ambiguous matching sessions are rejected. Its own TransportControls provide Play, Pause, Next and Previous.

`scripts/build-meld-bridge.sh` compiles the small `Resources/Android/MeldBridge.java` source against Android 34 and packages DEX into `Contents/Resources/MeldBridge.jar`. The runtime pushes that trusted helper into the isolated emulator's `/data/local/tmp` on connection. `app_process` initializes the Android 14 media framework and uses MediaSessionManager without root, application changes or security-policy changes. No account data or private Meld files are read. Metadata and at most a 160px JPEG thumbnail enter the UI model; no remote artwork URL is loaded.

MeldController runs on a serial background queue with bounded process time/output and explicit arguments. MusicCoordinator reads approximately every two seconds, including while folded. An in-flight read cannot overwrite a later user request. Command results must prove the requested state or track change; an exit code alone is insufficient. Polling never starts the emulator, activity or music. Unknown/closed/empty sessions clear apparent playback. Open Meld is an explicit return path, including when the emulator is running but the Android activity was closed. Music is not persisted by Lilt; restarting rereads Meld without a Play command. Compact presentation follows the explicitly selected view.

## Window and diagnostics

Fixed 680×300 transparent panel at true screen top above menu-bar icons. Expanded max(500,hardwareWidth+260) × (hardwareHeight+160); compact (hardwareWidth+132) × hardwareHeight. Black #000000, original spring, minimum hardware height. Native passthrough tracks rendered shape. First click accepted. Header/Fold/Escape close. Window-key loss folds, except while a native picker/menu is active.

`--ui-test-dir DIR` reads command.json `{id,steps,target?,snapshot:true?}` and writes response.json, optionally with capture.png. Steps are `call`, `message`, `intent`, `pointer`, `swipe`, `capture` and `wait`; with `target:'settings'` they address the settings window. Captures render the view's layer tree, need no screen-recording permission and omit window shadows. The response includes `result`, the model's `inspect()`. `--simulate-brainfm` and `--simulate-meld` use distinct fake native players. `--live-brainfm` or `--live-meld` enables only the respective real player in diagnostics. Default diagnostic/smoke never controls music/permissions. Simulated evidence is labeled separately.

Startup ignores a pre-existing command ID so reused diagnostic directories never replay an old playback or quit command. Submit a fresh ID after the app starts.

Only simulated diagnostics accept `testFocus {activity?,playback?,error?,message?,clearError?,remaining?,poll?}`. This updates the fake player or a bounded native test remainder, and never enables real music. Production UI has no fixture authority. Real file storage is covered by Swift tests and independent native interaction checks.

Only `--ui-test-dir` with `--simulate-meld` accepts `testMusic {availability?,id?,title?,playing?,buffering?,error?,message?,clearError?}`. This mutates the fake player and requests a read; normal and live modes ignore it. Checks using it are explicitly simulated evidence.

## Everyday controls

Settings additionally persist `shortcut {keyCode,modifiers}` (macOS virtual key code and Carbon modifier mask) and `focusNotificationsEnabled` (default false). Missing shortcut settings migrate to Control-Option-L. The native keyboard recorder accepts a key with Control, Option or Command; Escape cancels and Tab leaves recording. Replacement registration precedes storage and releases the old registration only after success. A conflict retains the previous binding. Diagnostic/smoke modes never register global shortcuts.

`shortcutRecord`/`shortcutCancelRecording` start/end recording in the settings window. Native `receiveShortcutRecording({recording,error?})` drives its visible state. `shortcutRecordingEnded` restores registration. Timer notification permission is requested only by the explicit `focusNotificationPermission` action, independently of other-app notification capture and Brain.fm. Snapshots include `focusNotificationStatus` and `focusNotificationRequesting`. Isolated modes do not create a system notification center or request permission; the opt-in is simulated locally. The OS schedules one completion notification for the current native deadline. Pause/reset/extension/opt-out cancel or replace pending notifications; opening a delivered notification only opens Focus.

`focusAction {command:'extend'}` adds five minutes, capped at a total of 180 minutes. `duration` remains the original preset; `totalDuration` includes persisted `extensionSeconds`, and `canExtend` controls availability. A completed Brain.fm work phase restarts only after confirmed Play. A paused phase stays paused, and an extended interval reopens the same phase without counting a work period twice. The next interval still requires explicit action. Idle/completed standalone Focus does not keep a repeating native timer active.

Shelf accepts directory references without recursion. `shelfAction {command:'paste'|'undo'}` reads the clipboard only after explicit paste or restores up to twenty in-memory removal operations. `canUndoRemoval` accompanies Shelf snapshots. Expired references and duplicate re-added references are not resurrected. Diagnostic paste uses a named pasteboard configured with `testShelfPaste {names:[...]}` from files under the isolated data directory's `fixtures` folder, never the user's clipboard.

`shelfDragRegions {regions:[{id,x,y,width,height}],selected:[id...]}` reports bounded visible hit regions and selection. Native mouse-down resolves the authoritative references synchronously; movement beyond four points begins an AppKit file drag, using that actual drag event. Shelf is not rebuilt to start it. The source only offers Copy and stays open during a native drag. Scroll/layout/selection changes update the regions. Mouse-up clears preparation so a late event cannot reuse previous files.

`dismissMenus()` closes transient Focus/Shelf menus and returns whether one was open. A blank click that dismisses a menu does not also fold Lilt. Native outside interactions use the same result, with stale-close callbacks invalidated by newer panel interactions.

Isolated checks: `scripts/check-native-notch.mjs` (fixtures `first.txt`, `folder`, `second.txt`) and `scripts/check-native-settings.mjs`. `testShelfKey` exercises Command-V/Command-Z with native key equivalents; `testShortcutKey` exercises native recording without system registration; `testOutsideInteraction` uses the normal outside-dismiss policy. These actions are ignored outside diagnostics. Diagnostic results expose native drag completion/operation counts, separately from a receiving-app drop.

`--isolate-desktop-input` with `--ui-test-dir` ignores unrelated global desktop input during deterministic probes. Native pointer fixtures and `testOutsideInteraction` still exercise local input and the normal dismissal policy. This flag does not establish real desktop or hardware acceptance. `LILT_APP_DIR` can direct a build to a separate absolute `.app` path, preserving a running user bundle.
