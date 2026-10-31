# Mac-Testversion veröffentlichen

Die erste Download-Version wird ausdrücklich als nicht notarisierte Beta veröffentlicht. Es ist aktuell kein gültiges Developer-ID-Zertifikat auf diesem Mac vorhanden. Ein Entwicklungszertifikat ersetzt keine Developer-ID-Signatur. Für einen späteren regulär notarisierten Download sind Apple-Developer-Zugang, Developer-ID-Signatur, passende Hardened-Runtime-Einstellungen und Notarisierung separat einzurichten.

## Paket erzeugen

Auf einem Mac mit Xcode, aus einem sauberen, committeten Quellstand:

```sh
./scripts/package-release.sh 0.1.0-beta.1
```

Das Skript exportiert ausschließlich den aktuellen Git-Commit in ein neues Build-Verzeichnis. Die laufende lokale Entwicklungs-App und ihre Signatur werden nicht ersetzt. Gebaut wird eine Universal-App für arm64/x86_64 ohne Android-Brücke und ohne Entwicklerzertifikat. Release-Bundle-ID: `io.github.thimorrow.Lilt`; lokale Entwicklungsbuilds behalten standardmäßig `local.lilt.preview`.

Ergebnis unter `build/releases/VERSION/`: DMG, ZIP, RELEASE-INFO.txt mit Quellcommit und SHA256SUMS.txt. Die Paketversion bezeichnet die Beta, die App-Version bleibt numerisch, zum Beispiel 0.1.0 mit Build 1. Vorhandene Pakete werden nicht überschrieben. Das Skript akzeptiert ausschließlich `MAJOR.MINOR.PATCH-beta.N`, damit ein nicht notarisiertes Paket nicht versehentlich als stabile Version entsteht.

## Vor Veröffentlichung prüfen

- Swift-/Node-Tests und GitHub-CI des Quellcommits müssen bestehen.
- `hdiutil verify` für das DMG; beide CPU-Architekturen mit `lipo` prüfen.
- DMG schreibgeschützt einhängen, App in einen temporären Installationsordner kopieren und die Signatur sowie mitgelieferte Lizenzen prüfen. ZIP separat entpacken und die App vergleichen.
- Tatsächlich entpackte App mit isolierten Diagnosedaten öffnen. Bestehende Nutzerinstanzen nicht beenden. Falls ihre Bundle-ID kollidiert, die Prüfung koordinieren; ein sofort beendeter Zweitprozess ist kein erfolgreicher Startnachweis.
- Gatekeeper-Ablehnung der nicht notarisierten Beta ehrlich dokumentieren; niemals als notarisiert ausgeben oder systemweite Schutzmechanismen ausschalten.
- Prüfsummen und Quellcommit mit dem Tag abgleichen. Keine Build-Caches, Nutzerdaten, Zugangsdaten oder Diagnoseaufnahmen hochladen.

## GitHub

Den beauftragten Quellstand committen/pushen und CI abwarten. Dann einen neuen Tag `vVERSION` genau auf den im Paket angegebenen Commit setzen und die vier Dateien als GitHub-**Prerelease** veröffentlichen. Weder vorhandene Tags noch Release-Assets überschreiben. Der Release-Text nennt Installationsschritte, fehlende Notarisierung und konkrete Prüfgrenzen. Anschließend die öffentlichen Assets erneut herunterladen und gegen SHA256SUMS.txt prüfen.

Installationshinweise: [INSTALL-BETA.txt](INSTALL-BETA.txt). Apple: [Apps auf dem Mac sicher öffnen](https://support.apple.com/en-us/102445), [Notarisierung](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
