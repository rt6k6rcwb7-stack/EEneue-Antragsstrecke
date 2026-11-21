#!/usr/bin/env python3
"""Erzeugt Sources/FitnessCore/Library/Resources/exercises.json.

Die JSON-Datei ist die maßgebliche Übungsquelle der App. Dieses Skript dient nur der
bequemen Pflege (weniger Wiederholungen). Neue Übungen können wahlweise hier oder direkt
in der JSON-Datei ergänzt werden – die App benötigt dafür keine Codeänderung.
Aufruf:  python3 Tools/generate_exercises.py
"""
import json, os

EX = []

def ex(id, de, en, cat, equip, prim, sec, diff, summary, start, direction, breathing,
       cues, mistakes, safety, regions, tags, load, rx, alts, anim,
       regression=None, progression=None, technique_check=False):
    kind, tier, lever = load
    sets, tkind, target, rest, per_side = rx
    EX.append({
        "id": id, "nameDE": de, "nameEN": en, "category": cat, "equipment": equip,
        "primaryMuscles": prim, "secondaryMuscles": sec, "difficulty": diff,
        "summary": summary, "startingPosition": start, "movementDirection": direction,
        "breathing": breathing, "techniqueCues": cues, "commonMistakes": mistakes,
        "safetyNotes": safety, "stressedRegions": regions, "tags": tags,
        "load": {k: v for k, v in {"kind": kind, "tier": tier, "leverHint": lever}.items() if v is not None},
        "defaultPrescription": {"sets": sets, "targetKind": tkind, "target": target,
                                "restSeconds": rest, "perSide": per_side},
        "alternatives": alts, "animation": anim, "requiresTechniqueCheck": technique_check,
        **({"regressionId": regression} if regression else {}),
        **({"progressionId": progression} if progression else {}),
    })

KB = ["kettlebell"]; TRX = ["trx"]; BW = ["bodyweight"]; MAT = ["mat"]
R = "reps"; S = "seconds"

# ───────────────────────── KETTLEBELL ─────────────────────────
ex("kb_goblet_squat", "Kettlebell Goblet Squat", "Kettlebell Goblet Squat", "kettlebell", KB,
   ["quadriceps", "glutes"], ["adductors", "core", "upperBack"], 1,
   "Kniebeuge mit der Kettlebell vor der Brust – Grundübung für Beine, Gesäß und aufrechte Haltung.",
   "Hüftbreiter bis etwas breiterer Stand, Fußspitzen leicht nach außen. Kettlebell an den Hörnern vor dem Brustbein, Ellenbogen zeigen nach unten.",
   "Hüfte nach hinten-unten zwischen die Fersen absenken, Knie folgen den Fußspitzen. Aus dem ganzen Fuß wieder aufrichten.",
   "Vor dem Absenken einatmen und Rumpf spannen, beim Aufrichten ausatmen.",
   ["Brustbein bleibt oben, Blick nach vorn", "Knie schieben nach außen über die Fußspitzen", "Ganzer Fuß bleibt am Boden", "Nur so tief, wie der Rücken neutral bleibt"],
   ["Fersen heben ab", "Knie fallen nach innen", "Rundrücken in der tiefen Position", "Kettlebell zieht vom Körper weg"],
   ["Tiefe an Knie- und Hüftbeweglichkeit anpassen – eine Box als Tiefenbegrenzung ist sinnvoll", "Bei Knieschmerzen Bewegungsumfang reduzieren oder TRX-gestützte Variante wählen"],
   ["knee", "hip", "lumbarSpine"], ["squat"], ("kettlebell", "medium", None), (2, R, 10, 75, False),
   ["trx_assisted_squat", "bw_squat"], "squat", regression="trx_assisted_squat")

ex("kb_deadlift", "Kettlebell Kreuzheben", "Kettlebell Deadlift", "kettlebell", KB,
   ["glutes", "hamstrings"], ["lowerBack", "forearms", "core", "upperBack"], 1,
   "Hüftbeugung (Hinge) mit der Kettlebell zwischen den Füßen – stärkt die gesamte hintere Kette.",
   "Füße hüftbreit, Kettlebell mittig zwischen den Fußgewölben. Hüfte nach hinten schieben, Schienbeine möglichst senkrecht, Griff mit beiden Händen.",
   "Hüfte nach vorn bringen und aufrichten, bis Körper gerade steht. Kontrolliert durch Hüftbeugung wieder absenken.",
   "Unten einatmen und Rumpf fest machen, oben ausatmen.",
   ["Bewegung aus der Hüfte, nicht aus dem Rücken", "Schulterblätter leicht nach hinten-unten ziehen", "Kettlebell nah am Körper", "Oben Gesäß anspannen, nicht ins Hohlkreuz lehnen"],
   ["Rundrücken beim Anheben", "Squat statt Hinge – Knie wandern weit nach vorn", "Überstrecken in der Endposition", "Ruckartiges Anheben"],
   ["Neutrale Wirbelsäule hat Vorrang vor Gewicht", "Bei Rückenbeschwerden mit leichter Kettlebell oder erhöhter Ablage beginnen"],
   ["lumbarSpine", "hip"], ["hinge"], ("kettlebell", "heavy", None), (2, R, 10, 75, False),
   ["kb_suitcase_deadlift", "bw_hip_hinge_drill", "kb_glute_bridge"], "hinge",
   regression="bw_hip_hinge_drill", progression="kb_romanian_deadlift")

ex("kb_suitcase_deadlift", "Kettlebell Suitcase Kreuzheben", "Kettlebell Suitcase Deadlift", "kettlebell", KB,
   ["glutes", "hamstrings", "obliques"], ["forearms", "core", "quadriceps"], 2,
   "Einseitiges Kreuzheben mit der Kettlebell neben dem Fuß – trainiert Hinge und seitliche Rumpfstabilität.",
   "Füße hüftbreit, Kettlebell seitlich neben einem Fuß.",
   "Hüfte beugen, Kettlebell greifen und aufrichten, ohne dass sich der Oberkörper zur Seite neigt.",
   "Unten einatmen, beim Aufrichten ausatmen.",
   ["Schultern bleiben waagerecht", "Freier Arm locker, Rumpf gegen seitliches Abkippen spannen", "Hüfte führt die Bewegung"],
   ["Seitliches Abknicken", "Rundrücken", "Kettlebell schwingt"],
   ["Mit der leichteren Kettlebell beginnen", "Bei Beschwerden der Lendenwirbelsäule nur schmerzfrei ausführen"],
   ["lumbarSpine", "hip"], ["hinge", "antiRotation"], ("kettlebell", "medium", None), (2, R, 8, 60, True),
   ["kb_deadlift", "kb_suitcase_carry"], "hinge")

ex("kb_romanian_deadlift", "Kettlebell Rumänisches Kreuzheben", "Kettlebell Romanian Deadlift", "kettlebell", KB,
   ["hamstrings", "glutes"], ["lowerBack", "forearms"], 2,
   "Kreuzheben mit nahezu gestreckten Beinen aus dem Stand – Fokus auf die hintere Oberschenkelmuskulatur.",
   "Aufrechter Stand, Kettlebell mit beiden Händen vor den Oberschenkeln, Knie leicht gebeugt.",
   "Hüfte nach hinten schieben, Kettlebell nah an den Beinen bis etwa Schienbeinmitte senken, dann Hüfte wieder nach vorn bringen.",
   "Beim Absenken einatmen, beim Aufrichten ausatmen.",
   ["Kniewinkel bleibt nahezu konstant", "Dehnung hinten im Oberschenkel spüren", "Rücken lang"],
   ["Zu tiefes Absenken mit Rundrücken", "Knie strecken ganz durch", "Gewicht auf den Zehen"],
   ["Bewegungsumfang an die Beweglichkeit der Oberschenkelrückseite anpassen"],
   ["lumbarSpine", "hip"], ["hinge"], ("kettlebell", "heavy", None), (2, R, 10, 75, False),
   ["kb_deadlift", "trx_hamstring_curl"], "hinge", regression="kb_deadlift")

ex("kb_swing", "Kettlebell Swing (beidarmig)", "Two-Hand Kettlebell Swing", "kettlebell", KB,
   ["glutes", "hamstrings"], ["core", "forearms", "upperBack", "cardiovascular"], 2,
   "Explosive Hüftstreckung mit schwingender Kettlebell – Kraftausdauer und Herz-Kreislauf. Nur bei sicherer Hinge-Technik.",
   "Kettlebell ca. 30 cm vor den Füßen, Hüfte gebeugt, Griff mit beiden Händen, Rücken neutral.",
   "Kettlebell zwischen die Oberschenkel zurückschwingen (Hike), dann Hüfte kräftig strecken – die Kettlebell schwebt bis etwa Brusthöhe. Arme führen nur.",
   "Beim Zurückschwingen einatmen, bei der Hüftstreckung kurz und kräftig ausatmen.",
   ["Kraft kommt aus der Hüfte, nicht aus den Armen", "Oben: Körper bildet eine Linie, Gesäß fest", "Kettlebell nicht über Brusthöhe", "Unterarme berühren beim Rückschwung die Oberschenkel"],
   ["Kniebeuge statt Hüftbeugung", "Mit den Armen heben", "Zurücklehnen in der Endposition", "Rundrücken im Rückschwung"],
   ["Nur einsetzen, wenn Kreuzheben technisch sicher sitzt (Technikbestätigung im Profil)", "Bei Beschwerden der Lendenwirbelsäule oder kardiovaskulären Einschränkungen durch Kreuzheben ersetzen", "Freien Raum vor und hinter dem Körper sicherstellen", "Satz beenden, sobald die Technik nachlässt"],
   ["lumbarSpine", "hip", "shoulder"], ["hinge", "ballistic", "cardioDemand"], ("kettlebell", "medium", None), (2, R, 12, 75, False),
   ["kb_deadlift", "kb_glute_bridge", "trx_squat_to_row"], "swing", regression="kb_deadlift", technique_check=True)

ex("kb_halo", "Kettlebell Halo", "Kettlebell Halo", "kettlebell", KB,
   ["shoulders", "core"], ["upperBack", "triceps", "rotatorCuff"], 1,
   "Langsames Kreisen der Kettlebell um den Kopf – Schulterbeweglichkeit und Rumpfspannung.",
   "Aufrechter Stand oder Halbkniestand, Kettlebell kopfüber an den Hörnern vor der Brust.",
   "Kettlebell eng um den Kopf führen: an einem Ohr vorbei, hinter dem Kopf, am anderen Ohr zurück. Richtung wechseln.",
   "Ruhig und gleichmäßig weiteratmen.",
   ["Langsam und kontrolliert", "Rumpf fest, kein Hohlkreuz", "Kopf bleibt ruhig, die Kettlebell bewegt sich"],
   ["Zu schweres Gewicht", "Ausweichen ins Hohlkreuz", "Kopf weicht der Kettlebell aus"],
   ["Nur leichte Kettlebell (8 kg)", "Bei Schulter- oder Nackenbeschwerden Radius verkleinern oder weglassen"],
   ["shoulder", "cervicalSpine"], ["rotation"], ("kettlebell", "light", None), (2, R, 5, 45, True),
   ["mob_wall_slide", "trx_y_raise"], "halo")

ex("kb_floor_press", "Kettlebell Bodendrücken", "Kettlebell Floor Press", "kettlebell", KB,
   ["chest", "triceps"], ["shoulders", "core"], 1,
   "Drücken in Rückenlage – der Boden begrenzt den Bewegungsumfang und schont die Schulter.",
   "Rückenlage, Knie gebeugt, Kettlebell im Rack: Griff in der Handfläche, Unterarm senkrecht, Oberarm ca. 45° vom Körper.",
   "Kettlebell senkrecht nach oben drücken, kontrolliert absenken, bis der Oberarm den Boden berührt.",
   "Beim Drücken ausatmen, beim Absenken einatmen.",
   ["Handgelenk gerade", "Oberarm im 45°-Winkel, nicht abgespreizt", "Oberarm am Boden kurz ablegen, nicht aufprallen"],
   ["Abgeknicktes Handgelenk", "Ellenbogen 90° abgespreizt", "Kettlebell schwankt über dem Gesicht"],
   ["Kettlebell zum Ablegen sicher zur Seite rollen", "Bei Schulterschmerz Bewegungsumfang verkleinern"],
   ["shoulder", "elbow", "wrist"], ["push", "floor"], ("kettlebell", "medium", None), (2, R, 8, 60, True),
   ["trx_chest_press", "bw_incline_push_up"], "floor_press")

ex("kb_single_arm_row", "Kettlebell Rudern einarmig (gestützt)", "Supported Single-Arm Kettlebell Row", "kettlebell", KB,
   ["upperBack", "lats"], ["biceps", "rearDelts", "core"], 1,
   "Einarmiges Rudern mit Abstützung – stärkt den oberen Rücken bei entlasteter Lendenwirbelsäule.",
   "Schrittstellung, freie Hand stützt sich auf Knie oder Bank, Rücken lang, Kettlebell hängt unter der Schulter.",
   "Ellenbogen nah am Körper nach hinten zur Hüfte ziehen, kurz halten, kontrolliert absenken.",
   "Beim Ziehen ausatmen, beim Absenken einatmen.",
   ["Schulterblatt zuerst nach hinten-unten", "Oberkörper dreht nicht auf", "Nacken lang"],
   ["Schwung aus dem Oberkörper", "Schulter zieht zum Ohr", "Rundrücken"],
   ["Abstützung entlastet den Rücken – nicht weglassen"],
   ["shoulder", "lumbarSpine"], ["pull", "hinge"], ("kettlebell", "heavy", None), (2, R, 10, 60, True),
   ["trx_row", "trx_single_arm_rotational_row"], "row_kb")

ex("kb_suitcase_carry", "Kettlebell Suitcase Carry", "Kettlebell Suitcase Carry", "kettlebell", KB,
   ["obliques", "forearms"], ["core", "glutes", "upperBack", "shoulders"], 1,
   "Gehen mit einer Kettlebell in einer Hand – seitliche Rumpfstabilität, Griffkraft und Haltung.",
   "Aufrecht stehen, Kettlebell seitlich in einer Hand, Schultern waagerecht.",
   "Mit ruhigen Schritten gehen (Strecke oder Zeit), dann Seite wechseln.",
   "Gleichmäßig atmen, Rumpf leicht gespannt halten.",
   ["Groß machen, Schultern waagerecht", "Nicht zur Kettlebell-Seite neigen", "Kontrollierte Schritte"],
   ["Seitliches Abkippen", "Schulter zieht nach oben", "Zu schnelles Gehen"],
   ["Kettlebell zum Abstellen über Hüftbeugung absetzen, nicht fallen lassen"],
   ["lumbarSpine", "shoulder"], ["carry", "antiRotation"], ("kettlebell", "heavy", None), (2, S, 30, 45, True),
   ["kb_farmers_carry", "side_plank"], "carry")

ex("kb_farmers_carry", "Farmer's Walk (zwei Kettlebells)", "Farmer's Carry", "kettlebell", KB,
   ["forearms", "upperBack"], ["core", "glutes", "calves"], 1,
   "Gehen mit je einer Kettlebell pro Hand – Griffkraft, Haltung und Ganzkörperspannung.",
   "Aufrecht stehen, je eine Kettlebell seitlich in jeder Hand.",
   "Ruhige, kontrollierte Schritte über Strecke oder Zeit.",
   "Gleichmäßig atmen.",
   ["Brust offen, Schultern tief", "Blick geradeaus", "Kurze, ruhige Schritte"],
   ["Vorgebeugter Oberkörper", "Hochgezogene Schultern"],
   ["Beide Kettlebells nacheinander über Hüftbeugung aufnehmen"],
   ["shoulder", "lumbarSpine"], ["carry"], ("kettlebell", "medium", None), (2, S, 40, 45, False),
   ["kb_suitcase_carry"], "carry")

ex("kb_goblet_reverse_lunge", "Goblet Ausfallschritt rückwärts", "Goblet Reverse Lunge", "kettlebell", KB,
   ["quadriceps", "glutes"], ["adductors", "core", "calves"], 2,
   "Ausfallschritt nach hinten mit Kettlebell vor der Brust – einbeinige Kraft und Gleichgewicht.",
   "Aufrechter Stand, Kettlebell im Goblet-Griff vor der Brust.",
   "Einen Schritt nach hinten setzen, hinteres Knie kontrolliert Richtung Boden senken, über das vordere Bein zurück in den Stand.",
   "Beim Absenken einatmen, beim Aufrichten ausatmen.",
   ["Vorderes Knie zeigt über den Fuß", "Oberkörper aufrecht", "Hinteres Knie setzt nicht auf"],
   ["Zu kurzer Schritt", "Knie fällt nach innen", "Wackeln – Tempo zu hoch"],
   ["Gleichgewicht vor Gewicht – zuerst TRX-gestützt üben"],
   ["knee", "hip"], ["lunge", "balance"], ("kettlebell", "light", None), (2, R, 8, 60, True),
   ["trx_assisted_reverse_lunge", "bw_split_squat"], "lunge", regression="trx_assisted_reverse_lunge")

ex("kb_half_kneeling_press", "Kettlebell Schulterdrücken im Halbkniestand", "Half-Kneeling Kettlebell Press", "kettlebell", KB,
   ["shoulders", "triceps"], ["core", "upperBack", "glutes"], 3,
   "Kontrolliertes einarmiges Überkopfdrücken – nur bei freier, schmerzfreier Schulterbeweglichkeit.",
   "Halbkniestand, Kettlebell im Rack auf der Seite des aufgestellten Knies gegenüber.",
   "Kettlebell langsam senkrecht über die Schulter drücken, Arm neben dem Ohr, kontrolliert zurück ins Rack.",
   "Vor dem Drücken einatmen, beim Drücken ausatmen.",
   ["Rippen unten, kein Hohlkreuz", "Gesäß des knienden Beins angespannt", "Langsames Tempo"],
   ["Ausweichen ins Hohlkreuz", "Seitliches Wegknicken", "Zu schweres Gewicht"],
   ["Überkopfbelastung: wird im Plan standardmäßig NICHT verwendet", "Nur mit vollem, schmerzfreiem Schulterbewegungsumfang und Freigabe im Profil", "Bei Schulter- oder HWS-Beschwerden meiden"],
   ["shoulder", "cervicalSpine", "lumbarSpine"], ["overhead", "push"], ("kettlebell", "light", None), (2, R, 6, 75, True),
   ["kb_floor_press", "trx_y_raise"], "overhead_press", regression="kb_floor_press")

ex("kb_glute_bridge", "Kettlebell Hüftheben", "Kettlebell Glute Bridge", "kettlebell", KB,
   ["glutes"], ["hamstrings", "core"], 1,
   "Hüftheben in Rückenlage mit Kettlebell auf dem Becken – rückenschonende Gesäßkräftigung.",
   "Rückenlage, Knie gebeugt, Füße hüftbreit, Kettlebell mit beiden Händen auf dem Becken.",
   "Becken anheben, bis Knie, Hüfte und Schultern eine Linie bilden, kurz halten, kontrolliert absenken.",
   "Beim Anheben ausatmen, beim Absenken einatmen.",
   ["Gesäß aktiv anspannen", "Rippen bleiben unten", "Druck über die Fersen"],
   ["Hohlkreuz statt Hüftstreckung", "Knie fallen auseinander"],
   ["Kettlebell sicher festhalten"],
   ["hip"], ["hinge", "floor"], ("kettlebell", "heavy", None), (2, R, 12, 45, False),
   ["bw_glute_bridge", "trx_hip_press"], "bridge", regression="bw_glute_bridge")

ex("kb_around_the_body", "Kettlebell um den Körper", "Kettlebell Around the Body", "kettlebell", KB,
   ["core", "forearms"], ["shoulders", "obliques"], 1,
   "Kettlebell auf Hüfthöhe um den Körper weiterreichen – Aktivierung von Rumpf und Griff im Aufwärmen.",
   "Aufrechter, hüftbreiter Stand, Kettlebell in einer Hand vor dem Körper.",
   "Kettlebell vor dem Körper in die andere Hand übergeben, hinter dem Rücken wieder zurück. Nach einigen Runden Richtung wechseln.",
   "Ruhig weiteratmen.",
   ["Rumpf bleibt stabil, Hüfte dreht nicht mit", "Sichere Übergabe"],
   ["Hüfte schwingt mit", "Zu schnelles Tempo"],
   ["Leichte Kettlebell verwenden"],
   ["wrist"], ["antiRotation"], ("kettlebell", "light", None), (1, R, 8, 30, False),
   ["warm_hip_circles"], "carry")

# ───────────────────────── TRX ─────────────────────────
ex("trx_row", "TRX Rudern", "TRX Row", "trx", TRX,
   ["upperBack", "lats"], ["biceps", "rearDelts", "core"], 1,
   "Ziehen des Körpers zu den Griffen – Grundübung für Rücken und Haltung.",
   "Mit Blick zum Ankerpunkt stehen, Griffe in den Händen, Arme gestreckt, Körper als gerade Linie nach hinten gelehnt.",
   "Brust zu den Händen ziehen, Ellenbogen nah am Körper, kontrolliert zurück in die Ausgangsposition.",
   "Beim Heranziehen ausatmen, beim Zurücklassen einatmen.",
   ["Körper bleibt eine Linie – Gesäß fest", "Schulterblätter zuerst zusammen", "Langsames Ablassen"],
   ["Hüfte knickt ein", "Schultern ziehen zu den Ohren", "Schwung"],
   ["Intensität über den Körperwinkel steuern: Füße weiter vor = schwerer"],
   ["shoulder", "elbow"], ["pull"], ("trx", None, "Körperwinkel ca. 45°; steiler = leichter"), (2, R, 10, 60, False),
   ["kb_single_arm_row", "trx_face_pull"], "row_trx")

ex("trx_chest_press", "TRX Brustdrücken", "TRX Chest Press", "trx", TRX,
   ["chest", "triceps"], ["shoulders", "core"], 1,
   "Liegestütz-Variante im Stand an den Schlingen – Brust, Arme und Rumpfspannung.",
   "Mit dem Rücken zum Ankerpunkt, Griffe auf Brusthöhe, Arme gestreckt, Körper nach vorn gelehnt.",
   "Ellenbogen beugen und Brust kontrolliert zwischen die Hände senken, dann wieder wegdrücken.",
   "Beim Absenken einatmen, beim Drücken ausatmen.",
   ["Körper bleibt eine Linie", "Ellenbogen ca. 45° vom Körper", "Schlingen dürfen die Arme nicht berühren"],
   ["Durchhängende Hüfte", "Zu tiefes Absenken mit Schulterschmerz", "Ungleiche Schlingenspannung"],
   ["Bewegungsumfang schmerzfrei halten – besonders bei Schulterproblemen"],
   ["shoulder", "elbow", "wrist"], ["push"], ("trx", None, "Körperwinkel ca. 60°; aufrechter = leichter"), (2, R, 10, 60, False),
   ["kb_floor_press", "bw_incline_push_up"], "press_trx")

ex("trx_assisted_squat", "TRX-gestützte Kniebeuge", "TRX Assisted Squat", "trx", TRX,
   ["quadriceps", "glutes"], ["adductors", "core"], 1,
   "Kniebeuge mit Halt an den Griffen – ideal zum Erlernen von Tiefe und Haltung.",
   "Mit Blick zum Ankerpunkt, Griffe vor der Brust, leichte Spannung in den Schlingen.",
   "Hüfte nach hinten-unten senken, Arme strecken sich leicht nach vorn, aus den Beinen aufstehen.",
   "Beim Absenken einatmen, beim Aufrichten ausatmen.",
   ["Nur so viel Zug wie nötig", "Brust aufrecht", "Knie über den Fußspitzen"],
   ["Mit den Armen hochziehen", "Fersen heben ab"],
   ["Gute Option bei eingeschränkter Knie- oder Hüftbeweglichkeit"],
   ["knee", "hip"], ["squat"], ("trx", None, None), (2, R, 12, 45, False),
   ["bw_squat", "kb_goblet_squat"], "squat", progression="kb_goblet_squat")

ex("trx_assisted_reverse_lunge", "TRX-gestützter Ausfallschritt rückwärts", "TRX Assisted Reverse Lunge", "trx", TRX,
   ["quadriceps", "glutes"], ["hipFlexors", "core", "calves"], 1,
   "Ausfallschritt nach hinten mit Halt an den Griffen – Beinkraft, Hüftmobilität und Gleichgewicht.",
   "Mit Blick zum Ankerpunkt, Griffe vor dem Körper, aufrechter Stand.",
   "Ein Bein nach hinten setzen, hinteres Knie Richtung Boden senken, über das vordere Bein zurück.",
   "Beim Absenken einatmen, beim Aufrichten ausatmen.",
   ["Gewicht auf dem vorderen Bein", "Oberkörper aufrecht", "Griffe nur zur Balance"],
   ["Knie fällt nach innen", "Zu kurzer Schritt"],
   ["Bei Knieschmerzen Schritttiefe verringern"],
   ["knee", "hip"], ["lunge", "balance"], ("trx", None, None), (2, R, 8, 45, True),
   ["bw_split_squat", "trx_assisted_squat"], "lunge", progression="kb_goblet_reverse_lunge")

ex("trx_squat_to_row", "TRX Kniebeuge mit Rudern", "TRX Squat to Row", "trx", TRX,
   ["quadriceps", "glutes", "upperBack"], ["lats", "biceps", "core", "cardiovascular"], 1,
   "Kombination aus Kniebeuge und Rudern – Ganzkörperkoordination mit moderater Herz-Kreislauf-Belastung.",
   "Mit Blick zum Ankerpunkt, Arme gestreckt, leichte Rücklage.",
   "In die Kniebeuge gehen, dabei Arme strecken; beim Aufstehen fließend in eine Ruderbewegung übergehen.",
   "Beim Absenken einatmen, beim Aufstehen und Rudern ausatmen.",
   ["Fließende Bewegung", "Schlingen bleiben gespannt", "Rücken neutral"],
   ["Hüfte knickt beim Rudern ein", "Hektisches Tempo"],
   ["Tempo moderat halten"],
   ["knee", "hip", "shoulder"], ["squat", "pull", "cardioDemand"], ("trx", None, "Körperwinkel ca. 30°"), (2, R, 10, 45, False),
   ["trx_row", "trx_assisted_squat"], "squat_row")

ex("trx_face_pull", "TRX Face Pull", "TRX Face Pull", "trx", TRX,
   ["rearDelts", "upperBack"], ["rotatorCuff", "biceps"], 1,
   "Ziehen der Griffe Richtung Stirn mit nach außen gedrehten Armen – Schultergesundheit und Haltung.",
   "Mit Blick zum Ankerpunkt, Arme gestreckt auf Schulterhöhe, Handflächen zueinander oder nach unten.",
   "Hände seitlich am Kopf vorbei ziehen, Ellenbogen hoch und weit, kontrolliert zurück.",
   "Beim Ziehen ausatmen.",
   ["Ellenbogen auf Schulterhöhe", "Schulterblätter nach hinten-unten", "Nacken lang"],
   ["Schultern ziehen hoch", "Kopf schiebt nach vorn"],
   ["Kleinerer Winkel bei empfindlicher Schulter"],
   ["shoulder", "cervicalSpine"], ["pull"], ("trx", None, "Körperwinkel steil, ca. 20–30°"), (2, R, 12, 45, False),
   ["trx_row", "trx_y_raise"], "row_trx")

ex("trx_y_raise", "TRX Y-Heben", "TRX Y Fly", "trx", TRX,
   ["rearDelts", "upperBack"], ["rotatorCuff", "core"], 2,
   "Arme in Y-Form nach oben-außen führen – Kräftigung der unteren Schulterblattmuskulatur.",
   "Mit Blick zum Ankerpunkt, Arme gestreckt vor dem Körper, leichte Rücklage.",
   "Gestreckte Arme schräg nach oben in eine Y-Position führen, Körper richtet sich dabei auf.",
   "Beim Heben ausatmen.",
   ["Sehr steiler Körperwinkel genügt", "Daumen zeigen nach oben", "Kein Hohlkreuz"],
   ["Zu flacher Winkel", "Schultern ziehen zu den Ohren"],
   ["Arme oberhalb der Schulter: bei Schulterbeschwerden durch Face Pull ersetzen"],
   ["shoulder"], ["pull"], ("trx", None, "Nahezu aufrecht, ca. 15°"), (2, R, 10, 45, False),
   ["trx_face_pull", "mob_wall_slide"], "y_raise")

ex("trx_biceps_curl", "TRX Bizepscurl", "TRX Biceps Curl", "trx", TRX,
   ["biceps"], ["forearms", "core"], 1,
   "Beugen der Arme mit fixierten Ellenbogen – Armkraft für Griff und Schlagbewegungen.",
   "Mit Blick zum Ankerpunkt, Arme gestreckt auf Schulterhöhe, Handflächen oben.",
   "Hände zur Stirn beugen, Ellenbogen bleiben auf Schulterhöhe, kontrolliert strecken.",
   "Beim Beugen ausatmen.",
   ["Ellenbogen bleiben ortsfest", "Körperlinie halten"],
   ["Ellenbogen sinken ab", "Hüfte knickt ein"],
   ["Bei Ellenbogenbeschwerden Winkel steiler wählen"],
   ["elbow"], ["pull"], ("trx", None, "Körperwinkel ca. 30°"), (2, R, 10, 45, False),
   ["trx_row"], "curl_trx")

ex("trx_hamstring_curl", "TRX Beinbeuger", "TRX Hamstring Curl", "trx", TRX,
   ["hamstrings", "glutes"], ["core", "calves"], 2,
   "In Rückenlage die Fersen in den Schlingen zum Gesäß ziehen – Oberschenkelrückseite und Gesäß.",
   "Rückenlage, Fersen in den Fußschlaufen unter dem Ankerpunkt, Arme seitlich am Boden.",
   "Becken anheben und Fersen zum Gesäß ziehen, kontrolliert wieder strecken.",
   "Beim Heranziehen ausatmen.",
   ["Becken bleibt oben", "Langsames Strecken"],
   ["Becken sinkt ab", "Hohlkreuz"],
   ["Bei Krampfneigung Bewegungsumfang verkürzen"],
   ["knee", "lumbarSpine"], ["floor", "hinge"], ("trx", None, "Schlaufen ca. 20 cm über dem Boden"), (2, R, 8, 45, False),
   ["kb_glute_bridge", "trx_hip_press"], "hamstring_curl", regression="trx_hip_press")

ex("trx_hip_press", "TRX Hüftheben", "TRX Hip Press", "trx", TRX,
   ["glutes", "hamstrings"], ["core"], 1,
   "Hüftheben mit Fersen in den Schlaufen – instabile Variante der Glute Bridge.",
   "Rückenlage, Fersen in den Fußschlaufen, Knie ca. 90° gebeugt.",
   "Becken anheben, bis Knie, Hüfte und Schultern eine Linie bilden, kontrolliert absenken.",
   "Beim Anheben ausatmen.",
   ["Gesäß anspannen", "Schlingen ruhig halten"],
   ["Hohlkreuz", "Pendeln der Schlingen"],
   ["Sicher aus den Schlaufen aussteigen"],
   ["hip"], ["floor", "hinge"], ("trx", None, None), (2, R, 10, 45, False),
   ["bw_glute_bridge", "kb_glute_bridge"], "bridge", progression="trx_hamstring_curl")

ex("trx_pallof_press", "TRX Pallof Press", "TRX Pallof Press", "trx", TRX,
   ["obliques", "core"], ["shoulders", "glutes"], 1,
   "Anti-Rotationsübung: Griffe vor der Brust wegdrücken, ohne dass der Rumpf aufdreht – Basis für Golf und Tennis.",
   "Seitlich zum Ankerpunkt stehen, beide Hände am Griff vor der Brust, Schlinge gespannt.",
   "Arme langsam nach vorn strecken, 2 Sekunden halten, zurückführen. Rumpf widersteht dem Zug zur Seite.",
   "Beim Wegdrücken ausatmen.",
   ["Hüfte und Schultern zeigen nach vorn", "Je weiter vom Anker, desto schwerer"],
   ["Rumpf dreht zum Ankerpunkt", "Hohlkreuz"],
   ["Schonende Rumpfübung, auch bei Rückenbeschwerden meist gut verträglich"],
   [], ["antiRotation", "isometric"], ("trx", None, "Seitlicher Abstand bestimmt die Last"), (2, R, 8, 30, True),
   ["side_plank", "bird_dog"], "pallof")

ex("trx_single_arm_rotational_row", "TRX einarmiges Rudern mit Rotation", "TRX Single-Arm Rotational Row", "trx", TRX,
   ["upperBack", "obliques"], ["lats", "biceps", "core"], 2,
   "Einarmiges Rudern mit kontrollierter Rumpfrotation – Rotationskraft für Golf- und Tennisschwung.",
   "Mit Blick zum Ankerpunkt, ein Griff in einer Hand, freier Arm zeigt zum Anker, Körper leicht zurückgelehnt.",
   "Ziehen und dabei Oberkörper zur Seite des Zugarms öffnen, freier Arm zeigt am Ende nach hinten. Kontrolliert zurück.",
   "Beim Ziehen ausatmen.",
   ["Rotation aus der Brustwirbelsäule", "Hüfte bleibt stabil", "Kontrolliertes Tempo"],
   ["Rotation aus der Lendenwirbelsäule", "Ruckartige Bewegung"],
   ["Bei Rückenbeschwerden ohne Rotation ausführen"],
   ["shoulder", "thoracicSpine"], ["pull", "rotation"], ("trx", None, "Körperwinkel ca. 30°"), (2, R, 8, 45, True),
   ["trx_row", "kb_single_arm_row"], "row_trx")

ex("trx_assisted_lateral_lunge", "TRX-gestützter Seitausfallschritt", "TRX Assisted Lateral Lunge", "trx", TRX,
   ["adductors", "glutes", "quadriceps"], ["core"], 2,
   "Seitlicher Ausfallschritt mit Halt – Hüftmobilität und seitliche Beinkraft (Tennis!).",
   "Mit Blick zum Ankerpunkt, Griffe vor dem Körper, breiter Stand.",
   "Hüfte zu einer Seite nach hinten schieben, ein Knie beugen, anderes Bein bleibt gestreckt; zurück zur Mitte.",
   "Beim Absenken einatmen.",
   ["Fußsohlen bleiben am Boden", "Knie über Fuß"],
   ["Knie schiebt weit vor die Fußspitze", "Rundrücken"],
   ["Bewegungsumfang an Hüft- und Leistenbeweglichkeit anpassen"],
   ["knee", "hip"], ["lunge", "balance"], ("trx", None, None), (2, R, 8, 45, True),
   ["trx_assisted_reverse_lunge"], "lateral_lunge")

ex("trx_deep_squat_hold", "TRX tiefe Hocke (Mobilität)", "TRX Deep Squat Hold", "mobility", TRX,
   ["hipFlexors", "adductors"], ["calves", "lowerBack"], 1,
   "Gehaltene tiefe Hocke mit Halt an den Griffen – Mobilität für Hüfte und Sprunggelenk.",
   "Mit Blick zum Ankerpunkt, Griffe vor dem Körper.",
   "In eine tiefe Hocke sinken, Arme halten das Gleichgewicht, ruhig atmen und Position halten.",
   "Tief und ruhig atmen.",
   ["Fersen möglichst am Boden", "Knie nach außen drücken", "Brust aufrecht"],
   ["Zu viel Zug an den Armen", "Schmerzhafte Kniebeugung"],
   ["Nur schmerzfreie Tiefe – bei Kniebeschwerden weglassen"],
   ["knee", "hip", "ankle"], ["stretch", "squat"], ("trx", None, None), (1, S, 30, 15, False),
   ["mob_hip_90_90"], "deep_squat")

ex("trx_chest_stretch", "TRX Brustöffner", "TRX Chest Opener", "mobility", TRX,
   ["chest", "shoulders"], ["biceps"], 1,
   "Dehnung der Brust- und vorderen Schultermuskulatur in den Schlingen.",
   "Mit dem Rücken zum Ankerpunkt, Arme seitlich in den Griffen, kleiner Schritt nach vorn.",
   "Körper langsam nach vorn lehnen, bis eine Dehnung in der Brust spürbar ist, halten.",
   "Ruhig in die Dehnung atmen.",
   ["Arme auf oder leicht unter Schulterhöhe", "Sanfte Dehnung"],
   ["Zu starke Dehnung", "Hohlkreuz"],
   ["Bei Schulterinstabilität nur sehr sanft"],
   ["shoulder"], ["stretch"], ("trx", None, None), (1, S, 30, 15, False),
   ["mob_open_book"], "chest_stretch")

ex("trx_hip_hinge_mobility", "TRX Hüftbeuge-Dehnung", "TRX Hip Hinge Stretch", "mobility", TRX,
   ["hamstrings", "lats"], ["lowerBack", "shoulders"], 1,
   "Mit gestreckten Armen in den Schlingen in die Hüftbeugung lehnen – Rückseite und Schultern öffnen.",
   "Mit Blick zum Ankerpunkt, Arme gestreckt, Griffe auf Hüfthöhe.",
   "Hüfte nach hinten schieben, Oberkörper sinkt zwischen die Arme, Rücken lang.",
   "Ruhig atmen, beim Ausatmen etwas tiefer sinken.",
   ["Knie leicht gebeugt", "Wirbelsäule lang"],
   ["Rundrücken"],
   [],
   ["hip", "shoulder"], ["stretch", "hinge"], ("trx", None, None), (1, S, 30, 15, False),
   ["cool_supine_hamstring_stretch"], "hinge")

# ───────────────────────── EIGENGEWICHT ─────────────────────────
ex("bw_squat", "Kniebeuge (Eigengewicht)", "Bodyweight Squat", "bodyweight", BW,
   ["quadriceps", "glutes"], ["adductors", "core"], 1,
   "Kniebeuge ohne Zusatzgewicht – Technikgrundlage und Aufwärmübung.",
   "Hüftbreiter Stand, Arme vor dem Körper.",
   "Hüfte nach hinten-unten senken, aus dem ganzen Fuß aufrichten.",
   "Beim Absenken einatmen, beim Aufrichten ausatmen.",
   ["Knie über den Fußspitzen", "Brust aufrecht"],
   ["Fersen heben ab", "Knie fallen nach innen"],
   [],
   ["knee", "hip"], ["squat"], ("bodyweight", None, None), (2, R, 12, 45, False),
   ["trx_assisted_squat"], "squat", progression="kb_goblet_squat")

ex("bw_incline_push_up", "Erhöhter Liegestütz", "Incline Push-Up", "bodyweight", BW + ["wall"],
   ["chest", "triceps"], ["shoulders", "core"], 1,
   "Liegestütz mit den Händen auf einer Erhöhung (Bank, Tisch, Wand) – dosierbare Drückübung.",
   "Hände schulterbreit auf einer stabilen Erhöhung, Körper gerade Linie.",
   "Brust kontrolliert zur Kante senken, wieder wegdrücken.",
   "Beim Absenken einatmen, beim Drücken ausatmen.",
   ["Höhere Ablage = leichter", "Körper als Brett"],
   ["Hüfte hängt durch", "Ellenbogen weit abgespreizt"],
   ["Stabile, rutschfeste Ablage wählen"],
   ["shoulder", "wrist", "elbow"], ["push"], ("bodyweight", None, None), (2, R, 10, 60, False),
   ["trx_chest_press", "kb_floor_press"], "push_up")

ex("bw_glute_bridge", "Hüftheben (Eigengewicht)", "Glute Bridge", "bodyweight", MAT,
   ["glutes"], ["hamstrings", "core"], 1,
   "Hüftheben in Rückenlage – aktiviert das Gesäß und entlastet den unteren Rücken.",
   "Rückenlage, Knie gebeugt, Füße hüftbreit, Arme neben dem Körper.",
   "Becken anheben bis zur Linie Knie–Hüfte–Schulter, kurz halten, absenken.",
   "Beim Anheben ausatmen.",
   ["Gesäß aktiv", "Kein Hohlkreuz"],
   ["Becken kippt", "Druck auf den Zehen"],
   [],
   ["hip"], ["hinge", "floor"], ("bodyweight", None, None), (2, R, 12, 30, False),
   ["kb_glute_bridge", "trx_hip_press"], "bridge", progression="kb_glute_bridge")

ex("bw_split_squat", "Split Squat", "Split Squat", "bodyweight", BW,
   ["quadriceps", "glutes"], ["hipFlexors", "core"], 1,
   "Statische Ausfallschrittposition, auf und ab – einbeinige Kraft ohne Schrittbewegung.",
   "Schrittstellung, hinterer Fuß auf dem Fußballen, Oberkörper aufrecht.",
   "Senkrecht nach unten sinken, bis das hintere Knie knapp über dem Boden ist, wieder hochdrücken.",
   "Beim Absenken einatmen.",
   ["Senkrechte Bewegung", "Vorderes Knie über dem Fuß"],
   ["Zu enge Spur – Wackeln"],
   ["Bei Bedarf an Wand oder TRX festhalten"],
   ["knee", "hip"], ["lunge", "balance"], ("bodyweight", None, None), (2, R, 8, 45, True),
   ["trx_assisted_reverse_lunge"], "lunge")

ex("bw_single_leg_balance", "Einbeinstand mit Reichbewegung", "Single-Leg Balance Reach", "bodyweight", BW,
   ["glutes", "calves"], ["core", "hamstrings"], 1,
   "Einbeinstand mit kontrolliertem Vorneigen – Gleichgewicht und Fußstabilität.",
   "Aufrechter Stand auf einem Bein, Standknie leicht gebeugt.",
   "Oberkörper nach vorn neigen, freies Bein nach hinten strecken, zurück in den Stand.",
   "Ruhig weiteratmen.",
   ["Hüfte bleibt waagerecht", "Blick auf einen festen Punkt"],
   ["Becken dreht auf", "Hektisches Ausgleichen"],
   ["In Wandnähe üben, bei Unsicherheit festhalten"],
   ["ankle", "hip"], ["balance", "hinge"], ("bodyweight", None, None), (2, R, 6, 30, True),
   ["trx_assisted_reverse_lunge"], "balance")

ex("bw_calf_raise", "Wadenheben", "Calf Raise", "bodyweight", BW,
   ["calves"], ["ankle" if False else "core"], 1,
   "Fersenheben im Stand – Kräftigung der Waden und Sprunggelenkstabilität (Tennis: Antritte).",
   "Aufrechter Stand, ggf. eine Hand an der Wand.",
   "Langsam auf die Fußballen hochdrücken, oben kurz halten, langsam absenken.",
   "Gleichmäßig atmen.",
   ["Langsames Absenken", "Gewicht über den Großzehen"],
   ["Schnelles Wippen"],
   [],
   ["ankle"], ["balance"], ("bodyweight", None, None), (2, R, 15, 30, False),
   ["bw_single_leg_balance"], "calf_raise")

ex("bw_hip_hinge_drill", "Hüftbeuge-Technikübung", "Hip Hinge Drill", "warmup", BW + ["wall"],
   ["hamstrings", "glutes"], ["lowerBack"], 1,
   "Hüfte nach hinten zur Wand schieben – erlernt das Hinge-Muster für Kreuzheben und Swing.",
   "Ca. eine Fußlänge vor einer Wand stehen, Rücken zur Wand, Hände an den Leisten.",
   "Hüfte nach hinten schieben, bis das Gesäß die Wand berührt, Rücken bleibt lang; wieder aufrichten.",
   "Beim Vorbeugen einatmen.",
   ["Schienbeine bleiben senkrecht", "Hände spüren die Hüftfalte"],
   ["Knie beugen sich stark", "Rundrücken"],
   [],
   ["hip"], ["hinge"], ("bodyweight", None, None), (1, R, 10, 20, False),
   ["kb_deadlift"], "hinge")

# ───────────────────────── CORE ─────────────────────────
ex("bird_dog", "Bird Dog", "Bird Dog", "core", MAT,
   ["core", "glutes"], ["lowerBack", "shoulders"], 1,
   "Im Vierfüßlerstand diagonal Arm und Bein strecken – Rückenstabilität und Koordination.",
   "Vierfüßlerstand, Hände unter den Schultern, Knie unter der Hüfte, Rücken neutral.",
   "Einen Arm und das gegenüberliegende Bein lang strecken, 2 Sekunden halten, zurück, Seite wechseln.",
   "Beim Strecken ausatmen.",
   ["Becken bleibt waagerecht", "Lang machen statt hoch heben", "Langsam"],
   ["Hohlkreuz", "Becken kippt zur Seite"],
   ["Sehr rückenfreundlich – geeignet auch bei leichten LWS-Beschwerden"],
   [], ["balance", "floor", "antiRotation"], ("bodyweight", None, None), (2, R, 6, 30, True),
   ["dead_bug", "trx_pallof_press"], "bird_dog")

ex("dead_bug", "Dead Bug", "Dead Bug", "core", MAT,
   ["core"], ["hipFlexors", "shoulders"], 1,
   "In Rückenlage gegengleich Arm und Bein absenken – tiefe Rumpfmuskulatur.",
   "Rückenlage, Arme senkrecht nach oben, Hüfte und Knie 90° gebeugt.",
   "Einen Arm über Kopf und das gegenüberliegende Bein lang zum Boden führen, zurück, Seite wechseln.",
   "Beim Absenken ausatmen.",
   ["Unterer Rücken bleibt am Boden", "Langsam und kontrolliert"],
   ["Hohlkreuz", "Luft anhalten"],
   ["Bewegungsumfang verkleinern, wenn der Rücken abhebt"],
   [], ["floor", "antiRotation"], ("bodyweight", None, None), (2, R, 6, 30, True),
   ["bird_dog"], "dead_bug")

ex("front_plank", "Unterarmstütz", "Front Plank", "core", MAT,
   ["core"], ["shoulders", "glutes"], 1,
   "Halten des Körpers auf Unterarmen und Fußspitzen – Rumpfspannung.",
   "Unterarme unter den Schultern, Beine gestreckt, Körper gerade Linie.",
   "Position halten, Gesäß und Bauch fest.",
   "Ruhig weiteratmen – nicht pressen.",
   ["Körper wie ein Brett", "Ellenbogen unter den Schultern"],
   ["Hüfte hängt durch oder ragt hoch", "Pressatmung"],
   ["Bei Bluthochdruck auf ruhige Atmung achten, Halte kurz halten", "Variante auf den Knien möglich"],
   ["shoulder"], ["isometric", "floor"], ("bodyweight", None, None), (2, S, 30, 30, False),
   ["bear_hold", "dead_bug"], "plank")

ex("side_plank", "Seitstütz", "Side Plank", "core", MAT,
   ["obliques", "core"], ["glutes", "shoulders"], 2,
   "Seitlicher Unterarmstütz – seitliche Rumpfkette, wichtig für Rotationssportarten.",
   "Seitlage, Unterarm unter der Schulter, Beine gestreckt oder Knie gebeugt (leichter).",
   "Becken anheben, bis der Körper eine Linie bildet, halten. Seite wechseln.",
   "Ruhig weiteratmen.",
   ["Becken nicht nach hinten schieben", "Schulter weg vom Ohr"],
   ["Becken sinkt ab", "Oberkörper dreht ein"],
   ["Variante mit gebeugten Knien bei Schulterbeschwerden"],
   ["shoulder"], ["isometric", "floor", "antiRotation"], ("bodyweight", None, None), (2, S, 20, 30, True),
   ["trx_pallof_press", "kb_suitcase_carry"], "side_plank")

ex("mcgill_curl_up", "McGill Curl-up", "McGill Curl-Up", "core", MAT,
   ["core"], ["neck"], 1,
   "Rückenfreundliche Bauchübung mit minimaler Wirbelsäulenbeugung.",
   "Rückenlage, ein Bein gestreckt, ein Knie gebeugt, Hände unter dem unteren Rücken.",
   "Kopf und Schultern nur wenige Zentimeter anheben, Nacken bleibt neutral, 8–10 Sekunden halten.",
   "Während des Haltens ruhig atmen.",
   ["Kopf und Brust als Einheit heben", "Kinn nicht zur Brust ziehen"],
   ["Zu hohes Aufrollen", "Nacken zieht"],
   ["Bei HWS-Beschwerden weglassen oder Kopf ablegen und nur anspannen"],
   ["cervicalSpine"], ["floor", "isometric"], ("bodyweight", None, None), (2, R, 5, 30, False),
   ["dead_bug"], "curl_up")

ex("bear_hold", "Bärenstand", "Bear Hold", "core", MAT,
   ["core", "shoulders"], ["quadriceps"], 1,
   "Aus dem Vierfüßlerstand Knie wenige Zentimeter anheben und halten.",
   "Vierfüßlerstand, Hände unter Schultern, Knie unter Hüfte, Zehen aufgestellt.",
   "Knie 2–5 cm anheben, Rücken bleibt flach, halten.",
   "Ruhig weiteratmen.",
   ["Rücken waagerecht", "Hände drücken den Boden weg"],
   ["Gesäß ragt hoch", "Luft anhalten"],
   ["Bei Handgelenkbeschwerden auf Fäusten oder Unterarmen"],
   ["wrist", "shoulder"], ["isometric", "floor"], ("bodyweight", None, None), (2, S, 20, 30, False),
   ["front_plank", "bird_dog"], "bear")

# ───────────────────────── MOBILITÄT ─────────────────────────
ex("mob_cat_cow", "Katze-Kuh", "Cat-Cow", "mobility", MAT,
   ["lowerBack", "upperBack"], ["core"], 1,
   "Wechsel zwischen Rundrücken und sanftem Hohlkreuz im Vierfüßlerstand – Mobilisation der Wirbelsäule.",
   "Vierfüßlerstand, Hände unter den Schultern, Knie unter der Hüfte.",
   "Wirbel für Wirbel einrollen (Katze), dann Brust nach vorn schieben (Kuh).",
   "Beim Einrollen ausatmen, beim Öffnen einatmen.",
   ["Langsam und fließend", "Bewegung über die ganze Wirbelsäule verteilen"],
   ["Nur der Nacken bewegt sich"],
   ["Kopfbewegung klein halten bei HWS-Beschwerden"],
   [], ["floor", "stretch"], ("bodyweight", None, None), (1, R, 8, 10, False),
   ["mob_open_book"], "cat_cow")

ex("mob_open_book", "Offenes Buch (BWS-Rotation)", "Open Book", "mobility", MAT,
   ["upperBack", "chest"], ["obliques"], 1,
   "In Seitlage den oberen Arm aufdrehen – Rotation der Brustwirbelsäule für Golf und Tennis.",
   "Seitlage, Knie 90° gebeugt (ggf. Kissen zwischen Knie), Arme gestreckt vor der Brust.",
   "Oberen Arm in einem Bogen zur anderen Seite öffnen, Blick folgt der Hand, zurück.",
   "Beim Öffnen ausatmen.",
   ["Knie bleiben zusammen am Boden", "Nur so weit, wie angenehm"],
   ["Becken dreht mit", "Ruckartiges Öffnen"],
   [],
   ["thoracicSpine", "shoulder"], ["rotation", "stretch", "floor"], ("bodyweight", None, None), (1, R, 6, 10, True),
   ["mob_worlds_greatest_stretch", "trx_chest_stretch"], "open_book")

ex("mob_worlds_greatest_stretch", "World's Greatest Stretch", "World's Greatest Stretch", "mobility", BW,
   ["hipFlexors", "hamstrings", "upperBack"], ["adductors", "obliques"], 2,
   "Ausfallschritt mit Rotation – Hüftbeuger, Leiste und Brustwirbelsäule in einer Übung.",
   "Tiefer Ausfallschritt, hinteres Knie kann am Boden abgelegt werden, Hände innen neben dem vorderen Fuß.",
   "Ellenbogen Richtung vorderen Fußknöchel senken, dann Arm zur Decke aufdrehen. Seite wechseln.",
   "Beim Aufdrehen ausatmen.",
   ["Hinteres Bein aktiv", "Rotation aus der Brust"],
   ["Hohlkreuz", "Hektisches Tempo"],
   ["Hinteres Knie ablegen, wenn das Gleichgewicht nicht reicht"],
   ["hip", "knee", "thoracicSpine"], ["stretch", "rotation", "lunge"], ("bodyweight", None, None), (1, R, 4, 10, True),
   ["mob_hip_flexor_stretch", "mob_open_book"], "lunge")

ex("mob_hip_90_90", "Hüfte 90/90", "90/90 Hip Switch", "mobility", MAT,
   ["glutes", "hipFlexors"], ["adductors"], 1,
   "Sitzend beide Knie 90° gebeugt, abwechselnd zu beiden Seiten kippen – Innen- und Außenrotation der Hüfte.",
   "Sitz am Boden, Hände hinter dem Körper abgestützt, Füße breit, Knie gebeugt.",
   "Beide Knie langsam zur einen Seite ablegen, dann zur anderen Seite wechseln.",
   "Ruhig atmen.",
   ["Oberkörper aufrecht", "Langsam, ohne Schwung"],
   ["Schmerzhafter Druck im Knie"],
   ["Bei Knie- oder Hüftschmerz Bewegungsumfang verkleinern"],
   ["hip", "knee"], ["stretch", "floor", "rotation"], ("bodyweight", None, None), (1, R, 8, 10, False),
   ["trx_deep_squat_hold"], "hip_90_90")

ex("mob_hip_flexor_stretch", "Hüftbeuger-Dehnung im Halbkniestand", "Half-Kneeling Hip Flexor Stretch", "mobility", MAT,
   ["hipFlexors"], ["quadriceps"], 1,
   "Dehnung der vorderen Hüfte – gleicht langes Sitzen aus und verbessert die Hüftstreckung.",
   "Halbkniestand, hinteres Knie auf weicher Unterlage.",
   "Becken leicht aufrichten (Gesäß anspannen) und Hüfte etwas nach vorn schieben, halten.",
   "Ruhig in die Dehnung atmen.",
   ["Becken aufrichten statt ins Hohlkreuz", "Oberkörper aufrecht"],
   ["Hohlkreuz", "Zu weites Vorschieben"],
   ["Polster unter dem Knie"],
   ["knee", "hip"], ["stretch"], ("bodyweight", None, None), (1, S, 30, 10, True),
   ["mob_worlds_greatest_stretch"], "hip_flexor_stretch")

ex("mob_wall_slide", "Wandgleiten", "Wall Slide", "mobility", ["wall"],
   ["rotatorCuff", "upperBack"], ["shoulders"], 1,
   "Unterarme an der Wand nach oben gleiten lassen – Schulterblattkontrolle und Überkopfbeweglichkeit ohne Last.",
   "Mit dem Gesicht zur Wand, Unterarme in Schulterbreite an der Wand, Ellenbogen auf Schulterhöhe.",
   "Unterarme langsam nach oben gleiten lassen, nur im schmerzfreien Bereich, zurück.",
   "Beim Hochgleiten ausatmen.",
   ["Schultern weg von den Ohren", "Rippen unten"],
   ["Hohlkreuz", "Schmerzhafte Endposition"],
   ["Nur schmerzfreier Bewegungsbereich"],
   ["shoulder"], ["stretch"], ("bodyweight", None, None), (1, R, 8, 10, False),
   ["mob_arm_circles"], "wall_slide")

ex("mob_chin_tuck", "Nackenrückzug (Chin Tuck)", "Chin Tuck", "mobility", BW,
   ["neck"], ["upperBack"], 1,
   "Kopf sanft waagerecht nach hinten schieben – aktiviert die tiefe Halsmuskulatur und verbessert die Kopfhaltung.",
   "Aufrecht sitzen oder stehen, Blick geradeaus.",
   "Kinn waagerecht nach hinten schieben (Doppelkinn), 3 Sekunden halten, lösen.",
   "Ruhig weiteratmen.",
   ["Kein Nicken – waagerechte Bewegung", "Sanft"],
   ["Kopf nach unten nicken", "Zu viel Kraft"],
   ["Bei Schwindel, Kribbeln oder ausstrahlenden Schmerzen abbrechen und ärztlich abklären"],
   ["cervicalSpine"], ["isometric"], ("bodyweight", None, None), (1, R, 8, 10, False),
   [], "chin_tuck")

# ───────────────────────── AUFWÄRMEN ─────────────────────────
ex("warm_march", "Marschieren auf der Stelle", "March in Place", "warmup", BW,
   ["hipFlexors", "cardiovascular"], ["core", "calves"], 1,
   "Lockeres Marschieren mit Armeinsatz – bringt den Kreislauf schonend in Gang.",
   "Aufrechter Stand.",
   "Knie abwechselnd anheben, Arme schwingen gegengleich mit. Tempo langsam steigern.",
   "Locker und gleichmäßig atmen.",
   ["Aufrecht bleiben", "Tempo moderat"],
   [],
   ["Kein Sprung, keine Stoßbelastung"],
   [], ["cardioDemand"], ("bodyweight", None, None), (1, S, 60, 0, False),
   ["warm_hip_circles"], "march")

ex("mob_arm_circles", "Armkreisen", "Arm Circles", "warmup", BW,
   ["shoulders"], ["upperBack"], 1,
   "Große, langsame Armkreise vorwärts und rückwärts – Schultergelenk mobilisieren.",
   "Aufrechter Stand, Arme locker seitlich.",
   "Arme in großen Kreisen bewegen, Richtung nach der Hälfte wechseln.",
   "Ruhig atmen.",
   ["Kreise zunächst klein, dann größer", "Nur schmerzfreier Bereich"],
   ["Schwungvolles Reißen"],
   ["Bei Schulterbeschwerden Kreise klein halten"],
   ["shoulder"], [], ("bodyweight", None, None), (1, S, 30, 0, False),
   ["mob_wall_slide"], "arm_circles")

ex("warm_hip_circles", "Hüftkreisen", "Hip Circles", "warmup", BW,
   ["hipFlexors", "glutes"], ["lowerBack"], 1,
   "Kreisende Beckenbewegung im Stand – Hüfte und unteren Rücken lockern.",
   "Hüftbreiter Stand, Hände an den Hüften.",
   "Becken in großen Kreisen bewegen, Richtung wechseln.",
   "Ruhig atmen.",
   ["Oberkörper bleibt ruhig"],
   [],
   [],
   ["lumbarSpine", "hip"], [], ("bodyweight", None, None), (1, S, 30, 0, False),
   ["mob_cat_cow"], "hip_circles")

ex("warm_leg_swings", "Beinpendel", "Leg Swings", "warmup", BW + ["wall"],
   ["hipFlexors", "hamstrings"], ["adductors", "glutes"], 1,
   "Lockeres Pendeln eines Beins vor und zurück bzw. seitlich – dynamische Hüftmobilisation.",
   "Seitlich zu Wand oder TRX stehen und festhalten.",
   "Bein locker vor und zurück pendeln, Amplitude langsam vergrößern, Seite wechseln.",
   "Ruhig atmen.",
   ["Oberkörper aufrecht", "Kontrollierte Amplitude"],
   ["Zu starker Schwung"],
   ["Festhalten für sicheres Gleichgewicht"],
   ["hip"], ["balance"], ("bodyweight", None, None), (1, R, 10, 0, True),
   ["warm_hip_circles"], "leg_swing")

# ───────────────────────── COOL-DOWN ─────────────────────────
ex("cool_crocodile_breathing", "Krokodilatmung", "Crocodile Breathing", "cooldown", MAT,
   ["core"], [], 1,
   "Bauchlage mit ruhiger Zwerchfellatmung – unterstützt den Übergang in die Erholung.",
   "Bauchlage, Stirn auf den Handrücken.",
   "Durch die Nase in den Bauch und die Flanken atmen, langsam ausatmen.",
   "Ca. 4 Sekunden ein, 6 Sekunden aus.",
   ["Ausatmung länger als Einatmung", "Schultern locker"],
   [],
   [],
   [], ["floor"], ("bodyweight", None, None), (1, S, 60, 0, False),
   ["cool_childs_pose"], "lying_breath")

ex("cool_childs_pose", "Kindhaltung", "Child's Pose", "cooldown", MAT,
   ["lowerBack", "lats"], ["hipFlexors"], 1,
   "Sitz auf den Fersen mit nach vorn gestreckten Armen – Entspannung für Rücken und Schultern.",
   "Vierfüßlerstand, Knie etwas breiter als hüftbreit.",
   "Gesäß Richtung Fersen schieben, Arme lang nach vorn, Stirn ablegen.",
   "Tief in den Rücken atmen.",
   ["Nur so weit, wie angenehm"],
   ["Druck im Knie ignorieren"],
   ["Bei Kniebeschwerden Kissen zwischen Gesäß und Fersen"],
   ["knee"], ["stretch", "floor"], ("bodyweight", None, None), (1, S, 45, 0, False),
   ["cool_crocodile_breathing"], "child_pose")

ex("cool_supine_hamstring_stretch", "Oberschenkelrückseite-Dehnung in Rückenlage", "Supine Hamstring Stretch", "cooldown", MAT,
   ["hamstrings"], ["calves"], 1,
   "In Rückenlage ein gestrecktes Bein anheben (ggf. mit TRX-Schlaufe) – schonende Dehnung.",
   "Rückenlage, ein Bein gestreckt am Boden, anderes Bein mit Schlaufe oder Händen am Oberschenkel.",
   "Bein gestreckt anheben, bis eine angenehme Dehnung spürbar ist, halten, Seite wechseln.",
   "Ruhig in die Dehnung atmen.",
   ["Becken bleibt am Boden", "Leichte Kniebeugung erlaubt"],
   ["Ziehen bis zum Schmerz"],
   [],
   ["hip"], ["stretch", "floor"], ("bodyweight", None, None), (1, S, 30, 0, True),
   ["trx_hip_hinge_mobility"], "hamstring_stretch")

ex("cool_thoracic_rotation_seated", "Sitzende Oberkörperrotation", "Seated Thoracic Rotation", "cooldown", BW,
   ["upperBack", "obliques"], [], 1,
   "Aufrecht sitzend den Oberkörper langsam zu beiden Seiten drehen – Rotation sanft ausklingen lassen.",
   "Aufrechter Sitz (Stuhl oder Boden), Arme vor der Brust verschränkt.",
   "Oberkörper langsam zu einer Seite drehen, kurz halten, zur anderen Seite.",
   "Beim Drehen ausatmen.",
   ["Becken bleibt ruhig", "Aufrichten vor dem Drehen"],
   ["Schwungvolles Drehen"],
   [],
   ["thoracicSpine"], ["rotation", "stretch"], ("bodyweight", None, None), (1, R, 6, 0, True),
   ["mob_open_book"], "rotation")

# Fix kleine Tippfehler-Absicherung
for e in EX:
    e["secondaryMuscles"] = [m for m in e["secondaryMuscles"] if m != "ankle"]

ids = {e["id"] for e in EX}
for e in EX:
    for a in e["alternatives"] + [e.get("regressionId"), e.get("progressionId")]:
        if a and a not in ids:
            raise SystemExit(f"Unbekannte Referenz {a} in {e['id']}")

out = os.path.join(os.path.dirname(__file__), "..", "Sources", "FitnessCore", "Library", "Resources", "exercises.json")
with open(out, "w", encoding="utf-8") as f:
    json.dump({"schemaVersion": 1, "exercises": EX}, f, ensure_ascii=False, indent=2)
print(f"{len(EX)} Übungen geschrieben → {os.path.normpath(out)}")
