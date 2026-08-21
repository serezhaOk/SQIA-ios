// The requests that reach Supabase, and what the answers are read as.
//
// No server here — the transport is a closure, so what is under test is the
// thing that actually has to be right: the columns asked for, the order, the
// filter on a write, the body of an insert, and the difference between a
// delete that matched a row and one that matched nothing. Those are the
// parts a browser and a phone have to agree on.

import Foundation
import Testing

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

@testable import SQIACore

private let session = SupabaseSession(accessToken: "jwt-here", userId: "user-1")

private func snapshot(bpm: Int = 120) -> ProjectSnapshot {
    ProjectSnapshot(
        bpm: bpm, rootPc: 4, scale: "dorian",
        tracks: [TrackSnapshot(voiceIdx: 2, muted: true, grid: NoteGrid())])
}

/// Every request the store made, and what to answer with.
private actor Wire {
    private(set) var requests: [URLRequest] = []
    private var replies: [(status: Int, body: String)]
    private let failWith: Error?

    init(replies: [(status: Int, body: String)] = [(200, "[]")], failWith: Error? = nil) {
        self.replies = replies
        self.failWith = failWith
    }

    func take(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if let failWith { throw failWith }
        let reply = replies.count > 1 ? replies.removeFirst() : replies[0]
        let response = HTTPURLResponse(
            url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
            headerFields: nil)!
        return (Data(reply.body.utf8), response)
    }

    var last: URLRequest? { requests.last }
    var count: Int { requests.count }
}

private func store(
    _ wire: Wire, session provider: @escaping SupabaseProjectStore.Session = { session }
) -> SupabaseProjectStore {
    SupabaseProjectStore(
        baseURL: URL(string: "https://example.supabase.co")!,
        key: "publishable-key",
        session: provider,
        random: Mulberry32(seed: 4),
        transport: { try await wire.take($0) })
}

private let oneRow = """
    [{"id":"abc","name":"Wild Amoeba","bpm":137,"root_pc":4,"scale":"dorian",\
    "tracks":[],"updated_at":"2026-08-21T12:00:00Z"}]
    """

@Suite("Supabase rows")
struct SupabaseProjectStoreTests {
    @Test("Listing asks for the web's columns, newest first")
    func listQuery() async throws {
        let wire = Wire(replies: [(200, oneRow)])
        let all = try await store(wire).list()

        #expect(all.count == 1)
        #expect(all[0].name == "Wild Amoeba")

        let request = await wire.last
        let url = request?.url?.absoluteString ?? ""
        #expect(request?.httpMethod == "GET")
        #expect(url.hasPrefix("https://example.supabase.co/rest/v1/projects?"))
        #expect(url.contains("select=id,name,bpm,root_pc,scale,tracks,updated_at"))
        #expect(url.contains("order=updated_at.desc"))
    }

    @Test("Every request carries the key and the session's token")
    func headers() async throws {
        let wire = Wire(replies: [(200, "[]")])
        _ = try await store(wire).list()

        // Read back through `value(forHTTPHeaderField:)`, which is
        // case-insensitive: Foundation canonicalises the spelling of a
        // header name differently on Linux than on Darwin, and that is
        // Foundation's business rather than something to pin down here.
        let request = await wire.last
        #expect(request?.value(forHTTPHeaderField: "apikey") == "publishable-key")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer jwt-here")
        #expect(request?.value(forHTTPHeaderField: "Prefer") == "return=representation")
        #expect(request?.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test("Creating spells out the owner, because the column has no default")
    func insertBody() async throws {
        let wire = Wire(replies: [(200, oneRow)])
        let made = try await store(wire).create(name: "Named", snapshot: snapshot(bpm: 137))
        #expect(made.id == "abc")

        let request = await wire.last
        #expect(request?.httpMethod == "POST")
        let body = try #require(request?.httpBody)
        let json = try #require(
            try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["user_id"] as? String == "user-1")
        #expect(json["name"] as? String == "Named")
        #expect(json["bpm"] as? Int == 137)
        #expect(json["root_pc"] as? Int == 4)
        #expect(json["scale"] as? String == "dorian")
        #expect(json["tracks"] is [Any])
        // Not ours to set: Postgres owns both.
        #expect(json["id"] == nil)
        #expect(json["updated_at"] == nil)
    }

    @Test("An unnamed project arrives already named")
    func insertNamesItself() async throws {
        let wire = Wire(replies: [(200, oneRow)])
        _ = try await store(wire).create(name: nil, snapshot: snapshot())

        let body = try #require(await wire.last?.httpBody)
        let json = try #require(
            try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let name = try #require(json["name"] as? String)
        #expect(!name.isEmpty)
    }

    @Test("Saving patches that row and writes only the pattern")
    func savePatch() async throws {
        let wire = Wire(replies: [(200, #"[{"id":"abc"}]"#)])
        try await store(wire).save(id: "abc", snapshot: snapshot(bpm: 91))

        let request = await wire.last
        #expect(request?.httpMethod == "PATCH")
        #expect(request?.url?.absoluteString.contains("id=eq.abc") == true)
        let body = try #require(request?.httpBody)
        let json = try #require(
            try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["bpm"] as? Int == 91)
        #expect(json["tracks"] is [Any])
        // A save is not a rename.
        #expect(json["name"] == nil)
    }

    @Test("Renaming writes the name and nothing else")
    func renamePatch() async throws {
        let wire = Wire(replies: [(200, #"[{"id":"abc"}]"#)])
        try await store(wire).rename(id: "abc", to: "Bee")

        let body = try #require(await wire.last?.httpBody)
        let json = try #require(
            try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["name"] as? String == "Bee")
        #expect(json.count == 1, "a rename wrote \(json.keys.sorted())")
    }

    @Test("A write that matched no row is a missing row, not a success")
    func emptyPatchIsNotFound() async throws {
        let wire = Wire(replies: [(200, "[]")])
        let subject = store(wire)

        await #expect(throws: ProjectStoreError.notFound) {
            try await subject.save(id: "gone", snapshot: snapshot())
        }
        await #expect(throws: ProjectStoreError.notFound) {
            try await subject.rename(id: "gone", to: "Nope")
        }
        await #expect(throws: ProjectStoreError.notFound) {
            try await subject.delete(id: "gone")
        }
    }

    @Test("Deleting filters to that row and asks what it hit")
    func deleteQuery() async throws {
        let wire = Wire(replies: [(200, #"[{"id":"abc"}]"#)])
        try await store(wire).delete(id: "abc")

        let request = await wire.last
        #expect(request?.httpMethod == "DELETE")
        #expect(request?.url?.absoluteString.contains("id=eq.abc") == true)
    }

    @Test("No session means nothing is asked of the network at all")
    func signedOut() async throws {
        let wire = Wire()
        let subject = store(wire, session: { nil })

        await #expect(throws: ProjectStoreError.notSignedIn) {
            _ = try await subject.list()
        }
        let asked = await wire.count
        #expect(asked == 0)
    }

    @Test("A refused request is a signed-out one, whatever it was doing")
    func unauthorized() async throws {
        for status in [401, 403] {
            let wire = Wire(replies: [(status, #"{"message":"JWT expired"}"#)])
            let subject = store(wire)
            await #expect(throws: ProjectStoreError.notSignedIn) {
                _ = try await subject.list()
            }
        }
    }

    @Test("Postgres's complaint is what gets carried up")
    func serverComplaint() async throws {
        let wire = Wire(
            replies: [
                (400, #"{"message":"invalid input syntax for type integer","code":"22P02"}"#)
            ])
        let subject = store(wire)
        await #expect(
            throws: ProjectStoreError.transport("invalid input syntax for type integer")
        ) {
            _ = try await subject.list()
        }
    }

    @Test("A reply with nothing to say still says something useful")
    func statusOnly() async throws {
        let wire = Wire(replies: [(500, "<html>gateway</html>")])
        let subject = store(wire)
        await #expect(throws: ProjectStoreError.transport("HTTP 500")) {
            _ = try await subject.list()
        }
    }

    @Test("A dropped connection reads as a transport failure, not a crash")
    func networkGone() async throws {
        let wire = Wire(failWith: URLError(.notConnectedToInternet))
        let subject = store(wire)
        // The message is the system's; what matters is the shape.
        await #expect(throws: ProjectStoreError.self) {
            _ = try await subject.list()
        }
    }

    @Test("A reply in a shape we do not know is not read as an empty library")
    func unreadableReply() async throws {
        let wire = Wire(replies: [(200, #"{"rows": []}"#)])
        let subject = store(wire)
        await #expect(throws: ProjectStoreError.transport("Unreadable reply")) {
            _ = try await subject.list()
        }
    }

    @Test("The shipped instance is the web's")
    func sameProject() {
        // A different project reference here would be a phone writing to a
        // database the browser cannot see.
        #expect(
            SupabaseProjectStore.projectURL.absoluteString
                == "https://iayngkirvbjlsmgtymnl.supabase.co")
        #expect(SupabaseProjectStore.publishableKey.hasPrefix("sb_publishable_"))
        #expect(SupabaseProjectStore.columns == "id,name,bpm,root_pc,scale,tracks,updated_at")
    }
}
