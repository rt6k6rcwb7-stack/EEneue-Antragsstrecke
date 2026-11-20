/*
 * schnellcheck.js – Schnell-Check auf der Landingpage
 * Tabs (WAI-ARIA), Vollständigkeit, Sofort-Indikation, Übergabe an die Anfrage.
 */
(function () {
  'use strict';

  var EE = window.EE;
  var CONFIG = EE.CONFIG;
  var form = document.getElementById('schnellcheck');
  if (!form) return;

  var el = {
    ergebnis: document.getElementById('sc-ergebnis'),
    annahmen: document.getElementById('sc-annahmen'),
    vollstWert: document.getElementById('sc-vollst-wert'),
    vollstBalken: document.getElementById('sc-vollst-balken'),
    vollstFuellung: document.getElementById('sc-vollst-fuellung'),
    vollstText: document.getElementById('sc-vollst-text'),
    p50Feld: document.getElementById('sc-p50-feld'),
    preisFeld: document.getElementById('sc-preis-feld'),
    speicherFeld: document.getElementById('sc-speicher-feld'),
    erloesmodellFeld: document.getElementById('sc-erloesmodell-feld'),
    gueteFeld: document.getElementById('sc-guete-feld'),
    gueteHinweis: document.getElementById('sc-guete-hinweis'),
    opex: document.getElementById('sc-opex'),
    opexHinweis: document.getElementById('sc-opex-hinweis'),
    genLabel: form.querySelector('[data-genehmigung-label]')
  };

  /* ---------------- Bundesländer befüllen ---------------- */
  document.querySelectorAll('select[data-bundeslaender]').forEach(function (sel) {
    EE.BUNDESLAENDER.forEach(function (land) {
      var opt = document.createElement('option');
      opt.value = land;
      opt.textContent = land;
      sel.appendChild(opt);
    });
  });

  /* ---------------- Tabs nach WAI-ARIA-Muster ---------------- */
  var tabs = Array.prototype.slice.call(form.querySelectorAll('[role="tab"]'));

  function aktiviereTab(tab, fokus) {
    tabs.forEach(function (t) {
      var aktiv = t === tab;
      t.setAttribute('aria-selected', aktiv ? 'true' : 'false');
      t.tabIndex = aktiv ? 0 : -1;
      document.getElementById(t.getAttribute('aria-controls')).hidden = !aktiv;
    });
    if (fokus) tab.focus();
  }

  tabs.forEach(function (tab, i) {
    tab.addEventListener('click', function () { aktiviereTab(tab, false); });
    tab.addEventListener('keydown', function (ev) {
      var ziel = null;
      if (ev.key === 'ArrowRight') ziel = tabs[(i + 1) % tabs.length];
      else if (ev.key === 'ArrowLeft') ziel = tabs[(i - 1 + tabs.length) % tabs.length];
      else if (ev.key === 'Home') ziel = tabs[0];
      else if (ev.key === 'End') ziel = tabs[tabs.length - 1];
      if (ziel) {
        ev.preventDefault();
        aktiviereTab(ziel, true);
      }
    });
  });

  form.querySelectorAll('[data-weiter]').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var tab = document.getElementById(btn.getAttribute('data-weiter'));
      aktiviereTab(tab, false);
      var panel = document.getElementById(tab.getAttribute('aria-controls'));
      var erstes = panel.querySelector('input:not([type="hidden"]), select');
      (erstes || panel).focus();
    });
  });

  /* ---------------- Logik ---------------- */
  function hatWert(v) {
    return v !== undefined && v !== null && String(v).trim() !== '';
  }

  function zahlOk(v) {
    var n = EE.parseZahl(v);
    return n !== null && n > 0;
  }

  /** Liefert relevante Felder je nach Technologie. */
  function felder(d) {
    var speicher = d.technologie === 'speicher';
    var alle = [
      { name: 'technologie', label: 'Technologie', pflicht: true, ok: hatWert(d.technologie) },
      { name: 'leistung_mw', label: 'Leistung', pflicht: true, ok: zahlOk(d.leistung_mw) },
      { name: 'bundesland', label: 'Bundesland', ok: hatWert(d.bundesland) },
      { name: 'inbetriebnahme', label: 'Inbetriebnahme', ok: hatWert(d.inbetriebnahme) },
      { name: 'rolle', label: 'Rolle', ok: hatWert(d.rolle) },
      { name: 'genehmigung', label: 'Genehmigung', ok: hatWert(d.genehmigung) },
      { name: 'netzanschluss', label: 'Netzanschluss', ok: hatWert(d.netzanschluss) },
      { name: 'flaechen', label: 'Flächen', ok: hatWert(d.flaechen) }
    ];
    if (speicher) {
      alle.push({ name: 'speicher_erloes', label: 'Erlöserwartung', pflicht: true, ok: zahlOk(d.speicher_erloes) });
    } else {
      alle.push({ name: 'erloesmodell', label: 'Erlösmodell', ok: hatWert(d.erloesmodell) });
      alle.push({ name: 'p50_h', label: 'Volllaststunden P50', pflicht: true, ok: zahlOk(d.p50_h) });
      if (d.technologie === 'wind') alle.push({ name: 'guetefaktor', label: 'Gütefaktor', ok: zahlOk(d.guetefaktor) });
      alle.push({ name: 'preis_eur_mwh', label: 'Erlös in €/MWh', pflicht: true, ok: zahlOk(d.preis_eur_mwh) });
    }
    alle.push({ name: 'capex_teur', label: 'Gesamtinvestition', pflicht: true, ok: zahlOk(d.capex_teur) });
    alle.push({ name: 'opex_teur', label: 'Betriebskosten', ok: zahlOk(d.opex_teur) });
    alle.push({ name: 'fk_quote', label: 'Fremdkapitalquote', ok: zahlOk(d.fk_quote) });
    return alle;
  }

  function aufzaehlung(liste) {
    if (liste.length <= 1) return liste.join('');
    return liste.slice(0, -1).join(', ') + ' und ' + liste[liste.length - 1];
  }

  function aktualisiereFelder(d) {
    var speicher = d.technologie === 'speicher';
    el.p50Feld.hidden = speicher;
    el.preisFeld.hidden = speicher;
    el.speicherFeld.hidden = !speicher;
    el.erloesmodellFeld.hidden = speicher;
    el.gueteFeld.hidden = d.technologie !== 'wind';
    var guete = EE.parseZahl(d.guetefaktor);
    var kfGilt = CONFIG.standort.wind.korrekturFuerErloesmodell.indexOf(d.erloesmodell) !== -1;
    if (guete !== null && guete > 0) {
      el.gueteHinweis.textContent = 'Korrekturfaktor ' + EE.fmtZahl(EE.korrekturfaktor(guete), 2) +
        (kfGilt ? ' – wird auf Ihren Zuschlagswert angewendet.' : ' – wirkt nur beim Erlösmodell EEG-Zuschlag.');
    } else {
      el.gueteHinweis.textContent = 'Standortgüte laut Ertragsgutachten (EEG-Referenzertragsmodell). Beim EEG-Zuschlag rechnen wir mit dem passenden Korrekturfaktor.';
    }
    el.genLabel.textContent = d.technologie === 'wind' ? 'Genehmigung nach BImSchG' : 'Baurecht / Genehmigung';

    // Platzhalter der Betriebskosten zeigt die angenommene Pauschale
    var pauschaleJeMW = CONFIG.opexPauschale[d.technologie];
    var mw = EE.parseZahl(d.leistung_mw);
    if (pauschaleJeMW) {
      if (mw > 0) {
        el.opex.placeholder = 'Pauschale: ' + EE.fmtZahl(mw * pauschaleJeMW) + ' T€/a';
      } else {
        el.opex.placeholder = 'Pauschale: ' + pauschaleJeMW + ' T€/MW';
      }
      el.opexHinweis.textContent = 'Leer lassen: Wir setzen ' + pauschaleJeMW + ' T€ je MW und Jahr an (' + EE.TECHNOLOGIEN[d.technologie].label + ').';
    } else {
      el.opex.placeholder = 'Pauschale';
      el.opexHinweis.textContent = 'Leer lassen: Wir setzen eine Pauschale je MW an.';
    }
  }

  function aktualisiereVollstaendigkeit(liste) {
    var erfuellt = liste.filter(function (f) { return f.ok; }).length;
    var prozent = Math.round(erfuellt / liste.length * 100);
    el.vollstWert.textContent = prozent + ' %';
    el.vollstFuellung.style.width = prozent + '%';
    el.vollstBalken.setAttribute('aria-valuenow', String(prozent));
    el.vollstBalken.setAttribute('aria-valuetext', prozent + ' Prozent');

    var text;
    if (prozent === 100) text = 'Vollständig – beste Grundlage für eine schnelle Vorprüfung.';
    else if (prozent >= 70) text = 'Fast geschafft – noch ' + (liste.length - erfuellt) + ' Angaben für ein vollständiges Bild.';
    else text = 'Je mehr Sie angeben, desto genauer wird die Indikation.';
    el.vollstText.textContent = text;
  }

  function renderErgebnis(d, liste) {
    var fehlend = liste.filter(function (f) { return f.pflicht && !f.ok; });
    // Im Schnell-Check gelten Zins und Laufzeit aus CONFIG; FK-Quote aus der Eingabe (sonst Standard).
    var erg = EE.berechne(EE.eingabenAusDaten(d, {
      zinsProzent: CONFIG.zinsProzent,
      laufzeitJahre: CONFIG.laufzeitJahre,
      fkQuoteProzent: CONFIG.fkQuoteProzent
    }));

    if (fehlend.length) {
      var n = fehlend.length;
      el.ergebnis.innerHTML =
        '<p class="ergebnis__leer"><svg class="icon" aria-hidden="true"><use href="#i-info"/></svg>' +
        '<span>Noch ' + n + (n === 1 ? ' Angabe' : ' Angaben') + ' bis zur Indikation: ' +
        aufzaehlung(fehlend.map(function (f) { return f.label; })) + '.</span></p>';
    } else {
      var u = EE.urteil(erg, d.genehmigung);
      el.ergebnis.innerHTML =
        '<dl class="kennzahlen">' +
          '<div class="kennzahl"><dt>Kreditwunsch</dt><dd>' + EE.fmtTEUR(erg.kredit) + '</dd></div>' +
          '<div class="kennzahl"><dt>Tragfähig bis ca.</dt><dd>' + EE.fmtTEUR(erg.tragfaehigerKredit) + '</dd></div>' +
          '<div class="kennzahl"><dt>DSCR P50</dt><dd>' + EE.fmtDSCR(erg.dscrP50) + '</dd></div>' +
        '</dl>' +
        (u ? '<div class="urteil"><span><span class="badge badge--' + u.stufe + '">' + u.titel + '</span></span><p>' + u.text + '</p></div>' : '') +
        plausibilitaetsHinweis(d);
    }

    el.annahmen.textContent =
      'Annahmen: Zins ' + EE.fmtProzent(CONFIG.zinsProzent, 1) + ' p. a., Laufzeit ' + CONFIG.laufzeitJahre +
      ' Jahre, Annuitätendarlehen, Mindest-DSCR P50 ' + EE.fmtDSCR(CONFIG.minDscrP50) + '. ' +
      (erg.opexPauschal
        ? 'Betriebskosten pauschal mit ' + erg.opexPauschaleJeMW + ' T€ je MW und Jahr angesetzt. '
        : (EE.parseZahl(d.opex_teur) !== null ? 'Betriebskosten nach Ihrer Angabe. ' : 'Betriebskosten pauschal je MW. ')) +
      (erg.korrekturAngewendet ? 'Zuschlagswert mit Korrekturfaktor ' + EE.fmtZahl(erg.korrekturfaktor, 2) + ' angesetzt. ' : '') +
      (erg.degradationProzent > 0 ? 'Degradation ' + EE.fmtZahl(erg.degradationProzent, 1) + ' % p. a., gemittelt über die Laufzeit. ' : '') +
      'Vereinfachte Rechnung ohne Steuern, Reserven und Bauzeitzinsen. Keine Kreditzusage.';
  }

  /** Hinweis, wenn P50 nicht zur üblichen Bandbreite des Bundeslands passt. */
  function plausibilitaetsHinweis(d) {
    if (d.technologie === 'speicher') return '';
    var pl = EE.plausibilitaet(d.technologie, d.bundesland, EE.parseZahl(d.p50_h));
    if (pl.stufe !== 'warn' && pl.stufe !== 'fail') return '';
    return '<p class="ergebnis__hinweis"><svg class="icon icon--klein" aria-hidden="true"><use href="#i-warn"/></svg>' +
      '<span>' + pl.text + '</span></p>';
  }

  var timer = null;
  function aktualisieren(sofort) {
    var d = EE.formularLesen(form);
    var liste = felder(d);
    aktualisiereFelder(d);
    aktualisiereVollstaendigkeit(liste);
    // Ergebnis (aria-live) leicht verzögert, damit Screenreader nicht bei jedem Tastendruck ansagen.
    clearTimeout(timer);
    if (sofort) renderErgebnis(d, liste);
    else timer = setTimeout(function () { renderErgebnis(d, liste); }, 350);
  }

  form.addEventListener('input', function () { aktualisieren(false); });
  form.addEventListener('change', function () { aktualisieren(false); });
  form.addEventListener('submit', function (ev) { ev.preventDefault(); });

  /* ---------------- Übergabe an die vollständige Anfrage ---------------- */
  function speichern() {
    var d = EE.formularLesen(form);
    d._quelle = 'schnellcheck';
    d._zeit = new Date().toISOString();
    EE.Store.schreiben(CONFIG.speicher.schnellcheck, d);
  }
  document.querySelectorAll('a[data-uebernahme]').forEach(function (link) {
    link.addEventListener('click', speichern);
  });

  /* ---------------- Start: frühere Eingaben wiederherstellen ---------------- */
  var gespeichert = EE.Store.lesen(CONFIG.speicher.schnellcheck);
  if (gespeichert) EE.formularBefuellen(form, gespeichert);
  aktualisieren(true);
})();
