import Foundation
import HealthKit
import WatchConnectivity
import FitnessCore

/// Zugriff auf Apple Health (iPhone). Minimale Berechtigungen, nur nach Einwilligung.
final class HealthKitService: @unchecked Sendable {
    let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    var isWatchPaired: Bool { WCSession.isSupported() && WCSession.default.isPaired }

    static let quantityTypes: [(HKQuantityTypeIdentifier, HKUnit)] = [
        (.heartRate, HKUnit.count().unitDivided(by: .minute())),
        (.restingHeartRate, HKUnit.count().unitDivided(by: .minute())),
        (.heartRateVariabilitySDNN, HKUnit.secondUnit(with: .milli)),
        (.activeEnergyBurned, .kilocalorie()),
        (.stepCount, .count()),
        (.respiratoryRate, HKUnit.count().unitDivided(by: .minute())),
        (.oxygenSaturation, .percent()),
    ]

    var readTypes: Set<HKObjectType> {
        var s = Set<HKObjectType>(Self.quantityTypes.map { HKQuantityType($0.0) })
        s.insert(HKCategoryType(.sleepAnalysis))
        s.insert(HKObjectType.workoutType())
        return s
    }

    /// Schreibrechte nur, wenn der Nutzer dem Speichern von Workouts zugestimmt hat.
    func requestAuthorization(write: Bool) async throws {
        guard isAvailable else { throw ProviderError.unavailable("Apple Health ist auf diesem Gerät nicht verfügbar") }
        let share: Set<HKSampleType> = write ? [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.heartRate)] : []
        try await store.requestAuthorization(toShare: share, read: readTypes)
    }

    /// Liest alle relevanten Proben seit `since` und bildet sie auf `HealthSampleDTO` ab.
    /// Hinweis: HealthKit verrät aus Datenschutzgründen nicht, ob Leserechte verweigert wurden –
    /// fehlende Daten erscheinen dann schlicht als „keine Daten“.
    func samples(since: Date, until: Date) async throws -> [HealthSampleDTO] {
        let datePredicate = HKQuery.predicateForSamples(withStart: since, end: until, options: [])
        var out: [HealthSampleDTO] = []
        // Ganztägige Herzfrequenz wird bewusst NICHT importiert (Datenmenge, Datensparsamkeit):
        // Der Trainingspuls kommt live von der Watch, der Ruhepuls als eigener Typ.
        for (id, unit) in Self.quantityTypes where id != .heartRate {
            let type = HKQuantityType(id)
            let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: type, predicate: datePredicate)],
                                                     sortDescriptors: [SortDescriptor(\.startDate)])
            for s in try await descriptor.result(for: store) {
                var v = s.quantity.doubleValue(for: unit)
                if id == .oxygenSaturation { v *= 100 }
                out.append(dto(s, typeId: id.rawValue, value: v))
            }
        }
        let sleep = HKSampleQueryDescriptor(predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: datePredicate)],
                                            sortDescriptors: [SortDescriptor(\.startDate)])
        for s in try await sleep.result(for: store) {
            out.append(dto(s, typeId: HKCategoryTypeIdentifier.sleepAnalysis.rawValue, value: 0, category: s.value))
        }
        let workouts = HKSampleQueryDescriptor(predicates: [.workout(datePredicate)], sortDescriptors: [SortDescriptor(\.startDate)])
        for w in try await workouts.result(for: store) {
            out.append(dto(w, typeId: HealthTypeID.workout, value: w.duration / 60))
        }
        return out
    }

    private func dto(_ s: HKSample, typeId: String, value: Double, category: Int? = nil) -> HealthSampleDTO {
        HealthSampleDTO(typeIdentifier: typeId, value: value, start: s.startDate, end: s.endDate, uuid: s.uuid.uuidString,
                        sourceBundleId: s.sourceRevision.source.bundleIdentifier, sourceName: s.sourceRevision.source.name,
                        deviceModel: s.device?.model ?? s.sourceRevision.productType, deviceName: s.device?.name,
                        categoryValue: category)
    }

    /// Speichert eine Einheit vom iPhone aus (nur wenn keine Watch-Aufzeichnung vorliegt).
    func saveWorkout(_ s: WorkoutSession) async throws -> String {
        let config = HKWorkoutConfiguration()
        config.activityType = s.dayType == .mobility || s.dayType == .recovery ? .flexibility : .functionalStrengthTraining
        config.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        try await builder.beginCollection(at: s.startedAt)
        try await builder.endCollection(at: s.endedAt ?? Date())
        try await builder.addMetadata([HKMetadataKeyWasUserEntered: false, "KBTRXSessionID": s.id.uuidString])
        guard let workout = try await builder.finishWorkout() else { throw ProviderError.unavailable("Workout konnte nicht erstellt werden") }
        return workout.uuid.uuidString
    }
}

/// HealthKit als Vitaldatenquelle (Apple Watch/iPhone bzw. Garmin über Apple Health).
struct HealthKitVitalProvider: VitalDataProvider {
    let service: HealthKitService
    let kind: IntegrationKind
    let ownBundleId: String?
    let include: @Sendable (DataSource) -> Bool

    init(service: HealthKitService, kind: IntegrationKind, ownBundleId: String?, include: @escaping @Sendable (DataSource) -> Bool) {
        self.service = service; self.kind = kind; self.ownBundleId = ownBundleId; self.include = include
    }

    func fetch(since: Date?, cursor: String?, until: Date) async throws -> ProviderBatch {
        let start = since ?? until.addingTimeInterval(-30 * 86400)
        let dtos = try await service.samples(since: start, until: until)
        let samples = dtos.flatMap { HealthSampleMapper.map($0, ownBundleId: ownBundleId) }.filter { include($0.source) }
        return ProviderBatch(samples: samples, cursor: nil, syncedUntil: until)
    }
}
