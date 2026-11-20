/*
 * calc.js – Rechenkern und zentrale Konfiguration
 * Projektfinanzierung Erneuerbare Energien
 *
 * Alle Bankparameter stehen ausschließlich im CONFIG-Objekt.
 * Die Rechnung ist bewusst vereinfacht: ohne Steuern, Reserven
 * (DSRA/MRA) und Bauzeitzinsen. Degradation geht als Mittelwert über
 * die Kreditlaufzeit ein, Abregelung als pauschaler Abschlag.
 * Sie ersetzt keine Kreditprüfung und stellt keine Kreditzusage dar.
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

    /*
     * Standortgüte
     * ACHTUNG: Alle Werte in diesem Block sind PLATZHALTER. Sie sind
     * grobe Erfahrungswerte und müssen von der Kreditabteilung bzw. dem
     * Risikomanagement der Bank festgelegt werden.
     */
    standort: {
      wind: {
        // Korrekturfaktoren des EEG-Referenzertragsmodells (Gütefaktor in % -> Faktor).
        // Stützstellen nach § 36h EEG 2023 – vor Livegang mit der aktuellen Fassung abgleichen.
        // Zwischen den Stützstellen wird linear interpoliert, außerhalb gilt der Randwert.
        korrekturfaktoren: [
          [50, 1.55], [60, 1.42], [70, 1.29], [80, 1.16], [90, 1.07], [100, 1.00],
          [110, 0.94], [120, 0.89], [130, 0.85], [140, 0.81], [150, 0.79]
        ],
        // Der Korrekturfaktor wird nur bei diesen Erlösmodellen auf den Preis angewendet
        // (Eingabe = Zuschlagswert für den 100-%-Referenzstandort).
        korrekturFuerErloesmodell: ['eeg'],
        // Ampel Dargebot: Gütefaktor unter "rot" = fail, unter "gelb" = warn
        guetefaktorRot: 60,
        guetefaktorGelb: 70
      },

      // Plausible Volllaststunden P50 je Bundesland [min, max] (PLATZHALTER).
      // Wind: Neuanlagen an Land. PV: PV-Freifläche, fest aufgeständert, Süd (kWh/kWp = h).
      bandbreiten: {
        'Schleswig-Holstein':     { wind: [2200, 3400], pv: [880, 1030] },
        'Hamburg':                { wind: [2100, 3200], pv: [880, 1020] },
        'Bremen':                 { wind: [2100, 3200], pv: [880, 1020] },
        'Niedersachsen':          { wind: [2000, 3300], pv: [890, 1040] },
        'Mecklenburg-Vorpommern': { wind: [2100, 3300], pv: [920, 1080] },
        'Brandenburg':            { wind: [1900, 3000], pv: [940, 1100] },
        'Berlin':                 { wind: [1800, 2800], pv: [930, 1080] },
        'Sachsen-Anhalt':         { wind: [1900, 3000], pv: [930, 1090] },
        'Nordrhein-Westfalen':    { wind: [1800, 2900], pv: [870, 1020] },
        'Sachsen':                { wind: [1700, 2800], pv: [940, 1100] },
        'Thüringen':              { wind: [1700, 2800], pv: [930, 1090] },
        'Hessen':                 { wind: [1700, 2800], pv: [920, 1080] },
        'Rheinland-Pfalz':        { wind: [1700, 2800], pv: [930, 1100] },
        'Saarland':               { wind: [1700, 2700], pv: [940, 1100] },
        'Baden-Württemberg':      { wind: [1500, 2500], pv: [980, 1180] },
        'Bayern':                 { wind: [1500, 2600], pv: [980, 1200] }
      },
      // PV-Bandbreite je Bauform relativ zur Freifläche (PLATZHALTER)
      pvFaktor: { pv_frei: 1.0, agri_pv: 0.95, pv_dach: 0.9 },
      // Ab wie viel % über dem Höchstwert der Bandbreite die Ampel auf rot geht
      bandbreiteRotUeberProzent: 15,

      // Gutachtenlage: Abstand P90 zu P50 in % von P50 (PLATZHALTER)
      p90AbstandGelbProzent: 10,
      p90AbstandRotProzent: 15,
      // Anzahl unabhängiger Ertragsgutachten, die für "grün" verlangt werden
      gutachtenGruen: { wind: 'zwei', pv_frei: 'eines', agri_pv: 'eines', pv_dach: 'eines', speicher: 'eines' },

      // Netz (PLATZHALTER)
      kabelGelbKm: 10,
      kabelRotKm: 20,
      abregelungGelbProzent: 5,
      abregelungRotProzent: 10,
      // Regionale Erfahrungswerte für Abregelung in % (nur als Hinweis, nicht automatisch angesetzt)
      abregelungErfahrung: {
        'Schleswig-Holstein': 6, 'Niedersachsen': 4, 'Mecklenburg-Vorpommern': 4,
        'Hamburg': 3, 'Bremen': 3, 'Brandenburg': 3, 'Sachsen-Anhalt': 3,
        standard: 1.5
      },

      // Degradation in % pro Jahr, wenn nichts angegeben ist (PLATZHALTER)
      degradationStandard: { wind: 0, pv_frei: 0.4, agri_pv: 0.4, pv_dach: 0.5, speicher: 1.0 }
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
    spannungsebene: {
      ns: 'Niederspannung',
      ms: 'Mittelspannung',
      hs: 'Hochspannung / eigenes Umspannwerk'
    },
    gutachten: {
      keines: 'Noch keines',
      vorlaeufig: 'Vorläufige Prognose',
      eines: 'Ein Gutachten',
      zwei: 'Zwei unabhängige Gutachten'
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

    // Standortfaktoren auf den Umsatz
    // 1. Korrekturfaktor (nur Wind mit EEG-Zuschlag und angegebenem Gütefaktor)
    r.korrekturfaktor = 1;
    r.korrekturAngewendet = false;
    if (tech === 'wind' && istZahl(e.guetefaktorProzent) &&
        CONFIG.standort.wind.korrekturFuerErloesmodell.indexOf(e.erloesmodell) !== -1) {
      r.korrekturfaktor = korrekturfaktor(e.guetefaktorProzent);
      r.korrekturAngewendet = true;
    }
    r.preisWirksam = istZahl(e.preisEURMWh) ? e.preisEURMWh * r.korrekturfaktor : null;
    // 2. Abregelung (nur wenn angegeben)
    r.abregelungProzent = istZahl(e.abregelungProzent) ? e.abregelungProzent : 0;
    // 3. Degradation: Angabe oder Standardwert je Technologie, gemittelt über die Kreditlaufzeit
    var degStandard = CONFIG.standort.degradationStandard[tech];
    r.degradationProzent = istZahl(e.degradationProzent) ? e.degradationProzent : (istZahl(degStandard) ? degStandard : 0);
    r.degradationStandard = !istZahl(e.degradationProzent);
    r.degradationsfaktor = degradationsfaktor(r.degradationProzent, laufzeit);
    r.umsatzfaktor = (1 - r.abregelungProzent / 100) * r.degradationsfaktor;

    // Umsatz in T€
    if (istZahl(mw) && mw > 0) {
      if (istSpeicher) {
        if (istZahl(e.speicherTEURMW)) r.umsatzP50 = mw * e.speicherTEURMW * r.umsatzfaktor;
        // Für Speicher gibt es keine P90-Ertragsbetrachtung.
      } else if (r.preisWirksam !== null) {
        if (istZahl(e.p50h)) r.umsatzP50 = mw * e.p50h * r.preisWirksam / 1000 * r.umsatzfaktor;
        if (istZahl(e.p90h)) r.umsatzP90 = mw * e.p90h * r.preisWirksam / 1000 * r.umsatzfaktor;
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

  /** Korrekturfaktor zum Gütefaktor (lineare Interpolation zwischen den Stützstellen). */
  function korrekturfaktor(guete) {
    var st = CONFIG.standort.wind.korrekturfaktoren;
    if (!istZahl(guete)) return null;
    if (guete <= st[0][0]) return st[0][1];
    if (guete >= st[st.length - 1][0]) return st[st.length - 1][1];
    for (var i = 0; i < st.length - 1; i++) {
      var a = st[i], b = st[i + 1];
      if (guete <= b[0]) return a[1] + (b[1] - a[1]) * (guete - a[0]) / (b[0] - a[0]);
    }
    return 1;
  }

  /** Mittlerer Ertragsfaktor über n Jahre bei d % Degradation pro Jahr (Jahr 1 = 100 %). */
  function degradationsfaktor(dProzent, n) {
    var d = dProzent / 100;
    if (!(d > 0) || !(n > 0)) return 1;
    return (1 - Math.pow(1 - d, n)) / (n * d);
  }

  /* ------------------------------------------------------------------
   * Standortgüte: Plausibilität und Ampel
   * ---------------------------------------------------------------- */
  var STUFE_RANG = { ok: 1, warn: 2, fail: 3 };

  function schlechteste(stufen) {
    var erg = null;
    stufen.forEach(function (s) {
      if (s && (!erg || STUFE_RANG[s] > STUFE_RANG[erg])) erg = s;
    });
    return erg;
  }

  /** Übliche Bandbreite der Volllaststunden P50 für Technologie und Bundesland, oder null. */
  function bandbreite(tech, land) {
    var b = CONFIG.standort.bandbreiten[land];
    if (!b) return null;
    if (tech === 'wind') return b.wind.slice();
    var f = CONFIG.standort.pvFaktor[tech];
    if (f === undefined) return null;
    return [Math.round(b.pv[0] * f), Math.round(b.pv[1] * f)];
  }

  /** Prüft P50 gegen die übliche Bandbreite. stufe: ok | warn | fail | null (keine Prüfung möglich). */
  function plausibilitaet(tech, land, p50h) {
    var band = bandbreite(tech, land);
    if (!band || !istZahl(p50h)) return { stufe: null, band: band, text: '' };
    var spanne = fmtZahl(band[0]) + '–' + fmtZahl(band[1]) + ' h';
    var rotGrenze = band[1] * (1 + CONFIG.standort.bandbreiteRotUeberProzent / 100);
    if (p50h > rotGrenze) {
      return { stufe: 'fail', band: band, text: 'P50 von ' + fmtZahl(p50h) + ' h liegt deutlich über der üblichen Bandbreite für ' + land + ' (' + spanne + '). Bitte durch Ertragsgutachten belegen.' };
    }
    if (p50h > band[1]) {
      return { stufe: 'warn', band: band, text: 'P50 von ' + fmtZahl(p50h) + ' h liegt über der üblichen Bandbreite für ' + land + ' (' + spanne + '). Bitte durch Ertragsgutachten belegen.' };
    }
    if (p50h < band[0]) {
      return { stufe: 'warn', band: band, text: 'P50 von ' + fmtZahl(p50h) + ' h liegt unter der üblichen Bandbreite für ' + land + ' (' + spanne + '). Standort und Anlagenauslegung bitte prüfen.' };
    }
    return { stufe: 'ok', band: band, text: 'P50 liegt in der üblichen Bandbreite für ' + land + ' (' + spanne + ').' };
  }

  function punkt(stufe, text) { return { stufe: stufe, text: text }; }

  function bereich(punkte, leerText) {
    var bewertet = punkte.filter(function (p) { return p.stufe; });
    if (!bewertet.length) return { stufe: null, punkte: [punkt(null, leerText)] };
    return { stufe: schlechteste(bewertet.map(function (p) { return p.stufe; })), punkte: punkte };
  }

  /**
   * Standort-Ampel aus den Formulardaten (Strings) und dem Rechenergebnis.
   * Fehlende Angaben werden als "warn" gewertet, sobald im Bereich etwas angegeben ist.
   * @returns {{dargebot, gutachten, netz, gesamt}} je Bereich {stufe, punkte:[{stufe,text}]}
   */
  function standortBewertung(d, erg) {
    var S = CONFIG.standort;
    var tech = d.technologie;
    var land = d.bundesland;
    var p50 = parseZahl(d.p50_h);
    var p90 = parseZahl(d.p90_h);
    var fehlt = 'warn';

    // 1. Dargebot (Wind bzw. Sonne)
    var dargebot;
    if (tech === 'speicher') {
      dargebot = { stufe: null, entfaellt: true, punkte: [punkt(null, 'Bei Speichern entfällt die Bewertung von Wind bzw. Sonne.')] };
    } else {
      var pd = [];
      var hatAngaben = istZahl(p50) || (tech === 'wind' && istZahl(parseZahl(d.guetefaktor)));
      if (tech === 'wind') {
        var g = parseZahl(d.guetefaktor);
        if (istZahl(g)) {
          var kf = korrekturfaktor(g);
          var stufeG = g < S.wind.guetefaktorRot ? 'fail' : g < S.wind.guetefaktorGelb ? 'warn' : 'ok';
          pd.push(punkt(stufeG, 'Gütefaktor ' + fmtZahl(g) + ' % (Korrekturfaktor ' + fmtZahl(kf, 2) + ')' +
            (stufeG === 'ok' ? '' : ' – unter ' + (stufeG === 'fail' ? S.wind.guetefaktorRot : S.wind.guetefaktorGelb) + ' %')));
        } else if (hatAngaben) {
          pd.push(punkt(fehlt, 'Gütefaktor fehlt'));
        }
      }
      if (!land) {
        if (hatAngaben) pd.push(punkt(null, 'Bundesland fehlt – keine regionale Einordnung möglich'));
      } else if (istZahl(p50)) {
        var pl = plausibilitaet(tech, land, p50);
        if (pl.stufe) pd.push(punkt(pl.stufe, pl.text));
      }
      dargebot = bereich(pd, 'Noch keine Angaben zum Ertrag');
    }

    // 2. Gutachtenlage
    var pg = [];
    var gs = d.gutachten;
    var verlangt = S.gutachtenGruen[tech] || 'eines';
    var gName = tech === 'speicher' ? 'Erlösgutachten' : 'Ertragsgutachten';
    if (gs) {
      var stufeGs;
      if (gs === 'keines') stufeGs = 'fail';
      else if (gs === 'vorlaeufig') stufeGs = 'warn';
      else if (gs === 'eines') stufeGs = verlangt === 'zwei' ? 'warn' : 'ok';
      else stufeGs = 'ok';
      pg.push(punkt(stufeGs, gName + ': ' + LABELS.gutachten[gs] +
        (gs === 'eines' && verlangt === 'zwei' ? ' – für Wind verlangen wir zwei unabhängige' : '')));
    }
    if (tech !== 'speicher' && istZahl(p50) && p50 > 0) {
      if (istZahl(p90)) {
        var abstand = (1 - p90 / p50) * 100;
        var stufeP = abstand > S.p90AbstandRotProzent ? 'fail' : abstand > S.p90AbstandGelbProzent ? 'warn' : 'ok';
        pg.push(punkt(stufeP, 'P90 liegt ' + fmtZahl(abstand, 1) + ' % unter P50' +
          (stufeP === 'ok' ? '' : ' – hohe Unsicherheit der Prognose')));
      } else {
        pg.push(punkt(fehlt, 'P90 fehlt – Unsicherheit der Prognose unbekannt'));
      }
    }
    if (!gs && pg.length) pg.unshift(punkt(fehlt, 'Stand des ' + gName + 's fehlt'));
    var gutachten = bereich(pg, 'Noch keine Angaben zum Gutachten');

    // 3. Netz
    var pn = [];
    var mw = parseZahl(d.leistung_mw);
    if (d.netzanschluss) {
      var stufeN = { zusage: 'ok', angefragt: 'warn', offen: 'fail' }[d.netzanschluss];
      pn.push(punkt(stufeN, 'Netzanschluss: ' + LABELS.netzanschluss[d.netzanschluss]));
    }
    if (d.spannungsebene === 'hs') {
      pn.push(punkt('warn', 'Eigenes Umspannwerk: Kosten und Zeitplan prüfen'));
    } else if (d.spannungsebene === 'ns' && istZahl(mw) && mw > 1) {
      pn.push(punkt('warn', 'Niederspannung ist für ' + fmtZahl(mw, mw % 1 ? 1 : 0) + ' MW ungewöhnlich'));
    } else if (d.spannungsebene) {
      pn.push(punkt('ok', 'Anschluss in ' + LABELS.spannungsebene[d.spannungsebene]));
    }
    var km = parseZahl(d.kabel_km);
    var hatNetz = pn.length > 0 || istZahl(km);
    if (istZahl(km)) {
      var stufeK = km > S.kabelRotKm ? 'fail' : km > S.kabelGelbKm ? 'warn' : 'ok';
      pn.push(punkt(stufeK, 'Kabeltrasse ' + fmtZahl(km, km % 1 ? 1 : 0) + ' km' + (stufeK === 'ok' ? '' : ' – Kosten und Trassensicherung prüfen')));
    } else if (hatNetz) {
      pn.push(punkt(fehlt, 'Länge der Kabeltrasse fehlt'));
    }
    var abr = parseZahl(d.abregelung_prozent);
    if (istZahl(abr)) {
      var stufeA = abr >= S.abregelungRotProzent ? 'fail' : abr >= S.abregelungGelbProzent ? 'warn' : 'ok';
      pn.push(punkt(stufeA, 'Erwartete Abregelung ' + fmtZahl(abr, abr % 1 ? 1 : 0) + ' %'));
    } else if (hatNetz) {
      pn.push(punkt(fehlt, 'Erwartete Abregelung fehlt (Erfahrungswert ' + (land || 'Region') + ': ' +
        fmtZahl(abregelungErfahrung(land), 1) + ' %)'));
    }
    var netz = bereich(pn, 'Noch keine Angaben zum Netz');

    return {
      dargebot: dargebot,
      gutachten: gutachten,
      netz: netz,
      gesamt: schlechteste([dargebot.stufe, gutachten.stufe, netz.stufe])
    };
  }

  /** Regionaler Erfahrungswert für Abregelung in % (Platzhalter). */
  function abregelungErfahrung(land) {
    var t = CONFIG.standort.abregelungErfahrung;
    return istZahl(t[land]) ? t[land] : t.standard;
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
      erloesmodell: d.erloesmodell,
      guetefaktorProzent: parseZahl(d.guetefaktor),
      abregelungProzent: parseZahl(d.abregelung_prozent),
      degradationProzent: parseZahl(d.degradation_prozent),
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
    korrekturfaktor: korrekturfaktor,
    degradationsfaktor: degradationsfaktor,
    bandbreite: bandbreite,
    plausibilitaet: plausibilitaet,
    standortBewertung: standortBewertung,
    abregelungErfahrung: abregelungErfahrung,
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
