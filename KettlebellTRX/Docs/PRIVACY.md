# Datenschutz und Datensicherheit

Gesundheitsdaten sind besondere Kategorien personenbezogener Daten (Art. 9 DSGVO). Die App ist
für die private Nutzung in der Familie ausgelegt – jede Person auf ihrem eigenen Gerät, ohne Datenaustausch – und verarbeitet Daten standardmäßig nur lokal.

## Umsetzung

| Anforderung | Umsetzung |
|---|---|
| Lokale Speicherung als Standard | JSON-Dateien in „Application Support“, keine Server, keine Cloud |
| iOS-Datenschutzmechanismen | Data Protection `completeUntilFirstUserAuthentication` (Training auch bei gesperrtem Gerät speicherbar); Export-Dateien `complete`; App-Ordner vom iCloud-Backup ausgeschlossen |
| Verschlüsselte Übertragung | `URLSessionHTTPClient` lehnt Nicht-HTTPS ab; WHOOP und Broker nur über HTTPS |
| Sichere Token-Speicherung | Keychain, `AfterFirstUnlockThisDeviceOnly`, nie im Export |
| Client-Secret | nur im Token-Broker (Server-Secret), nie in der App |
| Minimale Berechtigungen | nur benötigte HealthKit-Typen; Schreibrechte nur bei Zustimmung; WHOOP nur Lese-Scopes |
| Transparente Einwilligungen | `PrivacyConsents`: Apple Health lesen/schreiben, Cloud (aus), KI-Dienste (aus) |
| Widerruf | je Verbindung: Token löschen, WHOOP-Zugriff serverseitig beenden, optional importierte Daten löschen |
| Löschung | „Alle persönlichen Daten löschen“ entfernt sämtliche Dateien und Token |
| Export (Art. 20) | JSON (vollständig) + CSV (Sätze, Vitaldaten), Teilen über das System-Teilen-Menü |
| Keine Werbung/Tracking | keine Drittanbieter-SDKs; Privacy Manifest ohne Tracking und ohne erhobene Datentypen |
| KI-Dienste | in V1 nicht vorhanden; künftig nur mit gesonderter Einwilligung |

## Hinweise zu den Nutzungsbedingungen

* **Apple HealthKit**: Gesundheitsdaten dürfen nicht für Werbung genutzt oder verkauft werden;
  eine Datenschutzerklärung ist für TestFlight/App Store erforderlich.
* **WHOOP**: Die API-Bedingungen gelten für die eigene Developer-App; Daten nur für den
  angegebenen Zweck verwenden; Token schützen.
* **Garmin**: Developer Program nur für Unternehmen; Personal API laut Garmin nur für den
  persönlichen Gebrauch. Keine inoffiziellen Schnittstellen.

Dies ist eine technische Zusammenfassung und keine Rechtsberatung. Bei Weitergabe der App an
Dritte (z. B. TestFlight mit externen Testern) sind Datenschutzerklärung und ggf.
Datenschutz-Folgenabschätzung zu prüfen.
