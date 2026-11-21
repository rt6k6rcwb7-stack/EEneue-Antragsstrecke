# Nutzung in der Familie

Die App ist für die private Nutzung innerhalb der Familie gedacht:
**jede Person auf ihrem eigenen iPhone (und ggf. eigener Apple Watch), verteilt über TestFlight.**

## Grundprinzip

| | |
|---|---|
| Ein iPhone = eine Person | Apple Health und die Apple Watch gehören technisch immer der Person, der das iPhone gehört. Deshalb gibt es kein Mehrbenutzer-Profil auf einem Gerät. |
| Ersteinrichtung | Beim ersten Start führt ein Assistent durch Name, Geburtsjahr, Größe, Erfahrung, vorhandene Kettlebells/TRX, Trainingstage, Gesundheits-Check und Einwilligungen. Daraus entsteht ein persönlicher 8-Wochen-Plan. |
| Keine gemeinsamen Daten | Trainingsdaten, Vitaldaten und Beschwerden bleiben auf dem jeweiligen iPhone. Weder andere Familienmitglieder noch du als Herausgeber der App sehen sie. Es gibt keinen Server, kein Konto und keine Cloud. |
| Eigene Geräteverbindungen | Jede Person verbindet ihre eigene Apple Watch, ihr eigenes WHOOP-Konto und ggf. ihre eigene Garmin-Uhr (über Apple Health). |
| Gesundheits-Check | Sieben Ja/Nein-Fragen vor Trainingsbeginn. Bei einem „Ja“ empfiehlt die App eine ärztliche Rücksprache und setzt vorsichtige Einstellungen (keine Swings, Pulswarnung bzw. 80 % Intensität). Unter 16 Jahren nur mit begleitendem Erwachsenen. |

## Verteilung über TestFlight – Schritt für Schritt

Einmalig (durch dich):

1. **Apple Developer Program** beitreten (99 €/Jahr, developer.apple.com/programs).
2. In `project.yml` eintragen: `BUNDLE_ID_PREFIX` (z. B. `de.familiemustermann.kbtrx`) und `DEVELOPMENT_TEAM` (Team-ID).
   Optional `WHOOP_CLIENT_ID` und `WHOOP_BROKER_URL` (siehe unten) – dann muss in der Familie niemand etwas eintippen.
3. `xcodegen generate`, Projekt in Xcode öffnen, beide Targets signieren (Automatic Signing, HealthKit-Capability aktiv).
4. **App Store Connect** → Meine Apps → „+“ → Neue App: Plattform iOS, Name z. B. „KB & TRX Familie“,
   Bundle-ID `<prefix>.app`, SKU beliebig. Die App wird **nicht** im App Store veröffentlicht.
5. Unter „App-Informationen“ eine **Datenschutzrichtlinien-URL** hinterlegen
   (Vorlage: [DATENSCHUTZERKLAERUNG.md](DATENSCHUTZERKLAERUNG.md), z. B. über GitHub Pages veröffentlichen).
6. Xcode → Ziel „Any iOS Device (arm64)“ → Product → **Archive** → Distribute App → **TestFlight & App Store** → Upload.
   Die Watch-App ist im selben Build enthalten.
7. App Store Connect → TestFlight → beim Build die Exportkonformität bestätigen
   (`ITSAppUsesNonExemptEncryption = false` ist bereits gesetzt).

Familienmitglieder einladen – zwei Wege:

| | **Externe Testgruppe „Familie“** (empfohlen) | Interne Tester |
|---|---|---|
| Einladung | per E-Mail an die Apple-ID-Adresse (kein öffentlicher Link nötig) | Person muss Mitglied deines App-Store-Connect-Teams werden |
| Zugriff auf dein Entwicklerkonto | nein | ja (eingeschränkte Rolle) |
| Prüfung durch Apple | erster Build einer Version durchläuft die TestFlight-Beta-Prüfung (meist 1–2 Tage) | keine, sofort verfügbar |
| Anzahl | bis 10.000 | bis 100 |

8. TestFlight → „Externe Tests“ → Gruppe „Familie“ anlegen → Tester per E-Mail hinzufügen → Build zuweisen →
   Testinformationen ausfüllen (Beschreibung, Feedback-E-Mail) → zur Prüfung einreichen.

Auf jedem iPhone der Familie:

1. App **TestFlight** aus dem App Store installieren.
2. Einladungs-E-Mail öffnen → „Testen starten“ → App installieren.
3. Apple Watch: Die Watch-App wird automatisch installiert (oder in der Watch-App des iPhones unter „Verfügbare Apps“).
4. App öffnen → Einrichtungsassistent durchlaufen.

### Wichtig zu TestFlight

* **Builds laufen nach 90 Tagen ab.** Rechtzeitig einen neuen Build hochladen (gleiche Bundle-ID, höhere Build-Nummer
  `CURRENT_PROJECT_VERSION`). Die Daten in der App bleiben bei Updates erhalten.
* Vor dem Ablauf bzw. vor einem Gerätewechsel: **Einstellungen → Datenschutz → Daten exportieren** als Sicherung,
  da die App-Daten bewusst nicht in iCloud gesichert werden.
* Updates erscheinen in der TestFlight-App; automatische Updates lassen sich dort aktivieren.
* Familienfreigabe (Family Sharing) gilt nicht für TestFlight – jede Person braucht eine eigene Einladung.

## WHOOP in der Familie

* Du legst **eine** WHOOP-Developer-App und **einen** Token-Broker an (siehe [INTEGRATIONS.md](INTEGRATIONS.md#whoop)).
* Trägst du Client-ID und Broker-URL in `project.yml` ein (`WHOOP_CLIENT_ID`, `WHOOP_BROKER_URL`), sind sie in jeder
  installierten App vorbelegt. Beides ist öffentlich und kein Geheimnis; das Client-Secret liegt nur im Broker.
* Jede Person meldet sich in der App mit **ihrem eigenen WHOOP-Konto** an. Die Daten gehen direkt von WHOOP auf ihr iPhone.
  Der Broker tauscht nur Anmelde-Codes gegen Token und speichert nichts.
* Bitte im WHOOP Developer Dashboard prüfen, wie viele Mitglieder eine noch nicht freigegebene Developer-App verbinden darf.

## Garmin in der Familie

Jede Person aktiviert in **ihrer** Garmin-Connect-App die Freigabe an Apple Health. Die direkte Garmin-API ist laut
Garmin nur für den persönlichen Gebrauch der jeweiligen Person vorgesehen und bleibt in dieser Version deaktiviert.

## Datenschutz in der Familie

* Jede Person verarbeitet ihre eigenen Daten auf ihrem eigenen Gerät. Du als Herausgeber erhältst keine Daten.
* Für eine rein private, familiäre Nutzung greift in der Regel die Haushaltsausnahme der DSGVO
  (Art. 2 Abs. 2 lit. c). Das ist keine Rechtsberatung.
* Hinweis an die Familie: Sperrcode und Face ID/Touch ID auf dem iPhone schützen die Gesundheitsdaten zusätzlich
  (iOS-Datenschutzklasse).
