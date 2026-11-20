/*
 * Tests für den Rechenkern (assets/calc.js).
 * Ausführen: node tests/calc.test.js
 */
'use strict';
const assert = require('assert');
const EE = require('../assets/calc.js');

let anzahl = 0;
function test(name, fn) {
  fn();
  anzahl++;
  console.log('ok  ' + name);
}
const nahe = (ist, soll, tol, name) =>
  assert.ok(Math.abs(ist - soll) <= tol, `${name}: ${ist} statt ${soll} (±${tol})`);

const TESTFALL = {
  technologie: 'wind', leistungMW: 24, p50h: 2400, p90h: 2050, preisEURMWh: 73,
  capexTEUR: 34800, opexTEUR: 1100, fkQuoteProzent: 80, zinsProzent: 4.2, laufzeitJahre: 18
};

test('Testfall Wind aus der Vorgabe', () => {
  const r = EE.berechne(TESTFALL);
  nahe(r.dscrP50, 1.39, 0.005, 'DSCR P50');
  nahe(r.dscrP90, 1.11, 0.01, 'DSCR P90');
  nahe(r.annuitaet, 2235, 1, 'Annuität');
  assert.strictEqual(r.korrekturfaktor, 1);
  assert.strictEqual(r.umsatzfaktor, 1);
});

test('Zahlen im deutschen Format parsen', () => {
  assert.strictEqual(EE.parseZahl('4,2'), 4.2);
  assert.strictEqual(EE.parseZahl('4.2'), 4.2);
  assert.strictEqual(EE.parseZahl('34.800'), 34800);
  assert.strictEqual(EE.parseZahl('1.234,5'), 1234.5);
  assert.strictEqual(EE.parseZahl('abc'), null);
});

test('Korrekturfaktor: Stützstellen, Interpolation, Randwerte', () => {
  assert.strictEqual(EE.korrekturfaktor(100), 1);
  assert.strictEqual(EE.korrekturfaktor(80), 1.16);
  nahe(EE.korrekturfaktor(75), 1.225, 1e-9, 'Gütefaktor 75 %');
  assert.strictEqual(EE.korrekturfaktor(30), 1.55);
  assert.strictEqual(EE.korrekturfaktor(170), 0.79);
});

test('Korrekturfaktor wirkt nur bei Wind mit EEG-Zuschlag', () => {
  const eeg = EE.berechne(Object.assign({}, TESTFALL, { guetefaktorProzent: 80, erloesmodell: 'eeg' }));
  assert.strictEqual(eeg.korrekturfaktor, 1.16);
  nahe(eeg.preisWirksam, 73 * 1.16, 1e-9, 'wirksamer Preis');
  const ppa = EE.berechne(Object.assign({}, TESTFALL, { guetefaktorProzent: 80, erloesmodell: 'ppa' }));
  assert.strictEqual(ppa.korrekturfaktor, 1);
});

test('Abregelung als Abschlag auf den Umsatz', () => {
  const r = EE.berechne(Object.assign({}, TESTFALL, { abregelungProzent: 5 }));
  nahe(r.umsatzP50, 24 * 2400 * 73 / 1000 * 0.95, 1e-6, 'Umsatz P50');
});

test('Degradation: Standard für PV, Mittelwert über die Laufzeit', () => {
  nahe(EE.degradationsfaktor(0.4, 18), (1 - Math.pow(0.996, 18)) / (18 * 0.004), 1e-12, 'Faktor');
  assert.strictEqual(EE.degradationsfaktor(0, 18), 1);
  const pv = EE.berechne({ technologie: 'pv_frei', leistungMW: 10, p50h: 1000, preisEURMWh: 60,
    capexTEUR: 6000, fkQuoteProzent: 80, zinsProzent: 4.2, laufzeitJahre: 18 });
  assert.strictEqual(pv.degradationProzent, EE.CONFIG.standort.degradationStandard.pv_frei);
  assert.ok(pv.degradationsfaktor < 1 && pv.degradationsfaktor > 0.95);
});

test('Plausibilität P50 je Bundesland', () => {
  const band = EE.bandbreite('pv_frei', 'Bayern');
  assert.deepStrictEqual(band, EE.CONFIG.standort.bandbreiten.Bayern.pv);
  assert.strictEqual(EE.plausibilitaet('pv_frei', 'Bayern', band[0] + 10).stufe, 'ok');
  assert.strictEqual(EE.plausibilitaet('pv_frei', 'Bayern', band[1] + 10).stufe, 'warn');
  assert.strictEqual(EE.plausibilitaet('pv_frei', 'Bayern', band[1] * 1.3).stufe, 'fail');
  assert.strictEqual(EE.plausibilitaet('pv_frei', 'Bayern', band[0] - 10).stufe, 'warn');
  assert.strictEqual(EE.plausibilitaet('speicher', 'Bayern', 1000).stufe, null);
  assert.strictEqual(EE.plausibilitaet('wind', '', 2400).stufe, null);
});

test('Standort-Ampel: grüner Windstandort', () => {
  const d = { technologie: 'wind', bundesland: 'Niedersachsen', leistung_mw: '24', p50_h: '2.400', p90_h: '2.250',
    guetefaktor: '85', gutachten: 'zwei', netzanschluss: 'zusage', spannungsebene: 'ms', kabel_km: '6', abregelung_prozent: '2' };
  const s = EE.standortBewertung(d);
  assert.strictEqual(s.dargebot.stufe, 'ok');
  assert.strictEqual(s.gutachten.stufe, 'ok');
  assert.strictEqual(s.netz.stufe, 'ok');
  assert.strictEqual(s.gesamt, 'ok');
});

test('Standort-Ampel: Schwachstellen werden erkannt', () => {
  const d = { technologie: 'wind', bundesland: 'Bayern', leistung_mw: '24', p50_h: '2.400', p90_h: '1.900',
    guetefaktor: '55', gutachten: 'eines', netzanschluss: 'angefragt', spannungsebene: 'hs', kabel_km: '25' };
  const s = EE.standortBewertung(d);
  assert.strictEqual(s.dargebot.stufe, 'fail');   // Gütefaktor unter 60 %
  assert.strictEqual(s.gutachten.stufe, 'fail');  // P90 > 15 % unter P50
  assert.strictEqual(s.netz.stufe, 'fail');       // Kabeltrasse > 20 km
  assert.ok(s.netz.punkte.some(p => /Abregelung fehlt/.test(p.text)));
  assert.strictEqual(s.gesamt, 'fail');
});

test('Standort-Ampel: ohne Angaben neutral, Speicher ohne Dargebot', () => {
  const leer = EE.standortBewertung({ technologie: 'pv_frei' });
  assert.strictEqual(leer.gesamt, null);
  const sp = EE.standortBewertung({ technologie: 'speicher', gutachten: 'eines' });
  assert.strictEqual(sp.dargebot.entfaellt, true);
  assert.strictEqual(sp.gutachten.stufe, 'ok');
});

console.log(`\n${anzahl} Tests bestanden.`);
