# Installation auf iPhone und Apple Watch

## Voraussetzungen

* Mac mit **Xcode 15 oder neuer** (empfohlen: aktuelle Version aus dem App Store)
* iPhone mit **iOS 17** oder neuer, Apple Watch mit **watchOS 10** oder neuer, beide gekoppelt
* Apple-ID; für HealthKit auf echten Geräten genügt ein kostenloser Account (Apps laufen dann
  7 Tage). Für TestFlight und dauerhafte Installation: Apple Developer Program (99 €/Jahr).
* Optional: [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## 1. Projekt erzeugen

```bash
git clone <repository>
cd EEneue-Antragsstrecke/KettlebellTRX
swift test                 # optional: Kernlogik prüfen
brew install xcodegen
xcodegen generate          # erzeugt KettlebellTRX.xcodeproj
open KettlebellTRX.xcodeproj
```

Vorher in `project.yml` anpassen:
* `BUNDLE_ID_PREFIX: de.kbtrx` → eigene, eindeutige Kennung, z. B. `de.mustermann.kbtrx`
* `DEVELOPMENT_TEAM: ""` → eigene Team-ID (Xcode → Settings → Accounts → Team)

<details><summary>Ohne XcodeGen (manuell)</summary>

1. Xcode → File → New → Project → iOS App „KettlebellTRX“ (SwiftUI, Swift).
2. File → New → Target → watchOS → App → „KettlebellTRXWatch“ („Watch App for Existing iOS App“).
3. File → Add Package Dependencies → Add Local… → Ordner `KettlebellTRX` → Produkt `FitnessCore`
   beiden Targets hinzufügen.
4. Generierte `ContentView`/`App`-Dateien löschen; `Apps/iOS` dem iOS-Target und `Apps/watchOS`
   dem Watch-Target hinzufügen.
5. Bei beiden Targets: Signing & Capabilities → + Capability → **HealthKit**;
   Watch-Target zusätzlich **Background Modes → Workout processing**.
6. Info-Einträge aus `project.yml` (NSHealthShareUsageDescription, NSHealthUpdateUsageDescription,
   URL-Schema `kbtrx`) übernehmen.
</details>

## 2. Signieren

Für **beide** Targets (KettlebellTRX und KettlebellTRXWatch): Signing & Capabilities →
„Automatically manage signing“ → Team wählen. HealthKit muss als Capability erscheinen.

## 3. Auf iPhone und Apple Watch installieren

1. iPhone per Kabel verbinden (oder WLAN-Debugging aktivieren) und entsperren.
2. iPhone: Einstellungen → Datenschutz & Sicherheit → **Entwicklermodus** aktivieren (Neustart).
3. Apple Watch: Einstellungen → Datenschutz & Sicherheit → **Entwicklermodus** aktivieren.
   Die Watch muss mit dem iPhone gekoppelt, entsperrt und in Reichweite sein.
4. In Xcode Schema **KettlebellTRX** und als Ziel das iPhone wählen → ▶︎ Run.
   Die Watch-App wird automatisch mitinstalliert (alternativ Watch-App in der Watch-App
   des iPhones unter „Verfügbare Apps“ installieren).
5. Bei kostenlosem Account: iPhone → Einstellungen → Allgemein → VPN & Geräteverwaltung →
   Entwickler-App vertrauen.
6. Watch-App direkt debuggen: Schema **KettlebellTRXWatch**, Ziel Apple Watch → ▶︎ Run.

## 4. Erste Schritte in der App

1. Einstellungen (Zahnrad) → **Profil**: Angaben prüfen (vorbelegt: Jg. 1967, 193 cm,
   Kettlebells 8/12/16 kg, TRX, Mo/Mi/Fr, 30–40 min).
2. Einstellungen → **Gesundheit**: Einschränkungen, Pulsobergrenze, Technikfreigabe für Swings.
3. Einstellungen → **Geräte** → „Mit Apple Health verbinden“ und Berechtigungen erteilen.
   Optional „Workouts in Apple Health speichern“.
4. Garmin: In **Garmin Connect** → Mehr → Einstellungen → Verbundene Apps → Apple Health →
   Datenfreigabe aktivieren. Danach in der App „Verfügbare Garmin-Datenarten prüfen“.
5. WHOOP (optional): siehe [INTEGRATIONS.md](INTEGRATIONS.md#whoop).
6. Tab **Training** → Selbsteinschätzung → Empfehlung → Start. Die Watch-App öffnet sich.

## 5. TestFlight

1. Apple Developer Program erforderlich. In App Store Connect eine App mit der Bundle-ID
   `<prefix>.app` anlegen.
2. Xcode: Ziel „Any iOS Device (arm64)“ → Product → **Archive** → Distribute App →
   App Store Connect → Upload.
3. App Store Connect → TestFlight → Build freigeben (interne Tester: sofort).
4. Auf dem iPhone die TestFlight-App installieren und Einladung annehmen; die Watch-App wird
   über die Watch-App des iPhones installiert.

Hinweis: Für TestFlight-Builds mit HealthKit verlangt Apple eine Datenschutzrichtlinie
(Privacy Policy URL) in App Store Connect.
