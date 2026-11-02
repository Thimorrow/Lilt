# Native/UI contract

WKWebView serves only bundled Contents/Resources/Web at lilt-ui://app/index.html using WKURLSchemeHandler.

## Settings and direct players

The settings window serves only `lilt-ui://app/settings.html` from the same bundled directory, in its own nonpersistent WKWebView. Main-frame messages are accepted only from the matching WebView. Both native WebViews enable keyboard tab focus on links and form controls. Settings opens through the Notch gear, menu, ⌘, or application reopen. Closing/folding the Notch does not close settings.

`window.LiltSettings.receiveSnapshot` receives `{musicSource,sourceName,brainFMEnabled,focusMinutes,focusActivity,shelfShortDays,shelfLongDays,displayID,focusSound,shortcutEnabled,openAtLogin,shortcutLabel,shortcutConflict,displays,displayUnavailable,musicBusy,focusLocked,providers,brainFM,error,saved}`. Source is `spotify`, `appleMusic` or `meld`; minutes is an integer from 1–180. The Shelf retention values are whole days from 1–3650. `openAtLogin` reflects macOS login items, not `settings.json`; a `settingsUpdate` with only `openAtLogin` registers or removes it. Diagnostic and smoke runs simulate it and never register the global shortcut. Provider entries have `{id,name,installed,running,availability,permission,message}`. `brainFM` has `installed` and `permission` booleans. `configure({reducedMotion})` disables all motion when requested; `inspect()` returns rendered state and runtime errors.

Settings messages are `settingsReady`, `settingsUpdate {changes}`, `settingsClose`, `musicConnect`, `musicOpen`, `brainfmSettings` and `brainfm`. Only recognized settings fields and validated types cross the native boundary. Storage writes atomically to `settings.json` before runtime selection changes. A failed save keeps the last confirmed configuration. Music changes are refused while a transport command is pending. Focus defaults/integration changes are refused while a session is active or paused. Notch `focusConfigure` also updates saved defaults after an accepted native configuration.

The Notch receives `receiveSettingsSnapshot` and music snapshots additionally include `source` and `sourceName`. The selected tab is authoritative for both expanded and compact presentation. Running/paused/completed Focus does not override an explicitly selected Music or Shelf tab. Opening compact preserves the selected tab. Header, free inner surface, Escape and native outside clicks fold; interactive controls do not. There is no visible footer Fold button.

`DirectMusicController` uses a source enum and the installed app's scripting definition to send Apple Events only to the already running Spotify/Music PID. Polling never opens an app or prompts for Automation permission. `musicConnect` explicitly requests that permission on a background queue. `musicOpen` explicitly opens the selected app without a Play command. There is no OAuth, copied login, token, global media key or arbitrary app target. Commands compare fresh before/after observations and fail if playback or track change is unconfirmed. Source selection invalidates old reads and clears metadata; disconnected states clear stale artwork and controls.

Apple Music artwork is read natively; Spotify artwork is fetched only over HTTPS from `i.scdn.co`, without cookies/credentials/redirects and with bounded size/time. Both become at most 160px bounded JPEG data URIs before reaching the WebView. The Android bridge is optional at build/runtime for direct providers.

New installations default to Spotify with Brain.fm disabled. In independent mode, native Focus start/pause/resume/reset/finish never call the Brain.fm controller. A running deadline continues across restart; expired sessions remain completed. The persisted session records its integration mode. Legacy or mismatched active modes pause conservatively with an explicit message and do not read or modify music. When Brain.fm is enabled, the existing confirmed-playback lifecycle below applies.

Diagnostics may select `target: 'settings'`; `settingsSize: {width,height}` resizes only that window within bounded test dimensions. Diagnostic responses include actual settings frame/visibility/key state. `scripts/native-command.mjs DIRECTORY SCRIPT [EVIDENCE] [settings] [WIDTHxHEIGHT]` drives the existing isolated seam. With independent Focus, `testFocus` in diagnostic mode accepts only bounded `remaining` to check expiry; it cannot enable real playback. Normal app mode ignores that fixture.

`testPointer {phase:'down'|'up',x,y}` is accepted only in diagnostic mode from the Notch's main frame. Finite coordinates must lie within its WebView bounds. Native NSEvents are delivered exclusively to Lilt's own panel, including WebKit's real pointer/focus default actions. They do not move the global mouse or address another application. Normal app mode ignores this fixture. Dropdown regression tests use down/up pairs rather than DOM-only `click()` so transient WebKit focus loss is exercised.

## Experimental notification banners

Settings add `notificationBannersEnabled` (strict Boolean, persisted atomically, default/migrated value false), `notificationCaptureStatus` and `notificationCaptureMessage`. Status is `disabled`, `diagnostic`, `suspended`, `permission` or `unsupported`. Brain.fm trust does not constitute notification consent. `notificationPreview` from settings creates synthetic text only; `notificationAccessibilitySettings` opens the Accessibility pane only on an explicit action with opt-in, never in diagnostic/smoke mode. It never calls a prompting AX trust API.

`receiveNotificationBanner({id,source,title,body})` presents at most one banner, only while the panel is closed and no file chooser is active. Source/title/body are bounded to 80/160/360 characters and rendered with `textContent`. `receiveNotificationBanner({id,clear:true})` clears only the matching banner, including hidden text and announcements. `notificationTakeover({id,open})` transfers matching presentation ownership. UI sends `notificationDismiss {id}` or `notificationTakeover {id}`; tab takeover also confirms `openChanged {open:true,userOwned:true}` so native state remains correct if expiry won the native race. Native timers expire banners at about eight seconds. No backlog, history, source action, key-window activation or player changes are involved. The selected normal tab and authoritative Focus state are preserved; normal content is inert and accessibility-hidden while covered. The existing shell geometry, 520 ms spring and reduced-motion behavior are unchanged.

One main-run-loop 0.75-second tick services expiry and at most one serial background capture attempt. Enable/resume establishes a baseline, ephemeral dedup keys expire after 120 seconds with a 64-key maximum, and generations reject stale completions after disable, suspension or permission loss. These transitions clear presentation and pending session state. Sleep and session-inactive notifications suspend capture; initial normal launch checks on-console session state. This is not verified complete lock-screen exclusion.

Production capture currently fails closed. Its only intended target is `com.apple.notificationcenterui`; static bundle metadata supplies no verified transient-window/banner identifiers. `NotificationCenterCapture` only calls nonprompting `AXIsProcessTrusted` off the main thread and returns permission-needed or unsupported/unverified, without enumerating the notification AX tree or reading content. `NotificationTreeReading` separates metadata from text; `NotificationClassifier` demonstrates a metadata-first profile boundary with fictional fixture identifiers. Limits are four windows, 64 nodes, depth six, 24 strings, 512 characters per raw string and 150 ms elapsed. A future real public AX reader is still gated on verified layout evidence and enforcing a 40 ms AX messaging timeout plus all read budgets. No database, private API, Full Disk Access, screenshots or notification persistence/logging/hashes are used.

Only diagnostic main-frame `testNotification {source?,title?,body?,clear?,expire?}` injects, clears or expires synthetic banners. Normal mode ignores it. Diagnostic/smoke mode bypasses capture entirely even if the setting is true; there is no live-capture flag. General `Lilt.inspect()` includes only `notification {visible,hasText}` and a native `ready` marker, never banner text or dedup keys. Native diagnostic responses add only `notificationCaptureStatus`, `notificationVisible`, `notificationGeneration`, `notificationPanelKey` and `notificationAcceptsKey`. The last two are booleans for arrival-focus checks. A banner arrival sets the panel's key eligibility false before displaying it; only explicit interaction or takeover restores it.

Run `node scripts/native-command.mjs DIRECTORY scripts/check-native-notifications.js` against an isolated diagnostic app for synthetic hostile-text, expiry, ownership, clear, reduced-motion and restoration checks. Run `node scripts/native-command.mjs DIRECTORY scripts/check-native-notification-settings.js '' settings` for opt-in/status/Preview wiring. These are not live capture evidence. `scripts/build-app.sh` has no alternate output directory and always writes/signs `build/Lilt.app`; do not use it when preserving that app. `swift build --scratch-path /tmp/lilt-notifications-swift` compiles without replacing it. A temporary diagnostic bundle can copy that binary, `Resources/Web`, the three licence texts and its own unique Info.plist/bundle identifier, with `--ui-test-dir` pointing to isolated data.

## Native → UI

`window.Lilt` exposes:

- `configure({hardwareWidth?,hardwareHeight?,reducedMotion?})` applies supplied geometry/accessibility values.
- `setOpen(boolean)`, `setView('music'|'focus'|'shelf')`.
- `setDragging(boolean)` displays the native file-drag target state.
- `swipeGesture(phase,dx,dy,accepted,x,y,inputTime?)` receives precise native scroll phases (`begin`, `change`, `end`, `cancel`). Deltas retain macOS scroll direction; x/y are WebView coordinates and `inputTime` is the native monotonic event time in seconds. Pending calls are batched in order with one JavaScript evaluation in flight; no gesture phase or delta is discarded. The UI paints accumulated tracking once per display frame, including the tab marker, and settles from its current position and measured input velocity. Direct diagnostic calls may omit time. Vertical/horizontal-scroll exclusions, file drag, cancellation and reduced motion remain enforced. This API does not confirm a physical finger count or hardware performance.
- `receiveMusicSnapshot({availability,id,title,artist,album,queueID,duration,elapsed,playing,buffering,speed,cover,canPlay,canPause,canNext,canPrevious,pending,error})` mirrors the native MusicCoordinator. Times are seconds. Availability is checking, ready, offline, empty, unavailable or disabled. Cover is a bounded JPEG data URI or null; pending is play, pause, next, previous or null; error is `{code,message}` or null.
- `receiveFocusSnapshot({activity,duration,remaining,deadline,phase,owned,restoring,pending,error})` accepts the native FocusCoordinator snapshot. Activity is `deepWork` or `lightWork`; duration/remaining are seconds; deadline is Unix milliseconds or null. Phase is idle, running, paused, completed, uncertain or checking. Pending is `{id,action}` or null; error is `{code,message,action}` or null.
- `receiveShelfSnapshot({items,message})` replaces the visible shelf from native storage. An item contains `{id,name,location,available,kind,expiresAt,retention,thumbnail?}`. The optional bounded image preview is a data URI; full paths and bookmark data never enter the WebView. The ID identifies a native stored entry.
- `inspect()` returns the rendered UI/native mirror and JavaScript errors. It is read-only and does not drive the native timer.

Native FocusCoordinator owns duration, activity, optional confirmed playback, wall-clock deadline, pending operation ID, storage and recovery. The UI has no independent focus timer, optimistic playback state or completion authority. Music only interpolates elapsed playback time between confirmed selected-player snapshots. It never selects a new track or declares playback on its own.

## UI → native

Every message uses `window.webkit.messageHandlers.lilt.postMessage`:

- `ready`: configure geometry, deliver native stores and show the window.
- `openChanged {open}`: window state; rendered ResizeObserver hitRect supplies actual shape.
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

Native NotchWebView accepts real incoming file URLs from NSDraggingInfo rather than reducing a drop to JavaScript file names. Outbound drags use native URL pasteboard items. Mouse-down capture is scoped to Lilt's own panel; no global input is synthesized for Shelf.

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

`scripts/build-meld-bridge.sh` compiles the small `Resources/Android/MeldBridge.java` source against Android 34 and packages DEX into `Contents/Resources/MeldBridge.jar`. The runtime pushes that trusted helper into the isolated emulator's `/data/local/tmp` on connection. `app_process` initializes the Android 14 media framework and uses MediaSessionManager without root, application changes or security-policy changes. No account data or private Meld files are read. Metadata and at most a 160px JPEG thumbnail enter the WebView; no remote artwork URL is loaded.

MeldController runs on a serial background queue with bounded process time/output and explicit arguments. MusicCoordinator reads approximately every two seconds, including while folded. An in-flight read cannot overwrite a later user request. Command results must prove the requested state or track change; an exit code alone is insufficient. Polling never starts the emulator, activity or music. Unknown/closed/empty sessions clear apparent playback. Open Meld is an explicit return path, including when the emulator is running but the Android activity was closed. Music is not persisted by Lilt; restarting rereads Meld without a Play command. Compact presentation follows the explicitly selected view.

## Window and diagnostics

Fixed 680×300 transparent panel at true screen top above menu-bar icons. CSS k=1, expanded max(500,hardwareWidth+260) × (hardwareHeight+160); compact (hardwareWidth+132) × hardwareHeight. Black #000000, original spring, minimum hardware height. Native passthrough tracks rendered shape. First click accepted. Header/Fold/Escape close. Window-key loss folds, except while a native picker/menu is active.

`--ui-test-dir DIR` reads command.json `{id,script,snapshot:true?}`; async JS returns response.json and optionally capture.png. `--simulate-brainfm` and `--simulate-meld` use distinct fake native players. `--live-brainfm` or `--live-meld` enables only the respective real player in diagnostics. Default diagnostic/smoke never controls music/permissions. Simulated evidence is labeled separately.

Startup ignores a pre-existing command ID so reused diagnostic directories never replay an old playback or quit command. Submit a fresh ID after the app starts.

Only simulated diagnostics accept `testFocus {activity?,playback?,error?,message?,clearError?,remaining?,poll?}`. This updates the fake player or a bounded native test remainder, and never enables real music. Production UI has no fixture authority. `scripts/check-native-ui.js` checks this native simulation plus explicitly labeled UI-only shelf fixtures; real file storage is covered by Swift tests and independent native interaction checks.

Only `--ui-test-dir` with `--simulate-meld` accepts `testMusic {availability?,id?,title?,playing?,buffering?,error?,message?,clearError?}`. This mutates the fake player and requests a read; normal and live modes ignore it. `scripts/check-native-meld.js` is explicitly simulated evidence.

## Everyday controls

Settings additionally persist `shortcut {keyCode,modifiers}` (macOS virtual key code and Carbon modifier mask) and `focusNotificationsEnabled` (default false). Missing shortcut settings migrate to Control-Option-L. The native keyboard recorder accepts a key with Control, Option or Command; Escape cancels and Tab leaves recording. Replacement registration precedes storage and releases the old registration only after success. A conflict retains the previous binding. Diagnostic/smoke modes never register global shortcuts.

`shortcutRecord`/`shortcutCancelRecording` start/end recording in the settings window. Native `receiveShortcutRecording({recording,error?})` drives its visible state. `shortcutRecordingEnded` restores registration. Timer notification permission is requested only by the explicit `focusNotificationPermission` action, independently of other-app notification capture and Brain.fm. Snapshots include `focusNotificationStatus` and `focusNotificationRequesting`. Isolated modes do not create a system notification center or request permission; the opt-in is simulated locally. The OS schedules one completion notification for the current native deadline. Pause/reset/extension/opt-out cancel or replace pending notifications; opening a delivered notification only opens Focus.

`focusAction {command:'extend'}` adds five minutes, capped at a total of 180 minutes. `duration` remains the original preset; `totalDuration` includes persisted `extensionSeconds`, and `canExtend` controls availability. A completed Brain.fm work phase restarts only after confirmed Play. A paused phase stays paused, and an extended interval reopens the same phase without counting a work period twice. The next interval still requires explicit action. Idle/completed standalone Focus does not keep a repeating native timer active.

Shelf accepts directory references without recursion. `shelfAction {command:'paste'|'undo'}` reads the clipboard only after explicit paste or restores up to twenty in-memory removal operations. `canUndoRemoval` accompanies Shelf snapshots. Expired references and duplicate re-added references are not resurrected. Diagnostic paste uses a named pasteboard configured with `testShelfPaste {names:[...]}` from files under the isolated data directory's `fixtures` folder, never the user's clipboard.

`shelfDragRegions {regions:[{id,x,y,width,height}],selected:[id...]}` reports bounded visible hit regions and selection. Native mouse-down resolves the authoritative references synchronously; movement beyond four points begins an AppKit file drag, using that actual drag event. WebKit does not initiate an HTML drag and Shelf is not rebuilt to start it. The source only offers Copy and stays open during a native drag. Scroll/layout/selection changes update the regions. Mouse-up clears preparation so a late event cannot reuse previous files.

`dismissMenus()` closes transient Focus/Shelf menus and returns whether one was open. A blank click that dismisses a menu does not also fold Lilt. Native outside interactions use the same result, with stale-close callbacks invalidated by newer panel interactions.

Additional isolated checks: `check-native-everyday.js`, `check-native-shelf-everyday.js` (fixtures `first.txt`, `folder`, `second.txt`) and `check-native-everyday-settings.js`. `testShelfKey` exercises Command-V/Command-Z with native key equivalents; `testShortcutKey` exercises native recording without system registration; `testOutsideInteraction` uses the normal outside-dismiss policy. These actions are ignored outside diagnostics. Diagnostic results expose native drag completion/operation counts, separately from a receiving-app drop.

`--isolate-desktop-input` with `--ui-test-dir` ignores unrelated global desktop input during deterministic probes. Native pointer fixtures and `testOutsideInteraction` still exercise local input and the normal dismissal policy. This flag does not establish real desktop or hardware acceptance. `check-native-background.js` checks completion and pause while folded on a different tab. `LILT_APP_DIR` can direct a build to a separate absolute `.app` path, preserving a running user bundle.
