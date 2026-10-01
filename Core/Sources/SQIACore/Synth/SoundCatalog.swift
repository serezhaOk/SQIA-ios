// Sounds that arrive without a release.
//
// The Lab publishes a sound as a row in `sounds` and, if it is made of
// recordings, a folder of WAVs in the public `sounds` bucket (see
// supabase/migrations/20261001100000_sounds.sql). The app reads the table
// at launch, keeps the last answer on disk for when there is no network,
// and downloads a sound's recordings the first time something needs them.
//
// Everything here is plain HTTPS through an injected transport, so it is
// tested off a device and builds on Linux like the rest of the core.

import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// One row of `sounds`.
public struct SoundRow: Codable, Sendable, Equatable {
    public var id: Int
    public var name: String
    public var hint: String
    /// Nil for a row that only re-labels, re-orders, hides or locks a sound
    /// the bundle already has.
    public var preset: PresetFile?
    public var samples: SampleManifest?
    public var position: Int
    public var visible: Bool
    public var plus: Bool
    /// The core a sound needs. A sound made for features this build does not
    /// have is left out rather than played wrong.
    public var minCore: Int

    enum CodingKeys: String, CodingKey {
        case id, name, hint, preset, samples, position, visible, plus
        case minCore = "min_core"
    }

    public init(
        id: Int, name: String, hint: String = "", preset: PresetFile? = nil,
        samples: SampleManifest? = nil, position: Int = 0, visible: Bool = true,
        plus: Bool = false, minCore: Int = 1
    ) {
        self.id = id
        self.name = name
        self.hint = hint
        self.preset = preset
        self.samples = samples
        self.position = position
        self.visible = visible
        self.plus = plus
        self.minCore = minCore
    }
}

public enum SoundCatalog {
    /// What this build's SQIASound can play. Raised when the core learns
    /// something a preset could depend on.
    public static let coreVersion = 1

    /// The bundle's sounds with the table laid over them, in picker order.
    public static func merge(bundled: [Sound], rows: [SoundRow]) -> [Sound] {
        var sounds = Dictionary(uniqueKeysWithValues: bundled.map { ($0.id, $0) })
        for row in rows where row.minCore <= coreVersion && row.id >= TrackVoice.firstSoundIndex {
            if let preset = row.preset {
                guard
                    var sound = Sound(
                        id: row.id, preset: preset, hint: row.hint, samples: row.samples,
                        plus: row.plus, position: row.position, visible: row.visible)
                else { continue }
                sound.name = row.name
                sounds[row.id] = sound
            } else if var sound = sounds[row.id] {
                sound.name = row.name
                sound.hint = row.hint
                sound.position = row.position
                sound.visible = row.visible
                sound.plus = row.plus
                sounds[row.id] = sound
            }
        }
        return sounds.values.sorted { ($0.position, $0.id) < ($1.position, $1.id) }
    }
}

/// The table and the bucket, and the copies of both kept on the phone.
public actor SoundStore {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    /// Fetches one file, telling `progress` how many bytes have arrived.
    public typealias Downloader =
        @Sendable (URLRequest, _ progress: @escaping @Sendable (Int) -> Void) async throws -> Data

    public enum Failure: Error, Equatable {
        case http(Int)
        case unreadable
        case incomplete
    }

    static let bucket = "sounds"

    private let baseURL: URL
    private let key: String
    private let directory: URL
    private let transport: Transport
    private let downloader: Downloader

    public init(
        baseURL: URL = SupabaseProjectStore.projectURL,
        key: String = SupabaseProjectStore.publishableKey,
        directory: URL,
        transport: @escaping Transport = SupabaseProjectStore.urlSession,
        downloader: @escaping Downloader = SoundStore.urlSessionDownload
    ) {
        self.baseURL = baseURL
        self.key = key
        self.directory = directory
        self.transport = transport
        self.downloader = downloader
    }

    /// Where the phone keeps them: Application Support, which is not purged
    /// under storage pressure the way Caches is — a project should not go
    /// quiet because the phone ran low on space. The recordings are kept
    /// out of backups, since they can always be downloaded again.
    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sounds", isDirectory: true)
    }

    private var catalogFile: URL { directory.appendingPathComponent("catalog.json") }

    // ------------------------------------------------------------ the table --

    /// The rows as last fetched, or none if they never have been.
    public func cachedRows() -> [SoundRow] {
        guard let data = try? Data(contentsOf: catalogFile) else { return [] }
        return (try? JSONDecoder().decode([SoundRow].self, from: data)) ?? []
    }

    /// Every row, hidden ones included — a hidden sound still has to be
    /// found for the projects that use it. Kept on disk on success.
    public func fetchRows() async throws -> [SoundRow] {
        var request = URLRequest(
            url: baseURL.appendingPathComponent("rest/v1/sounds")
                .appending(query: "select=*&order=position.asc,id.asc"))
        request.setValue(key, forHTTPHeaderField: "apikey")
        let (data, response) = try await transport(request)
        guard (200..<300).contains(response.statusCode) else {
            throw Failure.http(response.statusCode)
        }
        guard let rows = try? JSONDecoder().decode([SoundRow].self, from: data) else {
            throw Failure.unreadable
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: catalogFile, options: .atomic)
        return rows
    }

    // ----------------------------------------------------------- the files --

    public func folder(for manifest: SampleManifest) -> URL {
        directory.appendingPathComponent("samples", isDirectory: true)
            .appendingPathComponent(manifest.folder, isDirectory: true)
    }

    /// All of it on the phone already. A file is written whole or not at
    /// all, so being there at the right size means being complete.
    public func isDownloaded(_ manifest: SampleManifest) -> Bool {
        let folder = folder(for: manifest)
        return manifest.samples.allSatisfy { entry in
            let path = folder.appendingPathComponent(entry.file).path
            guard let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int
            else { return false }
            return entry.bytes.map { $0 == size } ?? true
        }
    }

    /// Fetches whatever is missing. `progress` runs from 0 to 1 over the
    /// whole set, files already here counting as done.
    @discardableResult
    public func download(
        _ manifest: SampleManifest, progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> URL {
        let folder = folder(for: manifest)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        excludeFromBackup(directory.appendingPathComponent("samples", isDirectory: true))

        // Sizes may be missing from a hand-written manifest; a file then
        // counts as one unit, which is still a bar that moves.
        let weights = manifest.samples.map { max($0.bytes ?? 1, 1) }
        let total = Double(weights.reduce(0, +))
        var done = 0
        progress(0)

        for (entry, weight) in zip(manifest.samples, weights) {
            let file = folder.appendingPathComponent(entry.file)
            let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int
            if let size, entry.bytes.map({ $0 == size }) ?? true {
                done += weight
                progress(Double(done) / total)
                continue
            }
            try Task.checkCancellation()
            let base = done
            let request = URLRequest(url: publicURL(manifest.folder, entry.file))
            let data = try await downloader(request) { received in
                let partial = entry.bytes == nil ? 0 : min(received, weight)
                progress(Double(base + partial) / total)
            }
            if let bytes = entry.bytes, bytes != data.count { throw Failure.incomplete }
            try data.write(to: file, options: .atomic)
            done += weight
            progress(Double(done) / total)
        }
        return folder
    }

    /// Recordings no row points at any more — replaced by a newer upload,
    /// or the sound withdrawn. Run after a fresh catalogue.
    public func prune(keeping manifests: [SampleManifest]) {
        let root = directory.appendingPathComponent("samples", isDirectory: true)
        let keep = Set(manifests.map(\.folder))
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        for name in folders where !keep.contains(name) {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(name))
        }
    }

    private func excludeFromBackup(_ url: URL) {
        #if os(iOS) || os(macOS)
            var url = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        #endif
    }

    private func publicURL(_ folder: String, _ file: String) -> URL {
        baseURL.appendingPathComponent("storage/v1/object/public")
            .appendingPathComponent(Self.bucket)
            .appendingPathComponent(folder)
            .appendingPathComponent(file)
    }

    // ------------------------------------------------------------ transport --

    public static let urlSessionDownload: Downloader = { request, progress in
        #if canImport(FoundationNetworking)
            // Linux has no streaming reads; the bar jumps a file at a time.
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
            else { throw Failure.http((response as? HTTPURLResponse)?.statusCode ?? 0) }
            progress(data.count)
            return data
        #else
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
            else { throw Failure.http((response as? HTTPURLResponse)?.statusCode ?? 0) }
            var data = Data()
            if http.expectedContentLength > 0 { data.reserveCapacity(Int(http.expectedContentLength)) }
            var chunk = [UInt8]()
            chunk.reserveCapacity(64 * 1024)
            for try await byte in bytes {
                chunk.append(byte)
                if chunk.count == 64 * 1024 {
                    data.append(contentsOf: chunk)
                    chunk.removeAll(keepingCapacity: true)
                    progress(data.count)
                }
            }
            data.append(contentsOf: chunk)
            progress(data.count)
            return data
        #endif
    }
}
