// The real rows.
//
// The same table the web reads, through the same REST endpoint its client
// library talks to underneath. Row level security does the protecting, so
// the publishable key below is meant to ship — it grants nothing on its own,
// and every policy in supabase/schema.sql is `auth.uid() = user_id`.
//
// Talking to PostgREST directly rather than through a client library is a
// deliberate choice for this half. Five endpoints, four verbs, no state: a
// dependency would be carrying a session manager, a realtime socket and a
// storage client to get `GET /projects`. Auth is the opposite case — PKCE,
// refresh races, Keychain — and that is where the library earns its place.
// So the session arrives from outside, as a token and a user id.

import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// What a signed-in user is, as far as the rows are concerned.
public struct SupabaseSession: Sendable, Equatable {
    public let accessToken: String
    /// `auth.uid()`. Insert needs it spelled out: `user_id` has no default.
    public let userId: String

    public init(accessToken: String, userId: String) {
        self.accessToken = accessToken
        self.userId = userId
    }
}

public actor SupabaseProjectStore: ProjectStore {
    /// The project's own instance, from the web app's src/auth.ts.
    public static let projectURL = URL(string: "https://iayngkirvbjlsmgtymnl.supabase.co")!
    public static let publishableKey = "sb_publishable_9cBv22ifdlp-nFn_d4VhoQ_qoNoQOvF"

    /// The columns, in the web's order. A row written with any other set is
    /// a row a browser cannot read.
    static let columns = "id,name,bpm,root_pc,scale,tracks,updated_at"

    public typealias Session = @Sendable () async -> SupabaseSession?
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let baseURL: URL
    private let key: String
    private let session: Session
    private let transport: Transport
    private let random: RandomSource

    public init(
        baseURL: URL = SupabaseProjectStore.projectURL,
        key: String = SupabaseProjectStore.publishableKey,
        session: @escaping Session,
        random: RandomSource = SystemRandomSource(),
        transport: @escaping Transport = SupabaseProjectStore.urlSession
    ) {
        self.baseURL = baseURL
        self.key = key
        self.session = session
        self.random = random
        self.transport = transport
    }

    // -------------------------------------------------------------- the rows --

    public func list() async throws -> [Project] {
        try await send(
            .get, query: "select=\(Self.columns)&order=updated_at.desc",
            decoding: [Project].self)
    }

    public func create(name: String?, snapshot: ProjectSnapshot) async throws -> Project {
        let session = try await signedIn()
        let body = NewRow(
            userId: session.userId,
            name: name ?? ProjectNames.random(using: random),
            bpm: snapshot.bpm,
            rootPc: snapshot.rootPc,
            scale: snapshot.scale,
            tracks: snapshot.tracks)
        let rows = try await send(
            .post, query: "select=\(Self.columns)", body: try JSONEncoder().encode(body),
            decoding: [Project].self)
        guard let row = rows.first else { throw ProjectStoreError.transport("Insert wrote nothing") }
        return row
    }

    public func save(id: String, snapshot: ProjectSnapshot) async throws {
        let body = PatchRow(
            bpm: snapshot.bpm, rootPc: snapshot.rootPc, scale: snapshot.scale,
            tracks: snapshot.tracks)
        try await patch(id: id, body: try JSONEncoder().encode(body))
    }

    public func rename(id: String, to name: String) async throws {
        try await patch(id: id, body: try JSONEncoder().encode(PatchRow(name: name)))
    }

    public func delete(id: String) async throws {
        // `return=representation` is what makes a delete that matched
        // nothing distinguishable from one that matched a row.
        let rows = try await send(
            .delete, query: "id=eq.\(id)&select=id", decoding: [Touched].self)
        if rows.isEmpty { throw ProjectStoreError.notFound }
    }

    private func patch(id: String, body: Data) async throws {
        let rows = try await send(
            .patch, query: "id=eq.\(id)&select=id", body: body, decoding: [Touched].self)
        if rows.isEmpty { throw ProjectStoreError.notFound }
    }

    // ------------------------------------------------------------ the wire --

    private enum Method: String {
        case get = "GET"
        case post = "POST"
        case patch = "PATCH"
        case delete = "DELETE"
    }

    private func signedIn() async throws -> SupabaseSession {
        guard let session = await session() else { throw ProjectStoreError.notSignedIn }
        return session
    }

    private func send<T: Decodable>(
        _ method: Method, query: String, body: Data? = nil, decoding: T.Type
    ) async throws -> T {
        let session = try await signedIn()
        var request = URLRequest(
            url: baseURL.appendingPathComponent("rest/v1/projects")
                .appending(query: query))
        request.httpMethod = method.rawValue
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = body

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport(request)
        } catch {
            // No network, DNS gone, the request cancelled. Nothing above
            // here can tell those apart or act on the difference.
            throw ProjectStoreError.transport(error.localizedDescription)
        }

        guard (200..<300).contains(response.statusCode) else {
            throw Self.failure(response.statusCode, data)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ProjectStoreError.transport("Unreadable reply")
        }
    }

    /// PostgREST answers with `{ message, details, hint, code }`.
    static func failure(_ status: Int, _ data: Data) -> ProjectStoreError {
        if status == 401 || status == 403 { return .notSignedIn }
        if let body = try? JSONDecoder().decode(Complaint.self, from: data),
            let message = body.message, !message.isEmpty
        {
            return .transport(message)
        }
        return .transport("HTTP \(status)")
    }

    public static let urlSession: Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProjectStoreError.transport("Not an HTTP reply")
        }
        return (data, http)
    }

    // ------------------------------------------------------------- the body --

    private struct NewRow: Encodable {
        let userId: String
        let name: String
        let bpm: Int
        let rootPc: Int
        let scale: String
        let tracks: [TrackSnapshot]

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case name
            case bpm
            case rootPc = "root_pc"
            case scale
            case tracks
        }
    }

    /// A partial write. Only what is set is sent, which is what makes a
    /// rename a rename rather than a rename that also writes the pattern.
    private struct PatchRow: Encodable {
        var name: String?
        var bpm: Int?
        var rootPc: Int?
        var scale: String?
        var tracks: [TrackSnapshot]?

        init(
            name: String? = nil, bpm: Int? = nil, rootPc: Int? = nil,
            scale: String? = nil, tracks: [TrackSnapshot]? = nil
        ) {
            self.name = name
            self.bpm = bpm
            self.rootPc = rootPc
            self.scale = scale
            self.tracks = tracks
        }

        enum CodingKeys: String, CodingKey {
            case name
            case bpm
            case rootPc = "root_pc"
            case scale
            case tracks
        }
    }

    private struct Touched: Decodable {
        let id: String
    }

    struct Complaint: Decodable {
        let message: String?
    }
}

extension URL {
    /// `appending(queryItems:)` percent-encodes the `eq.` and the commas
    /// PostgREST wants left alone, so the query goes on as written.
    fileprivate func appending(query: String) -> URL {
        URL(string: absoluteString + "?" + query) ?? self
    }
}
