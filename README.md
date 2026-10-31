# Lilt

Lokale Mac-App für Musik, Fokus und Dateien an der Kameranotch. Die ursprüngliche Gestaltung und Bewegungsstudie stammt von **[Vayun Godara](https://github.com/vayungodara)**: [Lilt-Studie](https://vayun.net/studies/lilt/). Diese native Adaption wird mit seiner Erlaubnis veröffentlicht.

## Produktrichtung

Lilt verbindet Spotify und Apple Music direkt und bietet zusätzlich die lokale Meld-Anbindung. Focus funktioniert unabhängig; Brain.fm ist optional. Musikquelle, Fokusvorgaben und optionale Verbindungen werden im eigenen Einstellungsfenster gewählt und lokal gespeichert. Anforderungen stehen in [SPEC.md](SPEC.md), der tatsächliche Prüfstand und offene Live-Nachweise in [STATUS.md](STATUS.md).

Der Anwendungscode steht unter [MIT](LICENSE). Credits und abweichende Drittanbieterlizenzen stehen in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Lilt ist ein frühes Projekt zum lokalen Bauen; ein notarisiertes App-Release wird noch nicht angeboten. Ein echter Spotify-Wiedergabetest und zusätzliche Hardware-/Langzeitprüfungen sind noch offen.

## Voraussetzungen

Benötigt macOS 15+ und Xcode/Swift zum Bauen. Spotify, Apple Music, Focus und Shelf benötigen kein Android. Die optionale Meld-Brücke wird gebaut, wenn Android-SDK-Plattform 34, Build Tools 36.0.0 und das JDK vorhanden sind. `ANDROID_SDK_ROOT` und `JAVA_HOME` ersetzen die Buildpfade; `LILT_BUILD_MELD=0` lässt die Brücke ausdrücklich weg, `LILT_BUILD_MELD=1` verlangt sie.

## Starten

```sh
git clone https://github.com/Thimorrow/Lilt.git
cd Lilt
LILT_BUILD_MELD=0 LILT_SIGN_IDENTITY=- ./scripts/build-app.sh
open build/Lilt.app
```

Dieser Einstieg benötigt weder Android noch ein Apple-Entwicklerkonto. Er verwendet Ad-hoc-Signierung für den lokalen Build; macOS-Freigaben können nach Neubauten erneut nötig sein. Wer die Meld-Brücke verwenden möchte, kann mit eingerichtetem Android-SDK `./scripts/build-app.sh` ausführen. Weitere Hinweise: [CONTRIBUTING.md](CONTRIBUTING.md).

Auf die kompakte Notch klicken. Der obere Bereich, freie Innenflächen, Außenklicks und Escape klappen sie wieder ein. Buttons und andere Bedienelemente bleiben bedienbar; ein eigener Fold-Knopf entfällt. Music, Focus und Shelf wechseln die Ansichten. Das Zahnrad, das Menüleistensymbol oder ⌘, öffnen die Einstellungen. Beenden über das Menüleistensymbol.

## Einstellungen und direkte Musikverbindungen

- Unter Music Spotify, Apple Music oder Meld wählen. Die Auswahl wird gespeichert. Ein laufender Playerbefehl sperrt den Quellenwechsel; Antworten einer alten Quelle werden verworfen.
- Spotify beziehungsweise Apple Music als normale Mac-App installieren und öffnen. **Connect** erlaubt nach ausdrücklicher Entscheidung die macOS-Automation. Bloße Zustandsprüfung und Quellenwahl fragen keine Berechtigung an und starten weder Apps noch Musik.
- Titel, Interpret, Album, Cover, Dauer, Fortschritt und Wiedergabezustand kommen vom gewählten Player. Play/Pause und Vor/Zurück werden am tatsächlichen Ergebnis bestätigt. Ohne gewählten Titel zuerst im Player ein Lied auswählen.
- Spotify und Apple Music benötigen keine Meld-Umgebung, Web-Anmeldung in Lilt, API-Schlüssel oder Kontotokens. Lilt steuert ausschließlich den gewählten App-Prozess, keine globalen Medientasten. Cover gelangen als begrenzte JPEG-Daten in die Oberfläche; Spotify-Cover werden ausschließlich von dessen Bildserver geladen.
- Unter Focus Standarddauer und Aktivität einstellen. Die optionale Brain.fm-Verbindung ist auf neuen Installationen ausgeschaltet. Änderungen während einer laufenden oder pausierten Sitzung sind gesperrt, bis sie beendet oder zurückgesetzt wurde.
- Einstellungen verwenden die vorhandene Schrift und dunkle Gestaltung. Auswahl und Navigation bewegen sich kurz und unterbrechbar; Tastatureingaben und reduzierte Bewegung wechseln unmittelbar. Das Fenster bleibt unabhängig von der Notch geöffnet.

## Music und Meld

Music liest den tatsächlichen Player der separat eingerichteten Meld-Android-Umgebung. Titel, Künstler, Cover, Dauer und Wiedergabefortschritt kommen aus Meld. Play/Pause und Vor/Zurück verwenden ausschließlich dessen Android-Mediensitzung. Änderungen direkt in Meld werden ungefähr alle zwei Sekunden übernommen. Es gibt keine Beispieltitel oder lokalen Scheinwiedergaben mehr.

- Meld muss über `~/Applications/Meld.app` eingerichtet sein. Der zugehörige Emulator heißt `Meld` und verwendet Anschluss 5580; der lokale ADB-Server verwendet 5040. Andere Android-Geräte und Mac-Musikplayer werden nicht gesteuert.
- Die Zustandsprüfung öffnet Meld nicht und startet keine Musik. Bei geschlossenem Emulator oder fehlendem Titel bietet Music **Open Meld**. Wähle den ersten Titel in Meld selbst.
- Die kompakte Notch zeigt die zuletzt gewählte Ansicht. Music bleibt beim Falten ausgewählt, auch wenn ein Fokus-Timer läuft oder abgeschlossen ist.
- Angefragte Befehle sperren weitere Transportklicks bis zum bestätigten Ergebnis. Fehler werden angezeigt; ein erfolgreicher Befehlsaufruf allein wird nicht als laufende Wiedergabe dargestellt.
- Die Verbindung benötigt keine zusätzlichen macOS-Bedienungshilfen, keinen Spotify-/Google-Tokenzugriff und keinen Root-Zugriff in Android. Sie verändert Meld nicht. Ein kleiner gebündelter Java-Helfer läuft über das vorhandene Android-Diagnosewerkzeug und liest nur die Meld-Mediensitzung.
- Lilt speichert keine Meld-Anmeldung oder Wiedergabehistorie. Meld verwaltet seine eigenen Daten in der separaten Android-Umgebung. Lilt beendet oder pausiert Meld beim eigenen Beenden nicht automatisch.

## Focus und optionale Brain.fm-Verbindung

Ohne Brain.fm funktioniert Focus als nativer Timer mit Start, Pause, Fortsetzen, Reset und Abschluss. Der Timer läuft auch bei eingeklappter Notch. Laufende unabhängige Sitzungen behalten nach Neustart ihre Deadline; inzwischen abgelaufene Sitzungen werden als abgeschlossen angezeigt. Ausgeschaltetes Brain.fm wird weder gelesen noch gesteuert und benötigt keine Bedienungshilfen-Freigabe.

Die folgenden Regeln gelten bei ausdrücklich eingeschalteter Brain.fm-Verbindung:

- Den großen Timer anklicken, um 25, 50 oder eine eigene Dauer von 1–180 Minuten zu wählen. Den dezenten Aktivitätsnamen anklicken, um Deep Work oder Light Work einzustellen. Escape schließt erst die Auswahl und danach die Notch.
- Start wählt die gewünschte Aktivität in der installierten Brain.fm-App und startet oder setzt sie fort. Der Timer läuft erst nach bestätigter Wiedergabe.
- Während der Wiedergabe sind Aktivität und Dauer gesperrt. Eine Änderung nach Pause beginnt eine neue konfigurierte Sitzung.
- Pause, Reset und Timerende prüfen die tatsächlich ausgewählte Aktivität, bevor sie Musik pausieren. Andere Aktivitäten werden nur durch einen ausdrücklichen neuen Start gewechselt.
- Änderungen direkt im Brain.fm-Player werden etwa alle drei Sekunden gelesen, solange eine von Lilt verwaltete Sitzung besteht. Nicht eindeutig erkennbare Zustände werden als Fehler angezeigt.
- Nach App-Neustart wird eine gespeicherte Sitzung erst gegen Brain.fm geprüft. Es startet keine Musik automatisch. Bei unbekanntem externem Pausezeitpunkt bleibt die letzte bestätigte Restzeit erhalten.
- Bei ausgewähltem Focus zeigt die kompakte Notch die Restzeit und nach Abschluss Done. Andere gewählte Tabs bleiben beim Falten und Öffnen erhalten.
- Der native Timer funktioniert auch bei eingeklappter Notch. Ist Lilt vollständig beendet, kann es Brain.fm nicht am Timerende pausieren. Eine überfällige Sitzung wird beim nächsten Start geprüft und dann gegebenenfalls beendet.

Brain.fm muss installiert und angemeldet sein. „Run in Separate Window“ und „Infinite“ wurden auf diesem Mac mit Nutzerfreigabe eingestellt, damit der Player im Hintergrund erreichbar bleibt und Lilt die Zeit übernimmt.

Für Brain.fm benötigt Lilt die macOS-Freigabe unter Datenschutz & Sicherheit → Bedienungshilfen. **Allow control** in den Einstellungen fordert sie ausdrücklich an. Die App liest nur die benötigten Bedienelemente von Brain.fm. Eingaben werden ausschließlich an dessen überprüften Prozess geschickt. Die START-Navigation verwendet die angebotene Bedienungshilfen-Aktion des eindeutig erkannten Elements. Keine globalen Medien- oder Tastatureingaben, synthetischen Mausklicks, Browser, Kontotokens oder kopierten Anmeldedaten.

Eine offene Aktivitätsauswahl oder die Home-Ansicht mit Miniplayer bestätigt keine Pause. Bei unklarer Ansicht meldet Lilt einen Fehler und bietet Open Brain.fm. Wechselt der Nutzer zu einer anderen Aktivität, verwirft Reset nach bestätigtem Aktivitätsverlust nur die lokale Sitzung.

## Shelf

Lokale Dateien hineinziehen oder auswählen. Lilt speichert Dateiverweise einschließlich lokaler Bookmarks und verändert die Originaldateien nicht.

- Anklicken zeigt Quick Look. Das ⋯-Menü bietet Quick Look, Öffnen, im Finder zeigen und einzelnes Entfernen.
- Dateien lassen sich aus der Ablage in Finder oder andere Apps ziehen. Die Quelle bietet ausschließlich Kopieren an.
- Add fügt weitere Dateien hinzu. Clear entfernt nur die Verweise aus Lilt.
- Bis zu 24 Dateien sind über die horizontal scrollbar erreichbare Liste zugänglich. Gleichnamige Dateien aus verschiedenen Ordnern bleiben getrennt.
- Die Ablage bleibt nach Neustart erhalten. Fehlende Dateien bleiben als nicht verfügbare Einträge sichtbar und lassen sich entfernen.

Normale App-Daten liegen in `~/Library/Application Support/Lilt/focus.json`, `shelf.json` und `settings.json`. Einstellungen und lokale Verweise werden nicht hochgeladen.

## Prüfen

```sh
swift test
node --test scripts/test-ui.mjs scripts/test-focus.mjs scripts/test-settings.mjs
build/Lilt.app/Contents/MacOS/Lilt --smoke-test
```

Diagnoseläufe schließen eine bereits regulär laufende Instanz nicht selbst. Vorher Lilt beenden; die App verhindert doppelte Instanzen.

- `--ui-test-dir /tmp/lilt-review --simulate-brainfm --simulate-meld` prüft die Oberfläche mit ausdrücklich simuliertem nativen Player. `node scripts/native-command.mjs /tmp/lilt-review scripts/check-native-ui.js` führt den zusammenhängenden UI-Lauf aus.
- `scripts/check-native-tabs.js` und `scripts/check-native-motion.js` prüfen die unveränderten Tab-/Formübergänge.
- `scripts/check-native-focus-choices.js` prüft Timer-/Aktivitätsmenüs, Tastatur, eigene Dauer, Lesbarkeit und die stabile Play-Position im tatsächlichen WKWebView. Dafür dieselbe ausdrücklich simulierte Brain.fm-Testinstanz verwenden.
- `scripts/check-native-settings.js` prüft bestätigte Konfiguration, Validierung, Tastatur, Sperren und Animationszwischenstände. Mit `node scripts/native-command.mjs TEST_DIRECTORY scripts/check-native-settings.js EVIDENCE_NAME settings` im Einstellungsfenster ausführen.
- `scripts/check-native-independent-focus.js` prüft unabhängigen Timer, Pause/Fortsetzen, Abschluss und freie Klickflächen. Dafür eine Testinstanz ohne `--simulate-brainfm` und ohne aktivierte Brain.fm-Verbindung verwenden.
- `--ui-test-dir /tmp/lilt-review --live-brainfm` steuert die echte App und kann Audio starten. Nur für gezielte autorisierte Verbindungstests verwenden.
- Ohne diese Zusätze unterdrückt Diagnose-/Smoke-Modus alle echten Player. `--live-music` erlaubt gezielt Spotify/Apple Music, `--live-meld` die echte Meld-Verbindung; `--simulate-meld` wählt den getrennten Testplayer. `scripts/check-native-meld.js` prüft dessen leere, getrennte, externe und fehlerhafte Zustände ausdrücklich simuliert.
- Diagnosemodus speichert unter `TEST_DIRECTORY/data`. Smoke verwendet ein eigenes temporäres Verzeichnis. `--data-dir /private/tmp/lilt-review-data` wählt auch im normalen App-Betrieb einen isolierten Speicher, ohne echte Musiksteuerung zu unterdrücken. Das erlaubt echte Maus-/Tastatur- und Neustartprüfungen ohne Produktdaten zu verändern.
- Simulationsbefehle `testFocus` beziehungsweise `testMusic` werden ausschließlich bei `--ui-test-dir` zusammen mit `--simulate-brainfm` beziehungsweise `--simulate-meld` angenommen. Beim unabhängigen Timer erlaubt `testFocus` im Diagnosemodus ausschließlich eine begrenzte Restzeit für die Abschlussprüfung. Diese Befehle sind kein Nachweis echter Musiksteuerung.

Bei eingeschränkten Schreibrechten können die Swift-Caches auf ein temporäres Verzeichnis gelegt werden:

```sh
env CLANG_MODULE_CACHE_PATH=/private/tmp/lilt-clang SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/lilt-modules swift test --disable-sandbox --cache-path /private/tmp/lilt-spm --scratch-path /private/tmp/lilt-build
```

Das Build-Skript verwendet eine eindeutig vorhandene Apple-Entwicklungssignatur. Alternativ kann `LILT_SIGN_IDENTITY` gesetzt werden. Ohne eindeutige Identität fällt es auf Ad-hoc-Signierung zurück; dabei können macOS-Freigaben nach Neubauten ungültig werden. Eine bereits funktionierende Entwicklungssignatur für Verbindungstests beibehalten. Keine Veröffentlichung oder Notarisierung erfolgt.

## Aufbau

AppKit verwaltet Fenster, Hardwaregeometrie, Menü, Dateiauswahl und lokale Speicherung. `SettingsStore` speichert validierte Einstellungen atomar. `SettingsWindowController` zeigt die lokale Einstellungsoberfläche. `FocusCoordinator` ist die Autorität für Timer, optionale Musikbestätigung und Wiederherstellung. `MusicCoordinator` verwaltet die gewählte Quelle; `DirectMusicController` sendet gezielte Apple Events an Spotify oder Apple Music, `MeldController` prüft das feste Android-Ziel und verwendet den gebündelten `MeldBridge`. `ShelfStore` verwaltet lokale Dateiverweise. Die lokalen WKWebViews zeigen bestätigte native Zustände. Keine entfernte Webseite wird geladen.

Quellen und Motion-Vertrag: [docs/REFERENCE.md](docs/REFERENCE.md). Schnittstelle: [docs/BRIDGE.md](docs/BRIDGE.md). Aktueller Prüfstand und Grenzen: [STATUS.md](STATUS.md).

Die in den Dokumenten genannten Dateien unter `docs/evidence/` sind lokale Prüfaufnahmen und Diagnoseprotokolle. Sie werden nicht in das Repository hochgeladen. Dort dokumentierte ältere Prüfergebnisse wurden nicht automatisch durch einen neuen Checkout bestätigt.

## Mitwirken und Sicherheit

Beiträge: [CONTRIBUTING.md](CONTRIBUTING.md). Orientierung für Agenten: [AGENTS.md](AGENTS.md). Sicherheitsprobleme: [SECURITY.md](SECURITY.md). Die [GitHub-CI](.github/workflows/ci.yml) prüft automatisierte Tests, den Build ohne Android, mitgelieferte Lizenztexte und Zugangsdaten im Git-Verlauf. Sie ersetzt keine echte Player- oder Hardwareprüfung.

## Credits und Lizenz

Die ursprüngliche Lilt-Studie, ihre Gestaltung und Animationskurven stammen von [Vayun Godara](https://github.com/vayungodara). Familjen Grotesk stammt von den [Familjen Grotesk Project Authors](https://github.com/Familjen-Sthlm/Familjen-Grotesk) und bleibt unter SIL OFL 1.1. Vollständige Hinweise: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Der Anwendungscode wird unter der [MIT-Lizenz](LICENSE) veröffentlicht.
