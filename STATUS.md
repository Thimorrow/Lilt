# Status · 2026-10-31

## GitHub und neue Produktrichtung

- Auftrag: GitHub-Repository erstellen und als Ausgangsbasis den vorhandenen Quellcode sichern. Open-Source-Veröffentlichung ist vom Nutzer freigegeben; eine Lizenz wurde noch nicht gewählt.
- Zielrepository: `https://github.com/Thimorrow/Lilt`, zunächst privat. Kein öffentliches Release, keine Notarisierung und kein Merge.
- Neue Prioritäten: direkte, einfach einzurichtende Spotify-/Apple-Music-Anbindungen, Focus ohne verpflichtendes Brain.fm und zentrale Einstellungen innerhalb von Lilt. Anforderungen und prüfbare Akzeptanz stehen oben in SPEC.md. Noch keine Umsetzung dieser neuen Funktionen.
- Ablauf: bestehendes Konto/Repository und Git-Identität prüfen, Produktziel dokumentieren, lokale Diagnoseaufnahmen vom Upload ausschließen, vorhandene automatisierte Tests ausführen, initialen Commit erstellen und den neuen Remote-Stand prüfen.
- Arbeitsaufteilung: sequenziell, keine Subagenten; Quellcode wird für diesen Import nicht funktional geändert. Gemeinsamer Zustand sind Dokumentation und Git-Metadaten. Musikplayer, laufende App und Nutzerdaten werden nicht gesteuert.
- Prüfstand dieses Imports: 34 Swift- und 8 Node-Tests bestanden; beide Build-Skripte syntaktisch geprüft. Begrenzte lokale Mustersuche nach Zugangsdaten im Import ohne Treffer, kein vollständiges Sicherheits-Audit. GitHub bestätigt das neu angelegte private Repository. Der initiale Upload zielt auf main; der lokale Arbeitsbranch ist codex/chore/initial-source-import. Der Remote-Commit wird nach dem Push separat abgeglichen.
- Grenzen dieses Imports: kein neuer Release-/Signaturlauf und keine erneute laufende App-/Playerprüfung, da nur Dokumentation und Git-Ausschlüsse geändert wurden. Frühere App-Nachweise unten sind historische Ergebnisse. Die referenzierten Dateien in docs/evidence/ bleiben lokal und sind kein Bestandteil des Repository-Imports.
- Öffentlich noch offen: Projektlizenz und genaue Drittanbieterhinweise für Gestaltung, Schrift und Assets. Neue Integrationen und Einstellungsoberfläche benötigen eine eigene Umsetzung und Verifikation.

## Meld in Music · umgesetzt und geprüft
- Nutzerauftrag: Lilt soll die auf diesem Mac eingerichtete Meld-App erkennen und über Music verwenden. Der frühere Ausschluss echter Music-Steuerung ist für diese Anbindung aufgehoben.
- Ausgangslage: Unborn `main` ohne Commits bestätigt; vorhandene unversionierte Projektarbeit bleibt erhalten. Vor Änderungen bestanden 24 Swift- und 5 Node-Tests.
- Ziel: echter Titel, Künstler, Cover, Fortschritt und bestätigter Wiedergabezustand statt Beispieltiteln; Play/Pause und Vor/Zurück steuern ausschließlich Meld. Änderungen direkt in Meld werden nachgeführt. Geschlossener Emulator, kein gewählter Titel und Fehler müssen ehrlich sichtbar sein.
- Erhalt: Notch-Geometrie, Originalkurven, bestehende Tabs, Focus-Vorrang und Shelf-Verhalten. Keine globale Mac-Mediensteuerung, Konto-/Tokenzugriffe, fremde Playerbefehle, Veröffentlichung oder Git-Aktionen.
- Technischer Nachweis: Ein isolierter Android-Helfer konnte über die MediaSession-API bereits den tatsächlichen Meld-Titel, Künstler, die Dauer, Position und Pause lesen. Android-14 benötigt im `app_process` zusätzlich die Initialisierung des MediaServiceManager. Probe liegt nur in `/private/tmp/lilt-meld-probe`.
- Blockierende Vorbereitung: Projekt-/Bridge-Prüfung, unveränderte Ausgangstests und read-only Nachweis der Android-Metadaten. Erledigt.
- Unabhängige Arbeit: ein Implementierungsbesitzer für den zusammenhängenden Swift-/Android-/Web-Vertrag; Hauptagent prüft Quelltext und übernimmt echte App-Verifikation. Keine konkurrierenden Dateiänderungen.
- Gemeinsamer Zustand: Statusdatei und reale Playerbedienung beim Hauptagenten; Implementierungsdateien beim Implementierungsbesitzer. Diagnose-/App-Daten bleiben isoliert; echte Focus-/Shelf-Daten werden vor Tests nur gesichert und danach verglichen.
- Kleinste sichere Aufteilung: ein zusammenhängendes Implementierungspaket, danach unabhängige Prüfung von Tests, Release, Signatur, WKWebView und normaler Mausbedienung.
- Akzeptanz: Live-Erkennung, Play/Pause, Titelwechsel, externe Änderung, Neustart und getrennte Fehlerzustände prüfen; bestehende Focus-/Shelf-Tests und Bewegungschecks bestehen. Menschliche Designabnahme bleibt offen.
- Stand 2026-10-31: Implementierung und Verifikation abgeschlossen. 34 Swift- und 8 Node-Tests bestanden. Simulierte Meld-/gemeinsame UI, 72 Tabprüfungen und vier Formprüfungen im echten WKWebView bestanden, jeweils zusätzlich beide Fensterprüfungen. Echte Meld-Verbindung bestätigte Titel/Cover/Fortschritt, Play/Pause, Vor/Zurück, externe Änderungen, leere Sitzung, Offline-Zustand und Kaltstart über Open Meld ohne automatischen Musikstart.
- Gemeinsamer Build: `build/Lilt.app` enthält auch die aktuellen Focus-Timer-/Aktivitätsmenüs. Release und strikte Signaturprüfung mit vorhandener Team-ID `UH56V442WW` bestanden. Regulärer App-Modus ohne Diagnoseflags per Computer Use geöffnet und mit echtem Meld gestartet/pausiert. Normale Testdaten waren isoliert; originale `focus.json` und `shelf.json` sind per Prüfsumme unverändert.
- Nachweise und konkrete Grenzen: `docs/evidence/meld-normal-verification.md` sowie `meld-live-*.json/png`, `meld-ui-simulated`, `meld-combined-ui`, `meld-tabs`, `meld-motion`. Langzeitbetrieb und menschliche Designabnahme offen; ein erster physischer Klick aus einer fremden App wurde wegen eines Computer-Use-Toolfehlers nicht erneut belegt.
- UI-Testkoordination: Meld-Block abgeschlossen und Fenster jetzt FREIGEGEBEN. Sämtliche eigenen Lilt-Prüfprozesse beendet, Android-Meld wieder geöffnet und pausiert bei 17,574 Sekunden. Keine fremde Lilt-Instanz beendet. Focus/Shelf kann am gemeinsamen Build weiterprüfen; keine Meld-Implementierungswrites mehr vorgesehen.

## Focus und Shelf · umgesetzt, Prüfgrenzen dokumentiert
- Nutzerauftrag: Focus mit Deep Work/Light Work, wählbarer Dauer, nativer Timerverwaltung/Wiederherstellung und kompaktem Fokusvorrang; Shelf mit echten lokalen Dateiverweisen, Vorschau, Öffnen, Finder, einzelner Entfernung, Speicherung und Drag-Implementierung. Gemeinsame Meld-Anbindung blieb erhalten.
- Letzte Designentscheidung des Nutzers: Dauer direkt über den großen Timer einstellen. Aktivität über dezenten Textknopf. Keine dauerhaften Auswahlpillen oder nativen Dropdown-Felder. Die ursprüngliche ruhige Hierarchie bleibt erhalten; Pfeile zeigen sich bei Hover/Fokus oder geöffnetem Menü. Gewöhnliche Wiedergabe-/Pausenhinweise sind entfernt, nötige Fehler-/Ladezustände erhalten.
- Umsetzung: FocusSession/FocusCoordinator ist einzige Timer- und Speicherautorität. Bestätigte native Zustände, begrenzte Brain.fm-Steuerung, kein automatischer Musikstart nach Neustart, kein Übernehmen fremder Aktivitäten durch bloße Zustandsprüfung. Veraltete Poll-Antworten überschreiben keine neue Konfiguration. Fehlgeschlagenes Timerende bleibt als Abschlussabsicht erhalten.
- Echte Brain.fm-Nachweise: Deep Work und Light Work aus Lilt gestartet, externe Pause/Fortsetzung übernommen, Pause/Ende bestätigt. Einminütiges Ende funktionierte bei offenem Dateidialog. Abschließend Start/Pause und Menü/Escape im normalen App-Modus mit eigenen Testdaten bedient. Konfiguration/pausierte Sitzung nach Neustart wieder angezeigt.
- Echte Shelf-Nachweise: Datei per nativem Dialog hinzugefügt, Quick Look, Standard-App-Öffnen, Finder-Auswahl, Wiederherstellung nach Neustart und einzelnes Entfernen. Originale Fixture-Prüfsummen unverändert. Gleichnamige/fehlende Dateien und Clear/Limit zusätzlich im Dateimodell geprüft.
- Letzte Prüfungen: Swift 34 und Node 8 bestanden. Native Menüs 25, gemeinsame UI 38, Tabs 72, Formanimation 4 bestanden; jeweils beide Fensterprüfungen. Release und strikte Entwicklungssignatur gültig. Simulierte und echte Playernachweise sind getrennt.
- Belege und genaue Grenzen: `docs/evidence/focus-shelf-verification.md`. Neue Ruheansicht: `docs/evidence/focus-clean-final.png`. Vertrag: `docs/BRIDGE.md`, Umfang: `SPEC.md`.
- Offen: echter Datei-Drag konnte nicht ausgeführt werden, weil die Computer-Use-API AXError.notImplemented meldete. Kein vollständiger 25-Minuten-Dauertest, physischer Sleep-/Zusatzmonitor-Test oder eigenständiger echter Neustart bei laufender Musik. Menschliche Designbeurteilung bleibt beim Nutzer.
- Nutzer meldete zuletzt „alles funktioniert“. Weitere Funktionsprüfungen beendet. Alle eigenen Prüf-Instanzen geschlossen, reguläre `build/Lilt.app` ohne Testparameter wieder gestartet. Keine weitere Build-/UI-Sperre für den abgeschlossenen Meld-Auftrag. Keine Veröffentlichung, kein Autostart, keine Installation nach /Applications, kein Commit/Push/Merge.
- Relevante Dateien: Sources/Lilt/FocusSession.swift, BrainFMController.swift, ShelfStore.swift, NotchWebView.swift, AppDelegate.swift; Resources/Web/app.js, focus-state.mjs, index.html, notch.css; zugehörige Swift-/Node-/nativen Prüfungen. Unborn main und vorhandene unversionierte Arbeit erhalten.

## Tabwechsel · umgesetzt und geprüft
- Ziel: Music, Focus und Shelf wechseln mit ruhigen, kurzen Übergängen und einer gleitenden Auswahlmarkierung.
- Umfang: lokale Web-Oberfläche und passende UI-Prüfungen. Formanimation, Musiksteuerung und Datei-Vorschau bleiben funktional erhalten.
- Entscheidung nach Nutzerfeedback: seitlichen Schub verwerfen. Alter Inhalt blendet in 70 ms aus; danach erscheint der neue Inhalt mit 2 px vertikalem Weg und Skalierung von .99 auf 1. Keine übereinanderliegenden Beschriftungen beim regulären Wechsel. Pille gleitet unabhängig; ihre Beschriftungen behalten während der Fahrt Kontrast. Umkehrbare CSS-Übergänge, inaktive Ansichten sofort für Eingaben und Bedienungshilfen gesperrt. Tastatur und reduzierte Bewegung wechseln direkt.
- Weitere Nutzerkorrektur: Play in Music und Focus bekommt dieselbe feste horizontale und vertikale Position über gemeinsame Inhaltszeilen und gleiche Button-Abstände.
- Ablauf: zuerst bestehenden Wechsel und native Prüfschnittstelle prüfen; ein begrenzter Implementierungsauftrag für die zusammenhängende Oberfläche, anschließend unabhängige Prüfung und Tests. Keine parallelen Änderungen an denselben Dateien.
- Nachweise: 72 Prüfungen im echten WKWebView zu allen Tab-Richtungen, schneller Umkehr/Mehrfachklicks, aktiver Auswahl, stabiler Geometrie, identischer Play-Position, Tastatur und reduzierter Bewegung bestanden. Dazu 27 UI-Prüfungen mit ausdrücklich simulierten Brain.fm-Antworten, einschließlich Fehlerlayout und Play-Position bei Fehlern, sowie vier Formanimationsprüfungen. Je Lauf zusätzlich beide nativen Fensterprüfungen bestanden. Release-Build und Signaturprüfung erfolgreich; Swift 10 und Node 8 Prüfungen bestanden.
- Belege: `docs/evidence/tab-transitions.json`, `tab-ui-simulated.json`, `tab-notch-motion.json`. `tab-mid-transition.png` zeigt einen ausdrücklich bei 110 ms angehaltenen Diagnoseframe mit lesbaren Tab-Beschriftungen und ohne doppelte Inhalte.
- Danach normale signierte App per Computer Use neu gestartet: Öffnen, Music → Focus → Shelf → Music, Escape und erneutes Öffnen erfolgreich bedient. Music und Focus visuell geprüft; die App bleibt regulär geöffnet. Keine echte Audiosteuerung ausgelöst.
- Offen: subjektive Beurteilung des neuen Bewegungsgefühls durch den Nutzer. Echte Brain.fm-Steuerung wurde bei dieser reinen UI-Änderung nicht erneut ausgelöst.

## Ergebnis
`build/Lilt.app` läuft regulär. Fokus steht auf 25:00, Brain.fm ist nach den Tests pausiert. Kein Commit, Push, Release, Autostart oder Kopieren nach /Applications.

## Aktueller Umfang
- Originale Lilt-Animationskurven, Schrift, SVG-Cover und Icons lokal eingebettet.
- Nach Nutzerkorrektur: echtes Schwarz #000000, kompakte Höhe gleich Kameranotch (hier 32 statt 44 logische Pixel), 10-px-Unterkantenradius. Die sichtbare Form kann beim Falten nicht unter die Hardwarehöhe schrumpfen.
- Erster Klick funktioniert auch aus einer anderen App. Oberer Notch-Bereich, Fold und Escape schließen. Tabwechsel bleiben offen. Einklappen bei echtem Verlust des Tastaturfokus ersetzt die fehleranfällige globale Mausabfrage. Doppelte Instanzen werden verhindert.
- Brain.fm-Hintergrundsteuerung implementiert. Nutzer bestätigte Bedienungshilfen-Freigabe und Umstellung auf „Run in Separate Window“ + „Infinite“. Beide Brain.fm-Einstellungen wurden über die App vorgenommen und geprüft.
- Music und Shelf bleiben UI-Vorschauen. Nur Fokus steuert echte Musik.

## Brain.fm-Steuerung
Exakte Erkennung der Fokus-Ansicht und Play-/Pause-Schaltflächen per macOS Accessibility, ausschließlich für Bundle com.electron.brain.fm. Normale AXPress-Aktionen aktivierten den Player im Hintergrund nicht zuverlässig. Deshalb wird der erkannte Knopf fokussiert und Brain.fms eigene Enter-/Space-Steuerung gezielt an seinen Prozess geschickt. Keine globalen Medienkeys, keine fremde App-Modifikation, keine Tokens, kein Remote-Debugging.

Befehle haben eine Gesamtfrist von 12 Sekunden, maximal drei gezielte Versuche und Bestätigung durch stabile Folgezustände. Eine laufende Anfrage sperrt weitere Klicks. Der Timer startet oder pausiert erst nach bestätigter Musiksteuerung. Fehler bleiben sichtbar.

## Verifikation
- Release-Build erfolgreich. Stabile Apple-Entwicklungssignatur aus vorhandener Identität; Signaturprüfung außerhalb der Sandbox erfolgreich. Der vorherige Ad-hoc-Eintrag wurde mit der bereits erteilten Nutzerfreigabe durch die aktuelle App ersetzt. Ein weiterer Neubau behielt anschließend den funktionierenden Zugriff.
- `swift test`: 10 Prüfungen bestanden (4 Geometrie, 6 Controller-Entscheidungen).
- `node --test scripts/test-ui.mjs scripts/test-focus.mjs`: 8 Prüfungen bestanden, darunter fehlende Bestätigung, Berechtigungsfehler, doppelte/stale Antworten, Pause/Resume/Reset/Ende.
- WKWebView mit ausdrücklich simulierter Musikantwort: 23 UI- und 2 native Fensterprüfungen bestanden. `docs/evidence/brainfm-ui-simulated.json` ist kein Nachweis echter Audiosteuerung.
- Native Motion mit Hardwarehöhe: 4 Bewegungs- und 2 Fensterprüfungen bestanden, siehe `docs/evidence/hardware-notch-motion.json`.
- Echte Musik in Lilt-Diagnosemodus: Start, Pause, Resume, Reset gegen Brain.fm bestätigt, siehe `brainfm-live-start/pause/resume/reset.json`.
- Entscheidend: danach reguläre signierte App über Computer Use gestartet, Focus angeklickt, Brain.fm-Start bestätigt; Pause über Lilt bestätigt und separat Brain.fm-Button „Play“ beobachtet.
- Kaltstart: Brain.fm über sein eigenes Quit-Menü beendet, `isRunning:false` bestätigt. Regulärer Lilt-Fokusstart startete Brain.fm und Deep Work; anschließende Lilt-Pause wurde im echten Brain.fm-Player bestätigt (Infinite Play, Play-Knopf, Zähler 0:05).
- Echte Klickprüfung: ein Klick öffnet, Focus-Tab klappt nicht unerwartet zu, Header-Klick faltet. Vollständiger oberer Bildschirmstreifen bestätigte reines Schwarz und bündige Hardwarehöhe. Screenshot wegen anderer sichtbarer Fenster nur temporär gespeichert.
- Testinstanzen beendet. Normale App bereit; Timer zurückgesetzt, keine Testmusik läuft.

## Grenzen
- Menschliche Beurteilung des Bewegungsgefühls bleibt offen.
- Kein 25-Minuten-Dauertest. Ablauf-/Deadline-Zustände automatisiert geprüft; derselbe echte Pausepfad wurde live geprüft.
- Änderungen direkt in Brain.fm werden nicht fortlaufend gespiegelt. Lilt prüft den Zustand beim nächsten Befehl. Aktuelle Steuerung hängt von den zugänglichen Knöpfen der installierten Brain.fm-Version ab und meldet unbekannte Zustände als Fehler.
- Andere Playeraktivitäten (z. B. Sleep) werden nicht eigenmächtig als Fokus übernommen. Die App bittet dann um Auswahl einer Fokus-Sitzung.
- Mehrmonitor-/Fullscreen-Wechsel sind implementiert, aber nicht auf zusätzlicher Hardware live geprüft.

## Relevante Dateien
Sources/Lilt/BrainFMController.swift: gezielte Steuerung. AppDelegate.swift: Fenster, Berechtigungsanforderung und Bridge. Resources/Web/focus-state.mjs: bestätigungsbasierter Timerzustand. Resources/Web/notch.css: originale Kurven und native Hardwareanpassungen. docs/BRIDGE.md: aktueller Nachrichtenvertrag.
