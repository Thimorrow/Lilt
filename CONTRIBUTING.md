# An Lilt mitarbeiten

Kleine, klar begrenzte Beiträge sind willkommen. Größere Änderungen zuerst in einem [Issue](https://github.com/Thimorrow/Lilt/issues) besprechen. Bestehende Gestaltung, zugängliche Bedienung und lokale Datenverarbeitung erhalten.

## Lokal starten

Benötigt werden macOS 15 oder neuer, Xcode mit Swift und Node.js für die JavaScript-Tests. Die CI verwendet Node.js 24. Android ist ausschließlich für die optionale Meld-Anbindung erforderlich.

```sh
git clone https://github.com/Thimorrow/Lilt.git
cd Lilt
LILT_BUILD_MELD=0 LILT_SIGN_IDENTITY=- ./scripts/build-app.sh
open build/Lilt.app
```

Ad-hoc-Signierung benötigt kein Apple-Entwicklerkonto. Sie ist für lokale Builds gedacht; macOS-Berechtigungen können nach Neubauten erneut nötig sein. Der Quellcode-Start ist kein notarisiertes App-Release.

## Prüfen

```sh
swift test
node --test scripts/test-ui.mjs scripts/test-focus.mjs scripts/test-settings.mjs
bash -n scripts/build-app.sh scripts/build-meld-bridge.sh
git diff --check
```

Die GitHub-CI führt Tests, einen Release-Build ohne Android, eine Signaturprüfung und einen Gitleaks-Scan des Git-Verlaufs aus. Lokale App-/Playerprüfungen bleiben davon getrennt. Anleitungen für isolierte WKWebView-Prüfungen stehen im [README](README.md).

Tests mit `--ui-test-dir` oder einem eigenen `--data-dir` isolieren. Die normale App und echte Nutzerdaten nicht für automatisierte Wiederholungen verwenden. Echte Musiksteuerung oder Berechtigungsdialoge gezielt prüfen und anschließend den ursprünglichen Playerzustand wiederherstellen. Diagnoseaufnahmen können Titel, Dateipfade oder andere persönliche Inhalte enthalten und bleiben außerhalb des Repositorys.

## Pull Requests

- Beschreiben, welches Problem die Änderung löst und wie sie geprüft wurde.
- Relevante Logiktests ergänzen; sichtbare Änderungen zusätzlich in der tatsächlichen App bedienen. Fehlende Live-/Hardwareprüfungen nennen.
- Keine Zugangsdaten, Signierschlüssel, Kontodaten, Diagnoseaufnahmen oder Build-Ausgaben einchecken.
- Beiträge werden unter der Projektlizenz MIT eingereicht; Drittanbieterlizenzen und [Credits](THIRD_PARTY_NOTICES.md) erhalten.

Sicherheitsprobleme gemäß [SECURITY.md](SECURITY.md) vertraulich melden.
