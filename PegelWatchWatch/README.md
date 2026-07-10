# PegelWatch – Apple Watch App (Setup)

Diese vier Dateien bilden eine minimale watchOS-App auf Basis derselben
Datenquelle wie iOS-App und Widget (App-Group `group.de.felixschick.pegelwatch`).

**Wichtig:** Diese Dateien sind noch **nicht** einem Xcode-Target zugeordnet.
Um die Watch-App zu aktivieren, gehe folgendermaßen vor:

## 1. Watch-Target anlegen

1. In Xcode: `File → New → Target…`
2. `watchOS → App` auswählen.
3. Product Name: `PegelWatchWatch`
4. Bundle Identifier: `de.felixschick.pegelwatch.watchkitapp`
5. Interface: `SwiftUI`, Language: `Swift`
6. Storage: `None` (wir nutzen App Group)
7. Bei "Include Notification Scene" die Checkbox belassen falls du später
   Notifications auf der Watch möchtest — vorerst nicht nötig.

## 2. Dateien einbinden

1. Die von Xcode generierten `PegelWatchWatchApp.swift`, `ContentView.swift`
   etc. **löschen** (im neuen Target).
2. Die vier Dateien in diesem Ordner (`PegelWatchWatch/*.swift`) via
   `Add Files to "PegelWatch"…` dem **watchOS-Target** zuordnen.
3. Zusätzlich müssen folgende Dateien Multi-Target-Membership bekommen
   (sie liegen im iOS-Target — im File Inspector zusätzlich `PegelWatchWatch`
   ankreuzen):

   - `PegelWatch/Models/WatchedStation.swift`
   - `PegelWatch/Models/AlarmLevel.swift`
   - `PegelWatch/Models/AlarmEvent.swift`
   - `PegelWatch/Models/CustomAlarm.swift`
   - `PegelWatch/Networking/PegelOnlineAPI.swift`
   - `PegelWatch/Networking/HeichwaasserAPI.swift`

## 3. App Group Entitlement

Im watchOS-Target unter `Signing & Capabilities` → `+ Capability` →
`App Groups` → `group.de.felixschick.pegelwatch` aktivieren.

## 4. Optional: Komplikationen

Für Komplikationen (Corner / Circular / Rectangular) kann ein separates
Widget-Target für watchOS angelegt werden, das denselben Loader nutzt.
Das ist ein zweiter Schritt und hier bewusst nicht mitgeliefert.

## Was die App kann

- **Watchlist-Übersicht**: alle beobachteten Stationen mit Pegel, Trend, Alarmstufe
- **Detailansicht** je Station mit 24-h-Sparkline und Alarmschwelle
- **Pull-to-Refresh**: lädt live von den APIs; Ergebnisse werden ins
  App-Group-Container zurückgeschrieben (Widgets & iPhone sehen den frischen Stand)

## Was noch fehlt (bewusst)

- Alarm-Konfiguration (bleibt auf iPhone-App)
- Komplikationen (separates Widget-Target)
- Kartenansicht (auf watchOS eingeschränkt sinnvoll)
