# Projektfinanzierung Erneuerbare Energien – Frontend

Kunden-Frontend für die Projektfinanzierung von Wind-, PV- und Speicherprojekten einer Volks- und Raiffeisenbank.
Projektierer, Betreiber, Bürgerenergiegesellschaften, Landwirte und Stadtwerke machen ihre Angaben selbst.
Dadurch wird die Bearbeitung schneller und die Bank erhält strukturierte Daten für eine automatische Vorprüfung.

Reines HTML, CSS und Vanilla JavaScript. Kein Framework, kein Build-Schritt.

## Seitenübersicht

| Datei | Inhalt |
|---|---|
| `index.html` | Landingpage: Hero mit Schnell-Check (3 Reiter, Sofort-Indikation), Was wir finanzieren, Ablauf, Unterlagen-Checkliste, FAQ, Kontaktband, Footer |
| `anfrage.html` | Vollständige Anfrage in 6 Schritten mit Schrittnavigation (links), Formular (Mitte) und Live-Indikation (rechts), danach Erfolgsseite |
| `portal.html` | Kundenportal: Anfragen mit Status-Pipeline, offene Rückfragen, Ansprechpartner |
| `assets/styles.css` | Gesamtes Styling, Farben als CSS-Variablen |
| `assets/calc.js` | **Rechenkern und Konfiguration** (`CONFIG`), Zahlen-Parsing und -Formatierung, sessionStorage-Helfer |
| `assets/schnellcheck.js` | Tabs, Vollständigkeit, Indikation und Übergabe des Schnell-Checks |
| `assets/anfrage.js` | Schritte, Validierung, Vorbefüllung, Uploads, Entwurf, Einreichen |
| `assets/portal.js` | `loadData()` und Rendering per `<template>` |
| `tests/calc.test.js` | Tests des Rechenkerns (`node tests/calc.test.js`), laufen auch vor jeder Veröffentlichung |

## Start

```bash
python3 -m http.server 8000
```

Danach im Browser <http://localhost:8000> öffnen. Ein lokaler Server ist nötig, weil `sessionStorage` und `<template>` unter `file://` je nach Browser eingeschränkt sind.

### Online (GitHub Pages)

Die Seite wird bei jedem Push auf `main` automatisch veröffentlicht (`.github/workflows/pages.yml`):
<https://rt6k6rcwb7-stack.github.io/EEneue-Antragsstrecke/>

Der Workflow führt vorher die Tests des Rechenkerns aus (`tests/calc.test.js`) und veröffentlicht nur `index.html`, `anfrage.html`, `portal.html` und `assets/`.
Einmalig nötig: unter **Settings → Pages → Build and deployment → Source** „GitHub Actions“ auswählen.
Manuell auslösen: **Actions → GitHub Pages → Run workflow**.

## Konfiguration

Alle Bankparameter stehen zentral in `CONFIG` in `assets/calc.js`:

| Schlüssel | Wert | Bedeutung |
|---|---|---|
| `zinsProzent` | 4,5 | Zins im Schnell-Check |
| `laufzeitJahre` | 18 | Laufzeit im Schnell-Check |
| `fkQuoteProzent` | 80 | Standard-Fremdkapitalquote |
| `minDscrP50` | 1,20 | Mindest-DSCR P50 |
| `minDscrP90` | 1,05 | Mindest-DSCR P90 |
| `toleranzKnapp` | 0,05 | Ampel „knapp“, wenn bis zu diesem Wert unter dem Mindest-DSCR |
| `urteilKnappBand` | 0,15 | Urteil „Knapp – Struktur anpassen“ im Schnell-Check bis zu diesem Abstand |
| `opexPauschale` | Wind 45, PV-Freifläche 15, Agri-PV 18, PV-Dach 15, Speicher 12 | Betriebskosten in T€ je MW und Jahr, wenn keine Angabe gemacht wird |
| `anfrage` | Zins 4,2 %, 18 Jahre, 80 % FK | Vorbelegung von Schritt 4 der Anfrage (vom Kunden änderbar) |
| `upload` | max. 25 MB; PDF, Excel, Word, ZIP, JPG, PNG | Nur clientseitige Vorprüfung |
| `speicher` | Schlüsselnamen | Schlüssel im sessionStorage |
| `standort` | siehe unten | Standortgüte: Korrekturfaktoren, Bandbreiten, Ampel-Grenzwerte, Degradation |

### Standortgüte (`CONFIG.standort`) – Platzhalterwerte

**Alle Werte in diesem Block sind Platzhalter.** Es sind grobe Erfahrungswerte, die die Kreditabteilung bzw. das Risikomanagement festlegen muss.

| Schlüssel | Platzhalter | Bedeutung |
|---|---|---|
| `wind.korrekturfaktoren` | 50 % → 1,55 … 100 % → 1,00 … 150 % → 0,79 | Korrekturfaktoren des EEG-Referenzertragsmodells (Stützstellen nach § 36h EEG 2023, vor Livegang mit der geltenden Fassung abgleichen). Dazwischen wird linear interpoliert. |
| `wind.korrekturFuerErloesmodell` | `['eeg']` | Nur bei diesen Erlösmodellen wird der eingegebene Zuschlagswert mit dem Korrekturfaktor multipliziert |
| `wind.guetefaktorRot` / `Gelb` | 60 % / 70 % | Ampel Windangebot |
| `bandbreiten` | je Bundesland, z. B. Bayern Wind 1.500–2.600 h, PV 980–1.200 h | Übliche Volllaststunden P50 für die Plausibilitätsprüfung |
| `pvFaktor` | Freifläche 1,0 · Agri-PV 0,95 · Dach 0,9 | Skalierung der PV-Bandbreite je Bauform |
| `bandbreiteRotUeberProzent` | 15 % | Ab so viel über dem Höchstwert ist die Ampel rot |
| `p90AbstandGelbProzent` / `Rot` | 10 % / 15 % | Abstand P90 zu P50 (Unsicherheit der Prognose) |
| `gutachtenGruen` | Wind: zwei, sonst: eines | Anzahl unabhängiger Gutachten für „gut“ |
| `kabelGelbKm` / `kabelRotKm` | 10 km / 20 km | Ampel Kabeltrasse |
| `abregelungGelbProzent` / `Rot` | 5 % / 10 % | Ampel erwartete Abregelung |
| `abregelungErfahrung` | z. B. Schleswig-Holstein 6 %, Niedersachsen 4 %, Standard 1,5 % | Regionale Erfahrungswerte, **nur als Hinweis** angezeigt, nicht automatisch angesetzt |
| `degradationStandard` | Wind 0 · PV-Freifläche 0,4 · Agri-PV 0,4 · PV-Dach 0,5 · Speicher 1,0 % p. a. | Wird angesetzt, wenn der Kunde nichts angibt |

Hinweis: Im Schnell-Check gilt der Zins aus `CONFIG.zinsProzent` (4,5 %), in der Anfrage die änderbare Vorbelegung (4,2 %). Deshalb weichen die DSCR-Werte beider Seiten bei gleichen Eingaben leicht voneinander ab.

Texte in eckigen Klammern sind Platzhalter: `[Bankname]`, `[X Werktagen]`, Konditionen, Kontaktdaten und der Datenschutztext. Das Logo ist nur als Platzhalter „LOGO“ angelegt.

## Datenfluss

1. **Schnell-Check** (`index.html`): Die Eingaben werden bei jeder Änderung neu berechnet. Beim Klick auf „Vollständige Anfrage starten“ (und auf die anderen Links zur Anfrage) speichert die Seite alle Felder unter `ee_schnellcheck_v1` im sessionStorage.
2. **Anfrage** (`anfrage.html`): Die Feldnamen sind auf beiden Seiten identisch (`technologie`, `leistung_mw`, `bundesland`, `inbetriebnahme`, `rolle`, `genehmigung`, `netzanschluss`, `flaechen`, `erloesmodell`, `p50_h`, `preis_eur_mwh`, `speicher_erloes`, `capex_teur`, `opex_teur`, `fk_quote`, `guetefaktor`). Nur in der Anfrage: `spannungsebene`, `kabel_km`, `abregelung_prozent`, `nabenhoehe`, `windgeschwindigkeit`, `globalstrahlung`, `gutachten`, `degradation_prozent`. Beim Laden gilt diese Reihenfolge:
   - Liegt ein gespeicherter Entwurf (`ee_anfrage_entwurf_v1`) vor, wird er geladen.
   - Sonst werden die Schnell-Check-Daten übernommen.
   - In beiden Fällen erscheint ein Hinweis.
3. **Entwurf speichern**: Schreibt Felder, aktuellen Schritt und Dateinamen in den sessionStorage. Die Dateien selbst lassen sich dort nicht speichern und müssen nach dem Neuladen erneut ausgewählt werden.
4. **Einreichen**: Alle Schritte werden geprüft. Danach entsteht ein `FormData`:
   - `anfrage`: JSON mit Eingaben, geparsten Zahlen, Indikation (inkl. Korrekturfaktor und Abschlägen), Projektreife, Standort-Ampel mit Begründungen, Unterlagenliste und den verwendeten Parametern
   - `dokument_<id>`: je hochgeladener Datei, mit `id` ∈ `ertragsgutachten`, `genehmigung`, `netzanschluss`, `pacht`, `epc`, `wartung`, `erloes`, `gesellschaft`, `finanzmodell`

   Der `fetch`-Aufruf ist als TODO vorbereitet. Die Demo erzeugt eine vorläufige Vorgangsnummer und legt den Vorgang unter `ee_vorgaenge_v1` ab, damit er im Portal erscheint.
5. **Portal** (`portal.html`): `loadData()` liefert `{ vorgaenge, rueckfragen }`. Derzeit sind das 3 fiktive Demo-Projekte plus die in dieser Sitzung eingereichten Anfragen.

Jeder Zugriff auf den sessionStorage ist in `try/catch` gekapselt (`EE.Store`). Ist der Speicher blockiert, funktioniert die Seite weiter, nur die Übernahme der Daten entfällt.

## Rechenlogik (`calc.js`)

Alle Beträge sind in T€ angegeben.

```
Preis wirksam      = €/MWh × Korrekturfaktor   (nur Wind mit EEG-Zuschlag und Gütefaktor, sonst Faktor 1)
Umsatzfaktor       = (1 − Abregelung) × Degradationsfaktor
Degradationsfaktor = (1 − (1 − d)^n) / (n × d)   (Mittelwert über die Kreditlaufzeit n, Jahr 1 = 100 %)
Umsatz P50         = MW × Volllaststunden P50 × Preis wirksam / 1000 × Umsatzfaktor   (Speicher: MW × T€/MW/a × Umsatzfaktor)
Umsatz P90         = MW × Volllaststunden P90 × Preis wirksam / 1000 × Umsatzfaktor   (bei Speicher keine P90-Betrachtung)
Opex               = Angabe, sonst MW × Pauschale je MW
CFADS              = Umsatz − Opex
Kreditbetrag       = Capex × FK-Quote
Eigenkapital       = Capex − Kreditbetrag
Annuitätenfaktor   = r / (1 − (1 + r)^−n)
Annuität           = Kreditbetrag × Annuitätenfaktor
DSCR               = CFADS / Annuität
Tragfähiger Kredit = CFADS P50 / Mindest-DSCR P50 / Annuitätenfaktor
Ampel              = ok (≥ Mindestwert) · warn (bis 0,05 darunter) · fail (darunter)
```

**Urteil im Schnell-Check** (auf Basis DSCR P50):

| Urteil | Bedingung |
|---|---|
| Gut finanzierbar | DSCR ≥ Mindestwert und Genehmigung erteilt oder bestandskräftig |
| Tragfähig, Projekt in Entwicklung | DSCR ≥ Mindestwert, Genehmigung noch offen |
| Knapp – Struktur anpassen | DSCR bis 0,15 unter dem Mindestwert |
| Kreditwunsch zu hoch | DSCR darunter |

**Projektreife** in der Anfrage:

| Stufe | Bedingung |
|---|---|
| Baureif | Genehmigung erteilt oder bestandskräftig, Netzanschlusszusage liegt vor und Flächen vollständig gesichert |
| Fast baureif | 2 dieser 3 Punkte sind erfüllt |
| In Entwicklung | sonst |

Die offenen Punkte werden in der Live-Indikation aufgelistet.

**Standort-Ampel** in der Anfrage (`EE.standortBewertung`): drei Bereiche, jeweils „gut“, „prüfen“ oder „kritisch“, mit Begründung. Die Gesamtampel ist der schlechteste Bereich. Fehlende Angaben zählen als „prüfen“, sobald im Bereich etwas angegeben ist; ohne Angaben bleibt der Bereich „offen“.

| Bereich | Bewertet wird |
|---|---|
| Windangebot bzw. Sonneneinstrahlung | Gütefaktor (Wind) und P50 im Vergleich zur Bandbreite des Bundeslands. Bei Speichern entfällt der Bereich. |
| Gutachtenlage | Stand des Ertrags- bzw. Erlösgutachtens und Abstand P90 zu P50 |
| Netz | Netzanschluss-Status, Spannungsebene, Länge der Kabeltrasse, erwartete Abregelung |

**Plausibilitätsprüfung:** Liegt P50 außerhalb der üblichen Bandbreite des Bundeslands, zeigt der Schnell-Check einen Hinweis im Ergebnis und die Anfrage einen Punkt in der Standort-Ampel.

**Ausdrücklich vereinfacht:** Die Rechnung berücksichtigt keine Steuern, keine Reserven (DSRA/MRA) und keine Bauzeitzinsen. Degradation geht als Mittelwert über die Laufzeit ein; der DSCR des schwächsten (letzten) Jahres liegt bei PV daher etwas niedriger. Abregelung wird als pauschaler Erlösausfall angesetzt, auch wenn sie teilweise entschädigt wird. Die Annuität ist über die Laufzeit konstant. Das Ergebnis ist keine Kreditzusage.

**Zahleneingabe:** `parseZahl()` versteht `4,2`, `4.2`, `34.800` (Tausenderpunkt) und `1.234,5`. Die Ausgabe erfolgt mit `toLocaleString('de-DE')`.

### Testfall

Wind, 24 MW, P50 2.400 h, P90 2.050 h, 73 €/MWh, Capex 34.800 T€, Opex 1.100 T€/a, 80 % FK, 4,2 %, 18 Jahre.

| Größe | Ergebnis |
|---|---|
| Kreditbetrag | 27.840 T€ |
| Annuität | **2.235 T€** |
| CFADS P50 | 3.105 T€ |
| CFADS P90 | 2.492 T€ |
| DSCR P50 | **1,39x** |
| DSCR P90 | **1,11x** |

Der Testfall nutzt keinen Gütefaktor und keine Abregelung; für Wind ist die Standard-Degradation 0. Das Ergebnis ist daher unverändert.

Tests ohne Browser ausführen (prüfen Testfall, Zahlen-Parsing, Korrekturfaktor, Abschläge, Plausibilität und Standort-Ampel):

```bash
node tests/calc.test.js
```

## Barrierefreiheit (Ziel: WCAG 2.1 AA)

- Es werden echte Formularelemente verwendet. Die Auswahlchips sind versteckte Radio-Buttons mit sichtbarem Label und bleiben per Tastatur bedienbar.
- Der Schnell-Check nutzt das WAI-ARIA-Tab-Muster: Pfeiltasten, Pos1 und Ende, Roving-Tabindex.
- Klickflächen sind mindestens 44 px groß. Der Fokusring ist orange mit dunkelblauem Innenring und bleibt so auf hellem und dunklem Grund sichtbar.
- Texte haben einen Kontrast von mindestens 4,5:1. Auf Orange steht deshalb dunkelblaue Schrift (#002D5C).
- Ergebnisse und Statusmeldungen stehen in `aria-live`-Regionen. Der aktuelle Schritt ist mit `aria-current="step"` markiert, Fortschrittsbalken haben `role="progressbar"`.
- Bei Fehlern wird `aria-invalid` gesetzt und die Fehlermeldung über `aria-describedby` verknüpft. Der Fokus springt auf das erste fehlerhafte Feld.
- Animationen werden bei `prefers-reduced-motion` abgeschaltet.

## TODOs für das Backend

- **Anfrage-Endpunkt** (`anfrage.js`, Funktion `einreichen`): `POST multipart/form-data` mit dem Feld `anfrage` (JSON) und den Feldern `dokument_<id>`. Der Server vergibt die verbindliche Vorgangsnummer. CSRF-Schutz ist nötig.
- **Uploads serverseitig prüfen:** Dateityp per Magic Bytes (nicht nur über die Endung), Größe und Anzahl begrenzen und auf Schadsoftware scannen (z. B. ClamAV oder ICAP), bevor die Datei weiterverarbeitet oder Mitarbeitenden angezeigt wird. Die Prüfung im Browser ist nur Komfort.
- **Alle Eingaben und Berechnungen serverseitig erneut validieren.** Werte aus dem Client sind nicht vertrauenswürdig, die Vorprüfung rechnet der Server mit eigenen Parametern neu.
- **Portal:** Eine Authentifizierung ist **nicht enthalten**. `loadData()` in `portal.js` muss durch einen authentifizierten API-Aufruf ersetzt werden, z. B. über das Online-Banking-Login der Bank. Ebenfalls anzubinden sind der Upload zu Rückfragen und das Senden von Antworten (TODO-Kommentare in `portal.js`).
- **Dauerhafte Entwürfe:** sessionStorage hält Daten nur im aktuellen Tab. Für Entwürfe über Sitzungen und Geräte hinweg braucht es einen Server-Endpunkt mit Login.
- **Datenschutz:** Der Datenschutztext, die Einwilligungslogik und die Speicherfristen sind mit dem Datenschutzbeauftragten abzustimmen.
- **Corporate Design:** Die Farbwerte (`--blau`, `--blau-dunkel`, `--orange`, `--auf-orange`) sind nur angelehnt und müssen mit dem Corporate Design der Bank bzw. den Vorgaben des Verbands abgeglichen werden. Das gilt auch für Logo und Schrift. IBM Plex Sans wird derzeit von Google Fonts geladen und sollte für den Livebetrieb selbst gehostet werden.
