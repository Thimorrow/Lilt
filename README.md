# Lilt

Lokale Mac-App nach der [Lilt-Studie von Vayun Godara](https://vayun.net/studies/lilt/), mit originalen Animationskurven und Anpassung an die echte Kameranotch.

## Produktrichtung

Lilt soll eine eigenständig einstellbare Mac-App für Musik, Fokus und Dateien werden. Priorität haben direkte, einfach einzurichtende Anbindungen an Spotify und Apple Music. Musikanbieter und weitere Lilt-Einstellungen sollen innerhalb der App konfigurierbar sein. Focus soll auch ohne Brain.fm funktionieren; eine Brain.fm-Anbindung ist optional.

Dieser Ausgangsstand enthält noch die bisherige Meld-Musiksteuerung und den an Brain.fm gekoppelten Fokus-Timer. Direkte Spotify-/Apple-Music-Anbindungen, ein unabhängiger Fokus-Timer und eine zentrale Einstellungsansicht sind **noch nicht umgesetzt**. Die Anforderungen stehen in [SPEC.md](SPEC.md).

Das GitHub-Repository ist zunächst privat. Der Nutzer hat die Open-Source-Veröffentlichung freigegeben; die Projektlizenz und Hinweise zu übernommenen Assets sind vor der öffentlichen Freigabe noch festzulegen. Herkunft: [docs/REFERENCE.md](docs/REFERENCE.md).

## Voraussetzungen

Benötigt macOS 15+ und Xcode/Swift zum Bauen. Für die Meld-Anbindung werden die hier vorhandenen Android-SDK-Plattform 34, Build Tools 36.0.0 und das JDK aus Android Studio verwendet. `ANDROID_SDK_ROOT` und `JAVA_HOME` können die Buildpfade ersetzen.

## Starten

```sh
./scripts/build-app.sh
open build/Lilt.app
```

Auf die kompakte Notch klicken. Der obere Bereich, Fold und Escape klappen sie wieder ein. Music, Focus und Shelf wechseln die Ansichten. Beenden über das Menüleistensymbol.

## Music und Meld

Music liest den tatsächlichen Player der separat eingerichteten Meld-Android-Umgebung. Titel, Künstler, Cover, Dauer und Wiedergabefortschritt kommen aus Meld. Play/Pause und Vor/Zurück verwenden ausschließlich dessen Android-Mediensitzung. Änderungen direkt in Meld werden ungefähr alle zwei Sekunden übernommen. Es gibt keine Beispieltitel oder lokalen Scheinwiedergaben mehr.

- Meld muss über `~/Applications/Meld.app` eingerichtet sein. Der zugehörige Emulator heißt `Meld` und verwendet Anschluss 5580; der lokale ADB-Server verwendet 5040. Andere Android-Geräte und Mac-Musikplayer werden nicht gesteuert.
- Die Zustandsprüfung öffnet Meld nicht und startet keine Musik. Bei geschlossenem Emulator oder fehlendem Titel bietet Music **Open Meld**. Wähle den ersten Titel in Meld selbst.
- Aktive Musik erscheint auch bei einem zuletzt gewählten anderen Tab in der kompakten Notch. Eine aktive oder fehlgeschlagene Fokus-Sitzung behält Vorrang.
- Angefragte Befehle sperren weitere Transportklicks bis zum bestätigten Ergebnis. Fehler werden angezeigt; ein erfolgreicher Befehlsaufruf allein wird nicht als laufende Wiedergabe dargestellt.
- Die Verbindung benötigt keine zusätzlichen macOS-Bedienungshilfen, keinen Spotify-/Google-Tokenzugriff und keinen Root-Zugriff in Android. Sie verändert Meld nicht. Ein kleiner gebündelter Java-Helfer läuft über das vorhandene Android-Diagnosewerkzeug und liest nur die Meld-Mediensitzung.
- Lilt speichert keine Meld-Anmeldung oder Wiedergabehistorie. Meld verwaltet seine eigenen Daten in der separaten Android-Umgebung. Lilt beendet oder pausiert Meld beim eigenen Beenden nicht automatisch.

## Focus und Brain.fm

- Den großen Timer anklicken, um 25, 50 oder eine eigene Dauer von 1–180 Minuten zu wählen. Den dezenten Aktivitätsnamen anklicken, um Deep Work oder Light Work einzustellen. Escape schließt erst die Auswahl und danach die Notch.
- Start wählt die gewünschte Aktivität in der installierten Brain.fm-App und startet oder setzt sie fort. Der Timer läuft erst nach bestätigter Wiedergabe.
- Während der Wiedergabe sind Aktivität und Dauer gesperrt. Eine Änderung nach Pause beginnt eine neue konfigurierte Sitzung.
- Pause, Reset und Timerende prüfen die tatsächlich ausgewählte Aktivität, bevor sie Musik pausieren. Andere Aktivitäten werden nur durch einen ausdrücklichen neuen Start gewechselt.
- Änderungen direkt im Brain.fm-Player werden etwa alle drei Sekunden gelesen, solange eine von Lilt verwaltete Sitzung besteht. Nicht eindeutig erkennbare Zustände werden als Fehler angezeigt.
- Nach App-Neustart wird eine gespeicherte Sitzung erst gegen Brain.fm geprüft. Es startet keine Musik automatisch. Bei unbekanntem externem Pausezeitpunkt bleibt die letzte bestätigte Restzeit erhalten.
- Laufende, pausierte und fehlgeschlagene Fokus-Sitzungen haben in der kompakten Notch Vorrang vor dem zuletzt angesehenen Tab. Nach Abschluss steht dort Done. Der Klick öffnet Focus.
- Der native Timer funktioniert auch bei eingeklappter Notch. Ist Lilt vollständig beendet, kann es Brain.fm nicht am Timerende pausieren. Eine überfällige Sitzung wird beim nächsten Start geprüft und dann gegebenenfalls beendet.

Brain.fm muss installiert und angemeldet sein. „Run in Separate Window“ und „Infinite“ wurden auf diesem Mac mit Nutzerfreigabe eingestellt, damit der Player im Hintergrund erreichbar bleibt und Lilt die Zeit übernimmt.

Lilt benötigt die macOS-Freigabe unter Datenschutz & Sicherheit → Bedienungshilfen, ab macOS 27 „Device Control and Data Access“. Open Settings in Lilt fordert sie für die aktuelle App an. Die App liest nur die benötigten Bedienelemente von Brain.fm. Eingaben werden ausschließlich an dessen überprüften Prozess geschickt. Die START-Navigation verwendet die angebotene Bedienungshilfen-Aktion des eindeutig erkannten Elements. Keine globalen Medien- oder Tastatureingaben, synthetischen Mausklicks, Browser, Kontotokens oder kopierten Anmeldedaten.

Eine offene Aktivitätsauswahl oder die Home-Ansicht mit Miniplayer bestätigt keine Pause. Bei unklarer Ansicht meldet Lilt einen Fehler und bietet Open Brain.fm. Wechselt der Nutzer zu einer anderen Aktivität, verwirft Reset nach bestätigtem Aktivitätsverlust nur die lokale Sitzung.

## Shelf

Lokale Dateien hineinziehen oder auswählen. Lilt speichert Dateiverweise einschließlich lokaler Bookmarks und verändert die Originaldateien nicht.

- Anklicken zeigt Quick Look. Das ⋯-Menü bietet Quick Look, Öffnen, im Finder zeigen und einzelnes Entfernen.
- Dateien lassen sich aus der Ablage in Finder oder andere Apps ziehen. Die Quelle bietet ausschließlich Kopieren an.
- Add fügt weitere Dateien hinzu. Clear entfernt nur die Verweise aus Lilt.
- Bis zu 24 Dateien sind über die horizontal scrollbar erreichbare Liste zugänglich. Gleichnamige Dateien aus verschiedenen Ordnern bleiben getrennt.
- Die Ablage bleibt nach Neustart erhalten. Fehlende Dateien bleiben als nicht verfügbare Einträge sichtbar und lassen sich entfernen.

Normale App-Daten liegen in `~/Library/Application Support/Lilt/focus.json` und `shelf.json`. Es findet kein Upload statt.

## Prüfen

```sh
swift test
node --test scripts/test-ui.mjs scripts/test-focus.mjs
build/Lilt.app/Contents/MacOS/Lilt --smoke-test
```

Diagnoseläufe schließen eine bereits regulär laufende Instanz nicht selbst. Vorher Lilt beenden; die App verhindert doppelte Instanzen.

- `--ui-test-dir /tmp/lilt-review --simulate-brainfm --simulate-meld` prüft die Oberfläche mit ausdrücklich simuliertem nativen Player. `node scripts/native-command.mjs /tmp/lilt-review scripts/check-native-ui.js` führt den zusammenhängenden UI-Lauf aus.
- `scripts/check-native-tabs.js` und `scripts/check-native-motion.js` prüfen die unveränderten Tab-/Formübergänge.
- `scripts/check-native-focus-choices.js` prüft Timer-/Aktivitätsmenüs, Tastatur, eigene Dauer, Lesbarkeit und die stabile Play-Position im tatsächlichen WKWebView. Dafür dieselbe ausdrücklich simulierte Brain.fm-Testinstanz verwenden.
- `--ui-test-dir /tmp/lilt-review --live-brainfm` steuert die echte App und kann Audio starten. Nur für gezielte autorisierte Verbindungstests verwenden.
- Ohne diese Zusätze unterdrückt Diagnose-/Smoke-Modus sowohl die Brain.fm- als auch Meld-Steuerung. `--live-meld` erlaubt gezielt die echte Meld-Verbindung; `--simulate-meld` wählt den getrennten Testplayer. `scripts/check-native-meld.js` prüft dessen leere, getrennte, externe und fehlerhafte Zustände ausdrücklich simuliert.
- Diagnosemodus speichert unter `TEST_DIRECTORY/data`. Smoke verwendet ein eigenes temporäres Verzeichnis. `--data-dir /private/tmp/lilt-review-data` wählt auch im normalen App-Betrieb einen isolierten Speicher, ohne echte Musiksteuerung zu unterdrücken. Das erlaubt echte Maus-/Tastatur- und Neustartprüfungen ohne Produktdaten zu verändern.
- Simulationsbefehle `testFocus` beziehungsweise `testMusic` werden ausschließlich bei `--ui-test-dir` zusammen mit `--simulate-brainfm` beziehungsweise `--simulate-meld` angenommen. Sie sind kein Nachweis echter Musiksteuerung.

Bei eingeschränkten Schreibrechten können die Swift-Caches auf ein temporäres Verzeichnis gelegt werden:

```sh
env CLANG_MODULE_CACHE_PATH=/private/tmp/lilt-clang SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/lilt-modules swift test --disable-sandbox --cache-path /private/tmp/lilt-spm --scratch-path /private/tmp/lilt-build
```

Das Build-Skript verwendet eine eindeutig vorhandene Apple-Entwicklungssignatur. Alternativ kann `LILT_SIGN_IDENTITY` gesetzt werden. Ohne eindeutige Identität fällt es auf Ad-hoc-Signierung zurück; dabei können macOS-Freigaben nach Neubauten ungültig werden. Eine bereits funktionierende Entwicklungssignatur für Verbindungstests beibehalten. Keine Veröffentlichung oder Notarisierung erfolgt.

## Aufbau

AppKit verwaltet Fenster, Hardwaregeometrie, Menü, Dateiauswahl, lokale Sitzungs-/Dateispeicherung und Brain.fm-/Meld-Steuerung. `FocusCoordinator` ist die einzige Autorität für Timer, Befehlsbestätigung und Wiederherstellung. `MusicCoordinator` verwaltet den bestätigten Meld-Zustand; `MeldController` prüft das feste Android-Ziel und ruft den gebündelten `MeldBridge` auf. `ShelfStore` verwaltet lokale Dateiverweise. Ein lokales WKWebView zeichnet die Notch mit gebündelter Schrift und CSS und zeigt die bestätigten nativen Zustände. Keine entfernte Webseite wird in Lilt geladen.

Quellen und Motion-Vertrag: [docs/REFERENCE.md](docs/REFERENCE.md). Schnittstelle: [docs/BRIDGE.md](docs/BRIDGE.md). Aktueller Prüfstand und Grenzen: [STATUS.md](STATUS.md).

Die in den Dokumenten genannten Dateien unter `docs/evidence/` sind lokale Prüfaufnahmen und Diagnoseprotokolle. Sie werden nicht in das Repository hochgeladen. Dort dokumentierte ältere Prüfergebnisse wurden nicht automatisch durch einen neuen Checkout bestätigt.
