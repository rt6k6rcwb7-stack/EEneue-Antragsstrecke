import Foundation

/// Dateibasierter, lokaler Speicher (Standard: ausschließlich auf dem Gerät).
///
/// * Jede Sammlung liegt in einer eigenen JSON-Datei.
/// * Schreiben erfolgt atomar; die vorherige Version bleibt als `.bak` erhalten.
///   Ist eine Datei beschädigt, wird automatisch die Sicherung gelesen.
/// * Auf iOS/watchOS werden Dateien mit Data Protection geschrieben
///   (`completeUntilFirstUserAuthentication`, damit ein laufendes Training auch bei gesperrtem
///   Gerät gespeichert werden kann).
public final class LocalStore: @unchecked Sendable {
    public let directory: URL
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    public private(set) var recoveredFromBackup: [String] = []

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        excludeFromBackupIfNeeded()
    }

    /// Standardverzeichnis „Application Support/KettlebellTRX“.
    public static func defaultDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return base.appendingPathComponent("KettlebellTRX", isDirectory: true)
    }

    func url(_ name: String) -> URL { directory.appendingPathComponent("\(name).json") }
    func backupURL(_ name: String) -> URL { directory.appendingPathComponent("\(name).json.bak") }

    public func save<T: Encodable>(_ value: T, as name: String) throws {
        let data = try encoder.encode(value)
        try lock.withLock {
            let fm = FileManager.default
            let target = url(name)
            if fm.fileExists(atPath: target.path) {
                let bak = backupURL(name)
                try? fm.removeItem(at: bak)
                try? fm.copyItem(at: target, to: bak)
            }
            #if os(iOS) || os(watchOS)
            try data.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: target, options: [.atomic])
            #endif
        }
    }

    public func load<T: Decodable>(_ type: T.Type, from name: String) throws -> T? {
        try lock.withLock {
            let fm = FileManager.default
            let primary = url(name)
            guard fm.fileExists(atPath: primary.path) || fm.fileExists(atPath: backupURL(name).path) else { return nil }
            do {
                return try decoder.decode(T.self, from: Data(contentsOf: primary))
            } catch {
                let bak = backupURL(name)
                guard fm.fileExists(atPath: bak.path) else { throw error }
                let value = try decoder.decode(T.self, from: Data(contentsOf: bak))
                recoveredFromBackup.append(name)
                return value
            }
        }
    }

    public func rawJSON(_ name: String) throws -> Any? {
        let u = url(name)
        guard FileManager.default.fileExists(atPath: u.path) else { return nil }
        return try JSONSerialization.jsonObject(with: Data(contentsOf: u))
    }

    public func writeRawJSON(_ object: Any, as name: String) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: url(name), options: [.atomic])
    }

    public func remove(_ name: String) {
        lock.withLock {
            try? FileManager.default.removeItem(at: url(name))
            try? FileManager.default.removeItem(at: backupURL(name))
        }
    }

    /// Löscht ALLE lokal gespeicherten Daten der App.
    public func removeAll() throws {
        try lock.withLock {
            let items = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for i in items { try FileManager.default.removeItem(at: i) }
        }
    }

    private func excludeFromBackupIfNeeded() {
        // Gesundheitsdaten bleiben in iCloud-Gerätebackups nur, wenn der Nutzer Cloud-Funktionen aktiviert.
        // Standard: vom Backup ausgeschlossen.
        #if os(iOS) || os(macOS)
        var dir = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        #endif
    }
}

#if !canImport(Darwin)
extension NSLock {
    func withLock<R>(_ body: () throws -> R) rethrows -> R {
        lock(); defer { unlock() }
        return try body()
    }
}
#endif
