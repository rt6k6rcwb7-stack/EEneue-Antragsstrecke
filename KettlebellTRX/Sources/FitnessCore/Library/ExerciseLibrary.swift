import Foundation

/// Übungsbibliothek. Lädt die mitgelieferte `exercises.json` und optional eine
/// benutzerdefinierte Ergänzungsdatei (gleiches Format; gleiche IDs überschreiben).
public struct ExerciseLibrary: Sendable {
    public struct File: Codable, Sendable {
        public var schemaVersion: Int
        public var exercises: [Exercise]
    }

    public enum LoadError: Error, LocalizedError {
        case resourceMissing
        case unsupportedSchema(Int)
        case invalidReference(exercise: String, reference: String)

        public var errorDescription: String? {
            switch self {
            case .resourceMissing: return "Übungsdatei nicht gefunden."
            case .unsupportedSchema(let v): return "Übungsdatei hat eine nicht unterstützte Version (\(v))."
            case .invalidReference(let e, let r): return "Übung \(e) verweist auf unbekannte Übung \(r)."
            }
        }
    }

    public static let supportedSchemaVersion = 1

    public private(set) var exercises: [Exercise]
    private let index: [String: Int]

    public init(exercises: [Exercise]) {
        self.exercises = exercises
        var idx: [String: Int] = [:]
        for (i, e) in exercises.enumerated() { idx[e.id] = i }
        self.index = idx
    }

    /// Mitgelieferte Bibliothek (Bundle-Ressource).
    public static func bundled() throws -> ExerciseLibrary {
        guard let url = Bundle.module.url(forResource: "exercises", withExtension: "json") else {
            throw LoadError.resourceMissing
        }
        return try load(from: [url])
    }

    /// Lädt eine oder mehrere Dateien; spätere Dateien ergänzen/überschreiben frühere.
    public static func load(from urls: [URL]) throws -> ExerciseLibrary {
        var merged: [String: Exercise] = [:]
        var order: [String] = []
        for url in urls {
            let data = try Data(contentsOf: url)
            let file = try JSONDecoder().decode(File.self, from: data)
            guard file.schemaVersion <= supportedSchemaVersion else { throw LoadError.unsupportedSchema(file.schemaVersion) }
            for e in file.exercises {
                if merged[e.id] == nil { order.append(e.id) }
                merged[e.id] = e
            }
        }
        let lib = ExerciseLibrary(exercises: order.compactMap { merged[$0] })
        try lib.validate()
        return lib
    }

    public func validate() throws {
        for e in exercises {
            for ref in e.alternatives + [e.regressionId, e.progressionId].compactMap({ $0 }) where index[ref] == nil {
                throw LoadError.invalidReference(exercise: e.id, reference: ref)
            }
        }
    }

    public subscript(id: String) -> Exercise? { index[id].map { exercises[$0] } }

    public func exercises(in category: ExerciseCategory) -> [Exercise] {
        exercises.filter { $0.category == category }
    }

    public func search(_ text: String, category: ExerciseCategory? = nil, equipment: Equipment? = nil) -> [Exercise] {
        let q = text.trimmingCharacters(in: .whitespaces).lowercased()
        return exercises.filter { e in
            (category == nil || e.category == category) &&
            (equipment == nil || e.equipment.contains(equipment!)) &&
            (q.isEmpty || e.nameDE.lowercased().contains(q) || (e.nameEN?.lowercased().contains(q) ?? false)
                || e.primaryMuscles.contains { $0.displayName.lowercased().contains(q) })
        }
    }

    /// Mögliche Ersatzübungen: zuerst die hinterlegten Alternativen, dann Übungen mit gleicher
    /// Kategorie und überlappenden Hauptmuskeln.
    public func alternatives(for id: String) -> [Exercise] {
        guard let e = self[id] else { return [] }
        let explicit = e.alternatives.compactMap { self[$0] }
        let explicitIds = Set(explicit.map(\.id) + [e.id])
        let similar = exercises.filter {
            !explicitIds.contains($0.id) &&
            !Set($0.primaryMuscles).isDisjoint(with: e.primaryMuscles) &&
            ($0.category == e.category || $0.tags.contains { e.tags.contains($0) })
        }
        return explicit + similar
    }
}
