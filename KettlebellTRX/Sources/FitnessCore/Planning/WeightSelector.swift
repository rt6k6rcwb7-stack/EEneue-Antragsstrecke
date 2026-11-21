import Foundation

/// Bildet Laststufen auf die tatsächlich vorhandenen Kettlebells ab.
public struct WeightSelector: Sendable {
    public let available: [Double]

    public init(available: [Double]) { self.available = Array(Set(available)).sorted() }

    /// Empfohlenes Gewicht für eine Laststufe.
    /// Bei drei Kettlebells (8/12/16): leicht = 8, mittel = 12, schwer = 16.
    /// Einsteiger erhalten eine Stufe leichter.
    public func recommended(for tier: LoadTier, experience: ExperienceLevel = .intermediate) -> Double? {
        guard !available.isEmpty else { return nil }
        var position: Int
        switch tier {
        case .light: position = 0
        case .medium: position = (available.count - 1) / 2   // bei gerader Anzahl die leichtere Mitte
        case .heavy: position = available.count - 1
        }
        if experience == .beginner { position -= 1 }
        return available[min(max(position, 0), available.count - 1)]
    }

    public func next(above weight: Double) -> Double? { available.first { $0 > weight + 0.01 } }
    public func next(below weight: Double) -> Double? { available.last { $0 < weight - 0.01 } }

    public func recommended(for exercise: Exercise, experience: ExperienceLevel) -> Double? {
        guard exercise.load.kind == .kettlebell, let tier = exercise.load.tier else { return nil }
        return recommended(for: tier, experience: experience)
    }
}
