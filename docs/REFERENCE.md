# Referenz und Nachweis

Original: [Lilt](https://vayun.net/studies/lilt/) von [Vayun Godara](https://github.com/vayungodara), abgerufen und live geprüft am 2026-10-30. Aktuelle Credits und Lizenzabgrenzung: [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).

Die lokale UI adaptiert die Notch-HTML-Struktur, SVG-Symbole, Cover, Schrift und CSS-Animationen aus der öffentlich zugänglichen Studie. Die Website beschreibt die Musik ausdrücklich als stumme Beispieltracks und die Ablage als Namen-Vorschau. Das beschreibt die Herkunftsstudie. Die inzwischen beauftragten nativen Anbindungen für Meld, Brain.fm und lokale Dateiverweise sind im aktuellen README und in SPEC.md beschrieben; die Notch-Gestaltung und ihre Bewegung bleiben an der Studie orientiert.

Dateien der Referenz:
- https://vayun.net/studies/lilt/lilt.css
- https://vayun.net/studies/lilt/lilt.js
- https://vayun.net/studies/lilt/fonts/familjen-grotesk.woff2

## Originalbewegung

Im Browser wurden Falten, Öffnen und Tabwechsel ausgelöst und Zwischenstände per requestAnimationFrame gelesen. Die Messzeit beginnt nach dem Klick-Transport und ist deshalb kein exakter Startzeitpunkt der CSS-Animation. Die Dauer und Kurve stammen zusätzlich aus den tatsächlichen berechneten CSS-Werten.

| Eigenschaft | Wert |
| --- | --- |
| Form | 520 ms, piecewise linear spring |
| Höchster Kurvenwert | 1.042 bei 46 % |
| Inhalt beim Öffnen | 120 ms Verzögerung, 220 ms opacity, 320 ms blur |
| Inhalt beim Falten | 120 ms opacity/blur, danach unsichtbar |
| Kompakte Anzeige | 180 ms Verzögerung, 220 ms opacity |
| Tabs | 300 ms, -6 px vertikal, 4 px blur |
| Albumwechsel | 320 ms, ±10 px horizontal, .9 scale |
| Musikbalken | 900 ms alternierend, Offsets 0/-300/-700/-150/-500 ms |

Bei der beobachteten Desktop-Referenz: offen 560 × 215.43 CSS px, kompakt 376.54 × 44 px. Öffnen erreichte etwa 567.59 × 222.53 px und setzte sich auf die Zielgröße. Die native App nutzt den Original-Basismaßstab 1 und ersetzt ausschließlich die simulierte Hardware-Notch durch die tatsächliche Bildschirmgeometrie. Sie skaliert Inhalte nicht in jedem Animationsframe.

## Brain.fm

Focus funktioniert unabhängig. Die optionale Brain.fm-Anbindung steuert die separat installierte App; eine Browserumleitung und die Übernahme von Anmeldedaten gehören nicht zur aktuellen Umsetzung. Verhalten und Nachweise stehen in README.md und STATUS.md.

## Rechte und Nutzung

Gestaltung und Vorlagenassets stammen aus der Lilt-Studie von Vayun Godara und werden nicht als eigene Gestaltung ausgegeben. Der Projektinhaber hat am 2026-10-31 Vayuns Erlaubnis zur Open-Source-Veröffentlichung bestätigt und MIT als Projektlizenz gewählt. Die hier veröffentlichte Implementierung und ihre Anpassungen werden unter MIT bereitgestellt. Das erklärt nicht pauschal die ursprüngliche Website oder andere Werke des Urhebers zu MIT-lizenzierten Werken. Familjen Grotesk bleibt unter SIL OFL 1.1; der vollständige Text liegt unter Resources/Licenses und wird mit der App gebündelt. Details und Quellen: THIRD_PARTY_NOTICES.md.

## Native Notch-Platzierung

Der Host setzt `NSPrefersDisplaySafeAreaCompatibilityMode` auf false und erlaubt seiner eigenen NSPanel-Unterklasse die Positionierung im Kamerabereich. Grundlage: [Apple: NSPrefersDisplaySafeAreaCompatibilityMode](https://developer.apple.com/documentation/bundleresources/information-property-list/nsprefersdisplaysafeareacompatibilitymode). Anschließend wurde die tatsächliche Position am laufenden Mac geprüft, nicht nur die berechnete Geometrie. AppKit setzt beim Aktivieren von isFloatingPanel die Fensterebene zurück; deshalb folgt die finale Fensterebene dieser Eigenschaft.

## Nutzerkorrektur: echte Hardware und Brain.fm

Die originale Farb-/Kompaktgeometrie wurde nach ausdrücklichem Feedback angepasst: #000000 statt #060707, kompakte Höhe entspricht der echten Kameranotch statt mindestens44px, Radius10px, ein Klick auf den oberen Bereich faltet. Animationskurven und Inhaltsstaffelung bleiben erhalten.

Der frühere Brain.fm-Weblink wurde durch Steuerung der installierten App ersetzt. Der Nutzer autorisierte Bedienungshilfen sowie „Run in Separate Window“ und „Infinite“. Aktuelles Verhalten und Nachweise stehen in STATUS.md und den dort genannten lokalen Diagnoseaufnahmen.

## Nutzerkorrektur: Inhaltswechsel und Tab-Pille

Die Tabbewegung aus der Referenz wurde auf Wunsch überarbeitet. Der zunächst erprobte seitliche Inhaltswechsel wurde nach Nutzerfeedback verworfen. Der alte Inhalt blendet in 70 ms aus. Danach erscheint der neue mit 160 ms Opazität und 200 ms Bewegung, von 2 px Versatz und Skalierung .99 zur Ruheposition. Die Beschriftungen verschiedener Ansichten überlagern sich beim regulären Wechsel nicht. Die vorhandene Formanimation bleibt erhalten.

Die Tab-Pille gleitet unabhängig in 240 ms mit `cubic-bezier(.65,0,.35,1)`. Ihre Beschriftungen nutzen einen lokalen Differenz-Mischmodus, damit der überquerte Text auf heller und dunkler Fläche lesbar bleibt. Gleiche Inhaltszeilen und Button-Abstände verankern Play in Music und Focus an derselben Position. Tastaturwechsel und reduzierte Bewegung setzen Inhalt und Pille unmittelbar. CSS-Übergänge übernehmen bei Unterbrechungen den laufenden Zustand.

`scripts/check-native-tabs.js` prüft die tatsächlichen Zwischenzustände im nativen WKWebView, einschließlich aller Wechselrichtungen, Unterbrechung, Geometrie, Play-Position, Zugänglichkeit und reduzierter Bewegung. Ergebnisse stehen separat in `docs/evidence/tab-transitions.json`. Das ist eine Funktionsprüfung der Bewegung, kein Bildraten-Benchmark und keine menschliche Designabnahme.
