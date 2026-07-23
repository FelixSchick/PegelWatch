# Konzept: Remote-Push-Notifications & Live Activities über Novu

**App:** PegelWatch (iOS) · **Backend:** Vapor-Relay (`pegelwatch-relay.felixschick.de`) + Novu Self-Hosted v3.17.0 (`novu.felixschick.de`) · **Stand:** Juli 2026

---

## 1. Ausgangslage

Die App kann heute bereits alles lokal: `NotificationManager` wertet Schwellenwerte aus und feuert lokale Mitteilungen (Kategorie `PEGEL_ALARM` mit Stumm-Aktionen), `LiveActivityManager` startet/aktualisiert Live Activities (Standard + Critical) bei jedem Level-Refresh — allerdings mit `pushType: nil`, also nur solange die App selbst aktualisiert. `APNSManager` registriert Device-Tokens über das Relay bei Novu (Subscriber + Credentials sind also schon vorhanden).

**Das Kernproblem:** Alle Alarme entstehen in der App. Ist die App länger geschlossen (iOS drosselt Background Refresh aggressiv), bekommt der Nutzer bei Hochwasser nichts mit. Genau das lösen Remote Pushes — aber dafür muss der Server wissen, *welche* Stationen ein Nutzer mit *welchen* Schwellen beobachtet, und selbst erkennen, wann eine Schwelle reißt.

Die App-Logik bleibt unverändert die primäre Quelle, solange die App läuft. Der Server ist das Sicherheitsnetz für alle anderen Fälle.

## 2. Zielbild

```
PegelOnline API ──poll──▶ Relay (Monitoring) ──trigger──▶ Novu ──▶ APNs ──▶ App (Alarm-Push)
                              │
                              └────── direkt HTTP/2 ─────────────▶ APNs ──▶ Live Activity Update
App ──sync──▶ Relay: Watchlist + Schwellen + Mute-Status + LiveActivity-Tokens
```

Zwei getrennte Push-Pfade, bewusst:

1. **Alarm-Notifications laufen über Novu.** Dafür ist Novu da: Workflows, Digest/Dedup, Präferenzen, Notification-Log im Dashboard.
2. **Live-Activity-Updates gehen vom Relay direkt an APNs.** Der Push-Typ `liveactivity` braucht spezielle Header (`apns-push-type: liveactivity`, Topic `<bundle-id>.push-type.liveactivity`) und ein exaktes `content-state`-Payload. Novus APNs-Provider ist dafür nicht gebaut — der Umweg lohnt sich nicht. Vapor bringt mit `APNSwift` alles mit.

## 3. Baustein A — Watchlist-Sync (App → Relay)

Das Relay bekommt einen neuen Endpoint, den die App bei jeder relevanten Änderung aufruft (Station hinzugefügt/entfernt, Schwelle geändert, Alarm stummgeschaltet):

```
PUT /api/subscribers/{subscriberId}/watchlist
X-App-Token: …
{
  "stations": [
    {
      "uuid": "593647aa-…",            // PegelOnline-Stations-UUID
      "threshold": 450,                 // cm
      "alarmLevels": ["warning", "danger", "critical"],
      "muteUntil": "2026-07-11T09:00:00Z"   // optional
    }
  ]
}
```

Idempotent als Vollersatz (kein Diff-Protokoll nötig). Persistenz im Relay: SQLite/Postgres via Fluent, Tabellen `subscribers`, `watched_stations`. Die Stumm-Aktionen aus der Notification (`MUTE_1H`/`MUTE_24H`) müssen zusätzlich `muteUntil` an den Server melden, sonst pusht der Server weiter, während die App lokal schweigt.

Wichtig für Konsistenz: Die App synchronisiert die Watchlist auch beim App-Start (Reconcile), damit Server-Zustand nie veraltet.

## 4. Baustein B — Monitoring im Relay

Ein Scheduler (Vapor `Queues` oder simpler `AsyncTimer`-Job) pollt PegelOnline zyklisch:

- Intervall: alle 10 Minuten für alle Stationen, die mindestens ein Subscriber beobachtet (dedupliziert — 100 Nutzer derselben Station = 1 Request). PegelOnline liefert `W`-Messwerte typisch in 15-Minuten-Auflösung.
- Pro Station und Subscriber wird der Alarm-Zustand berechnet (dieselbe Stufenlogik wie `AlarmLevel` in der App — die Logik einmal sauber portieren, idealerweise als kleine, testbare Funktion).
- **Zustandsübergänge statt Zustände** lösen Pushes aus: `normal → warning`, `warning → critical`, `critical → normal (Entwarnung)`. Der letzte gemeldete Zustand wird pro (Subscriber, Station) gespeichert.
- **Hysterese:** Entwarnung erst, wenn der Pegel z. B. 5 % unter der Schwelle liegt, sonst flattert es bei Pegeln nahe der Schwelle.
- `muteUntil` wird vor jedem Trigger geprüft.

## 5. Baustein C — Novu-Workflows für Alarm-Pushes

In Novu drei Workflows anlegen (oder einer mit Payload-Steuerung; drei sind im Dashboard übersichtlicher):

| Workflow | Trigger-ID | Inhalt |
|---|---|---|
| Pegel-Warnung | `pegel-warning` | „⚠️ {{stationName}}: {{level}} cm — Schwelle {{threshold}} cm erreicht" |
| Pegel-Kritisch | `pegel-critical` | „🔴 {{stationName}}: {{level}} cm — kritischer Stand!" |
| Entwarnung | `pegel-recovered` | „✅ {{stationName}}: Pegel wieder unter {{threshold}} cm" |

Das Relay triggert:

```http
POST https://novu-api.felixschick.de/v1/events/trigger
Authorization: ApiKey {NOVU_SECRET_KEY}
{
  "name": "pegel-critical",
  "to": { "subscriberId": "<idfv>" },
  "payload": { "stationName": "Köln", "level": 512, "threshold": 450, "stationID": "…" },
  "overrides": {
    "providers": {
      "apns": {
        "payload": {
          "aps": {
            "category": "PEGEL_ALARM",
            "sound": "alarm_sirene.wav",
            "interruption-level": "time-sensitive",
            "thread-id": "{{stationID}}"
          }
        },
        "headers": { "apns-collapse-id": "{{stationID}}" }
      }
    }
  }
}
```

Details, die zählen:

- **APNs-Integration in Novu:** Token-basiert (`.p8`-Key, Key-ID, Team-ID, Bundle-ID `de.felixschick.pegelwatch`). Production- und Sandbox-Umgebung als zwei Novu-Environments (Development/Production) abbilden.
- `category: PEGEL_ALARM` aktiviert die bestehenden Stumm-Aktionen auch bei Remote-Pushes — die App-Seite (`NotificationDelegate`) funktioniert unverändert.
- Custom Sounds (`alarm_sirene.wav` etc.) funktionieren remote nur, wenn die Datei im App-Bundle liegt — ist sie ja. Die vom Nutzer gewählte `AlarmSoundSettings`-Auswahl muss dafür mit in den Watchlist-Sync.
- `interruption-level: time-sensitive` für warning/danger; für `critical` später `"critical": 1` — **setzt das Apple Critical-Alert-Entitlement voraus** (Antrag bei Apple nötig, wie im Code-Kommentar schon vermerkt).
- `apns-collapse-id` pro Station verhindert Notification-Stapel bei schnellen Folge-Updates.
- Falls die Override-Struktur in v3.17.0 abweicht: mit einem Test-Workflow verifizieren, *bevor* die Workflows final gebaut werden (Novu-Dashboard → Activity Feed zeigt das tatsächlich gesendete Payload).

## 6. Baustein D — Live Activities per Push

### 6.1 App-Seite

Der vorbereitende Kommentar in `APNSManager` beschreibt es schon richtig:

1. `Activity.request(…, pushType: .token)` in `LiveActivityManager` (beide Aktivitätstypen).
2. Nach dem Start `activity.pushTokenUpdates` beobachten und jeden Token ans Relay melden:

```
POST /api/subscribers/{subscriberId}/live-activity-tokens
{ "activityToken": "…", "activityKind": "standard" | "critical", "stationID": "…" }
```

3. **Push-to-Start (iOS 17.2+):** Zusätzlich `Activity<Attrs>.pushToStartTokenUpdates` beobachten und den Push-to-Start-Token hochladen. Damit kann der Server eine Live Activity *starten*, auch wenn die App geschlossen ist — das ist für den Hochwasser-Fall der eigentliche Gewinn: Pegel reißt Schwelle → Live Activity erscheint auf dem Lockscreen, ohne dass der Nutzer die App öffnet.
4. Token-Lifecycle: Bei `activityStateUpdates == .ended/.dismissed` Token am Relay löschen.

### 6.2 Relay-Seite

Direkter APNs-Versand via `APNSwift` (gleicher `.p8`-Key wie Novu):

```
POST https://api.push.apple.com/3/device/{activityToken}
apns-push-type:  liveactivity
apns-topic:      de.felixschick.pegelwatch.push-type.liveactivity
apns-priority:   10   (kritisch) / 5 (normale Updates)

{
  "aps": {
    "timestamp": 1783087200,
    "event": "update",                // "start" | "update" | "end"
    "content-state": {
      "currentLevel": 512, "threshold": 450,
      "alarmLevel": "critical", "updatedAt": "…", "trend": -1
    },
    "stale-date": <now + 30min>,
    "dismissal-date": <bei "end">,
    "alert": { … }                     // nur bei "start" via Push-to-Start
  }
}
```

**Achtung:** `content-state` muss dem `Codable`-Encoding der `ContentState`-Structs exakt entsprechen (Feldnamen, Datumsformat — `updatedAt` als ISO8601 oder Unix-Timestamp konsistent halten; ggf. explizite `CodingKeys`/`DateEncodingStrategy` festlegen). Ein Feld falsch → Update wird stillschweigend verworfen.

Update-Kadenz: Live-Activity-Updates bei jedem Poll (10 min) für Stationen im Warn-/Kritisch-Zustand; APNs budgetiert Liveactivity-Pushes, daher nicht öfter als nötig senden und `stale-date` nutzen.

### 6.3 Koexistenz lokal + remote

Wenn App und Server dieselbe Activity bedienen, braucht es eine Regel: Die per Push-to-Start vom Server gestartete Activity ist führend; `LiveActivityManager` erkennt bestehende Activities über `Activity<Attrs>.activities` (statt nur über sein lokales Dictionary) und aktualisiert diese, statt Duplikate zu starten. Gleiches Deduplizieren wie bei Notifications: Server sendet nur bei Zustandsänderung oder neuem Messwert.

## 7. Umsetzungsphasen

**Phase 1 — Alarm-Pushes (größter Nutzen, geringstes Risiko):**
Watchlist-Sync-Endpoint + Persistenz im Relay → Monitoring-Job → 3 Novu-Workflows → App: Sync-Aufrufe + Dedup (Remote-Push unterdrücken, wenn App denselben Alarm gerade lokal gezeigt hat, z. B. via `thread-id`/`apns-collapse-id` und lokalem Zeitfenster).

**Phase 2 — Live-Activity-Updates per Push:**
`pushType: .token` + Token-Upload → APNSwift im Relay → Updates für laufende Activities. Damit bleiben Activities aktuell, auch wenn die App im Hintergrund hängt.

**Phase 3 — Push-to-Start + Entwarnungs-Flow:**
Push-to-Start-Token → Server startet Critical-Activity bei Schwellenriss → `event: end` mit `hasRecovered: true` bei Entwarnung.

**Phase 4 — Kür:**
Critical-Alert-Entitlement bei Apple beantragen; Novu-Digest (mehrere Stationen in einer Sammel-Push); Nutzer-Präferenzen über Novu Preferences statt eigener Mute-Logik.

## 8. Risiken & offene Punkte

- **Datenschutz:** Der Server speichert erstmals Nutzerdaten (Watchlist pro Gerät). IDFV ist pseudonym, aber: Datenschutzhinweis in der App ergänzen, Lösch-Endpoint (`DELETE /api/subscribers/{id}`) vorsehen.
- **Novu-Overrides:** Struktur der APNs-Overrides in v3.17.0 früh mit einem Wegwerf-Workflow verifizieren (Punkt mit dem größten Überraschungspotenzial).
- **Token-Hygiene:** APNs-Feedback (410 Unregistered) im Relay auswerten und tote Tokens/Subscriber aufräumen.
- **PegelOnline-Verfügbarkeit:** Bei API-Ausfall keine Fehl-Entwarnungen senden — alter Zustand bleibt stehen, optional „Daten veraltet"-Hinweis via `stale-date`.
- **Doppel-Benachrichtigung:** App-lokal + remote kann doppelt feuern. Pragmatisch: lokale Notifications abschalten, sobald Remote-Registrierung erfolgreich war, und lokal nur als Fallback ohne Netz/Server behalten.
