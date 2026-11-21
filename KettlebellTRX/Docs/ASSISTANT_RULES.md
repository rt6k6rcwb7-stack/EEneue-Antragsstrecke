# Entscheidungsregeln des Trainingsassistenten (Version 1, regelbasiert)

Implementierung: `Sources/FitnessCore/Assistant/TrainingAssistant.swift`,
`Planning/ProgressionEngine.swift`, `Planning/SafetyFilter.swift`, `Vitals/VitalAlerts.swift`.
Jede Empfehlung listet die ausgelösten Regeln (ID, Begründung, Datengrundlage) und benennt
fehlende Daten.

## Grundsätze

1. **Die strengste ausgelöste Regel entscheidet.** Stufen: wie geplant (100 %) < Wiederholungen
   reduzieren (90 %) < Intensität reduzieren (80 %) < Mobilität statt Kraft < zusätzliche
   Regeneration < kein Training/ärztliche Abklärung.
2. **Gute Werte heben keine Warnung auf.** Ein hoher Recovery Score oder eine hohe HRV führen nie
   allein zu mehr Intensität und übersteuern keine Sicherheits- oder Belastungsregel.
3. **Keine medizinische Freigabe.** Nach (fieberhafter) Erkrankung oder bei kardiovaskulärer
   Einschränkung empfiehlt die App keine Rückkehr zu intensivem Training.
4. **Bestätigung durch den Nutzer.** Laststeigerungen sind Vorschläge; Übersteuerungen werden protokolliert.
5. **Vergleich nur innerhalb derselben Quelle und Messmethode.**
6. **Beispieldaten fließen nie in Empfehlungen ein.**

## Sicherheitsregeln (S)

| ID | Bedingung | Ergebnis |
|---|---|---|
| S1 | Warnsymptome angegeben (Brustschmerz/-enge, Atemnot, Schwindel, Herzstolpern, Ohnmacht) | kein Training, ärztliche Abklärung (Notruf-Hinweis), **nicht übersteuerbar** |
| S2 | Fieber | zusätzliche Regeneration, nicht übersteuerbar |
| S2b | akute Infektzeichen ohne Fieber | höchstens Mobilität |
| S3 | Programm pausiert | zusätzliche Regeneration |
| S4 | Wiedereinstieg nach Erkrankung/Verletzung (Status „returning“) | max. 80 % Intensität; Status endet nur durch den Nutzer |
| S5 | kardiovaskuläre Einschränkung im Profil | Hinweis; keine automatische Steigerung, keine ballistischen Übungen, Pulswarnung |
| S6 | Beschwerden ≥ 7/10 in den letzten 7 Tagen | Mobilität statt Kraft + Abklärungshinweis |
| S6b | Beschwerden ≥ 5/10 in den letzten 7 Tagen | Intensität reduzieren; betroffene Übungen werden ersetzt |
| S7 | aktuelle Beschwerden in der Selbsteinschätzung | Intensität reduzieren; betroffene Übungen heute ersetzt |

## Belastungsregeln (L)

| ID | Bedingung | Ergebnis |
|---|---|---|
| L1 | intensive Einheit (Kraft/Kondition) vor < 36 h und heute erneut intensiv geplant | Mobilität statt Kraft |
| L2 | Ø Session-RPE der letzten 3 Einheiten ≥ 8,5 | Intensität reduzieren |
| L3 | nach letzter Einheit „erschöpft“ | Intensität reduzieren |
| L4 / L4b | Schlafqualität oder Energie 1 / 2 (von 5) | Intensität reduzieren / Wdh. reduzieren |
| L5 / L5b | Muskelkater 5 / 4 (von 5) | Mobilität / Wdh. reduzieren |

## Vitaldatenregeln (V)

| ID | Bedingung (gleiche Quelle, Basislinie ≥ 5 Tage aus 28) | Ergebnis |
|---|---|---|
| V1 | Ruhepuls ≥ Basislinie + 7 S/min | Intensität reduzieren |
| V2 | HRV < 75 % des Basislinien-Medians (RMSSD bzw. SDNN getrennt) | Intensität reduzieren |
| V3 / V3b | Schlaf letzte Nacht < 5 h / < 6 h | Intensität reduzieren / Wdh. reduzieren |
| V4 | Recovery Score < 34 % | Intensität reduzieren |
| V5 | mindestens zwei von V1–V4 | Mobilität statt Kraft |

Fehlen Daten, wird die Regel nicht ausgelöst und die fehlende Datenart in der Empfehlung genannt.

## Progressionsregeln (P) – Vorschläge nach zwei Einheiten

| ID | Bedingung | Vorschlag |
|---|---|---|
| P1 | 2 Einheiten in Folge: alle Sätze/Wiederholungen erreicht, RPE ≤ 7, Gewicht nicht „zu schwer“, keine Beschwerden in betroffener Region (14 Tage); ab Woche 4; Gewicht „zu leicht“ oder ≥ 12 Wdh. | nächste Kettlebell |
| P2 | wie P1, aber keine schwerere Kettlebell bzw. TRX/Eigengewicht | +2 Wdh. bzw. +5 s (max. 15 Wdh./60 s) |
| P3 | RPE ≥ 9, Gewicht „zu schwer“, Ziel um > 20 % verfehlt oder Beschwerden | nächstleichtere Kettlebell |
| P4 | wie P3 ohne leichtere Kettlebell | −2 Wdh. bzw. −5 s |
| – | Sperre für P1/P2 | kardiovaskuläre Einschränkung, Programm nicht „aktiv“, allgemeine Intensität < 100 % |

Vorschläge gelten ab der folgenden Woche für alle noch nicht absolvierten Einheiten und lassen
manuell geänderte Werte unangetastet.

## Hinweise während des Trainings

| Bedingung | Hinweis |
|---|---|
| Puls > persönliche Obergrenze | Warnung: Tempo reduzieren, Pause verlängern |
| Puls > geschätzte HFmax (Tanaka: 208 − 0,7 × Alter) | Warnung + Abbruch-/Notfallhinweis bei Symptomen |
| Puls > 90 % HFmax | Hinweis auf moderat vorgesehene Belastung |

Tägliche Hinweise: Ruhepuls ≥ +7 (Hinweis) bzw. drei Tage ≥ +10 (Warnung mit Abklärungshinweis),
HRV unter Basislinie, zwei Nächte < 6 h Schlaf.

## Erweiterung um KI

Ein späterer KI-Assistent erhält dieselbe Eingabe (`AssistantContext`) und muss dieselbe Ausgabe
(`Recommendation` mit begründeten `RuleHit`s) liefern. Die Sicherheitsregeln S1–S7 bleiben als
vorgeschaltete, nicht übersteuerbare Schicht bestehen. Übermittlung von Gesundheitsdaten an
KI-Dienste nur nach gesonderter Einwilligung.
