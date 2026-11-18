/*
 * calc.js – Rechenkern und zentrale Konfiguration
 * Projektfinanzierung Erneuerbare Energien
 *
 * Alle Bankparameter stehen ausschließlich im CONFIG-Objekt.
 * Die Rechnung ist bewusst vereinfacht: ohne Steuern, Reserven
 * (DSRA/MRA), Bauzeitzinsen und Degradation. Sie ersetzt keine
 * Kreditprüfung und stellt keine Kreditzusage dar.
 *
 * Läuft im Browser (window.EE) und in Node (module.exports) –
 * so lässt sich der Testfall ohne Browser prüfen.
 */
(function (global) {
  'use strict';

  /* ------------------------------------------------------------------
   * Konfiguration (Bankparameter)
   * ---------------------------------------------------------------- */
  var CONFIG = {
    // Schnell-Check: Standardkonditionen der Indikation
    zinsProzent: 4.5,
    laufzeitJahre: 18,
    fkQuoteProzent: 80,

    // Mindest-Schuldendienstdeckungsgrade
    minDscrP50: 1.20,
    minDscrP90: 1.05,

    // Ampel: "knapp", wenn bis zu diesem Wert unter dem Mindest-DSCR
    toleranzKnapp: 0.05,
    // Urteil im Schnell-Check: "Knapp – Struktur anpassen" bis zu diesem Abstand
    urteilKnappBand: 0.15,

    // Opex-Pauschalen in T€ je MW und Jahr (wenn keine Betriebskosten angegeben)
    opexPauschale: {
      wind: 45,
      pv_frei: 15,
      agri_pv: 18,
      pv_dach: 15,
      speicher: 12
    },

    // Vorbelegung der vollständigen Anfrage (Schritt 4)
    anfrage: {
      zinsProzent: 4.2,
      laufzeitJahre: 18,
      fkQuoteProzent: 80
    },

    // Uploads (nur clientseitige Vorprüfung – serverseitig zwingend erneut prüfen)
    upload: {
      maxMB: 25,
      endungen: ['.pdf', '.xlsx', '.xls', '.xlsm', '.docx', '.doc', '.zip', '.jpg', '.jpeg', '.png']
    },

    // Schlüssel für sessionStorage
    speicher: {
      schnellcheck: 'ee_schnellcheck_v1',
      entwurf: 'ee_anfrage_entwurf_v1',
      vorgaenge: 'ee_vorgaenge_v1'
    }
  };

  /* ------------------------------------------------------------------
   * Stammdaten
   * ---------------------------------------------------------------- */
  var TECHNOLOGIEN = {
    wind: { label: 'Wind an Land', kurz: 'Wind' },
    pv_frei: { label: 'PV-Freifläche', kurz: 'PV-Freifläche' },
    agri_pv: { label: 'Agri-PV', kurz: 'Agri-PV' },
    pv_dach: { label: 'PV-Dach', kurz: 'PV-Dach' },
    speicher: { label: 'Speicher', kurz: 'Speicher' }
  };

  var LABELS = {
    genehmigung: {
      vorbereitung: 'In Vorbereitung',
      beantragt: 'Beantragt',
      erteilt: 'Erteilt',
      bestandskraeftig: 'Bestandskräftig'
    },
    netzanschluss: {
      offen: 'Offen',
      angefragt: 'Angefragt',
      zusage: 'Zusage liegt vor'
    },
    flaechen: {
      nein: 'Nein',
      teilweise: 'Teilweise',
      vollstaendig: 'Vollständig'
    },
    erloesmodell: {
      eeg: 'EEG-Zuschlag',
      ppa: 'PPA',
      eeg_ppa: 'EEG + PPA',
      merchant: 'Merchant'
    },
    rolle: {
      projektierer: 'Projektierer',
      betreiber: 'Betreiber',
      buergerenergie: 'Bürgerenergiegesellschaft',
      landwirt: 'Landwirt / Flächeneigentümer',
      stadtwerk: 'Stadtwerk',
      sonstige: 'Sonstige'
    }
  };

  var BUNDESLAENDER = [
    'Baden-Württemberg', 'Bayern', 'Berlin', 'Brandenburg', 'Bremen', 'Hamburg',
    'Hessen', 'Mecklenburg-Vorpommern', 'Niedersachsen', 'Nordrhein-Westfalen',
    'Rheinland-Pfalz', 'Saarland', 'Sachsen', 'Sachsen-Anhalt',
    'Schleswig-Holstein', 'Thüringen'
  ];

  /* ------------------------------------------------------------------
   * Zahlen parsen und formatieren
   * ---------------------------------------------------------------- */

  /**
   * Robustes Parsen deutscher und englischer Zahleneingaben.
   * "4,2" -> 4.2 · "4.2" -> 4.2 · "34.800" -> 34800 · "1.234,5" -> 1234.5
   * Gibt null zurück, wenn keine Zahl erkennbar ist.
   */
  function parseZahl(wert) {
    if (wert === null || wert === undefined) return null;
    if (typeof wert === 'number') return isFinite(wert) ? wert : null;
    var s = String(wert).trim().replace(/[\s  €%]/g, '').replace(/^\+/, '');
    if (s === '') return null;

    var hatPunkt = s.indexOf('.') !== -1;
    var hatKomma = s.indexOf(',') !== -1;

    if (hatPunkt && hatKomma) {
      // Das zuletzt stehende Zeichen ist das Dezimaltrennzeichen.
      if (s.lastIndexOf(',') > s.lastIndexOf('.')) {
        s = s.replace(/\./g, '').replace(',', '.');
      } else {
        s = s.replace(/,/g, '');
      }
    } else if (hatKomma) {
      // Mehrere Kommas = Tausendertrenner (selten), sonst Dezimalkomma.
      if ((s.match(/,/g) || []).length > 1) s = s.replace(/,/g, '');
      else s = s.replace(',', '.');
    } else if (hatPunkt) {
      // "34.800" oder "1.234.567" = deutsche Tausenderpunkte;
      // "4.2" oder "0.800" = Dezimalpunkt.
      if (/^-?[1-9]\d{0,2}(\.\d{3})+$/.test(s)) s = s.replace(/\./g, '');
    }

    if (!/^-?\d*\.?\d+$/.test(s)) return null;
    var n = Number(s);
    return isFinite(n) ? n : null;
  }

  function fmtZahl(n, nachkomma) {
    if (n === null || n === undefined || !isFinite(n)) return '–';
    var d = nachkomma === undefined ? 0 : nachkomma;
    return n.toLocaleString('de-DE', { minimumFractionDigits: d, maximumFractionDigits: d });
  }

  function fmtTEUR(n) {
    return isFinite(n) && n !== null ? fmtZahl(n, 0) + ' T€' : '–';
  }

  function fmtDSCR(n) {
    return isFinite(n) && n !== null ? fmtZahl(n, 2) + 'x' : '–';
  }

  function fmtProzent(n, nachkomma) {
    return isFinite(n) && n !== null ? fmtZahl(n, nachkomma === undefined ? 1 : nachkomma) + ' %' : '–';
  }

  /* ------------------------------------------------------------------
   * Rechenlogik
   * ---------------------------------------------------------------- */

  /** Annuitätenfaktor = r / (1 − (1 + r)^−n); r als Dezimalzahl (0,042). */
  function annuitaetenfaktor(r, n) {
    if (!(n > 0)) return null;
    if (!r) return 1 / n;
    return r / (1 - Math.pow(1 + r, -n));
  }

  function istZahl(n) {
    return typeof n === 'number' && isFinite(n);
  }

  /**
   * Hauptberechnung.
   * @param {object} e Eingaben (bereits geparste Zahlen):
   *   technologie, leistungMW, p50h, p90h, preisEURMWh, speicherTEURMW,
   *   capexTEUR, opexTEUR (null = Pauschale), fkQuoteProzent, zinsProzent, laufzeitJahre
   * @returns {object} Ergebnisse in T€ bzw. als Verhältniszahl
   */
  function berechne(e) {
    var tech = e.technologie;
    var mw = e.leistungMW;
    var istSpeicher = tech === 'speicher';
    var fk = istZahl(e.fkQuoteProzent) ? e.fkQuoteProzent : CONFIG.fkQuoteProzent;
    var zins = istZahl(e.zinsProzent) ? e.zinsProzent : CONFIG.zinsProzent;
    var laufzeit = istZahl(e.laufzeitJahre) ? e.laufzeitJahre : CONFIG.laufzeitJahre;

    var r = {
      istSpeicher: istSpeicher,
      fkQuoteProzent: fk,
      zinsProzent: zins,
      laufzeitJahre: laufzeit,
      umsatzP50: null,
      umsatzP90: null,
      opex: null,
      opexPauschal: false,
      opexPauschaleJeMW: CONFIG.opexPauschale[tech] || null,
      cfadsP50: null,
      cfadsP90: null,
      kredit: null,
      eigenkapital: null,
      faktor: annuitaetenfaktor(zins / 100, laufzeit),
      annuitaet: null,
      dscrP50: null,
      dscrP90: null,
      tragfaehigerKredit: null,
      capexJeMW: null
    };

    // Umsatz in T€
    if (istZahl(mw) && mw > 0) {
      if (istSpeicher) {
        if (istZahl(e.speicherTEURMW)) r.umsatzP50 = mw * e.speicherTEURMW;
        // Für Speicher gibt es keine P90-Ertragsbetrachtung.
      } else if (istZahl(e.preisEURMWh)) {
        if (istZahl(e.p50h)) r.umsatzP50 = mw * e.p50h * e.preisEURMWh / 1000;
        if (istZahl(e.p90h)) r.umsatzP90 = mw * e.p90h * e.preisEURMWh / 1000;
      }
    }

    // Betriebskosten: Angabe oder Pauschale je MW
    if (istZahl(e.opexTEUR)) {
      r.opex = e.opexTEUR;
    } else if (istZahl(mw) && r.opexPauschaleJeMW !== null) {
      r.opex = mw * r.opexPauschaleJeMW;
      r.opexPauschal = true;
    }

    if (r.umsatzP50 !== null && r.opex !== null) r.cfadsP50 = r.umsatzP50 - r.opex;
    if (r.umsatzP90 !== null && r.opex !== null) r.cfadsP90 = r.umsatzP90 - r.opex;

    if (istZahl(e.capexTEUR)) {
      r.kredit = e.capexTEUR * fk / 100;
      r.eigenkapital = e.capexTEUR - r.kredit;
      if (istZahl(mw) && mw > 0) r.capexJeMW = e.capexTEUR / mw;
    }

    if (r.kredit !== null && r.faktor) r.annuitaet = r.kredit * r.faktor;

    if (r.cfadsP50 !== null && r.annuitaet > 0) r.dscrP50 = r.cfadsP50 / r.annuitaet;
    if (r.cfadsP90 !== null && r.annuitaet > 0) r.dscrP90 = r.cfadsP90 / r.annuitaet;

    if (r.cfadsP50 !== null && r.faktor) {
      r.tragfaehigerKredit = Math.max(0, r.cfadsP50 / CONFIG.minDscrP50 / r.faktor);
    }

    return r;
  }

  /** Ampel: ok (≥ Mindestwert), warn (bis Toleranz darunter), fail (darunter). */
  function ampel(dscr, minWert) {
    if (!istZahl(dscr)) return null;
    if (dscr >= minWert) return 'ok';
    if (dscr >= minWert - CONFIG.toleranzKnapp - 1e-9) return 'warn';
    return 'fail';
  }

  var AMPEL_TEXT = { ok: 'erfüllt', warn: 'knapp', fail: 'unter Mindestwert' };

  function genehmigungErteilt(g) {
    return g === 'erteilt' || g === 'bestandskraeftig';
  }

  /** Urteil im Schnell-Check auf Basis DSCR P50 und Genehmigungsstand. */
  function urteil(ergebnis, genehmigung) {
    var d = ergebnis.dscrP50;
    var min = CONFIG.minDscrP50;
    if (!istZahl(d)) return null;
    if (d >= min) {
      if (genehmigungErteilt(genehmigung)) {
        return {
          stufe: 'ok',
          titel: 'Gut finanzierbar',
          text: 'Der Kapitaldienst ist aus den erwarteten Erlösen gut gedeckt und die Genehmigung liegt vor. Mit vollständigen Unterlagen kann die Prüfung zügig starten.'
        };
      }
      return {
        stufe: 'info',
        titel: 'Tragfähig, Projekt in Entwicklung',
        text: 'Die Zahlen tragen den Kreditwunsch. Für eine Kreditentscheidung brauchen wir die erteilte Genehmigung – wir begleiten Ihr Projekt gern schon in der Entwicklung.'
      };
    }
    if (d >= min - CONFIG.urteilKnappBand - 1e-9) {
      return {
        stufe: 'warn',
        titel: 'Knapp – Struktur anpassen',
        text: 'Der Schuldendienstdeckungsgrad liegt knapp unter unserem Mindestwert. Mehr Eigenkapital, eine längere Laufzeit oder ein Förderkredit können das Projekt finanzierbar machen.'
      };
    }
    return {
      stufe: 'fail',
      titel: 'Kreditwunsch zu hoch',
      text: 'Die erwarteten Erlöse reichen für diesen Kreditbetrag nicht aus. Orientieren Sie sich am tragfähigen Kreditvolumen oder prüfen Sie Erlöse und Kosten erneut.'
    };
  }

  /** Projektreife aus Genehmigung, Netzanschluss und Flächensicherung. */
  function projektreife(d, istWind) {
    var offen = [];
    var gesichert = 0;
    var genLabel = istWind ? 'BImSchG-Genehmigung' : 'Baurecht / Genehmigung';

    if (genehmigungErteilt(d.genehmigung)) {
      gesichert++;
      if (d.genehmigung === 'erteilt') offen.push(genLabel + ': Bestandskraft steht noch aus');
    } else {
      offen.push(genLabel + ': ' + (LABELS.genehmigung[d.genehmigung] || 'keine Angabe'));
    }
    if (d.netzanschluss === 'zusage') gesichert++;
    else offen.push('Netzanschluss: ' + (LABELS.netzanschluss[d.netzanschluss] || 'keine Angabe'));
    if (d.flaechen === 'vollstaendig') gesichert++;
    else offen.push('Flächensicherung: ' + (LABELS.flaechen[d.flaechen] || 'keine Angabe'));

    var stufe = gesichert === 3 ? 'baureif' : gesichert === 2 ? 'fast' : 'entwicklung';
    var titel = { baureif: 'Baureif', fast: 'Fast baureif', entwicklung: 'In Entwicklung' }[stufe];
    return { stufe: stufe, titel: titel, gesichert: gesichert, offen: offen };
  }

  /* ------------------------------------------------------------------
   * sessionStorage – jeder Zugriff abgesichert
   * ---------------------------------------------------------------- */
  var Store = {
    lesen: function (schluessel) {
      try {
        var roh = global.sessionStorage && global.sessionStorage.getItem(schluessel);
        return roh ? JSON.parse(roh) : null;
      } catch (err) {
        return null;
      }
    },
    schreiben: function (schluessel, wert) {
      try {
        global.sessionStorage.setItem(schluessel, JSON.stringify(wert));
        return true;
      } catch (err) {
        return false;
      }
    },
    entfernen: function (schluessel) {
      try {
        global.sessionStorage.removeItem(schluessel);
      } catch (err) { /* ignorieren */ }
    }
  };

  /* ------------------------------------------------------------------
   * Hilfsfunktionen für Formulare
   * ---------------------------------------------------------------- */

  /** Liest alle benannten Felder eines Formulars als einfache Werte (ohne Dateien). */
  function formularLesen(form) {
    var daten = {};
    Array.prototype.forEach.call(form.elements, function (el) {
      if (!el.name || el.type === 'file' || el.type === 'submit' || el.type === 'button') return;
      if (el.type === 'radio') {
        if (el.checked) daten[el.name] = el.value;
        else if (!(el.name in daten)) daten[el.name] = '';
      } else if (el.type === 'checkbox') {
        daten[el.name] = el.checked;
      } else {
        daten[el.name] = el.value.trim();
      }
    });
    return daten;
  }

  /** Schreibt Werte in gleichnamige Formularfelder. Gibt die Anzahl gesetzter Felder zurück. */
  function formularBefuellen(form, daten) {
    var gesetzt = 0;
    if (!daten) return gesetzt;
    Object.keys(daten).forEach(function (name) {
      var wert = daten[name];
      var felder = form.querySelectorAll('[name="' + name + '"]');
      Array.prototype.forEach.call(felder, function (el) {
        if (el.type === 'file') return;
        if (el.type === 'radio') {
          el.checked = el.value === wert;
          if (el.checked) gesetzt++;
        } else if (el.type === 'checkbox') {
          el.checked = !!wert;
        } else if (wert !== '' && wert !== null && wert !== undefined) {
          el.value = wert;
          gesetzt++;
        }
      });
    });
    return gesetzt;
  }

  /** Wandelt Formularwerte (Strings) in Eingaben für berechne() um. */
  function eingabenAusDaten(d, vorgaben) {
    vorgaben = vorgaben || {};
    var zins = parseZahl(d.zins);
    var laufzeit = parseZahl(d.laufzeit);
    var fk = parseZahl(d.fk_quote);
    return {
      technologie: d.technologie,
      leistungMW: parseZahl(d.leistung_mw),
      p50h: parseZahl(d.p50_h),
      p90h: parseZahl(d.p90_h),
      preisEURMWh: parseZahl(d.preis_eur_mwh),
      speicherTEURMW: parseZahl(d.speicher_erloes),
      capexTEUR: parseZahl(d.capex_teur),
      opexTEUR: parseZahl(d.opex_teur),
      fkQuoteProzent: fk !== null ? fk : vorgaben.fkQuoteProzent,
      zinsProzent: zins !== null ? zins : vorgaben.zinsProzent,
      laufzeitJahre: laufzeit !== null ? laufzeit : vorgaben.laufzeitJahre
    };
  }

  var EE = {
    CONFIG: CONFIG,
    TECHNOLOGIEN: TECHNOLOGIEN,
    LABELS: LABELS,
    BUNDESLAENDER: BUNDESLAENDER,
    parseZahl: parseZahl,
    fmtZahl: fmtZahl,
    fmtTEUR: fmtTEUR,
    fmtDSCR: fmtDSCR,
    fmtProzent: fmtProzent,
    annuitaetenfaktor: annuitaetenfaktor,
    berechne: berechne,
    ampel: ampel,
    AMPEL_TEXT: AMPEL_TEXT,
    urteil: urteil,
    projektreife: projektreife,
    genehmigungErteilt: genehmigungErteilt,
    Store: Store,
    formularLesen: formularLesen,
    formularBefuellen: formularBefuellen,
    eingabenAusDaten: eingabenAusDaten
  };

  if (typeof module !== 'undefined' && module.exports) module.exports = EE;
  global.EE = EE;
})(typeof window !== 'undefined' ? window : globalThis);
