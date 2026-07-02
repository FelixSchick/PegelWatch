# PegelWatch – UX-Verbesserungsplan

Stand: Juli 2026 · Zielplattform: iOS 26+

## 1. Bereits umgesetzt (dieser Branch)

- **Chart-Skalierung**: Der Y-Bereich folgt primär dem Pegelverlauf. Schwellen
  werden nur eingeblendet, solange sie den Verlauf nicht zusammenstauchen
  (max. 1,5× Datenspanne oberhalb des Maximums). Weiter entfernte Schwellen
  erscheinen als Hinweis-Button und lassen sich auf Wunsch voll einblenden.
- **Liquid Glass & Design-Vereinheitlichung**: Zentraler Kartenstil
  (`pegelCard()` in `DesignSystem.swift`) mit `glassEffect`, einheitlicher
  Eckenradius, Glass-Buttons (Station entfernen, Schwellen-Toggle).
  Alarmzustand färbt das Glas der Pegel-Karte.
- Eigene Alarmtöne, Lautstärkeregler, Stummschalt-Aktionen (voriger Commit).

## 2. Design-Vereinheitlichung – nächste Schritte

| Maßnahme | Nutzen | Aufwand |
|---|---|---|
| Tutorial (`TutorialStep.swift`) von hartem Weiß-auf-Dunkel-Design auf Systemfarben + Liquid Glass umstellen | Konsistenz, Dark/Light korrekt | mittel |
| Abstände/Typografie als Tokens in `DesignSystem.swift` (Spacing, Fonts) und überall verwenden | Wartbarkeit, ruhigeres Layout | klein |
| Semantische Alarmfarben zentral (heute: teils `AlarmLevel.color`, teils hart kodiert wie in `SavedSnapshot.snapshotColor`) | Einheitliche Farbsprache | klein |
| Accessibility-Audit: Dynamic Type (feste `size: 56`-Fonts skalierbar machen), VoiceOver-Labels für Gauge/Chart, Kontraste | Barrierefreiheit, App-Store-Qualität | mittel |
| App-Icon-Varianten (dark/tinted) | Wirkt auf iOS 26 Homescreens integriert | klein |

## 3. Apple-Plattform-Features (priorisiert)

### 3.1 Widgets ausbauen (hoher Nutzen, Basis vorhanden)
- **Interaktive Widgets**: Button im Widget (AppIntent) zum Aktualisieren oder
  Stummschalten eines Alarms – ohne App-Start.
- **Sparkline im Medium/Large-Widget**: Swift-Charts-Miniverlauf (24 h) statt
  nur Zahl + Trendpfeil.
- **Lock-Screen-Widgets** (`accessoryCircular/Rectangular/Inline`): Pegel +
  Trend direkt auf dem Sperrbildschirm; profitiert automatisch von StandBy.
- **Control-Center-Control** (`ControlWidget`): Schnellzugriff „Pegel prüfen"
  bzw. Deep-Link zur Wunschstation.

### 3.2 Siri, Shortcuts & Spotlight
- **App Shortcuts / App Intents**: „Wie hoch ist der Pegel in Koblenz?" –
  Intent mit Stations-Parameter (die `StationAppEntity` aus dem Widget lässt
  sich wiederverwenden), Ergebnis als Snippet mit Pegel, Trend, Alarmstatus.
- **Spotlight**: Beobachtete Stationen als `IndexedEntity` indexieren –
  Suche „Iffezheim" öffnet direkt die Detailansicht.
- **Interactive Snippets (iOS 26)**: Pegel-Snippet mit „Stummschalten"-Button
  direkt in Siri/Spotlight.

### 3.3 Live Activities verfeinern (Basis vorhanden)
- Dynamic-Island-Präsentationen (compact/minimal) mit Trendpfeil und Farbe.
- **Apple Watch Smart Stack**: Live Activities erscheinen ab watchOS 26
  automatisch – Layout dafür prüfen/optimieren.
- Fortschrittsbalken Richtung Alarmschwelle in der expanded-Ansicht.

### 3.4 Karte & Kontext
- **MapKit-Tab**: Alle beobachteten Stationen auf einer Karte, Marker in
  Alarmfarbe, Clustering, Tap → Detailansicht. Für BOS-Nutzung (Lageübersicht)
  besonders wertvoll.
- MNW/MHW-Referenzwerte aus der PEGELONLINE-API als Kontextband im Chart.

### 3.5 Feinschliff
- **TipKit** statt einmaligem Tutorial: kontextuelle Tipps (z. B. „Lange
  drücken zum Stummschalten"), erscheint genau dann, wenn relevant.
- **Haptik** (`sensoryFeedback`): spürbares Feedback bei Alarmwechsel und
  beim Ziehen der Schwellen-Slider.
- **Chart-Interaktion**: `chartScrollableAxes` für horizontales Scrollen in
  längeren Zeiträumen, Pinch-Zoom.
- Onboarding: Benachrichtigungs-Berechtigung erst nach Erklärung anfragen
  (Pre-Permission-Screen) statt sofort beim Start.

## 4. Empfohlene Reihenfolge

1. Lock-Screen-Widgets + interaktive Widgets (schneller Gewinn, Basis da)
2. App Shortcuts + Spotlight (Reichweite außerhalb der App)
3. Tutorial-Redesign + Accessibility-Audit (Konsistenz abschließen)
4. Karten-Tab (größtes neues Feature)
5. TipKit, Haptik, Chart-Scrolling (Feinschliff)
