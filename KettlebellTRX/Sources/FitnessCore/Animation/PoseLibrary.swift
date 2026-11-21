import Foundation

/// 2D-Punkt (plattformunabhängig, ohne CoreGraphics).
public struct Vec2: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func * (a: Vec2, s: Double) -> Vec2 { Vec2(a.x * s, a.y * s) }
}

/// Körperhaltung über absolute Segmentwinkel (Grad, Seitenansicht, Blick nach rechts).
/// 0° = nach oben, 90° = nach vorn (rechts), 180° = nach unten, 270° bzw. −90° = nach hinten (links).
/// „A“ = zugewandte Gliedmaße, „B“ = abgewandte Gliedmaße (heller dargestellt).
public struct Pose: Hashable, Sendable {
    public var torso: Double
    public var head: Double        // relativ zum Rumpf
    public var thighA: Double, shinA: Double
    public var thighB: Double, shinB: Double
    public var upperArmA: Double, forearmA: Double
    public var upperArmB: Double, forearmB: Double
    /// Zusätzliche Anhebung (z. B. Wadenheben), Anteil der Bildhöhe.
    public var lift: Double

    public init(torso: Double = 0, head: Double = 0,
                thighA: Double = 180, shinA: Double = 180, thighB: Double = 180, shinB: Double = 180,
                upperArmA: Double = 180, forearmA: Double = 180, upperArmB: Double = 180, forearmB: Double = 180,
                lift: Double = 0) {
        self.torso = torso; self.head = head
        self.thighA = thighA; self.shinA = shinA; self.thighB = thighB; self.shinB = shinB
        self.upperArmA = upperArmA; self.forearmA = forearmA; self.upperArmB = upperArmB; self.forearmB = forearmB
        self.lift = lift
    }

    /// Lineare Interpolation aller Winkel.
    public static func lerp(_ a: Pose, _ b: Pose, _ t: Double) -> Pose {
        func l(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        return Pose(torso: l(a.torso, b.torso), head: l(a.head, b.head),
                    thighA: l(a.thighA, b.thighA), shinA: l(a.shinA, b.shinA),
                    thighB: l(a.thighB, b.thighB), shinB: l(a.shinB, b.shinB),
                    upperArmA: l(a.upperArmA, b.upperArmA), forearmA: l(a.forearmA, b.forearmA),
                    upperArmB: l(a.upperArmB, b.upperArmB), forearmB: l(a.forearmB, b.forearmB),
                    lift: l(a.lift, b.lift))
    }
}

public enum Joint: String, CaseIterable, Sendable {
    case head, shoulder, hip
    case elbowA, handA, elbowB, handB
    case kneeA, footA, kneeB, footB
}

/// Fertig berechnete Gelenkpositionen in einem Einheitsquadrat (0…1, y nach unten).
public struct Skeleton: Sendable {
    public var joints: [Joint: Vec2]
    public var headRadius: Double
    public subscript(_ j: Joint) -> Vec2 { joints[j] ?? Vec2(0.5, 0.5) }
}

public enum StrapAttachment: String, Sendable { case none, hands, feet }

/// Eine Bewegungsanimation (Keyframes werden hin und zurück abgespielt).
public struct MovementAnimation: Sendable {
    public var id: String
    public var keyframes: [Pose]
    /// Dauer eines Durchgangs (hin) in Sekunden.
    public var cycleSeconds: Double
    /// Gelenk, das horizontal ortsfest bleibt (z. B. Fuß beim Squat).
    public var anchor: Joint
    public var kettlebellInHands: (a: Bool, b: Bool)
    public var straps: StrapAttachment
    /// Horizontale Position des TRX-Ankerpunkts (0 = links, 1 = rechts).
    public var strapAnchorX: Double
    public var caption: String

    public init(id: String, keyframes: [Pose], cycleSeconds: Double = 2.4, anchor: Joint = .footA,
                kettlebell: (Bool, Bool) = (false, false), straps: StrapAttachment = .none, strapAnchorX: Double = 0.9,
                caption: String = "") {
        self.id = id; self.keyframes = keyframes; self.cycleSeconds = cycleSeconds; self.anchor = anchor
        self.kettlebellInHands = (kettlebell.0, kettlebell.1); self.straps = straps
        self.strapAnchorX = strapAnchorX; self.caption = caption
    }

    /// Pose zu einem Zeitpunkt (Ping-Pong mit sanftem Ein-/Ausblenden).
    public func pose(at time: Double) -> Pose {
        guard keyframes.count > 1 else { return keyframes.first ?? Pose() }
        let segments = Double(keyframes.count - 1)
        let period = cycleSeconds * 2
        var phase = time.truncatingRemainder(dividingBy: period) / cycleSeconds // 0…2
        if phase < 0 { phase += 2 }
        let forward = phase <= 1 ? phase : 2 - phase                            // 0…1…0
        let pos = forward * segments
        let i = min(Int(pos), keyframes.count - 2)
        let local = pos - Double(i)
        let eased = 0.5 - 0.5 * cos(local * .pi)
        return Pose.lerp(keyframes[i], keyframes[i + 1], eased)
    }
}

/// Vorwärtskinematik und Normierung für die Darstellung.
public enum PoseRenderer {
    public static let floorY = 0.92
    static let torsoLength = 0.28, neck = 0.085, headRadius = 0.045
    static let upperArm = 0.15, forearm = 0.14, thigh = 0.22, shin = 0.22

    static func dir(_ deg: Double) -> Vec2 {
        let r = deg * .pi / 180
        return Vec2(sin(r), -cos(r))
    }

    /// Rohe Gelenkpositionen relativ zur Hüfte (0,0).
    public static func rawSkeleton(_ p: Pose) -> [Joint: Vec2] {
        let hip = Vec2(0, 0)
        let shoulder = hip + dir(p.torso) * torsoLength
        let head = shoulder + dir(p.torso + p.head) * neck
        let elbowA = shoulder + dir(p.upperArmA) * upperArm
        let handA = elbowA + dir(p.forearmA) * forearm
        let elbowB = shoulder + dir(p.upperArmB) * upperArm
        let handB = elbowB + dir(p.forearmB) * forearm
        let kneeA = hip + dir(p.thighA) * thigh
        let footA = kneeA + dir(p.shinA) * shin
        let kneeB = hip + dir(p.thighB) * thigh
        let footB = kneeB + dir(p.shinB) * shin
        return [.hip: hip, .shoulder: shoulder, .head: head, .elbowA: elbowA, .handA: handA,
                .elbowB: elbowB, .handB: handB, .kneeA: kneeA, .footA: footA, .kneeB: kneeB, .footB: footB]
    }

    /// Skelett zu einem Zeitpunkt: auf den Boden gestellt und am Ankergelenk ausgerichtet.
    public static func skeleton(for animation: MovementAnimation, at time: Double) -> Skeleton {
        let reference = rawSkeleton(animation.keyframes.first ?? Pose())
        // Horizontale Verschiebung so, dass die Referenzpose mittig steht.
        let xs = reference.values.map(\.x)
        let centerOffset = 0.5 - ((xs.min() ?? 0) + (xs.max() ?? 0)) / 2
        let anchorX = (reference[animation.anchor]?.x ?? 0) + centerOffset

        let pose = animation.pose(at: time)
        var raw = rawSkeleton(pose)
        let dx = anchorX - (raw[animation.anchor]?.x ?? 0)
        // Tiefster Punkt (inkl. Kopfunterkante) liegt auf dem Boden.
        let lowest = max(raw.values.map(\.y).max() ?? 0, (raw[.head]?.y ?? 0) + headRadius)
        let dy = floorY - lowest - pose.lift
        for (k, v) in raw { raw[k] = Vec2(v.x + dx, v.y + dy) }
        return Skeleton(joints: raw, headRadius: headRadius)
    }
}

/// Bibliothek der eigenen Bewegungsdarstellungen (keine Fremdinhalte).
public enum PoseLibrary {
    public static func animation(for id: String) -> MovementAnimation? { all[id] }
    public static var ids: Set<String> { Set(all.keys) }

    static let stand = Pose()

    // Hilfsposen
    static let gobletArms = (upper: 160.0, fore: 15.0)

    public static let all: [String: MovementAnimation] = {
        var a: [String: MovementAnimation] = [:]
        func add(_ m: MovementAnimation) { a[m.id] = m }

        add(.init(id: "squat", keyframes: [
            Pose(upperArmA: gobletArms.upper, forearmA: gobletArms.fore, upperArmB: gobletArms.upper, forearmB: gobletArms.fore),
            Pose(torso: 35, thighA: 98, shinA: 205, thighB: 98, shinB: 205,
                 upperArmA: 175, forearmA: 40, upperArmB: 175, forearmB: 40),
        ], cycleSeconds: 2.2, kettlebell: (true, false), caption: "Hüfte nach hinten-unten, Brust bleibt aufrecht"))

        add(.init(id: "hinge", keyframes: [
            stand,
            Pose(torso: 75, thighA: 165, shinA: 185, thighB: 165, shinB: 185),
        ], cycleSeconds: 2.2, kettlebell: (true, false), caption: "Bewegung aus der Hüfte, Rücken bleibt lang"))

        add(.init(id: "swing", keyframes: [
            Pose(torso: 70, thighA: 160, shinA: 185, thighB: 160, shinB: 185, upperArmA: 205, forearmA: 210, upperArmB: 205, forearmB: 210),
            Pose(torso: 0, upperArmA: 92, forearmA: 92, upperArmB: 92, forearmB: 92),
        ], cycleSeconds: 0.9, kettlebell: (true, false), caption: "Kräftige Hüftstreckung – die Arme führen nur"))

        add(.init(id: "row_trx", keyframes: [
            Pose(torso: -35, thighA: 145, shinA: 145, thighB: 145, shinB: 145, upperArmA: 55, forearmA: 55, upperArmB: 55, forearmB: 55),
            Pose(torso: -22, thighA: 158, shinA: 158, thighB: 158, shinB: 158, upperArmA: 205, forearmA: 70, upperArmB: 205, forearmB: 70),
        ], cycleSeconds: 2.0, straps: .hands, strapAnchorX: 0.95, caption: "Körper als Linie, Brust zu den Händen"))

        add(.init(id: "row_kb", keyframes: [
            Pose(torso: 70, thighA: 160, shinA: 180, thighB: 195, shinB: 185, upperArmA: 180, forearmA: 180, upperArmB: 150, forearmB: 175),
            Pose(torso: 70, thighA: 160, shinA: 180, thighB: 195, shinB: 185, upperArmA: 245, forearmA: 175, upperArmB: 150, forearmB: 175),
        ], cycleSeconds: 2.0, kettlebell: (true, false), caption: "Ellenbogen zur Hüfte ziehen"))

        add(.init(id: "press_trx", keyframes: [
            Pose(torso: 32, thighA: 212, shinA: 212, thighB: 212, shinB: 212, upperArmA: 85, forearmA: 85, upperArmB: 85, forearmB: 85),
            Pose(torso: 40, thighA: 220, shinA: 220, thighB: 220, shinB: 220, upperArmA: 195, forearmA: 75, upperArmB: 195, forearmB: 75),
        ], cycleSeconds: 2.0, straps: .hands, strapAnchorX: 0.05, caption: "Körperspannung halten, Brust zwischen die Hände"))

        add(.init(id: "floor_press", keyframes: [
            Pose(torso: 270, thighA: 45, shinA: 160, thighB: 45, shinB: 160, upperArmA: 90, forearmA: 0, upperArmB: 90, forearmB: 0),
            Pose(torso: 270, thighA: 45, shinA: 160, thighB: 45, shinB: 160, upperArmA: 0, forearmA: 0, upperArmB: 90, forearmB: 0),
        ], cycleSeconds: 2.0, anchor: .hip, kettlebell: (true, false), caption: "Senkrecht drücken, Oberarm sanft ablegen"))

        add(.init(id: "push_up", keyframes: [
            Pose(torso: 65, thighA: 245, shinA: 245, thighB: 245, shinB: 245, upperArmA: 165, forearmA: 165, upperArmB: 165, forearmB: 165),
            Pose(torso: 72, thighA: 252, shinA: 252, thighB: 252, shinB: 252, upperArmA: 230, forearmA: 150, upperArmB: 230, forearmB: 150),
        ], cycleSeconds: 2.0, caption: "Körper als Brett, kontrolliert absenken"))

        add(.init(id: "lunge", keyframes: [
            stand,
            Pose(torso: 5, thighA: 100, shinA: 180, thighB: 200, shinB: 262),
        ], cycleSeconds: 2.2, caption: "Schritt zurück, hinteres Knie senkt sich"))

        add(.init(id: "lateral_lunge", keyframes: [
            Pose(thighA: 170, shinA: 175, thighB: 190, shinB: 185, upperArmA: 80, forearmA: 80, upperArmB: 80, forearmB: 80),
            Pose(torso: 30, thighA: 110, shinA: 195, thighB: 170, shinB: 180, upperArmA: 85, forearmA: 85, upperArmB: 85, forearmB: 85),
        ], cycleSeconds: 2.2, straps: .hands, strapAnchorX: 0.95, caption: "Hüfte zur Seite nach hinten schieben"))

        add(.init(id: "carry", keyframes: [
            Pose(thighA: 165, shinA: 185, thighB: 195, shinB: 190),
            Pose(thighA: 195, shinA: 190, thighB: 165, shinB: 185),
        ], cycleSeconds: 0.7, anchor: .hip, kettlebell: (true, false), caption: "Aufrecht, Schultern waagerecht"))

        add(.init(id: "halo", keyframes: [
            Pose(upperArmA: 35, forearmA: -40, upperArmB: 35, forearmB: -40),
            Pose(upperArmA: -20, forearmA: 70, upperArmB: -20, forearmB: 70),
        ], cycleSeconds: 1.8, kettlebell: (true, false), caption: "Langsam und eng um den Kopf"))

        add(.init(id: "overhead_press", keyframes: [
            Pose(thighA: 92, shinA: 180, thighB: 182, shinB: 270, upperArmA: 165, forearmA: 10),
            Pose(thighA: 92, shinA: 180, thighB: 182, shinB: 270, upperArmA: 2, forearmA: 2),
        ], cycleSeconds: 2.2, kettlebell: (true, false), caption: "Rippen unten, langsam drücken"))

        add(.init(id: "plank", keyframes: [
            Pose(torso: 80, thighA: 260, shinA: 260, thighB: 260, shinB: 260, upperArmA: 180, forearmA: 90, upperArmB: 180, forearmB: 90),
            Pose(torso: 78, thighA: 258, shinA: 258, thighB: 258, shinB: 258, upperArmA: 180, forearmA: 90, upperArmB: 180, forearmB: 90),
        ], cycleSeconds: 2.5, anchor: .footA, caption: "Körper als Brett – ruhig atmen"))

        add(.init(id: "side_plank", keyframes: [
            Pose(torso: 75, thighA: 258, shinA: 258, thighB: 258, shinB: 258, upperArmA: 180, forearmA: 90, upperArmB: 200, forearmB: 130),
            Pose(torso: 72, thighA: 255, shinA: 255, thighB: 255, shinB: 255, upperArmA: 180, forearmA: 90, upperArmB: 200, forearmB: 130),
        ], cycleSeconds: 2.5, caption: "Becken hoch, Körper in einer Linie"))

        add(.init(id: "bird_dog", keyframes: [
            Pose(torso: 90, thighA: 180, shinA: 270, thighB: 180, shinB: 270, upperArmA: 180, forearmA: 180, upperArmB: 180, forearmB: 180),
            Pose(torso: 90, thighA: 180, shinA: 270, thighB: 272, shinB: 272, upperArmA: 88, forearmA: 88, upperArmB: 180, forearmB: 180),
        ], cycleSeconds: 2.4, anchor: .kneeA, caption: "Arm und Gegenbein lang machen"))

        add(.init(id: "dead_bug", keyframes: [
            Pose(torso: 270, thighA: 0, shinA: 90, thighB: 0, shinB: 90, upperArmA: 0, forearmA: 0, upperArmB: 0, forearmB: 0),
            Pose(torso: 270, thighA: 0, shinA: 90, thighB: 82, shinB: 86, upperArmA: -88, forearmA: -88, upperArmB: 0, forearmB: 0),
        ], cycleSeconds: 2.4, anchor: .hip, caption: "Unterer Rücken bleibt am Boden"))

        add(.init(id: "bridge", keyframes: [
            Pose(torso: 270, thighA: 55, shinA: 160, thighB: 55, shinB: 160, upperArmA: 90, forearmA: 90, upperArmB: 90, forearmB: 90),
            Pose(torso: 248, thighA: 75, shinA: 172, thighB: 75, shinB: 172, upperArmA: 110, forearmA: 110, upperArmB: 110, forearmB: 110),
        ], cycleSeconds: 2.0, anchor: .footA, kettlebell: (false, false), caption: "Becken heben bis zur Linie"))

        add(.init(id: "cat_cow", keyframes: [
            Pose(torso: 96, head: 35, thighA: 180, shinA: 270, thighB: 180, shinB: 270, upperArmA: 180, forearmA: 180, upperArmB: 180, forearmB: 180),
            Pose(torso: 84, head: -30, thighA: 180, shinA: 270, thighB: 180, shinB: 270, upperArmA: 180, forearmA: 180, upperArmB: 180, forearmB: 180),
        ], cycleSeconds: 3.0, anchor: .kneeA, caption: "Einrollen – öffnen, im Atemrhythmus"))

        add(.init(id: "open_book", keyframes: [
            Pose(torso: 270, thighA: 30, shinA: 140, thighB: 30, shinB: 140, upperArmA: 90, forearmA: 90, upperArmB: 90, forearmB: 90),
            Pose(torso: 270, head: -20, thighA: 30, shinA: 140, thighB: 30, shinB: 140, upperArmA: -85, forearmA: -85, upperArmB: 90, forearmB: 90),
        ], cycleSeconds: 3.0, anchor: .hip, caption: "Oberen Arm öffnen, Blick folgt"))

        add(.init(id: "rotation", keyframes: [
            Pose(thighA: 90, shinA: 180, thighB: 90, shinB: 180, upperArmA: 150, forearmA: 40, upperArmB: 150, forearmB: 40),
            Pose(head: 20, thighA: 90, shinA: 180, thighB: 90, shinB: 180, upperArmA: 120, forearmA: 20, upperArmB: 190, forearmB: 60),
        ], cycleSeconds: 2.6, anchor: .hip, caption: "Aufrichten, dann langsam drehen"))

        add(.init(id: "march", keyframes: [
            Pose(thighA: 110, shinA: 180, upperArmA: 200, forearmA: 160, upperArmB: 150, forearmB: 110),
            Pose(thighB: 110, shinB: 180, upperArmA: 150, forearmA: 110, upperArmB: 200, forearmB: 160),
        ], cycleSeconds: 0.7, anchor: .hip, caption: "Locker marschieren"))

        add(.init(id: "balance", keyframes: [
            Pose(thighB: 190, shinB: 200),
            Pose(torso: 80, thighA: 172, shinA: 182, thighB: 268, shinB: 268),
        ], cycleSeconds: 2.6, caption: "Hüfte waagerecht, ruhiger Blick"))

        add(.init(id: "calf_raise", keyframes: [
            stand,
            Pose(lift: 0.035),
        ], cycleSeconds: 1.6, caption: "Langsam hoch, langsam ab"))

        add(.init(id: "curl_trx", keyframes: [
            Pose(torso: -30, thighA: 150, shinA: 150, thighB: 150, shinB: 150, upperArmA: 70, forearmA: 70, upperArmB: 70, forearmB: 70),
            Pose(torso: -22, thighA: 158, shinA: 158, thighB: 158, shinB: 158, upperArmA: 70, forearmA: -40, upperArmB: 70, forearmB: -40),
        ], cycleSeconds: 2.0, straps: .hands, strapAnchorX: 0.95, caption: "Ellenbogen bleiben auf Schulterhöhe"))

        add(.init(id: "y_raise", keyframes: [
            Pose(torso: -18, thighA: 162, shinA: 162, thighB: 162, shinB: 162, upperArmA: 75, forearmA: 75, upperArmB: 75, forearmB: 75),
            Pose(torso: -8, thighA: 172, shinA: 172, thighB: 172, shinB: 172, upperArmA: 25, forearmA: 25, upperArmB: 25, forearmB: 25),
        ], cycleSeconds: 2.0, straps: .hands, strapAnchorX: 0.95, caption: "Arme in ein Y führen"))

        add(.init(id: "hamstring_curl", keyframes: [
            Pose(torso: 258, thighA: 82, shinA: 82, thighB: 82, shinB: 82, upperArmA: 90, forearmA: 90, upperArmB: 90, forearmB: 90),
            Pose(torso: 245, thighA: 35, shinA: 150, thighB: 35, shinB: 150, upperArmA: 100, forearmA: 100, upperArmB: 100, forearmB: 100),
        ], cycleSeconds: 2.2, anchor: .shoulder, straps: .feet, strapAnchorX: 0.95, caption: "Becken oben, Fersen heranziehen"))

        add(.init(id: "pallof", keyframes: [
            Pose(upperArmA: 150, forearmA: 105, upperArmB: 150, forearmB: 105),
            Pose(upperArmA: 92, forearmA: 92, upperArmB: 92, forearmB: 92),
        ], cycleSeconds: 2.6, straps: .hands, strapAnchorX: 0.95, caption: "Rumpf widersteht der Drehung"))

        add(.init(id: "squat_row", keyframes: [
            Pose(torso: 30, thighA: 100, shinA: 200, thighB: 100, shinB: 200, upperArmA: 65, forearmA: 65, upperArmB: 65, forearmB: 65),
            Pose(torso: -20, thighA: 160, shinA: 160, thighB: 160, shinB: 160, upperArmA: 205, forearmA: 70, upperArmB: 205, forearmB: 70),
        ], cycleSeconds: 2.2, straps: .hands, strapAnchorX: 0.95, caption: "Fließend von der Hocke ins Rudern"))

        add(.init(id: "deep_squat", keyframes: [
            Pose(torso: 38, thighA: 78, shinA: 212, thighB: 78, shinB: 212, upperArmA: 75, forearmA: 75, upperArmB: 75, forearmB: 75),
            Pose(torso: 33, thighA: 80, shinA: 210, thighB: 80, shinB: 210, upperArmA: 78, forearmA: 78, upperArmB: 78, forearmB: 78),
        ], cycleSeconds: 3.0, straps: .hands, strapAnchorX: 0.95, caption: "Tief und ruhig atmen"))

        add(.init(id: "chest_stretch", keyframes: [
            Pose(torso: 12, thighA: 165, shinA: 180, thighB: 200, shinB: 195, upperArmA: 255, forearmA: 255, upperArmB: 255, forearmB: 255),
            Pose(torso: 25, thighA: 160, shinA: 180, thighB: 205, shinB: 195, upperArmA: 262, forearmA: 262, upperArmB: 262, forearmB: 262),
        ], cycleSeconds: 3.0, straps: .hands, strapAnchorX: 0.05, caption: "Sanft nach vorn lehnen"))

        add(.init(id: "hip_90_90", keyframes: [
            Pose(torso: -10, thighA: 70, shinA: 165, thighB: 55, shinB: 150, upperArmA: 205, forearmA: 205, upperArmB: 205, forearmB: 205),
            Pose(torso: -10, thighA: 55, shinA: 150, thighB: 70, shinB: 165, upperArmA: 205, forearmA: 205, upperArmB: 205, forearmB: 205),
        ], cycleSeconds: 2.6, anchor: .hip, caption: "Knie langsam von Seite zu Seite"))

        add(.init(id: "hip_flexor_stretch", keyframes: [
            Pose(thighA: 95, shinA: 180, thighB: 192, shinB: 270),
            Pose(torso: -4, thighA: 85, shinA: 188, thighB: 212, shinB: 272),
        ], cycleSeconds: 3.0, anchor: .footA, caption: "Becken aufrichten, Hüfte nach vorn"))

        add(.init(id: "wall_slide", keyframes: [
            Pose(upperArmA: 80, forearmA: 0, upperArmB: 80, forearmB: 0),
            Pose(upperArmA: 20, forearmA: 10, upperArmB: 20, forearmB: 10),
        ], cycleSeconds: 2.4, caption: "Schultern weg von den Ohren"))

        add(.init(id: "chin_tuck", keyframes: [
            Pose(head: 0),
            Pose(head: -12),
        ], cycleSeconds: 2.0, caption: "Kinn waagerecht zurück"))

        add(.init(id: "arm_circles", keyframes: [
            Pose(upperArmA: 180, forearmA: 180, upperArmB: 180, forearmB: 180),
            Pose(upperArmA: 90, forearmA: 90, upperArmB: 90, forearmB: 90),
            Pose(upperArmA: 0, forearmA: 0, upperArmB: 0, forearmB: 0),
            Pose(upperArmA: -90, forearmA: -90, upperArmB: -90, forearmB: -90),
        ], cycleSeconds: 2.4, caption: "Große, langsame Kreise"))

        add(.init(id: "hip_circles", keyframes: [
            Pose(torso: 8, thighA: 172, thighB: 172),
            Pose(torso: -8, thighA: 188, thighB: 188),
        ], cycleSeconds: 1.6, caption: "Becken kreisen, Oberkörper ruhig"))

        add(.init(id: "leg_swing", keyframes: [
            Pose(thighA: 125, shinA: 140, upperArmB: 90, forearmB: 90),
            Pose(thighA: 220, shinA: 205, upperArmB: 90, forearmB: 90),
        ], cycleSeconds: 1.2, anchor: .footB, caption: "Locker pendeln"))

        add(.init(id: "lying_breath", keyframes: [
            Pose(torso: 90, head: 0, thighA: 270, shinA: 270, thighB: 270, shinB: 270, upperArmA: 120, forearmA: 270, upperArmB: 120, forearmB: 270),
            Pose(torso: 88, head: 0, thighA: 270, shinA: 270, thighB: 270, shinB: 270, upperArmA: 120, forearmA: 270, upperArmB: 120, forearmB: 270),
        ], cycleSeconds: 5.0, anchor: .hip, caption: "4 s ein, 6 s aus"))

        add(.init(id: "child_pose", keyframes: [
            Pose(torso: 110, head: 15, thighA: 125, shinA: 270, thighB: 125, shinB: 270, upperArmA: 100, forearmA: 100, upperArmB: 100, forearmB: 100),
            Pose(torso: 106, head: 15, thighA: 125, shinA: 270, thighB: 125, shinB: 270, upperArmA: 98, forearmA: 98, upperArmB: 98, forearmB: 98),
        ], cycleSeconds: 5.0, anchor: .kneeA, caption: "In den Rücken atmen"))

        add(.init(id: "hamstring_stretch", keyframes: [
            Pose(torso: 270, thighA: 45, shinA: 45, thighB: 90, shinB: 90, upperArmA: 60, forearmA: 30, upperArmB: 90, forearmB: 90),
            Pose(torso: 270, thighA: 12, shinA: 15, thighB: 90, shinB: 90, upperArmA: 40, forearmA: 10, upperArmB: 90, forearmB: 90),
        ], cycleSeconds: 3.0, anchor: .hip, caption: "Bein gestreckt anheben"))

        add(.init(id: "curl_up", keyframes: [
            Pose(torso: 270, thighA: 45, shinA: 135, thighB: 90, shinB: 90, upperArmA: 100, forearmA: 90, upperArmB: 100, forearmB: 90),
            Pose(torso: 282, thighA: 45, shinA: 135, thighB: 90, shinB: 90, upperArmA: 100, forearmA: 90, upperArmB: 100, forearmB: 90),
        ], cycleSeconds: 2.4, anchor: .hip, caption: "Kopf und Schultern minimal anheben"))

        add(.init(id: "bear", keyframes: [
            Pose(torso: 90, thighA: 180, shinA: 270, thighB: 180, shinB: 270, upperArmA: 180, forearmA: 180, upperArmB: 180, forearmB: 180),
            Pose(torso: 88, thighA: 168, shinA: 252, thighB: 168, shinB: 252, upperArmA: 180, forearmA: 180, upperArmB: 180, forearmB: 180),
        ], cycleSeconds: 2.4, anchor: .handA, caption: "Knie wenige Zentimeter anheben"))

        return a
    }()
}
