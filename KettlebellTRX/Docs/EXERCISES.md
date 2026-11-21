# Übungsbibliothek erweitern

Die Übungen liegen in `Sources/FitnessCore/Library/Resources/exercises.json` (Schema-Version 1)
und werden ohne Codeänderung geladen. 58 Übungen: Kettlebell 14, TRX 13, Mobilität 10,
Eigengewicht 6, Core 6, Aufwärmen 5, Regeneration 4.

## Neue Übung hinzufügen

Bequem über `Tools/generate_exercises.py` (ein `ex(...)`-Aufruf je Übung, danach
`python3 Tools/generate_exercises.py`) oder direkt in der JSON-Datei. `ExerciseLibrary.load(from:)`
kann zusätzlich eine eigene Datei laden, deren Einträge ergänzen bzw. gleiche IDs überschreiben.

Pflichtfelder: `id` (stabil, nie umbenennen – Historie verweist darauf), `nameDE`, `category`,
`equipment`, `primaryMuscles`, `difficulty`, `summary`, `startingPosition`, `movementDirection`,
`breathing`, `techniqueCues`, `commonMistakes`, `safetyNotes`, `stressedRegions`, `tags`,
`load` (`kind`, bei Kettlebell `tier`), `defaultPrescription`, `alternatives`, `animation`,
`requiresTechniqueCheck`. Optional: `nameEN`, `regressionId`, `progressionId`, `mediaFile`.

`stressedRegions` und `tags` (`overhead`, `ballistic`, `rotation` …) steuern die Sicherheitsregeln –
bitte sorgfältig pflegen. Verweise werden beim Laden geprüft, die Tests prüfen Vollständigkeit.

## Darstellung

* `animation`: Kennung aus `PoseLibrary` (43 eigene Bewegungsanimationen, Strichfigur mit
  Kettlebell/TRX-Schlingen, Seitenansicht). Neue Animationen werden als Winkel-Keyframes
  (`Pose`) definiert; Bodenkontakt und Position berechnet `PoseRenderer` automatisch.
* `mediaFile`: optional ein **eigenes oder lizenziertes** Video, das lokal im App-Bundle bzw.
  Dokumentenordner liegt (Anzeige im Player ist vorbereitet, in V1 noch nicht verdrahtet).
  Keine Fremdinhalte ohne Lizenz verwenden.
