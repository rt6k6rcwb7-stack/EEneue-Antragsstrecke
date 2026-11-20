/*
 * anfrage.js – Vollständige Anfrage in sechs Schritten
 * Vorbefüllung aus dem Schnell-Check, Validierung je Schritt, Live-Indikation,
 * Uploads, Entwurf, Einreichen per FormData.
 */
(function () {
  'use strict';

  var EE = window.EE;
  var CONFIG = EE.CONFIG;
  var LABELS = EE.LABELS;

  var form = document.getElementById('formular');
  if (!form) return;

  var ANZAHL = 6;
  var aktuell = 1;
  var besucht = { 1: true };
  var dateien = {};            // id -> File (nur im Speicher dieser Seite)
  var dateinamenEntwurf = {};  // id -> Dateiname aus einem gespeicherten Entwurf

  var $ = function (id) { return document.getElementById(id); };
  var schritte = Array.prototype.slice.call(form.querySelectorAll('.schritt'));
  var navButtons = Array.prototype.slice.call(document.querySelectorAll('#schrittnav button'));
  var btnZurueck = $('btn-zurueck');
  var btnWeiter = $('btn-weiter');
  var btnEntwurf = $('btn-entwurf');
  var statusMeldung = $('status-meldung');

  /* ------------------------------------------------------------------
   * Unterlagen (technologieabhängig benannt)
   * ---------------------------------------------------------------- */
  var DOKUMENTE = [
    {
      id: 'ertragsgutachten',
      titel: function (d) {
        if (d.technologie === 'wind') return 'Zwei unabhängige Ertragsgutachten';
        if (d.technologie === 'speicher') return 'Erlös- bzw. Vermarktungsgutachten';
        return 'Ertragsgutachten (PV-Ertragsprognose)';
      },
      hinweis: function (d) {
        if (d.technologie === 'wind') return 'Mit P50 und P90, von zwei unabhängigen Gutachtern – gern zusammen als ZIP.';
        if (d.technologie === 'speicher') return 'Erlösprognose für Arbitrage, Regelenergie und ggf. Tolling.';
        return 'Mit P50- und P90-Werten und Annahmen zur Degradation.';
      }
    },
    {
      id: 'genehmigung',
      titel: function (d) { return d.technologie === 'wind' ? 'BImSchG-Bescheid' : 'Baugenehmigung bzw. Bebauungsplan'; },
      hinweis: function (d) { return d.technologie === 'wind' ? 'Genehmigungsbescheid inklusive Nebenbestimmungen.' : 'Baugenehmigung, B-Plan oder Bestätigung der Genehmigungsfreiheit.'; }
    },
    {
      id: 'netzanschluss',
      titel: function () { return 'Netzanschlusszusage'; },
      hinweis: function () { return 'Zusage oder Reservierung des Netzbetreibers mit Anschlusspunkt und -leistung.'; }
    },
    {
      id: 'pacht',
      titel: function (d) { return d.technologie === 'pv_dach' ? 'Dachnutzungs- bzw. Gestattungsvertrag' : 'Pacht- und Nutzungsverträge'; },
      hinweis: function (d) { return d.technologie === 'pv_dach' ? 'Inklusive Grundbuchsicherung (Dienstbarkeit), falls vorhanden.' : 'Für Anlagen-, Wege- und Kabelflächen, inklusive Dienstbarkeiten.'; }
    },
    {
      id: 'epc',
      titel: function (d) {
        if (d.technologie === 'wind') return 'Turbinenliefer- und EPC-Verträge';
        if (d.technologie === 'speicher') return 'Liefer- und EPC-Vertrag Batteriesystem';
        return 'EPC-Vertrag (Generalunternehmer)';
      },
      hinweis: function () { return 'Lieferumfang, Preis, Zahlungsplan, Fertigstellungstermin und Garantien.'; }
    },
    {
      id: 'wartung',
      titel: function (d) { return d.technologie === 'wind' ? 'Vollwartungsvertrag' : 'Wartungs- und Betriebsführungsvertrag'; },
      hinweis: function (d) { return d.technologie === 'wind' ? 'Mit Verfügbarkeitsgarantie des Herstellers.' : 'Technische und kaufmännische Betriebsführung, Verfügbarkeitsgarantie.'; }
    },
    {
      id: 'erloes',
      titel: function (d) {
        if (d.technologie === 'speicher') return 'Vermarktungs- bzw. Tolling-Vertrag';
        switch (d.erloesmodell) {
          case 'eeg': return 'Zuschlag der Bundesnetzagentur (EEG)';
          case 'ppa': return 'PPA-Vertrag';
          case 'eeg_ppa': return 'EEG-Zuschlag und PPA-Vertrag';
          case 'merchant': return 'Marktpreisgutachten und Vermarktungskonzept';
          default: return 'Erlösnachweis (EEG-Zuschlag, PPA o. Ä.)';
        }
      },
      hinweis: function () { return 'Nachweis der im Finanzmodell angesetzten Erlöse.'; }
    },
    {
      id: 'gesellschaft',
      titel: function () { return 'Gesellschaftsunterlagen'; },
      hinweis: function () { return 'Handelsregisterauszug, Gesellschaftsvertrag, Gesellschafterliste.'; }
    },
    {
      id: 'finanzmodell',
      titel: function () { return 'Finanzmodell'; },
      hinweis: function () { return 'Cashflow-Planung über die gesamte Kreditlaufzeit, bevorzugt als Excel.'; }
    }
  ];

  /* ------------------------------------------------------------------
   * Hilfsfunktionen
   * ---------------------------------------------------------------- */
  function lesen() { return EE.formularLesen(form); }
  function istSpeicher(d) { return d.technologie === 'speicher'; }
  function leer(v) { return v === undefined || v === null || String(v).trim() === ''; }
  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function dateigroesse(bytes) {
    if (bytes < 1024) return '< 1 KB';
    if (bytes < 1024 * 1024) return EE.fmtZahl(bytes / 1024, 0) + ' KB';
    return EE.fmtZahl(bytes / 1024 / 1024, 1) + ' MB';
  }
  function badge(stufe, text) {
    return '<span class="badge badge--' + stufe + '">' + escapeHtml(text) + '</span>';
  }

  /* ------------------------------------------------------------------
   * Validierung
   * ---------------------------------------------------------------- */
  function pflicht(name, meldung) {
    return { name: name, pruefe: function (d) { return leer(d[name]) ? meldung : null; } };
  }
  function zahl(name, meldung, opt) {
    opt = opt || {};
    return {
      name: name,
      pruefe: function (d) {
        if (leer(d[name])) return opt.optional ? null : meldung;
        var n = EE.parseZahl(d[name]);
        if (n === null) return 'Bitte geben Sie eine Zahl ein, z. B. ' + (opt.beispiel || '24') + '.';
        if (opt.min !== undefined && n < opt.min) return opt.bereich || ('Der Wert muss mindestens ' + EE.fmtZahl(opt.min) + ' sein.');
        if (opt.max !== undefined && n > opt.max) return opt.bereich || ('Der Wert darf höchstens ' + EE.fmtZahl(opt.max) + ' sein.');
        if (opt.groesserNull && !(n > 0)) return 'Der Wert muss größer als 0 sein.';
        if (opt.extra) return opt.extra(n, d);
        return null;
      }
    };
  }

  function regeln(schritt, d) {
    var speicher = istSpeicher(d);
    switch (schritt) {
      case 1: return [
        pflicht('technologie', 'Bitte wählen Sie die Technologie aus.'),
        pflicht('projektname', 'Bitte geben Sie einen Projektnamen ein.'),
        zahl('leistung_mw', 'Bitte geben Sie die Leistung in MW an.', { groesserNull: true, max: 2000, beispiel: '24 oder 4,2' })
      ];
      case 2: return [
        pflicht('genehmigung', 'Bitte wählen Sie den Stand der Genehmigung aus.'),
        pflicht('netzanschluss', 'Bitte wählen Sie den Stand des Netzanschlusses aus.'),
        pflicht('flaechen', 'Bitte geben Sie an, ob die Flächen gesichert sind.'),
        zahl('kabel_km', '', { optional: true, min: 0, max: 100, beispiel: '6', bereich: 'Bitte geben Sie eine Länge zwischen 0 und 100 km an.' }),
        zahl('abregelung_prozent', '', { optional: true, min: 0, max: 50, beispiel: '3', bereich: 'Bitte geben Sie einen Wert zwischen 0 und 50 % an.' })
      ];
      case 3: {
        var r3;
        if (speicher) {
          r3 = [
            zahl('speicher_erloes', 'Bitte geben Sie Ihre Erlöserwartung in T€ je MW und Jahr an.', { groesserNull: true, beispiel: '110' })
          ];
        } else {
          r3 = [
            zahl('p50_h', 'Bitte geben Sie die Volllaststunden P50 an.', { groesserNull: true, max: 8760, beispiel: '2.400' }),
            zahl('p90_h', '', {
              optional: true, max: 8760, beispiel: '2.050',
              extra: function (n, dd) {
                var p50 = EE.parseZahl(dd.p50_h);
                return p50 !== null && n > p50 ? 'P90 darf nicht größer als P50 sein.' : null;
              }
            }),
            pflicht('erloesmodell', 'Bitte wählen Sie das Erlösmodell aus.'),
            zahl('preis_eur_mwh', 'Bitte geben Sie den Preis in €/MWh an.', { groesserNull: true, max: 1000, beispiel: '73' }),
            zahl('ppa_laufzeit', '', { optional: true, min: 1, max: 30, beispiel: '10', bereich: 'Bitte geben Sie eine Laufzeit zwischen 1 und 30 Jahren an.' })
          ];
          if (d.technologie === 'wind') {
            r3.push(
              zahl('guetefaktor', '', { optional: true, min: 20, max: 200, beispiel: '80', bereich: 'Bitte geben Sie einen Gütefaktor zwischen 20 und 200 % an.' }),
              zahl('nabenhoehe', '', { optional: true, min: 30, max: 250, beispiel: '166', bereich: 'Bitte geben Sie eine Nabenhöhe zwischen 30 und 250 m an.' }),
              zahl('windgeschwindigkeit', '', { optional: true, min: 2, max: 15, beispiel: '6,8', bereich: 'Bitte geben Sie einen Wert zwischen 2 und 15 m/s an.' })
            );
          } else {
            r3.push(zahl('globalstrahlung', '', { optional: true, min: 600, max: 1500, beispiel: '1.120', bereich: 'Bitte geben Sie einen Wert zwischen 600 und 1.500 kWh/m² an.' }));
          }
        }
        r3.push(zahl('degradation_prozent', '', { optional: true, min: 0, max: 5, beispiel: '0,4', bereich: 'Bitte geben Sie einen Wert zwischen 0 und 5 % an.' }));
        return r3;
      }
      case 4: return [
        zahl('capex_teur', 'Bitte geben Sie die Gesamtinvestition in T€ an.', { groesserNull: true, beispiel: '34.800' }),
        zahl('opex_teur', '', { optional: true, min: 0, beispiel: '1.100' }),
        zahl('fk_quote', '', { optional: true, min: 0, max: 100, beispiel: '80', bereich: 'Bitte geben Sie eine Quote zwischen 0 und 100 % an.' }),
        zahl('zins', '', { optional: true, min: 0, max: 20, beispiel: '4,2', bereich: 'Bitte geben Sie einen Zins zwischen 0 und 20 % an.' }),
        zahl('laufzeit', '', { optional: true, min: 1, max: 40, beispiel: '18', bereich: 'Bitte geben Sie eine Laufzeit zwischen 1 und 40 Jahren an.' })
      ];
      case 5: return [];
      case 6: return [
        pflicht('ansprechpartner', 'Bitte geben Sie eine Ansprechpartnerin oder einen Ansprechpartner an.'),
        {
          name: 'email',
          pruefe: function (dd) {
            if (leer(dd.email)) return 'Bitte geben Sie Ihre E-Mail-Adresse an.';
            return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(dd.email) ? null : 'Bitte geben Sie eine gültige E-Mail-Adresse ein, z. B. name@beispiel.de.';
          }
        },
        {
          name: 'bestaetigung',
          pruefe: function (dd) { return dd.bestaetigung ? null : 'Bitte bestätigen Sie Ihre Angaben und die Datenschutzhinweise.'; }
        }
      ];
    }
    return [];
  }

  function pruefeSchritt(schritt, d) {
    var fehler = [];
    d = d || lesen();
    regeln(schritt, d).forEach(function (r) {
      var m = r.pruefe(d);
      if (m) fehler.push({ name: r.name, meldung: m });
    });
    return fehler;
  }

  function feldContainer(name) { return form.querySelector('[data-feld="' + name + '"]'); }

  function setzeFehler(name, meldung) {
    var box = feldContainer(name);
    if (!box) return;
    var fehlerId = 'fehler-' + name;
    var p = $(fehlerId);
    if (!p) {
      p = document.createElement('p');
      p.className = 'fehler';
      p.id = fehlerId;
      box.appendChild(p);
    }
    var inputs = form.querySelectorAll('[name="' + name + '"]');
    if (meldung) {
      p.innerHTML = '<svg class="icon icon--klein" aria-hidden="true"><use href="#i-warn"/></svg><span>' + escapeHtml(meldung) + '</span>';
      p.hidden = false;
    } else {
      p.hidden = true;
    }
    Array.prototype.forEach.call(inputs, function (inp) {
      var ids = (inp.getAttribute('aria-describedby') || '').split(/\s+/).filter(Boolean)
        .filter(function (x) { return x !== fehlerId; });
      if (meldung) {
        inp.setAttribute('aria-invalid', 'true');
        ids.push(fehlerId);
      } else {
        inp.removeAttribute('aria-invalid');
      }
      if (ids.length) inp.setAttribute('aria-describedby', ids.join(' '));
      else inp.removeAttribute('aria-describedby');
    });
  }

  function zeigeFehlerFuerSchritt(schritt) {
    var d = lesen();
    regeln(schritt, d).forEach(function (r) { setzeFehler(r.name, null); });
    var fehler = pruefeSchritt(schritt, d);
    fehler.forEach(function (f) { setzeFehler(f.name, f.meldung); });
    return fehler;
  }

  function fokussiereErstenFehler(fehler) {
    if (!fehler.length) return;
    var erstes = form.querySelector('[name="' + fehler[0].name + '"]');
    if (erstes) erstes.focus();
    statusMeldung.style.color = 'var(--fail-text)';
    statusMeldung.textContent = fehler.length === 1
      ? 'Bitte prüfen Sie 1 Angabe in diesem Schritt.'
      : 'Bitte prüfen Sie ' + fehler.length + ' Angaben in diesem Schritt.';
  }

  // Fehler sofort entfernen, sobald ein Feld korrigiert wurde.
  function nachpruefen(ev) {
    var name = ev.target.name;
    if (!name) return;
    var p = $('fehler-' + name);
    if (!p || p.hidden) return;
    var d = lesen();
    var regel = regeln(aktuell, d).filter(function (r) { return r.name === name; })[0];
    if (regel) setzeFehler(name, regel.pruefe(d));
  }

  /* ------------------------------------------------------------------
   * Schritte
   * ---------------------------------------------------------------- */
  navButtons.forEach(function (btn) {
    var sr = document.createElement('span');
    sr.className = 'sr-only';
    sr.setAttribute('data-status', '');
    btn.appendChild(sr);
  });

  function zeigeSchritt(n, fokus) {
    aktuell = n;
    besucht[n] = true;
    schritte.forEach(function (s) { s.hidden = Number(s.getAttribute('data-schritt')) !== n; });
    navButtons.forEach(function (b) {
      if (Number(b.getAttribute('data-ziel')) === n) b.setAttribute('aria-current', 'step');
      else b.removeAttribute('aria-current');
    });
    btnZurueck.hidden = n === 1;
    var letzter = n === ANZAHL;
    btnWeiter.className = 'btn ' + (letzter ? 'btn-cta' : 'btn-primaer');
    btnWeiter.innerHTML = letzter
      ? 'Anfrage einreichen<svg class="icon icon--klein" aria-hidden="true"><use href="#i-pfeil"/></svg>'
      : 'Weiter<svg class="icon icon--klein" aria-hidden="true"><use href="#i-pfeil"/></svg>';
    statusMeldung.textContent = '';
    if (letzter) renderZusammenfassung();
    aktualisiereNav();
    if (fokus) {
      var h = form.querySelector('.schritt[data-schritt="' + n + '"] h2');
      h.focus({ preventScroll: true });
      var oben = $('formular-bereich').getBoundingClientRect().top + window.pageYOffset - 16;
      if (window.pageYOffset > oben) window.scrollTo(0, oben);
    }
  }

  function aktualisiereNav() {
    var d = lesen();
    navButtons.forEach(function (b) {
      var n = Number(b.getAttribute('data-ziel'));
      var ok = besucht[n] && n !== aktuell && pruefeSchritt(n, d).length === 0;
      var fehler = besucht[n] && n < aktuell && pruefeSchritt(n, d).length > 0;
      b.classList.toggle('ist-erledigt', !!ok);
      b.classList.toggle('hat-fehler', !!fehler);
      b.querySelector('[data-status]').textContent = ok ? ' – erledigt' : fehler ? ' – unvollständig' : '';
    });
  }

  function weiter() {
    var fehler = zeigeFehlerFuerSchritt(aktuell);
    if (fehler.length) {
      fokussiereErstenFehler(fehler);
      return;
    }
    if (aktuell < ANZAHL) zeigeSchritt(aktuell + 1, true);
    else einreichen();
  }

  navButtons.forEach(function (btn) {
    btn.addEventListener('click', function () {
      var ziel = Number(btn.getAttribute('data-ziel'));
      if (ziel === aktuell) return;
      if (ziel > aktuell) {
        var fehler = zeigeFehlerFuerSchritt(aktuell);
        if (fehler.length) {
          fokussiereErstenFehler(fehler);
          return;
        }
      }
      zeigeSchritt(ziel, true);
    });
  });

  btnZurueck.addEventListener('click', function () {
    if (aktuell > 1) zeigeSchritt(aktuell - 1, true);
  });

  form.addEventListener('submit', function (ev) {
    ev.preventDefault();
    weiter();
  });

  /* ------------------------------------------------------------------
   * Abhängige Felder und Beschriftungen
   * ---------------------------------------------------------------- */
  var PREIS_LABEL = {
    eeg: 'Anzulegender Wert (EEG-Zuschlag)',
    ppa: 'PPA-Preis',
    eeg_ppa: 'Mischpreis aus EEG und PPA',
    merchant: 'Erwarteter Marktpreis'
  };

  /** Bei Wind mit EEG-Zuschlag wird der Zuschlagswert eingegeben und mit dem Korrekturfaktor umgerechnet. */
  function preisLabel(d) {
    if (d.technologie === 'wind' && CONFIG.standort.wind.korrekturFuerErloesmodell.indexOf(d.erloesmodell) !== -1) {
      return 'Zuschlagswert (EEG)';
    }
    return PREIS_LABEL[d.erloesmodell] || 'Erlös';
  }

  function aktualisiereFelder(d) {
    var speicher = istSpeicher(d);
    form.querySelectorAll('[data-nur="speicher"]').forEach(function (e) { e.hidden = !speicher; });
    form.querySelectorAll('[data-nur="nicht-speicher"]').forEach(function (e) { e.hidden = speicher; });
    var wind = d.technologie === 'wind';
    var pv = /^(pv_frei|agri_pv|pv_dach)$/.test(d.technologie || '');
    form.querySelectorAll('[data-nur="wind"]').forEach(function (e) { e.hidden = !wind; });
    form.querySelectorAll('[data-nur="pv"]').forEach(function (e) { e.hidden = !pv; });
    aktualisiereStandortHinweise(d, wind, pv);
    $('f-ppa-feld').hidden = speicher || !(d.erloesmodell === 'ppa' || d.erloesmodell === 'eeg_ppa');
    $('f-preis-label').textContent = preisLabel(d);
    form.querySelectorAll('[data-genehmigung-label]').forEach(function (e) {
      e.textContent = d.technologie === 'wind' ? 'Genehmigung nach BImSchG' : 'Baurecht / Genehmigung';
    });

    var pauschale = CONFIG.opexPauschale[d.technologie];
    var mw = EE.parseZahl(d.leistung_mw);
    var opex = $('f-opex');
    if (pauschale) {
      opex.placeholder = mw > 0 ? 'Pauschale: ' + EE.fmtZahl(mw * pauschale) + ' T€/a' : 'Pauschale: ' + pauschale + ' T€/MW';
      $('f-opex-hinweis').textContent = 'Leer lassen: Wir setzen ' + pauschale + ' T€ je MW und Jahr an.';
    } else {
      opex.placeholder = 'Pauschale';
    }

    // Unterlagen-Bezeichnungen
    DOKUMENTE.forEach(function (dok) {
      $('dok-' + dok.id + '-titel').textContent = dok.titel(d);
      $('dok-' + dok.id + '-hinweis').textContent = dok.hinweis(d);
    });
  }

  function aktualisiereStandortHinweise(d, wind, pv) {
    var S = CONFIG.standort;
    var band = EE.bandbreite(d.technologie, d.bundesland);
    var p50Hinweis = pv ? 'Entspricht dem spezifischen Ertrag in kWh/kWp.' : '';
    if (band) p50Hinweis += (p50Hinweis ? ' ' : '') + 'Üblich in ' + d.bundesland + ': ' + EE.fmtZahl(band[0]) + '–' + EE.fmtZahl(band[1]) + ' h.';
    $('f-p50-hinweis').textContent = p50Hinweis;

    // Gütefaktor und Korrekturfaktor
    var guete = EE.parseZahl(d.guetefaktor);
    var kfGilt = wind && S.wind.korrekturFuerErloesmodell.indexOf(d.erloesmodell) !== -1;
    $('f-guete-hinweis').textContent = guete > 0
      ? 'Korrekturfaktor ' + EE.fmtZahl(EE.korrekturfaktor(guete), 2) + (kfGilt ? '' : ' (wirkt nur beim EEG-Zuschlag)')
      : 'Laut Gutachten (Referenzertragsmodell).';
    var preis = EE.parseZahl(d.preis_eur_mwh);
    var preisHinweis = '';
    if (kfGilt) {
      if (guete > 0 && preis > 0) {
        var kf = EE.korrekturfaktor(guete);
        preisHinweis = 'Zuschlagswert × Korrekturfaktor ' + EE.fmtZahl(kf, 2) + ' = anzulegender Wert ' + EE.fmtZahl(preis * kf, 2) + ' €/MWh.';
      } else {
        preisHinweis = 'Ihr Zuschlagswert gilt für den 100-%-Referenzstandort. Mit Gütefaktor rechnen wir den Korrekturfaktor ein.';
      }
    }
    $('f-preis-hinweis').textContent = preisHinweis;

    // Abregelung: regionaler Erfahrungswert
    var erfahrung = EE.abregelungErfahrung(d.bundesland);
    $('f-abregelung').placeholder = 'z. B. ' + EE.fmtZahl(erfahrung, 1);
    $('f-abregelung-hinweis').textContent = 'Anteil der Jahreserzeugung, der durch Netzengpässe verloren geht. Erfahrungswert ' +
      (d.bundesland || 'ohne Bundesland') + ': ' + EE.fmtZahl(erfahrung, 1) + ' %. Wird nur angesetzt, wenn Sie einen Wert eintragen.';

    // Degradation: Standardwert je Technologie
    var deg = S.degradationStandard[d.technologie];
    var degFeld = $('f-degradation');
    degFeld.placeholder = deg !== undefined ? 'Standard: ' + EE.fmtZahl(deg, 1) : '';
    $('f-degradation-hinweis').textContent = deg !== undefined
      ? 'Jährlicher Leistungsverlust. Leer lassen: Wir setzen ' + EE.fmtZahl(deg, 1) + ' % p. a. an (' + EE.TECHNOLOGIEN[d.technologie].label + ').'
      : 'Jährlicher Leistungsverlust. Leer lassen: Wir setzen einen Standardwert an.';

    $('f-gutachten-legend').textContent = d.technologie === 'speicher' ? 'Stand des Erlösgutachtens' : 'Stand des Ertragsgutachtens';
  }

  /* ------------------------------------------------------------------
   * Uploads
   * ---------------------------------------------------------------- */
  function renderUploads() {
    var ul = $('uploads');
    var accept = CONFIG.upload.endungen.join(',');
    document.querySelectorAll('[data-upload-max]').forEach(function (e) { e.textContent = CONFIG.upload.maxMB; });
    ul.innerHTML = DOKUMENTE.map(function (dok) {
      var id = 'dok-' + dok.id;
      return '<li class="upload" data-dok="' + dok.id + '">' +
        '<div><span class="upload__titel" id="' + id + '-titel"></span><span class="upload__hinweis" id="' + id + '-hinweis"></span></div>' +
        '<div class="upload__aktion" style="position:relative">' +
          '<input type="file" id="' + id + '" name="dokument_' + dok.id + '" accept="' + accept + '" aria-labelledby="' + id + '-titel ' + id + '-knopf" aria-describedby="' + id + '-hinweis ' + id + '-status">' +
          '<label for="' + id + '" class="btn btn-sekundaer"><svg class="icon icon--klein" aria-hidden="true"><use href="#i-upload"/></svg><span id="' + id + '-knopf">Datei wählen</span></label>' +
        '</div>' +
        '<div class="upload__status" id="' + id + '-status" aria-live="polite"></div>' +
      '</li>';
    }).join('');

    DOKUMENTE.forEach(function (dok) {
      var input = $('dok-' + dok.id);
      input.addEventListener('change', function () {
        var datei = input.files && input.files[0];
        if (!datei) return;
        var fehler = pruefeDatei(datei);
        if (fehler) {
          input.value = '';
          delete dateien[dok.id];
          renderUploadStatus(dok.id, fehler);
        } else {
          dateien[dok.id] = datei;
          delete dateinamenEntwurf[dok.id];
          renderUploadStatus(dok.id);
        }
        aktualisieren();
      });
      renderUploadStatus(dok.id);
    });

    $('uploads').addEventListener('click', function (ev) {
      var btn = ev.target.closest('[data-entfernen]');
      if (!btn) return;
      var id = btn.getAttribute('data-entfernen');
      delete dateien[id];
      delete dateinamenEntwurf[id];
      $('dok-' + id).value = '';
      renderUploadStatus(id);
      $('dok-' + id).focus();
      aktualisieren();
    });
  }

  function pruefeDatei(datei) {
    var name = datei.name.toLowerCase();
    var endungOk = CONFIG.upload.endungen.some(function (e) { return name.slice(-e.length) === e; });
    if (!endungOk) return 'Dateityp nicht erlaubt. Erlaubt: ' + CONFIG.upload.endungen.join(', ') + '.';
    if (datei.size > CONFIG.upload.maxMB * 1024 * 1024) return 'Die Datei ist größer als ' + CONFIG.upload.maxMB + ' MB.';
    if (datei.size === 0) return 'Die Datei ist leer.';
    return null;
  }

  function renderUploadStatus(id, fehler) {
    var li = form.querySelector('.upload[data-dok="' + id + '"]');
    var status = $('dok-' + id + '-status');
    var knopf = $('dok-' + id + '-knopf');
    var datei = dateien[id];
    li.classList.toggle('ist-hochgeladen', !!datei);
    li.classList.toggle('hat-fehler', !!fehler);
    if (fehler) {
      status.innerHTML = badge('fail', 'Nicht übernommen') + '<span>' + escapeHtml(fehler) + '</span>';
      knopf.textContent = 'Datei wählen';
    } else if (datei) {
      status.innerHTML = badge('ok', 'Hochgeladen') +
        '<span class="upload__datei">' + escapeHtml(datei.name) + ' (' + dateigroesse(datei.size) + ')</span>' +
        '<button type="button" class="btn btn-text" data-entfernen="' + id + '"><svg class="icon icon--klein" aria-hidden="true"><use href="#i-x"/></svg>Entfernen<span class="sr-only">: ' + escapeHtml(datei.name) + '</span></button>';
      knopf.textContent = 'Ersetzen';
    } else if (dateinamenEntwurf[id]) {
      status.innerHTML = badge('warn', 'Bitte erneut auswählen') +
        '<span class="upload__datei">' + escapeHtml(dateinamenEntwurf[id]) + '</span>';
      knopf.textContent = 'Datei wählen';
    } else {
      status.innerHTML = badge('neutral', 'Noch nicht hochgeladen');
      knopf.textContent = 'Datei wählen';
    }
  }

  function anzahlUnterlagen() { return Object.keys(dateien).length; }

  /* ------------------------------------------------------------------
   * Live-Indikation
   * ---------------------------------------------------------------- */
  function berechnen(d) { return EE.berechne(EE.eingabenAusDaten(d, CONFIG.anfrage)); }

  function dscrAnzeige(wertId, badgeId, minId, dscr, min, hinweisOhne) {
    $(wertId).textContent = EE.fmtDSCR(dscr);
    var a = EE.ampel(dscr, min);
    $(badgeId).innerHTML = a ? badge(a === 'ok' ? 'ok' : a, EE.AMPEL_TEXT[a]) : badge('neutral', 'offen');
    $(minId).textContent = a || !hinweisOhne ? 'Mindestwert ' + EE.fmtDSCR(min) : hinweisOhne;
    return a;
  }

  function aktualisiereIndikation(d) {
    var erg = berechnen(d);
    var speicher = istSpeicher(d);

    var a50 = dscrAnzeige('ind-dscr-p50', 'ind-dscr-p50-badge', 'ind-dscr-p50-min', erg.dscrP50, CONFIG.minDscrP50, 'Mindestwert ' + EE.fmtDSCR(CONFIG.minDscrP50));
    if (speicher) {
      $('ind-dscr-p90').textContent = '–';
      $('ind-dscr-p90-badge').innerHTML = badge('neutral', 'entfällt');
      $('ind-dscr-p90-min').textContent = 'Bei Speichern keine P90-Betrachtung';
    } else {
      dscrAnzeige('ind-dscr-p90', 'ind-dscr-p90-badge', 'ind-dscr-p90-min', erg.dscrP90, CONFIG.minDscrP90,
        EE.parseZahl(d.p90_h) === null ? 'P90 fehlt – Mindestwert ' + EE.fmtDSCR(CONFIG.minDscrP90) : null);
    }

    var capex = EE.parseZahl(d.capex_teur);
    $('ind-capex').textContent = EE.fmtTEUR(capex);
    $('ind-kredit').textContent = EE.fmtTEUR(erg.kredit);
    $('ind-ek').textContent = EE.fmtTEUR(erg.eigenkapital);
    $('ind-annuitaet').textContent = EE.fmtTEUR(erg.annuitaet);
    $('ind-cfads-p50').textContent = EE.fmtTEUR(erg.cfadsP50);
    $('ind-cfads-p90').textContent = speicher ? 'entfällt' : EE.fmtTEUR(erg.cfadsP90);

    $('ind-sub').textContent = 'Zins ' + EE.fmtProzent(erg.zinsProzent, 2) + ', ' + EE.fmtZahl(erg.laufzeitJahre) +
      ' Jahre, FK-Quote ' + EE.fmtProzent(erg.fkQuoteProzent, 0) + '. Unverbindlich, keine Kreditzusage.';
    $('ind-opex-hinweis').textContent = erg.opexPauschal
      ? 'Betriebskosten pauschal angesetzt: ' + erg.opexPauschaleJeMW + ' T€/MW/a = ' + EE.fmtTEUR(erg.opex) + ' p. a.'
      : '';

    // Wirkung der Standortfaktoren auf den Umsatz
    var faktoren = [];
    if (erg.korrekturAngewendet) faktoren.push('Korrekturfaktor ' + EE.fmtZahl(erg.korrekturfaktor, 2));
    if (erg.abregelungProzent > 0) faktoren.push('Abregelung ' + EE.fmtZahl(erg.abregelungProzent, 1) + ' %');
    if (erg.degradationProzent > 0) {
      faktoren.push('Degradation ' + EE.fmtZahl(erg.degradationProzent, 1) + ' % p. a.' +
        (erg.degradationStandard ? ' (Standard)' : '') + ', Ø ' + EE.fmtZahl((1 - erg.degradationsfaktor) * 100, 1) + ' % weniger');
    }
    $('ind-umsatz-hinweis').textContent = faktoren.length ? 'Im Umsatz berücksichtigt: ' + faktoren.join(' · ') + '.' : '';

    renderStandort(d, erg);

    // Projektreife
    var reife = EE.projektreife(d, d.technologie === 'wind');
    var reifeStufe = { baureif: 'ok', fast: 'info', entwicklung: 'warn' }[reife.stufe];
    $('ind-reife-badge').innerHTML = badge(reifeStufe, reife.titel);
    $('ind-offen').innerHTML = reife.offen.length
      ? reife.offen.map(function (o) { return '<li>' + escapeHtml(o) + '</li>'; }).join('')
      : '<li>Keine offenen Punkte</li>';

    // Unterlagen
    var n = anzahlUnterlagen();
    var gesamt = DOKUMENTE.length;
    $('ind-unterlagen-wert').textContent = n + ' von ' + gesamt;
    $('ind-unterlagen-fuellung').style.width = Math.round(n / gesamt * 100) + '%';
    var balken = $('ind-unterlagen-balken');
    balken.setAttribute('aria-valuenow', String(n));
    balken.setAttribute('aria-valuemax', String(gesamt));
    balken.setAttribute('aria-valuetext', n + ' von ' + gesamt + ' Unterlagen hochgeladen');

    // Abgeleitete Werte in Schritt 4
    $('abg-capex-mw').textContent = erg.capexJeMW !== null ? EE.fmtZahl(erg.capexJeMW) + ' T€/MW' : '–';
    $('abg-kredit').textContent = EE.fmtTEUR(erg.kredit);
    $('abg-annuitaet').textContent = EE.fmtTEUR(erg.annuitaet);

    // Mobile Kurzanzeige
    $('mini-dscr').textContent = EE.fmtDSCR(erg.dscrP50);
    $('mini-badge').innerHTML = a50 ? badge(a50, EE.AMPEL_TEXT[a50]) : '';

    return erg;
  }

  var STANDORT_TEXT = { ok: 'gut', warn: 'prüfen', fail: 'kritisch' };

  function renderStandort(d, erg) {
    var b = EE.standortBewertung(d, erg);
    var titelDargebot = d.technologie === 'wind' ? 'Windangebot'
      : /^(pv_frei|agri_pv|pv_dach)$/.test(d.technologie || '') ? 'Sonneneinstrahlung' : 'Wind / Sonne';
    var bereiche = [[titelDargebot, b.dargebot], ['Gutachtenlage', b.gutachten], ['Netz', b.netz]];
    $('ind-standort').innerHTML = bereiche.map(function (x) {
      var be = x[1];
      var bd = be.stufe ? badge(be.stufe, STANDORT_TEXT[be.stufe]) : badge('neutral', be.entfaellt ? 'entfällt' : 'offen');
      return '<div><div class="standort__kopf"><span>' + x[0] + '</span>' + bd + '</div>' +
        '<ul class="offene-punkte">' + be.punkte.map(function (pk) { return '<li>' + escapeHtml(pk.text) + '</li>'; }).join('') + '</ul></div>';
    }).join('');
    $('ind-standort-badge').innerHTML = b.gesamt ? badge(b.gesamt, STANDORT_TEXT[b.gesamt]) : badge('neutral', 'offen');
    return b;
  }

  /* ------------------------------------------------------------------
   * Zusammenfassung (Schritt 6)
   * ---------------------------------------------------------------- */
  function wert(v, einheit) {
    if (leer(v)) return '<span class="hinweis" style="display:inline">keine Angabe</span>';
    var n = EE.parseZahl(v);
    var text = n !== null && einheit ? EE.fmtZahl(n, n % 1 ? 1 : 0) + ' ' + einheit : String(v);
    return escapeHtml(text);
  }
  function auswahl(gruppe, v) { return leer(v) ? wert('') : escapeHtml(LABELS[gruppe][v] || v); }
  function monat(v) {
    if (leer(v)) return wert('');
    var t = String(v).split('-');
    return t.length === 2 ? escapeHtml(t[1] + '/' + t[0]) : escapeHtml(v);
  }

  function renderZusammenfassung() {
    var d = lesen();
    var erg = berechnen(d);
    var speicher = istSpeicher(d);
    var tech = EE.TECHNOLOGIEN[d.technologie];

    function block(titel, schritt, zeilen) {
      return '<h3>' + titel + ' <button type="button" class="btn btn-text" data-ziel-schritt="' + schritt + '">Ändern<span class="sr-only">: ' + titel + '</span></button></h3>' +
        '<dl>' + zeilen.map(function (z) { return '<dt>' + z[0] + '</dt><dd>' + z[1] + '</dd>'; }).join('') + '</dl>';
    }

    var ertrag = speicher
      ? [['Erlöserwartung', wert(d.speicher_erloes, 'T€/MW/a')]]
      : [
        ['Volllaststunden P50', wert(d.p50_h, 'h/a')],
        ['Volllaststunden P90', wert(d.p90_h, 'h/a')],
        ['Erlösmodell', auswahl('erloesmodell', d.erloesmodell)],
        [preisLabel(d), wert(d.preis_eur_mwh, '€/MWh') +
          (erg.korrekturAngewendet ? ' (anzulegender Wert ' + escapeHtml(EE.fmtZahl(erg.preisWirksam, 2)) + ' €/MWh)' : '')]
      ];
    if (!speicher && (d.erloesmodell === 'ppa' || d.erloesmodell === 'eeg_ppa')) ertrag.push(['PPA-Laufzeit', wert(d.ppa_laufzeit, 'Jahre')]);
    if (d.technologie === 'wind') {
      ertrag.push(['Gütefaktor', leer(d.guetefaktor) ? wert('') :
        wert(d.guetefaktor, '%') + ' (Korrekturfaktor ' + escapeHtml(EE.fmtZahl(EE.korrekturfaktor(EE.parseZahl(d.guetefaktor)), 2)) +
        (erg.korrekturAngewendet ? ', angewendet' : ', nicht angewendet') + ')']);
      ertrag.push(['Nabenhöhe', wert(d.nabenhoehe, 'm')]);
      ertrag.push(['Mittlere Windgeschwindigkeit', leer(d.windgeschwindigkeit) ? wert('') : escapeHtml(EE.fmtZahl(EE.parseZahl(d.windgeschwindigkeit), 1)) + ' m/s']);
    } else if (!speicher) {
      ertrag.push(['Globalstrahlung', wert(d.globalstrahlung, 'kWh/m²/a')]);
    }
    ertrag.push([speicher ? 'Erlösgutachten' : 'Ertragsgutachten', auswahl('gutachten', d.gutachten)]);
    ertrag.push(['Degradation', leer(d.degradation_prozent)
      ? escapeHtml(EE.fmtZahl(erg.degradationProzent, 1)) + ' % p. a. (Standard)'
      : escapeHtml(EE.fmtZahl(EE.parseZahl(d.degradation_prozent), 1)) + ' % p. a.']);

    var html =
      block('Projekt', 1, [
        ['Technologie', tech ? escapeHtml(tech.label) : wert('')],
        ['Projektname', wert(d.projektname)],
        ['Gemeinde / Standort', wert(d.gemeinde)],
        ['Bundesland', wert(d.bundesland)],
        ['Projektgesellschaft', wert(d.projektgesellschaft)],
        ['Rolle', auswahl('rolle', d.rolle)],
        ['Leistung', wert(d.leistung_mw, 'MW')],
        ['Inbetriebnahme', monat(d.inbetriebnahme)]
      ]) +
      block('Genehmigungen &amp; Netz', 2, [
        [d.technologie === 'wind' ? 'Genehmigung nach BImSchG' : 'Baurecht / Genehmigung', auswahl('genehmigung', d.genehmigung)],
        ['Netzanschluss', auswahl('netzanschluss', d.netzanschluss)],
        ['Flächen gesichert', auswahl('flaechen', d.flaechen)],
        ['Spannungsebene', auswahl('spannungsebene', d.spannungsebene)],
        ['Kabeltrasse', leer(d.kabel_km) ? wert('') : escapeHtml(EE.fmtZahl(EE.parseZahl(d.kabel_km), 1)) + ' km'],
        ['Erwartete Abregelung', leer(d.abregelung_prozent) ? wert('') : escapeHtml(EE.fmtZahl(EE.parseZahl(d.abregelung_prozent), 1)) + ' %']
      ]) +
      block('Ertrag &amp; Erlöse', 3, ertrag) +
      block('Kosten &amp; Finanzierung', 4, [
        ['Gesamtinvestition', wert(d.capex_teur, 'T€')],
        ['Betriebskosten', leer(d.opex_teur) ? (erg.opex !== null ? escapeHtml(EE.fmtTEUR(erg.opex)) + ' p. a. (Pauschale)' : wert('')) : wert(d.opex_teur, 'T€/a')],
        ['Fremdkapitalquote', wert(d.fk_quote, '%')],
        ['Zins (Annahme)', wert(d.zins, '% p. a.')],
        ['Laufzeit', wert(d.laufzeit, 'Jahre')],
        ['Förderkredit (KfW)', d.foerderkredit ? 'gewünscht' : 'nicht gewünscht'],
        ['Kreditbetrag', escapeHtml(EE.fmtTEUR(erg.kredit))],
        ['Annuität p. a.', escapeHtml(EE.fmtTEUR(erg.annuitaet))],
        ['DSCR P50 / P90', escapeHtml(EE.fmtDSCR(erg.dscrP50)) + ' / ' + (speicher ? 'entfällt' : escapeHtml(EE.fmtDSCR(erg.dscrP90)))]
      ]) +
      block('Unterlagen', 5, DOKUMENTE.map(function (dok) {
        var f = dateien[dok.id];
        return [escapeHtml(dok.titel(d)), f ? escapeHtml(f.name) : '<span class="hinweis" style="display:inline">fehlt – später nachreichen</span>'];
      }));

    $('zusammenfassung').innerHTML = html;

    var fehlend = DOKUMENTE.filter(function (dok) { return !dateien[dok.id]; });
    var box = $('fehlende-unterlagen');
    box.hidden = fehlend.length === 0;
    if (fehlend.length) {
      $('fehlende-unterlagen-titel').textContent = fehlend.length === 1
        ? 'Es fehlt noch 1 Unterlage.'
        : 'Es fehlen noch ' + fehlend.length + ' Unterlagen.';
      $('fehlende-unterlagen-liste').textContent = fehlend.map(function (dok) { return dok.titel(d); }).join(', ') + '.';
    }
  }

  $('zusammenfassung').addEventListener('click', function (ev) {
    var btn = ev.target.closest('[data-ziel-schritt]');
    if (btn) zeigeSchritt(Number(btn.getAttribute('data-ziel-schritt')), true);
  });

  /* ------------------------------------------------------------------
   * Entwurf speichern
   * ---------------------------------------------------------------- */
  function entwurfSpeichern() {
    var namen = {};
    Object.keys(dateinamenEntwurf).forEach(function (id) { namen[id] = dateinamenEntwurf[id]; });
    Object.keys(dateien).forEach(function (id) { namen[id] = dateien[id].name; });
    var ok = EE.Store.schreiben(CONFIG.speicher.entwurf, {
      daten: lesen(),
      schritt: aktuell,
      besucht: besucht,
      dateien: namen,
      zeit: new Date().toISOString()
    });
    statusMeldung.style.color = ok ? '' : 'var(--fail-text)';
    statusMeldung.textContent = ok
      ? 'Entwurf gespeichert um ' + new Date().toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' }) +
        ' Uhr. Er bleibt in diesem Browser-Tab erhalten. Dateien müssen nach dem Neuladen erneut ausgewählt werden.'
      : 'Der Entwurf konnte nicht gespeichert werden, weil Ihr Browser den Speicher blockiert.';
  }
  btnEntwurf.addEventListener('click', entwurfSpeichern);

  /* ------------------------------------------------------------------
   * Einreichen
   * ---------------------------------------------------------------- */
  function vorgangsnummer() {
    var zahl;
    try {
      var a = new Uint32Array(1);
      window.crypto.getRandomValues(a);
      zahl = a[0] % 1000000;
    } catch (e) {
      zahl = Math.floor(Math.random() * 1000000);
    }
    return 'EE-' + new Date().getFullYear() + '-' + String(zahl).padStart(6, '0');
  }

  function einreichen() {
    // Alle Schritte prüfen; beim ersten fehlerhaften Schritt anhalten.
    for (var s = 1; s <= ANZAHL; s++) {
      if (pruefeSchritt(s).length) {
        if (s !== aktuell) zeigeSchritt(s, false);
        var fehler = zeigeFehlerFuerSchritt(s);
        fokussiereErstenFehler(fehler);
        return;
      }
    }

    var d = lesen();
    var erg = berechnen(d);
    var reife = EE.projektreife(d, d.technologie === 'wind');
    var nr = vorgangsnummer();

    var anfrage = {
      schemaVersion: 1,
      vorgangsnummer: nr, // vorläufig; die verbindliche Nummer vergibt der Server
      erstelltAm: new Date().toISOString(),
      daten: d,
      zahlen: EE.eingabenAusDaten(d, CONFIG.anfrage),
      indikation: {
        umsatzP50: erg.umsatzP50, umsatzP90: erg.umsatzP90, opex: erg.opex, opexPauschal: erg.opexPauschal,
        cfadsP50: erg.cfadsP50, cfadsP90: erg.cfadsP90, kredit: erg.kredit, eigenkapital: erg.eigenkapital,
        annuitaet: erg.annuitaet, dscrP50: erg.dscrP50, dscrP90: erg.dscrP90,
        ampelP50: EE.ampel(erg.dscrP50, CONFIG.minDscrP50), ampelP90: EE.ampel(erg.dscrP90, CONFIG.minDscrP90),
        tragfaehigerKredit: erg.tragfaehigerKredit,
        korrekturfaktor: erg.korrekturfaktor, korrekturAngewendet: erg.korrekturAngewendet,
        preisWirksam: erg.preisWirksam, abregelungProzent: erg.abregelungProzent,
        degradationProzent: erg.degradationProzent, degradationsfaktor: erg.degradationsfaktor
      },
      standort: EE.standortBewertung(d, erg),
      projektreife: { stufe: reife.stufe, offen: reife.offen },
      unterlagen: DOKUMENTE.map(function (dok) {
        var f = dateien[dok.id];
        return { id: dok.id, bezeichnung: dok.titel(d), feld: 'dokument_' + dok.id, datei: f ? f.name : null, groesse: f ? f.size : null };
      }),
      parameter: {
        minDscrP50: CONFIG.minDscrP50, minDscrP90: CONFIG.minDscrP90, toleranzKnapp: CONFIG.toleranzKnapp,
        standort: CONFIG.standort
      }
    };

    var fd = new FormData();
    fd.append('anfrage', JSON.stringify(anfrage));
    Object.keys(dateien).forEach(function (id) {
      fd.append('dokument_' + id, dateien[id], dateien[id].name);
    });

    // TODO Backend: Anfrage an den Server senden, z. B.
    // fetch('/api/ee/anfragen', {
    //   method: 'POST',
    //   body: fd,                         // Content-Type setzt der Browser (multipart/form-data)
    //   credentials: 'same-origin',
    //   headers: { 'X-CSRF-Token': csrfToken }
    // })
    //   .then(function (res) { if (!res.ok) throw new Error(res.status); return res.json(); })
    //   .then(function (antwort) { zeigeErfolg(antwort.vorgangsnummer, anfrage); })
    //   .catch(function () { /* Fehlermeldung anzeigen, Entwurf behalten */ });
    if (window.console && console.info) {
      console.info('[Demo] FormData bereit:', Array.from(fd.keys()), anfrage);
    }

    zeigeErfolg(nr, anfrage);
  }

  function zeigeErfolg(nr, anfrage) {
    // Für die Demo im Kundenportal sichtbar machen (nur in diesem Browser-Tab)
    var vorgaenge = EE.Store.lesen(CONFIG.speicher.vorgaenge) || [];
    var d = anfrage.daten;
    vorgaenge.unshift({
      vorgangsnummer: nr,
      name: d.projektname,
      technologie: d.technologie,
      leistungMW: EE.parseZahl(d.leistung_mw),
      inbetriebnahme: d.inbetriebnahme,
      kreditTEUR: anfrage.indikation.kredit,
      stufe: 0,
      naechsterSchritt: 'Eingangsbestätigung und Vorprüfung durch das Team Erneuerbare Energien.',
      rueckfragen: 0,
      unterlagen: { vorhanden: anfrage.unterlagen.filter(function (u) { return u.datei; }).length, gesamt: anfrage.unterlagen.length }
    });
    EE.Store.schreiben(CONFIG.speicher.vorgaenge, vorgaenge);
    EE.Store.entfernen(CONFIG.speicher.entwurf);
    EE.Store.entfernen(CONFIG.speicher.schnellcheck);

    form.hidden = true;
    $('vorbefuellt').hidden = true;
    $('schrittnav').hidden = true;
    document.querySelector('.antrag').classList.add('ist-fertig');
    $('erfolg-nr').textContent = nr;
    $('erfolg').hidden = false;
    window.scrollTo(0, 0);
    $('erfolg-titel').focus();
  }

  /* ------------------------------------------------------------------
   * Aktualisierung bei Eingaben
   * ---------------------------------------------------------------- */
  var timer = null;
  function aktualisieren() {
    var d = lesen();
    aktualisiereFelder(d);
    clearTimeout(timer);
    timer = setTimeout(function () {
      aktualisiereIndikation(lesen());
      aktualisiereNav();
    }, 250);
  }

  form.addEventListener('input', function (ev) { nachpruefen(ev); aktualisieren(); });
  form.addEventListener('change', function (ev) { nachpruefen(ev); aktualisieren(); });

  /* ------------------------------------------------------------------
   * Start
   * ---------------------------------------------------------------- */
  document.querySelectorAll('select[data-bundeslaender]').forEach(function (sel) {
    EE.BUNDESLAENDER.forEach(function (land) {
      var opt = document.createElement('option');
      opt.value = land;
      opt.textContent = land;
      sel.appendChild(opt);
    });
  });

  // Vorgaben aus CONFIG (eine Quelle für alle Bankparameter)
  $('f-fk').value = EE.fmtZahl(CONFIG.anfrage.fkQuoteProzent, 0);
  $('f-zins').value = EE.fmtZahl(CONFIG.anfrage.zinsProzent, 1);
  $('f-laufzeit').value = EE.fmtZahl(CONFIG.anfrage.laufzeitJahre, 0);

  renderUploads();

  var entwurf = EE.Store.lesen(CONFIG.speicher.entwurf);
  var schnellcheck = EE.Store.lesen(CONFIG.speicher.schnellcheck);
  var hinweis = $('vorbefuellt');
  var startSchritt = 1;

  if (entwurf && entwurf.daten) {
    EE.formularBefuellen(form, entwurf.daten);
    dateinamenEntwurf = entwurf.dateien || {};
    besucht = entwurf.besucht || { 1: true };
    startSchritt = entwurf.schritt || 1;
    var zeit = entwurf.zeit ? new Date(entwurf.zeit) : null;
    $('vorbefuellt-text').textContent = 'Ihr gespeicherter Entwurf' +
      (zeit ? ' von ' + zeit.toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' }) + ' Uhr' : '') +
      ' wurde geladen. Bereits gewählte Dateien wählen Sie bitte erneut aus.';
    hinweis.hidden = false;
    DOKUMENTE.forEach(function (dok) { renderUploadStatus(dok.id); });
  } else if (schnellcheck) {
    var n = EE.formularBefuellen(form, schnellcheck);
    if (n > 0) {
      $('vorbefuellt-text').textContent = 'Wir haben ' + n + (n === 1 ? ' Angabe' : ' Angaben') +
        ' aus Ihrem Schnell-Check übernommen. Bitte prüfen und ergänzen Sie sie.';
      hinweis.hidden = false;
    }
  }

  aktualisiereFelder(lesen());
  aktualisiereIndikation(lesen());
  zeigeSchritt(startSchritt, false);
})();
