# Plan: Shelf, Fokusintervalle und Bildschirme ohne Notch

Stand: 31. Oktober 2026. Dieser Plan beschreibt zukünftige Arbeit, keine bereits umgesetzten Funktionen. Die vereinbarten direkten Musikverbindungen, der unabhängige Fokus-Timer und die Einstellungen stehen in [SPEC.md](../SPEC.md) und gehen diesen Erweiterungen voraus. Ihr tatsächlicher Umsetzungs- und Prüfstand steht in [STATUS.md](../STATUS.md).

## Ziel und Reihenfolge

Lilt bleibt eine ruhige App für Musik, Fokus und Dateien. Bestehende Notch-Form, Bewegungen, Tabs und zugängliche Bedienung bilden die Grundlage.

## Verschiedene MacBook-Notches

Lilt soll auf MacBooks verschiedener Größen mit unterschiedlichen Notch-Abmessungen korrekt funktionieren. Die kompakte und geöffnete Darstellung sollen sich an die jeweilige Hardware anpassen; Position, Übergänge und Bedienelemente müssen dabei stimmen. Auch fehlende oder unplausible Bildschirmdaten sind nachvollziehbar zu behandeln.

Abnahme: Geometrie für verschiedene Notch-Breiten und -Höhen automatisiert prüfen und die gerenderte App auf unterschiedlichen echten MacBook-Modellen hinsichtlich Position, Darstellung und Bedienung testen. Nicht verfügbare Modelle als fehlenden Hardware-Nachweis dokumentieren.

## Navigation mit dem Magic Trackpad

In der geöffneten Notch soll ein horizontaler Zwei-Finger-Wisch nach links oder rechts zwischen Music, Focus und Shelf wechseln. Die bestehenden Klick- und Tastaturwege bleiben erhalten. Die Geste soll nicht versehentlich auslösen, wenn Inhalte horizontal gescrollt oder Dateien gezogen werden. Richtung und Verhalten an den Enden der Tab-Reihe werden beim Entwurf festgelegt; die macOS-Einstellung für die Scrollrichtung ist zu berücksichtigen.

Abnahme: Beide Wischrichtungen und alle Tab-Übergänge auf einem echten Magic Trackpad prüfen. Horizontales Scrollen im Shelf, Drag-and-drop, Klicks und Tastaturbedienung dürfen nicht beeinträchtigt werden. Übergänge mit aktivierter reduzierter Bewegung gesondert prüfen.

1. Bereits vereinbarte Musik-, Fokus- und Einstellungsarbeit abschließen und prüfen.
2. Shelf als zusammenhängenden Schritt überarbeiten: Oberfläche, Mehrfachauswahl und Teilen.
3. Optionale Fokus- und Pausenintervalle auf dem unabhängigen Timer aufbauen.
4. Nutzung auf Bildschirmen ohne Notch gesondert gestalten und umsetzen.

## 1. Shelf: Oberfläche und Dateiaktionen

### Ergebnis

Dateien sind schnell erkennbar und können einzeln oder gemeinsam ausgewählt, geöffnet, betrachtet, herausgezogen und geteilt werden. Zusätzliche Aktionen erscheinen im Kontext der Auswahl, ohne die Oberfläche dauerhaft zu überladen.

- Dateinamen und geeignete Vorschauen beziehungsweise Dateisymbole gut lesbar darstellen. Lange und gleiche Namen unterscheidbar machen.
- Leeren Zustand, aktives Hineinziehen, Auswahl, viele Dateien und nicht verfügbare Dateien sichtbar und verständlich gestalten.
- Mehrfachauswahl per ⌘-Klick, zusammenhängende Auswahl per ⇧-Klick sowie zugängliche Tastaturbedienung vorsehen. Einzelne Dateien bleiben einfach zu öffnen und in Quick Look anzusehen.
- Ausgewählte Dateien gemeinsam herausziehen und über das macOS-Teilen-Menü übergeben; AirDrop ist dort ein mögliches Ziel, sofern verfügbar.
- Einzelne oder mehrere Einträge entfernen. Das entfernt ausschließlich Lilts gespeicherte Verweise; Originaldateien werden weder verschoben noch gelöscht. Auch Clear behält diese Bedeutung.
- Bestehende Wiederherstellung nach Neustart, Finder-Aktion, lokale Dateiverweise und den Umgang mit fehlenden Dateien erhalten.

### Design und Prüfung

Vor der Implementierung die tatsächliche Shelf-Oberfläche und ihre Platzverhältnisse prüfen und ein konkretes Konzept für Datei-Kacheln, Auswahl, Aktionen und Fehlerzustände erarbeiten. Die verpflichtende UI-Beratung nach Projektregeln einbeziehen. Notch-Geometrie und vereinbarte Bewegungen erhalten; reduzierte Bewegung berücksichtigen.

Abnahme: Dateien einzeln und mehrfach mit Maus und Tastatur auswählen; Vorschau, Finder, gemeinsames Herausziehen, Teilen und Entfernen prüfen. Leeren Zustand, viele Einträge, gleichnamige und fehlende Dateien sowie Wiederherstellung nach Neustart prüfen. Originale von Testdateien vor und nach den Aktionen vergleichen. Das gerenderte Ergebnis prüfen; für einen vollständigen AirDrop-Test wird ein empfangendes Gerät benötigt. Menschliche Designabnahme gesondert festhalten.

## 2. Optionale Fokus- und Pausenintervalle

### Ergebnis

Neben einer einzelnen Sitzung kann eine Folge aus Arbeits- und Pausenzeiten gewählt werden. Dauer und aktuelle Phase sind verständlich; die kompakte Notch zeigt die laufende Zeit und unterscheidet Arbeit von Pause.

- Arbeits- und Pausendauer vor Beginn einstellen; Start, Pause, Fortsetzen und Beenden für beide Phasen anbieten.
- Phasenende dezent anzeigen. Vorschlag: Die nächste Phase beginnt erst nach ausdrücklicher Bestätigung.
- Zustand nach Neustart nachvollziehbar wiederherstellen und keine Musik ungefragt starten.
- Brain.fm bleibt optional und darf den unabhängigen Timer nicht blockieren.

### Offene Entscheidungen und Prüfung

Vor Umsetzung festlegen, ob und wie viele Intervalle vorausgeplant werden, wie Pausen übersprungen werden und ob Brain.fm beim Phasenwechsel pausiert oder fortgesetzt werden soll. Verhalten bei geschlossener App und überfälliger Phase ausdrücklich definieren.

Abnahme: Beide Phasen und ihre Übergänge einschließlich Pause, Fortsetzen, Abbruch und Neustart prüfen. Kompakte Anzeige und Tastaturbedienung im gerenderten Ergebnis prüfen. Unabhängigen Timer und optionale echte Brain.fm-Verbindung getrennt nachweisen.

## 3. Bildschirme ohne physische Notch

### Ergebnis

Auf einem Mac oder externen Bildschirm ohne Notch lässt sich Lilt über eine kleine Fläche am oberen Bildschirmrand öffnen. Music, Focus und Shelf bleiben erreichbar.

- Position und Form passend zur Menüleiste gestalten und in den Einstellungen eine Bildschirmwahl ermöglichen.
- Bildschirmwechsel, Trennen und Wiederverbinden sowie unterschiedliche Auflösungen berücksichtigen.
- Bestehende Bedienung auf einem Bildschirm mit Notch erhalten.

### Offene Entscheidungen und Prüfung

Vor Umsetzung festlegen, auf welchen Bildschirmen Lilt standardmäßig erscheint und wie sich die Fläche bei Vollbild und mehreren Monitoren verhält. Das Design anhand eines gerenderten Entwurfs prüfen.

Abnahme: Öffnen, Schließen, Tabs, Fokus und Shelf auf einem Bildschirm ohne Notch und auf einem mit Notch prüfen. Bildschirmwechsel und Menüleistenüberschneidungen auf echter Hardware testen. Fehlende Hardware als offene Prüfgrenze dokumentieren.

## Allgemeine Nachweise

Für jede Erweiterung relevante Logiktests und bestehende Projektchecks ausführen. Datei- und automatisierte Tests, tatsächliche App-Bedienung, externe Geräte und menschliche Designabnahme getrennt dokumentieren. Bestehende Änderungen im Arbeitsverzeichnis bei der Umsetzung erhalten.
