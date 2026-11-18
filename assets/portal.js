/*
 * portal.js – Kundenportal
 * Rendert Anfragen und Rückfragen per <template>. Daten kommen aus loadData().
 */
(function () {
  'use strict';

  var EE = window.EE;
  var CONFIG = EE.CONFIG;

  var STUFEN = [
    'Eingereicht',
    'Vorprüfung',
    'Due Diligence',
    'Term Sheet',
    'Kreditentscheidung',
    'Vertrag & Auszahlung'
  ];

  /* ------------------------------------------------------------------
   * Fiktive Demo-Daten
   * ---------------------------------------------------------------- */
  var DEMO = {
    vorgaenge: [
      {
        vorgangsnummer: 'EE-2026-104233',
        name: 'Windpark Musterhöhe',
        technologie: 'wind',
        leistungMW: 24,
        inbetriebnahme: '2027-09',
        kreditTEUR: 27840,
        stufe: 2,
        naechsterSchritt: 'Technische Due Diligence durch [Gutachter] – Abschluss voraussichtlich [Datum].',
        unterlagen: { vorhanden: 8, gesamt: 9 }
      },
      {
        vorgangsnummer: 'EE-2026-118702',
        name: 'Solarpark Am Mühlbach',
        technologie: 'pv_frei',
        leistungMW: 12.5,
        inbetriebnahme: '2027-04',
        kreditTEUR: 7600,
        stufe: 1,
        naechsterSchritt: 'Bitte beantworten Sie die offene Rückfrage zum Zuschlagswert, danach erstellen wir die Vorprüfung.',
        unterlagen: { vorhanden: 6, gesamt: 9 }
      },
      {
        vorgangsnummer: 'EE-2026-097415',
        name: 'Batteriespeicher Talheim',
        technologie: 'speicher',
        leistungMW: 10,
        inbetriebnahme: '2026-12',
        kreditTEUR: 5200,
        stufe: 4,
        naechsterSchritt: 'Kreditentscheidung im Kreditausschuss am [Datum]. Wir informieren Sie direkt im Anschluss.',
        unterlagen: { vorhanden: 9, gesamt: 9 }
      }
    ],
    rueckfragen: [
      {
        id: 'rf-1',
        vorgangsnummer: 'EE-2026-104233',
        frage: 'Bitte reichen Sie das zweite unabhängige Ertragsgutachten nach.',
        datum: '2026-11-12'
      },
      {
        id: 'rf-2',
        vorgangsnummer: 'EE-2026-104233',
        frage: 'Ist die Kabeltrasse über Flurstück [Nr.] bereits dinglich gesichert?',
        datum: '2026-11-14'
      },
      {
        id: 'rf-3',
        vorgangsnummer: 'EE-2026-118702',
        frage: 'Bitte bestätigen Sie den Zuschlagswert aus der Ausschreibungsrunde [Datum] und laden Sie den Zuschlag hoch.',
        datum: '2026-11-16'
      }
    ]
  };

  /**
   * Lädt Anfragen und Rückfragen.
   * TODO Backend: durch einen authentifizierten API-Aufruf ersetzen, z. B.
   *   return fetch('/api/ee/vorgaenge', { credentials: 'same-origin' })
   *     .then(function (res) { if (!res.ok) throw new Error(res.status); return res.json(); });
   * Erwartetes Format: { vorgaenge: [...], rueckfragen: [...] } wie DEMO.
   */
  function loadData() {
    // In dieser Sitzung eingereichte Anfragen (nur Demo, sessionStorage)
    var eigene = EE.Store.lesen(CONFIG.speicher.vorgaenge) || [];
    return Promise.resolve({
      vorgaenge: eigene.concat(DEMO.vorgaenge),
      rueckfragen: DEMO.rueckfragen.slice()
    });
  }

  /* ------------------------------------------------------------------
   * Rendering
   * ---------------------------------------------------------------- */
  function feld(wurzel, name) { return wurzel.querySelector('[data-feld="' + name + '"]'); }

  function monat(v) {
    if (!v) return '–';
    var t = String(v).split('-');
    if (t.length !== 2) return v;
    var d = new Date(Number(t[0]), Number(t[1]) - 1, 1);
    return d.toLocaleDateString('de-DE', { month: 'long', year: 'numeric' });
  }

  function datum(v) {
    var d = new Date(v);
    return isNaN(d) ? v : d.toLocaleDateString('de-DE');
  }

  function badgeEl(stufe, text) {
    var s = document.createElement('span');
    s.className = 'badge badge--' + stufe;
    s.textContent = text;
    return s;
  }

  function renderVorgaenge(vorgaenge, rueckfragen) {
    var liste = document.getElementById('projekte');
    var vorlage = document.getElementById('projekt-vorlage');
    liste.innerHTML = '';

    if (!vorgaenge.length) {
      liste.innerHTML = '<p>Sie haben noch keine Anfragen gestellt.</p>';
      return;
    }

    vorgaenge.forEach(function (v, i) {
      var knoten = vorlage.content.cloneNode(true);
      var karte = knoten.querySelector('article');
      var titelId = 'projekt-' + i + '-titel';
      var h = feld(karte, 'name');
      h.id = titelId;
      h.textContent = v.name || 'Ohne Namen';
      karte.setAttribute('aria-labelledby', titelId);

      var tech = EE.TECHNOLOGIEN[v.technologie];
      feld(karte, 'technologie').textContent = tech ? tech.label : '–';
      feld(karte, 'leistung').textContent = v.leistungMW != null ? EE.fmtZahl(v.leistungMW, v.leistungMW % 1 ? 1 : 0) + ' MW' : '–';
      feld(karte, 'inbetriebnahme').textContent = monat(v.inbetriebnahme);
      feld(karte, 'vorgang').textContent = v.vorgangsnummer;
      feld(karte, 'volumen').textContent = EE.fmtTEUR(v.kreditTEUR);
      feld(karte, 'naechster').textContent = v.naechsterSchritt || '–';

      // Badges
      var badges = feld(karte, 'badges');
      var offen = rueckfragen.filter(function (r) { return r.vorgangsnummer === v.vorgangsnummer; }).length;
      badges.appendChild(offen
        ? badgeEl('warn', offen === 1 ? '1 Rückfrage offen' : offen + ' Rückfragen offen')
        : badgeEl('ok', 'Keine Rückfragen'));
      if (v.unterlagen) {
        var vollst = v.unterlagen.vorhanden >= v.unterlagen.gesamt;
        badges.appendChild(badgeEl(vollst ? 'ok' : 'info',
          'Unterlagen ' + v.unterlagen.vorhanden + '/' + v.unterlagen.gesamt + (vollst ? ' vollständig' : '')));
      }

      // Status-Pipeline
      var pipeline = feld(karte, 'pipeline');
      pipeline.setAttribute('aria-label', 'Bearbeitungsstand: Stufe ' + (v.stufe + 1) + ' von ' + STUFEN.length);
      STUFEN.forEach(function (name, s) {
        var li = document.createElement('li');
        li.textContent = name;
        var zustand = document.createElement('span');
        zustand.className = 'sr-only';
        if (s < v.stufe) {
          li.className = 'ist-erledigt';
          zustand.textContent = ' (erledigt)';
        } else if (s === v.stufe) {
          li.className = 'ist-aktuell';
          li.setAttribute('aria-current', 'step');
          zustand.textContent = ' (aktuell)';
        } else {
          zustand.textContent = ' (ausstehend)';
        }
        li.appendChild(zustand);
        pipeline.appendChild(li);
      });

      liste.appendChild(knoten);
    });
  }

  function renderRueckfragen(rueckfragen, vorgaenge) {
    var ul = document.getElementById('rueckfragen');
    var vorlage = document.getElementById('rueckfrage-vorlage');
    var anzahl = document.getElementById('rueckfragen-anzahl');
    ul.innerHTML = '';
    anzahl.innerHTML = '';
    anzahl.appendChild(badgeEl(rueckfragen.length ? 'warn' : 'ok', String(rueckfragen.length)));

    if (!rueckfragen.length) {
      ul.innerHTML = '<li>Keine offenen Rückfragen.</li>';
      return;
    }

    var namen = {};
    vorgaenge.forEach(function (v) { namen[v.vorgangsnummer] = v.name; });

    rueckfragen.forEach(function (r) {
      var knoten = vorlage.content.cloneNode(true);
      var li = knoten.querySelector('li');
      var fragId = r.id + '-frage';
      feld(li, 'projekt').textContent = (namen[r.vorgangsnummer] || r.vorgangsnummer) + ' · ' + datum(r.datum);
      var frage = feld(li, 'frage');
      frage.id = fragId;
      frage.textContent = r.frage;

      var datei = feld(li, 'datei');
      var status = feld(li, 'status');
      var form = feld(li, 'antwortform');
      var text = feld(li, 'antworttext');
      var label = feld(li, 'antwortlabel');
      var btnHoch = li.querySelector('[data-aktion="hochladen"]');
      var btnAntw = li.querySelector('[data-aktion="antworten"]');

      datei.id = r.id + '-datei';
      datei.setAttribute('aria-labelledby', fragId);
      datei.setAttribute('accept', CONFIG.upload.endungen.join(','));
      form.id = r.id + '-form';
      text.id = r.id + '-text';
      label.setAttribute('for', text.id);
      btnHoch.setAttribute('aria-describedby', fragId);
      btnAntw.setAttribute('aria-describedby', fragId);
      btnAntw.setAttribute('aria-controls', form.id);

      btnHoch.addEventListener('click', function () { datei.click(); });
      datei.addEventListener('change', function () {
        var f = datei.files && datei.files[0];
        if (!f) return;
        if (f.size > CONFIG.upload.maxMB * 1024 * 1024) {
          status.style.color = 'var(--fail-text)';
          status.textContent = 'Die Datei ist größer als ' + CONFIG.upload.maxMB + ' MB.';
          return;
        }
        // TODO Backend: Datei zur Rückfrage hochladen, z. B.
        // var fd = new FormData(); fd.append('dokument', f);
        // fetch('/api/ee/rueckfragen/' + encodeURIComponent(r.id) + '/dokumente', { method: 'POST', body: fd, credentials: 'same-origin' });
        status.style.color = '';
        status.textContent = '„' + f.name + '“ ausgewählt – in der Demo wird nichts übertragen.';
      });

      btnAntw.addEventListener('click', function () {
        var offen = form.hidden;
        form.hidden = !offen;
        btnAntw.setAttribute('aria-expanded', offen ? 'true' : 'false');
        if (offen) text.focus();
      });

      form.addEventListener('submit', function (ev) {
        ev.preventDefault();
        if (!text.value.trim()) {
          text.setAttribute('aria-invalid', 'true');
          status.style.color = 'var(--fail-text)';
          status.textContent = 'Bitte geben Sie eine Antwort ein.';
          text.focus();
          return;
        }
        text.removeAttribute('aria-invalid');
        // TODO Backend: Antwort senden, z. B.
        // fetch('/api/ee/rueckfragen/' + encodeURIComponent(r.id) + '/antworten', {
        //   method: 'POST', credentials: 'same-origin',
        //   headers: { 'Content-Type': 'application/json' },
        //   body: JSON.stringify({ text: text.value })
        // });
        form.hidden = true;
        btnAntw.setAttribute('aria-expanded', 'false');
        status.style.color = '';
        status.textContent = 'Antwort gespeichert (Demo). Ihr Ansprechpartner wird benachrichtigt.';
        btnAntw.focus();
      });

      ul.appendChild(knoten);
    });
  }

  var liste = document.getElementById('projekte');
  loadData()
    .then(function (daten) {
      renderVorgaenge(daten.vorgaenge, daten.rueckfragen);
      renderRueckfragen(daten.rueckfragen, daten.vorgaenge);
    })
    .catch(function () {
      liste.innerHTML = '<div class="box box--warn" role="alert"><p>Ihre Anfragen konnten nicht geladen werden. Bitte versuchen Sie es später erneut.</p></div>';
    })
    .then(function () {
      liste.setAttribute('aria-busy', 'false');
    });
})();
