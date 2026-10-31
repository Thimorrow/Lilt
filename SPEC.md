# Lilt

## Ziel
Eigenständig einstellbare lokale Mac-App an der Bildschirm-Notch nach https://vayun.net/studies/lilt/. Musik, Fokus und Dateien sollen ohne die spezielle Einrichtung dieses Macs nutzbar sein. Notch-Geometrie und bestehende Bewegung erhalten.

## Aktuelle Produktrichtung · 2026-10-31

Diese Anforderungen ersetzen die früheren Beschränkungen auf Meld und verpflichtendes Brain.fm. Direkte Controller, unabhängiger Timer und zentrale Einstellungen sind implementiert. Tatsächliche Abnahme und offene Live-Nachweise stehen in STATUS.md; spätere Abschnitte dokumentieren auch frühere Anforderungen.

- **Music:** direkte, einfach einzurichtende Unterstützung für Spotify und Apple Music. Diese Anbieter dürfen keine Meld-/Android-Umgebung voraussetzen. Metadaten und Wiedergabebefehle müssen den tatsächlichen Zustand des gewählten Players zeigen beziehungsweise bestätigen.
- **Focus:** als Timer ohne Brain.fm nutzbar. Brain.fm ist eine optionale Integration. Fehlendes Brain.fm oder dessen Berechtigung darf den unabhängigen Timer nicht blockieren.
- **Einstellungen:** eigenes natives Fenster mit Music-/Focus-Navigation, im Lilt-Stil mit gebündelter Schrift, dunklen Flächen und kurzen unterbrechbaren Auswahl-/Ansichtsübergängen. Playerquelle, optionale Brain.fm-Verbindung, Fokusdauer und Aktivität werden nativ bestätigt und gespeichert. Tastatur und reduzierte Bewegung wechseln unmittelbar. Öffnen über Zahnrad, Menü oder ⌘,; Fenstergrößen ab 700 × 540.
- **Kompaktansicht:** die ausdrücklich gewählte Ansicht bleibt beim Falten und Öffnen erhalten. Music darf durch laufenden, pausierten oder abgeschlossenen Focus nicht verdrängt werden. Das ersetzt den früheren automatischen Fokusvorrang. Freie Innenflächen und Außenklicks schließen die Notch; Bedienelemente bleiben bedienbar. Der sichtbare Fold-Knopf entfällt.
- **Dropdowns und Popover:** vollständiger Maus-Down/Up-Klick auf Deep Work/Light Work übernimmt die Auswahl, ohne die Notch zu schließen. Eintritt scale .95 → 1 und opacity 0 → 1 in 200 ms mit cubic-bezier(.23,1,.32,1). Austritt scale 1 → .95 und opacity 1 → 0 in 150 ms ease-in. Skalierungsursprung am jeweiligen Auslöser, kein scale(0). Unterbrechbare Umkehr, sofortige Eingabesperre beim Schließen und direkte Umschaltung bei Tastatur/reduzierter Bewegung erhalten.
- **Einrichtung:** benötigte Apps und Berechtigungen nachvollziehbar anzeigen; kein automatischer Musikstart beim Einrichten oder Neustarten. Keine kopierten Kontoanmeldungen und keine Zugangsdaten im Repository.
- **Open Source:** Veröffentlichung vom Nutzer freigegeben, MIT als Projektlizenz gewählt. Vayun Godara als Urheber der ursprünglichen Studie nennen; seine Erlaubnis zur Veröffentlichung wurde vom Nutzer bestätigt. Familjen Grotesk bleibt unter OFL-1.1. Nach Abschlussprüfungen das bestehende Repository öffentlich schalten; kein notarisiertes App-Release ist damit zugesagt.

### Akzeptanz der nächsten Umsetzung

- [ ] Spotify auf einem Mac ohne Meld auswählen, tatsächliche Titelinformationen lesen und Play/Pause sowie Vor/Zurück mit bestätigtem Ergebnis ausführen.
- [x] Apple Music: tatsächliche Titelinformationen, bestätigtes Play/Pause und Vor/Zurück im signierten App-Prozess geprüft; ursprünglichen Titel/Wiedergabezustand wiederhergestellt. Leere Sitzung und ausdrückliche Automation-Freigabe ebenfalls tatsächlich beobachtet. Fehlende/geschlossene Player zusätzlich in Controller-Tests.
- [x] Musikquelle in Lilt auswählen; Auswahl bleibt nach tatsächlichem Neustart erhalten. Quellenwechsel-/Pending-/Stale-Reply-Schutz automatisiert geprüft.
- [x] Focus ohne Brain.fm-Aufrufe starten, pausieren, fortsetzen und beenden; mit deaktiviertem nativen Brain.fm-Transport im echten WKWebView geprüft. Brain.fm ist auf diesem Mac installiert, wurde dafür weder entfernt noch verwendet. Wiederherstellung separat geprüft.
- [x] Optionale Brain.fm-Verbindung ausdrücklich aktivieren; ausgeschaltet keine Brain.fm-Steuerung und keine dafür nötige Berechtigung anfordern. Native Einstellungen, unabhängiger Lauf und Controller-Aufrufprüfungen bestanden.
- [x] Einstellungen im echten WKWebView bedienen, speichern und nach tatsächlichem Neustart wiederfinden. Maus-/Tab-Tasteneingabe zusätzlich nativ geprüft; weitere Tastaturinteraktionen im gerenderten JS-Lauf. Notch-, Tab- und Shelf-Regressionen bestanden.
- [x] Gewählte Music-/Shelf-Ansicht beim Falten und Öffnen erhalten, auch bei laufendem, pausiertem oder abgeschlossenem Focus. Freie Innenfläche/Außenklick schließen; Bedienelemente bleiben offen.
- [x] Automatisierte Prüfungen, tatsächliche Player-Verbindungen und gerenderte Bedienung getrennt nachweisen. Fehlender Spotify-Livetest und menschliche Designabnahme bleiben ausdrücklich offen.

## Bisherige Umsetzung

## Oberfläche und Bewegung
- Native AppKit-Menüleisten-App, transparentes rahmenloses NSPanel, lokal gebündeltes WKWebView. Keine entfernte Webseite/Analytics im UI.
- Originalschrift, Cover, Icons und Kurven. Vayun Godara als Quelle dokumentiert.
- Form: 520 ms, linear(0, .062 3.5%, .24 8.5%, .5 14.5%, .76 21.5%, .93 29%, 1.024 38%, 1.042 46%, 1.03 56%, 1.008 70%, 1).
- Öffnen: Inhalt nach 120 ms, opacity 220 ms linear, blur 320 ms cubic-bezier(.16,1,.3,1). Falten: Inhalt 120 ms; Compact erscheint nach 180 ms mit 220 ms opacity.
- Tabs nach Nutzerfeedback: alter Inhalt 70 ms ausblenden, danach neuer Inhalt mit 160 ms opacity und 200 ms transform, 2 px Weg und scale .99. Pille separat 240 ms; Beschriftungen bleiben beim Gleiten lesbar. Umkehrbare CSS-Übergänge, Tastatur und Reduced Motion direkt. Play sitzt in Music und Focus an derselben Position.
- Cover: 320 ms, ±10 px und scale .9. Musikbalken: 900 ms mit fünf versetzten Phasen.
- Nach expliziter Hardwarekorrektur #000000, kompakte Höhe gleich safeAreaInsets.top, Radius 10 px. Originalkurven bleiben erhalten.
- Erster Klick aus anderen Apps muss funktionieren. Oberer Notch-Bereich, freie Innenflächen, Außenklick und Escape falten. Tabs und andere Bedienelemente dürfen nicht versehentlich schließen. Kein sichtbarer Fold-Knopf. Keine doppelten Instanzen.
- Reduced Motion wird berücksichtigt.

## Brain.fm
- Installierte App com.electron.brain.fm verwenden, keine Browserumleitung.
- Nutzer autorisierte macOS-Bedienungshilfen sowie Brain.fm „Run in Separate Window“ und „Infinite“.
- Start startet Deep Work oder setzt vorhandene Fokusmusik fort. Pause pausiert Musik und Timer. Reset und Ende pausieren die laufende Sitzung.
- Timerzustand erst nach bestätigtem Playerzustand ändern. Pending verhindert doppelte Befehle. Fehler sichtbar, keine simulierten Erfolgsmeldungen im normalen Betrieb.
- Steuerung ausschließlich der erkannten Brain.fm-Instanz. Keine globalen Medientasten, kopierten Tokens oder Änderungen am fremden App-Bundle.
- Fremde Aktivitäten wie Sleep nicht eigenmächtig als Fokus übernehmen.
- Berechtigungen nur nach Nutzerentscheidung. Stabile vorhandene Entwicklungssignatur verwenden, damit lokale Neubauten die Identität erhalten.

## Verifikation
- Release-App bauen/starten, Signatur prüfen.
- Geometrie-/Controller- und Fokus-Zustandstests.
- Echte WKWebView-Animation und Hardwareposition prüfen.
- Normale App per Maus/Tastatur bedienen: Öffnen, Tabwechsel, obere/freie Klickfläche, Außenklick, Escape und Einstellungen.
- Reales Brain.fm: Start, Pause, Fortsetzen, Reset, Kaltstart. Simulierte UI-Prüfungen getrennt dokumentieren.
- Stand und Belege: STATUS.md. Menschliche Designabnahme bleibt beim Nutzer.

## Bisherige Begrenzungen
Music unterstützt Spotify, Apple Music und die unten dokumentierte Meld-Anbindung. Allgemeine Unterstützung beliebiger Player, ein globales Tastenkürzel, Sprachwechsel, Autostart und Installation nach /Applications sind damit nicht zugesagt. Der aktuelle Feature-Auftrag umfasst lokale Umsetzung und Verifikation, keinen Commit, Push, Release oder Merge.

## Erweiterung vom 2026-10-30

### Beauftragt
- Focus vervollständigen: wählbare Dauer, Brain.fm Deep Work oder Light Work, externe Wiedergabeänderungen abgleichen, Sitzungen nach Neustart nachvollziehbar wiederherstellen, klarer dezenter Abschluss.
- Laufender oder fehlgeschlagener Fokus hat in der kompakten Notch Vorrang vor dem zuletzt besuchten Tab. Beim Öffnen führt die aktive Fokus-Anzeige zur Fokusansicht.
- Shelf mit echten lokalen Dateiverweisen: Hineinziehen/Dateiauswahl, Herausziehen, Öffnen, einzelnes Entfernen, Vorschau und im Finder zeigen. Dateiverweise überleben Neustarts. Originale werden weder verschoben noch gelöscht oder hochgeladen.
- Nutzer bestätigte für Shelf sowohl Vorschau/Finder als auch Wiederherstellung nach Neustart.

### Umsetzungsentscheidungen
- Bestehende Notch-Form, Schwarz, Kurven, Tabs und gleiche Play-Position erhalten.
- Nutzerkorrektur vom 2026-10-31: keine dauerhaften Auswahlleisten oder nativen Dropdown-Felder. Fokusdauer direkt über den großen Timer einstellen; Aktivität über schlichten Textknopf mit Chevron. Kleine dunkle kontextuelle Menüs, erst nach Klick sichtbar. Escape schließt erst das Menü und danach die Notch. Tastaturbedienung und reduzierte Bewegung erhalten.
- Focus bietet 25 und 50 Minuten sowie eine begrenzte eigene Dauer. Aktivität und Dauer sind im laufenden/angefragten Zustand gesperrt; eine Änderung im pausierten Zustand setzt die konfigurierte Sitzung nachvollziehbar zurück.
- Native App verwaltet Fokuszustand, Deadline und lokale Wiederherstellung, damit Timerende und Speicherung nicht von sichtbarer Web-Oberfläche abhängen. UI zeigt bestätigten Zustand. Nach Neustart wird keine Musik ungefragt gestartet.
- Zustandsprüfung darf Brain.fm lesen, aber außerhalb eines ausdrücklichen Starts keine neue fremde Sitzung übernehmen oder starten. Ende/Reset pausieren nur die von Lilt kontrollierte Aktivität.
- Keine neuen macOS-Berechtigungen als Voraussetzung für Shelf. Bereits ausgewählte Dateiverweise werden lokal gespeichert; Fehler und nicht mehr verfügbare Dateien bleiben nachvollziehbar.
- Abschluss bleibt innerhalb von Lilt sichtbar und reißt keine andere App aus dem Vordergrund.

### Akzeptanz
- [ ] Deep Work und Light Work aus Lilt auswählen und in echter Brain.fm-App starten, pausieren und zurücksetzen.
- [ ] Andere Brain.fm-Aktivitäten werden beim ausdrücklichen Start kontrolliert gewechselt; reine Zustandsprüfung startet oder wechselt keine Aktivität.
- [ ] Dauer lässt sich wählen, laufende Sitzung lässt sich pausieren/fortsetzen, Timer startet erst nach bestätigter Wiedergabe.
- [ ] Änderungen direkt in Brain.fm werden abgeglichen; unbekannter Zustand wird nicht als bestätigte Wiedergabe dargestellt.
- [ ] Neustart stellt konfigurierte/pausierte Sitzung und Dateiverweise wieder her; aktive Wiederherstellung wird gegen echten Player geprüft.
- [ ] Timerende führt zur bestätigten Pause und sichtbarem Abschluss; Fehlschlag bleibt sichtbar und wiederholbar.
- [ ] Laufender Fokus bleibt in kompakter Notch bei allen Tabwechseln sichtbar; Öffnen landet bei Fokus.
- [ ] Shelf mit isolierten Testdateien hinein-/herausziehen, öffnen, Vorschau, Finder, entfernen und nach Neustart wiederherstellen.
- [ ] Fehlende Dateien und gleichnamige Dateien aus verschiedenen Ordnern funktionieren nachvollziehbar.
- [ ] Originale Testdateien nach Dateiaktionen unverändert vergleichen.
- [ ] Swift-/Node-Prüfungen, Release-Build, Signatur, echter WKWebView und normale App-Bedienung prüfen. Simulierte Brain.fm-Prüfungen getrennt ausweisen.
- [ ] Nutzer beurteilt neue Oberfläche und Bewegungsgefühl selbst.

## Erweiterung vom 2026-10-31 · Meld

Der Nutzer beauftragt, dass Lilt die auf diesem Mac eingerichtete Meld-App erkennt und verwendet. Das ersetzt die frühere Begrenzung von Music auf eine UI-Vorschau.

- Music zeigt tatsächliche Meld-Metadaten, Cover, Fortschritt und bestätigte Wiedergabe; keine Beispieltitel oder selbst erzeugten Titelwechsel.
- Play, Pause, Vor und Zurück wirken ausschließlich auf die eindeutige Meld-Mediensitzung der separaten Android-Umgebung. AVD und Paket werden vor Operationen geprüft.
- Geschlossene Verbindung, fehlender Titel, Ladezustand, Fehler und laufende Anfrage bleiben erkennbar. Open Meld ist der ausdrückliche Rückweg; Lesen startet weder Emulator noch Musik.
- Direkte Änderungen in Meld werden nachgeführt. Neustart liest den aktuellen Zustand ohne automatische Wiedergabe. Aktiver Focus bleibt in der kompakten Notch vorrangig.
- Originale Notch-Geometrie, Kurven, Tabs und gleiche Play-Position bleiben erhalten. Keine Kontodaten, globalen Medienkeys oder zusätzlichen Systemberechtigungen.
- Neue Logiktests sowie getrennte simulierte WKWebView- und reale Meld-Prüfungen. Release/Signatur und bestehende Focus-/Shelf-/Bewegungsprüfungen bleiben erforderlich. Menschliche Designabnahme bleibt beim Nutzer.
