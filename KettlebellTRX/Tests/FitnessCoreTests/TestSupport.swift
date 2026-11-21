import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import FitnessCore

enum TS {
    static let library: ExerciseLibrary = try! ExerciseLibrary.bundled()
    static var cal: Calendar { .iso8601Monday }

    /// Montag, 2. November 2026, 08:00 Ortszeit.
    static var monday: Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 8))! }

    static func date(_ day: Int, _ hour: Int = 8, month: Int = 11) -> Date {
        cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    static func tempDir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("fc-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static func plan(profile: UserProfile = .initial()) -> TrainingPlan {
        PlanGenerator(library: library, profile: profile).generate(startDate: monday)
    }

    static func sample(_ t: VitalType, _ v: Double, day: Int, source: DataSource, channel: DataChannel = .healthKit,
                       id: String? = nil, month: Int = 11) -> VitalSample {
        let end = date(day, 7, month: month)
        return VitalSample(type: t, value: v, start: end.addingTimeInterval(-3600), end: end, source: source, channel: channel,
                           sourceRecordId: id ?? "\(t.rawValue)-\(source.rawValue)-\(month)-\(day)")
    }
}

/// Deterministischer HTTP-Client für Tests.
final class MockHTTP: HTTPClient, @unchecked Sendable {
    var handler: (URLRequest) throws -> (Int, Data, [String: String])
    private(set) var requests: [URLRequest] = []
    private let lock = NSLock()
    init(_ handler: @escaping (URLRequest) throws -> (Int, Data, [String: String])) { self.handler = handler }

    private func record(_ r: URLRequest) { lock.lock(); requests.append(r); lock.unlock() }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        record(request)
        let (status, data, headers) = try handler(request)
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
    }
}
