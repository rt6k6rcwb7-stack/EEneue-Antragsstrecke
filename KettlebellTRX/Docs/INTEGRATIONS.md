# Geräte- und API-Anbindungen

Grundsatz: Es werden ausschließlich offizielle, dokumentierte Schnittstellen genutzt. Fehlende
Werte bleiben fehlend (`nil` → „nicht verfügbar“) und werden nie unbemerkt geschätzt.
Geschätzte Werte der Quellen (z. B. Energieverbrauch) tragen `quality = estimated`.

## Apple Health / HealthKit

| Zweck | Typen | Richtung |
|---|---|---|
| Regeneration | `restingHeartRate`, `heartRateVariabilitySDNN`, `sleepAnalysis` (Kern/Tief/REM/Wach) | lesen |
| Aktivität | `activeEnergyBurned` (als Schätzung gekennzeichnet), `stepCount`, `respiratoryRate`, `oxygenSaturation`, Workouts | lesen |
| Training | `HKWorkout` (funktionelles Krafttraining bzw. Beweglichkeit) | schreiben **nur nach Zustimmung** |

* Ganztägige Herzfrequenz wird bewusst nicht importiert (Datensparsamkeit). Der Trainingspuls
  kommt live von der Watch.
* Quellen werden über `HKSource.bundleIdentifier` und das Gerätemodell erkannt
  (`HealthSourceClassifier`): Apple Watch, iPhone, Garmin (`com.garmin.connect…`), WHOOP, andere.
* HealthKit verrät nicht, ob Leserechte verweigert wurden – die App zeigt dann „keine Daten“.
* Abruf: Zeitfenster seit letzter Synchronisierung minus 36 h Überlappung; Duplikate werden über
  die HealthKit-UUID erkannt.

**Workout-APIs:** `HKWorkoutSession`, `HKLiveWorkoutBuilder`, `HKLiveWorkoutDataSource`,
`startMirroringToCompanionDevice()`, `workoutSessionMirroringStartHandler`,
`sendToRemoteWorkoutSession(data:)`, `recoverActiveWorkoutSession()`, ergänzend
WatchConnectivity (`transferUserInfo`, `updateApplicationContext`). Mindestversionen iOS 17 / watchOS 10.

## Garmin Approach S70

### Stufe 1 – über Apple Health (umgesetzt)

Garmin Connect kann laut öffentlichen Angaben u. a. Schritte, Herzfrequenz inkl. Ruhepuls,
Schlaf (inkl. Phasen, geräteabhängig), aktive und Ruheenergie sowie Workouts (ohne GPS-Route,
Workout-Puls teils nur Min/Max) an Apple Health übertragen. **Welche Datenarten die S70
tatsächlich liefert, lässt sich nur auf dem echten Gerät feststellen.** Dafür gibt es in der App
Einstellungen → Geräte → Garmin → **„Verfügbare Garmin-Datenarten prüfen“**
(`SourceAvailabilityReport`: Anzahl Werte und letzter Zeitpunkt je Datenart).

Voraussetzung: Garmin Connect → Einstellungen → Verbundene Apps → Apple Health → Freigaben aktivieren.

### Stufe 2 – direkte Garmin-Schnittstelle (geprüft, nicht aktiviert)

Ergebnis der Recherche (November 2026):

* **Garmin Connect Developer Program** (Health API, Activity API): laut Garmin ausschließlich
  für **geschäftliche** Nutzung; Zugang per Antrag und Freigabe, danach Evaluierungsumgebung.
  Für einzelne Kennzahlen können kommerzielle Lizenzgebühren anfallen. Berichte über pausierte
  bzw. abgelehnte Anträge existieren. Für eine private Einzelperson-App ungeeignet.
* **Garmin Personal API**: Garmin nennt eine Personal API für Einzelpersonen zum Zugriff auf
  die eigenen Daten (nicht für kommerzielle Mehrnutzer-Apps). Laut Drittquelle wird ein
  persönlicher Schlüssel in den Garmin-Connect-Kontoeinstellungen erzeugt.
  **Authentifizierung, Endpunkte, Datenfelder, Historie, Synchronisierungsintervalle und
  Nutzungsgrenzen konnten aus der Entwicklungsumgebung nicht verifiziert werden** (Garmin-Seiten
  waren nicht erreichbar).

Entscheidung gemäß Auftrag: Ohne bestätigten Zugang keine Implementierung. `GarminDirectProvider`
meldet ausdrücklich „nicht verfügbar“. Keine inoffiziellen Schnittstellen, kein Scraping.

**Nächster Schritt:** In Garmin Connect prüfen, ob die Personal API für dein Konto angeboten
wird, und die Dokumentation (Endpunkte, Token-Format, Limits, Bedingungen) bereitstellen. Dann
genügt ein neuer `VitalDataProvider` (Vorlage: `WhoopProvider`).

Quellen: [Garmin Health API](https://developer.garmin.com/gc-developer-program/health-api),
[Program FAQ](https://developer.garmin.com/gc-developer-program/program-faq),
[Personal FAQ](https://developer.garmin.com/gc-developer-program/personal/personal-faq/),
[the5krunner: Garmin personal API](https://the5krunner.com/2026/10/22/garmin-personal-api/).

## WHOOP

Offizielle **WHOOP Developer API v2**, OAuth 2.0 (Authorization Code).

| Punkt | Umsetzung |
|---|---|
| Autorisierung | `https://api.prod.whoop.com/oauth/oauth2/auth` im System-Browser (`ASWebAuthenticationSession`, ephemer), `state` ≥ 8 Zeichen gegen CSRF |
| Scopes | `read:recovery read:sleep read:cycles read:workout offline` (`offline` für Refresh-Token) |
| Token | Austausch/Erneuerung über `https://api.prod.whoop.com/oauth/oauth2/token` – **nur im Token-Broker**, weil das Client-Secret benötigt wird |
| Speicherung | Keychain, `AfterFirstUnlockThisDeviceOnly`; Erneuerung 2 min vor Ablauf und bei HTTP 401 (einmal) |
| Endpunkte | `GET /developer/v2/recovery`, `/v2/activity/sleep`, `/v2/cycle`, `/v2/activity/workout` mit `start`, `end`, `limit=25`, `nextToken` |
| Abbildung | Recovery Score, Ruhepuls, HRV (**RMSSD**, getrennt von Apples SDNN), SpO₂, Schlafdauer/-phasen (Nickerchen ausgenommen), Strain, Workouts |
| Nicht bewertete Datensätze | `PENDING_SCORE`/`UNSCORABLE` → kein Wert; `user_calibrating` → `quality = calibrating` |
| Fehler | 401/403 → „erneut verbinden“, 429 → Backoff, sichtbar im Sync-Status |
| Widerruf | `DELETE /developer/v2/user/access` (Best Effort) + Token lokal löschen; optional importierte Daten löschen |
| Doppelzählung | Solange WHOOP direkt verbunden ist, werden WHOOP-Kopien in Apple Health ignoriert |

### Einrichtung

1. Im [WHOOP Developer Dashboard](https://developer-dashboard.whoop.com) eine App anlegen,
   Redirect-URI `kbtrx://oauth/whoop` eintragen, Scopes wie oben.
2. Token-Broker bereitstellen (Beispiel Cloudflare Worker, kostenloser Plan genügt):
   ```bash
   cd Backend/whoop-token-broker
   npx wrangler login
   npx wrangler secret put WHOOP_CLIENT_ID
   npx wrangler secret put WHOOP_CLIENT_SECRET
   npx wrangler deploy        # → https://kbtrx-whoop-token-broker.<konto>.workers.dev
   ```
   Der Broker speichert weder Token noch Gesundheitsdaten und akzeptiert nur die hinterlegte Redirect-URI.
3. In der App: Einstellungen → Geräte → WHOOP → Client-ID, Redirect-URI und Broker-URL eintragen → „Mit WHOOP verbinden“.

### Webhooks – bewusst nicht in Version 1

WHOOP bietet Webhooks (u. a. `recovery.updated`, `sleep.updated`, `workout.updated`; signiert mit
dem Client-Secret; keine Webhooks für Zyklen). Sie setzen einen dauerhaft erreichbaren Server
voraus, der Ereignisse entgegennimmt und die App per Push benachrichtigt – also zusätzliche
Server-Infrastruktur mit Gesundheitsbezug. Für eine lokale Einzelnutzer-App ist der Nutzen
gering: synchronisiert wird beim Öffnen der App und per Pull-to-Refresh. Bei Bedarf kann der
Broker um einen signaturprüfenden Webhook-Endpunkt erweitert werden.

Quellen: [WHOOP OAuth](https://developer.whoop.com/docs/developing/oauth),
[v1→v2 Migration](https://developer.whoop.com/docs/developing/v1-v2-migration),
[Webhooks](https://developer.whoop.com/docs/developing/webhooks/),
[API-Referenz](https://developer.whoop.com/api/).
**Feldnamen und Endpunkte vor der ersten echten Nutzung gegen die aktuelle Referenz prüfen**
– getestet wurde nur mit nachgebildeten Antworten.

## Datenharmonisierung (Kurzfassung)

1. Duplikate: `channel + type + sourceRecordId`, zusätzlich `source + type + start + value`.
2. Originalquelle (`source`) und Übertragungsweg (`channel`) bleiben erhalten; Rohdaten werden nie überschrieben.
3. Prioritäten je Messwerttyp, in der App änderbar (Standard: Live-Puls Apple Watch, Regeneration WHOOP, Aktivität Garmin).
4. HRV: `hrvSDNN` und `hrvRMSSD` sind getrennte Typen und werden nie vermischt.
5. Trends und Basislinien nur innerhalb derselben Quelle (mind. 5 Messtage in 28 Tagen).
6. Sync-Fehler sichtbar je Quelle (Zeitpunkt, Meldung, Anzahl Fehlversuche).
7. Quellen einzeln deaktivierbar (Rohdaten bleiben, fließen aber nicht in Auswertungen ein).
