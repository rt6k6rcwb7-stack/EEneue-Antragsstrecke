import Foundation

/// Plattformunabhängige Abbildung eines HealthKit-Datensatzes. Die iOS-App erzeugt diese
/// Objekte aus `HKSample`; die Logik (Quellenerkennung, Typzuordnung) ist hier testbar.
public struct HealthSampleDTO: Hashable, Sendable {
    public var typeIdentifier: String
    public var value: Double             // bereits in Zieleinheit (S/min, ms, kcal, Anzahl, %, min)
    public var start: Date
    public var end: Date
    public var uuid: String
    public var sourceBundleId: String
    public var sourceName: String
    public var deviceModel: String?
    public var deviceName: String?
    /// Für Schlafanalyse: Rohwert von `HKCategoryValueSleepAnalysis`.
    public var categoryValue: Int?

    public init(typeIdentifier: String, value: Double, start: Date, end: Date, uuid: String, sourceBundleId: String,
                sourceName: String, deviceModel: String? = nil, deviceName: String? = nil, categoryValue: Int? = nil) {
        self.typeIdentifier = typeIdentifier; self.value = value; self.start = start; self.end = end; self.uuid = uuid
        self.sourceBundleId = sourceBundleId; self.sourceName = sourceName; self.deviceModel = deviceModel
        self.deviceName = deviceName; self.categoryValue = categoryValue
    }
}

public enum HealthTypeID {
    public static let heartRate = "HKQuantityTypeIdentifierHeartRate"
    public static let restingHeartRate = "HKQuantityTypeIdentifierRestingHeartRate"
    public static let hrvSDNN = "HKQuantityTypeIdentifierHeartRateVariabilitySDNN"
    public static let activeEnergy = "HKQuantityTypeIdentifierActiveEnergyBurned"
    public static let steps = "HKQuantityTypeIdentifierStepCount"
    public static let respiratoryRate = "HKQuantityTypeIdentifierRespiratoryRate"
    public static let oxygenSaturation = "HKQuantityTypeIdentifierOxygenSaturation"
    public static let sleepAnalysis = "HKCategoryTypeIdentifierSleepAnalysis"
    public static let workout = "HKWorkoutTypeIdentifier"

    /// Alle Typen, für die Leserechte angefragt werden (minimal notwendig).
    public static let readTypes = [heartRate, restingHeartRate, hrvSDNN, activeEnergy, steps, respiratoryRate,
                                   oxygenSaturation, sleepAnalysis, workout]
}

public enum HealthSourceClassifier {
    /// Bekannte Bundle-IDs. Garmin Connect: com.garmin.connect.mobile (auf Gerät zu verifizieren).
    public static let garminBundlePrefixes = ["com.garmin.connect"]
    public static let whoopKeywords = ["whoop"]

    public static func classify(bundleId: String, deviceModel: String?, ownBundleId: String? = nil) -> DataSource {
        let b = bundleId.lowercased()
        if let own = ownBundleId?.lowercased(), b.hasPrefix(own) { return .app }
        if garminBundlePrefixes.contains(where: { b.hasPrefix($0) }) { return .garmin }
        if whoopKeywords.contains(where: { b.contains($0) }) { return .whoop }
        if b.hasPrefix("com.apple.health") {
            let m = deviceModel?.lowercased() ?? ""
            if m.contains("watch") { return .appleWatch }
            if m.contains("iphone") { return .iPhone }
            return .iPhone
        }
        return .otherHealthApp
    }
}

public enum HealthSampleMapper {
    /// Werte von HKCategoryValueSleepAnalysis.
    public enum Sleep: Int { case inBed = 0, asleepUnspecified = 1, awake = 2, asleepCore = 3, asleepDeep = 4, asleepREM = 5 }

    public static func map(_ d: HealthSampleDTO, ownBundleId: String? = nil, importedAt: Date = Date()) -> [VitalSample] {
        let source = HealthSourceClassifier.classify(bundleId: d.sourceBundleId, deviceModel: d.deviceModel, ownBundleId: ownBundleId)
        func s(_ t: VitalType, _ v: Double, q: MeasurementQuality = .measured) -> VitalSample {
            VitalSample(type: t, value: v, start: d.start, end: d.end, source: source, channel: .healthKit,
                        deviceId: d.deviceName ?? d.deviceModel, sourceRecordId: d.uuid, quality: q, importedAt: importedAt)
        }
        switch d.typeIdentifier {
        case HealthTypeID.heartRate: return [s(.heartRate, d.value)]
        case HealthTypeID.restingHeartRate: return [s(.restingHeartRate, d.value)]
        case HealthTypeID.hrvSDNN: return [s(.hrvSDNN, d.value)]
        case HealthTypeID.activeEnergy: return [s(.activeEnergy, d.value, q: .estimated)]
        case HealthTypeID.steps: return [s(.steps, d.value)]
        case HealthTypeID.respiratoryRate: return [s(.respiratoryRate, d.value)]
        case HealthTypeID.oxygenSaturation: return [s(.oxygenSaturation, d.value)]
        case HealthTypeID.sleepAnalysis:
            guard let raw = d.categoryValue, let stage = Sleep(rawValue: raw) else { return [] }
            let minutes = d.end.timeIntervalSince(d.start) / 60
            switch stage {
            case .inBed: return []
            case .awake: return [s(.sleepAwake, minutes, q: .derived)]
            case .asleepUnspecified: return [s(.sleepDuration, minutes, q: .derived)]
            case .asleepCore: return [s(.sleepDuration, minutes, q: .derived), s(.sleepLight, minutes, q: .derived)]
            case .asleepDeep: return [s(.sleepDuration, minutes, q: .derived), s(.sleepDeep, minutes, q: .derived)]
            case .asleepREM: return [s(.sleepDuration, minutes, q: .derived), s(.sleepREM, minutes, q: .derived)]
            }
        case HealthTypeID.workout: return [s(.workoutDuration, d.value)]
        default: return []
        }
    }
}

/// Prüfbericht: Welche Datenarten liefert eine Quelle tatsächlich nach Apple Health?
/// (Auftrag: „Prüfe konkret, welche Datenarten tatsächlich verfügbar sind.“)
public struct SourceAvailabilityReport: Hashable, Sendable {
    public struct Entry: Hashable, Sendable {
        public var type: VitalType
        public var sampleCount: Int
        public var lastSample: Date?
    }
    public var source: DataSource
    public var checkedTypes: [VitalType]
    public var entries: [Entry]
    public var generatedAt: Date

    public var availableTypes: [VitalType] { entries.filter { $0.sampleCount > 0 }.map(\.type) }
    public var missingTypes: [VitalType] { checkedTypes.filter { !availableTypes.contains($0) } }

    public static func build(source: DataSource, samples: [VitalSample], checked: [VitalType], now: Date = Date()) -> SourceAvailabilityReport {
        let own = samples.filter { $0.source == source }
        let entries = checked.map { t -> Entry in
            let list = own.filter { $0.type == t }
            return Entry(type: t, sampleCount: list.count, lastSample: list.map(\.start).max())
        }
        return SourceAvailabilityReport(source: source, checkedTypes: checked, entries: entries, generatedAt: now)
    }
}
