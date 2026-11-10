//
//  EmulatorBackend.swift
//  TeacherMinuteUITests
//
//  The test's own line to the local Firebase emulators, over their REST APIs:
//  it creates accounts, writes the data a scene needs, reads back what the app
//  and the backend did, and plays other people — a second teacher accepting —
//  by calling the real functions.
//
//  Admin writes go in as the emulators' `owner`, which skips the security
//  rules, the way the backend's own writes do. Everything here exists only in
//  the emulators: the project is `demo-teacher-in-a-moment`, which Firebase
//  never resolves to a real one.
//
//  The runner on a simulator shares the Mac's network, so 127.0.0.1 is the
//  Mac running the emulators.
//

import Foundation

struct EmulatorBackend {
    static let host = "127.0.0.1"
    static let projectID = "demo-teacher-in-a-moment"

    private let authBase = "http://\(host):9099"
    private let firestoreBase = "http://\(host):8085/v1/projects/\(projectID)/databases/(default)/documents"
    private let databaseBase = "http://\(host):9000"
    /// The namespace the Functions emulator uses for a demo project — the
    /// bare project id — so the test, the app and the backend share one
    /// database.
    private let databaseNamespace = projectID
    private let functionsBase = "http://\(host):5001/\(projectID)/us-central1"

    struct Account {
        let uid: String
        let email: String
        let password: String
        let idToken: String
    }

    /// What a callable answered: its result, or the refusal's status and reason.
    struct CallOutcome: CustomStringConvertible {
        let succeeded: Bool
        let status: String?
        let reason: String?
        let message: String?
        var result: [String: Any]? = nil

        var description: String {
            succeeded ? "succeeded" : "refused status=\(status ?? "-") reason=\(reason ?? "-") message=\(message ?? "-")"
        }
    }

    enum Failure: Error, CustomStringConvertible {
        case unreachable(String)
        case badResponse(String)

        var description: String {
            switch self {
            case .unreachable(let what): "emulator unreachable: \(what)"
            case .badResponse(let what): "unexpected emulator response: \(what)"
            }
        }
    }

    // MARK: - Reachability

    /// True when the Auth and Functions emulators both answer. The suite
    /// skips itself otherwise, so a plain UI-test run never fails on it.
    func isRunning() async -> Bool {
        for url in ["\(authBase)/", "\(functionsBase)/acceptInvite"] {
            var request = URLRequest(url: URL(string: url)!)
            request.timeoutInterval = 3
            guard (try? await URLSession.shared.data(for: request)) != nil else { return false }
        }
        return true
    }

    // MARK: - Auth

    func createAccount(prefix: String) async throws -> Account {
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let email = "\(prefix).\(stamp).\(Int.random(in: 100...999))@example.com"
        let password = "Emulator-\(Int.random(in: 100_000...999_999))"
        let json = try await send(
            "POST",
            "\(authBase)/identitytoolkit.googleapis.com/v1/accounts:signUp?key=emulator",
            body: ["email": email, "password": password, "returnSecureToken": true]
        )
        guard let uid = json?["localId"] as? String, let token = json?["idToken"] as? String else {
            throw Failure.badResponse("signUp: \(String(describing: json))")
        }
        return Account(uid: uid, email: email, password: password, idToken: token)
    }

    // MARK: - Firestore

    /// Merges `fields` into the document, creating it if needed.
    func merge(_ path: String, _ fields: [String: Any]) async throws {
        let mask = fields.keys.map { "updateMask.fieldPaths=\($0)" }.joined(separator: "&")
        _ = try await send(
            "PATCH",
            "\(firestoreBase)/\(path)?\(mask)",
            body: ["fields": fields.mapValues(Self.firestoreValue)],
            owner: true
        )
    }

    /// The document's string fields, or nil if it does not exist.
    func strings(_ path: String) async throws -> [String: String]? {
        guard let json = try await send("GET", "\(firestoreBase)/\(path)", owner: true, allowMissing: true),
              let fields = json["fields"] as? [String: [String: Any]] else { return nil }
        return fields.compactMapValues { $0["stringValue"] as? String }
    }

    private static func firestoreValue(_ value: Any) -> [String: Any] {
        switch value {
        case let value as Bool: ["booleanValue": value]
        case let value as Int: ["integerValue": String(value)]
        case let value as Double: ["doubleValue": value]
        case let value as String: ["stringValue": value]
        case let value as Date: ["timestampValue": ISO8601DateFormatter().string(from: value)]
        case let value as [Any]: ["arrayValue": ["values": value.map(firestoreValue)]]
        case let value as [String: Any]: ["mapValue": ["fields": value.mapValues(firestoreValue)]]
        default: ["nullValue": NSNull()]
        }
    }

    // MARK: - Realtime Database

    func put(_ path: String, _ value: Any) async throws {
        _ = try await send("PUT", databaseURL(path), body: value, owner: true)
    }

    /// Merges `value` into what is stored at `path`.
    func patch(_ path: String, _ value: [String: Any]) async throws {
        _ = try await send("PATCH", databaseURL(path), body: value, owner: true)
    }

    func delete(_ path: String) async throws {
        _ = try await raw("DELETE", databaseURL(path), body: nil, owner: true)
    }

    /// What is stored at `path`, decoded from JSON; nil when nothing is.
    func value(_ path: String) async throws -> Any? {
        let (data, _) = try await raw("GET", databaseURL(path), body: nil, owner: true)
        let decoded = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return decoded is NSNull ? nil : decoded
    }

    /// The names of the children of `path`, without their contents.
    func childKeys(_ path: String) async throws -> [String] {
        let (data, _) = try await raw("GET", databaseURL(path) + "&shallow=true", body: nil, owner: true)
        return ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]).map { Array($0.keys) } ?? []
    }

    /// Whether anything is stored at `path`.
    func exists(_ path: String) async throws -> Bool {
        let (data, _) = try await raw("GET", databaseURL(path), body: nil, owner: true)
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) != "null"
    }

    private func databaseURL(_ path: String) -> String {
        "\(databaseBase)/\(path).json?ns=\(databaseNamespace)"
    }

    // MARK: - Functions

    /// Calls a callable as `account`, the way the apps do.
    func call(_ function: String, as account: Account, data: [String: Any]) async throws -> CallOutcome {
        var request = URLRequest(url: URL(string: "\(functionsBase)/\(function)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(account.idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": data])
        request.timeoutInterval = 60
        let (body, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        if let error = json?["error"] as? [String: Any] {
            let details = error["details"] as? [String: Any]
            return CallOutcome(
                succeeded: false,
                status: error["status"] as? String,
                reason: details?["reason"] as? String,
                message: error["message"] as? String
            )
        }
        return CallOutcome(
            succeeded: json?["result"] != nil, status: nil, reason: nil, message: nil,
            result: json?["result"] as? [String: Any]
        )
    }

    // MARK: - Transport

    private func send(
        _ method: String,
        _ url: String,
        body: Any? = nil,
        owner: Bool = false,
        allowMissing: Bool = false
    ) async throws -> [String: Any]? {
        let (data, status) = try await raw(method, url, body: body, owner: owner)
        if allowMissing && status == 404 { return nil }
        guard (200..<300).contains(status) else {
            throw Failure.badResponse("\(method) \(url) → \(status) \(String(data: data, encoding: .utf8) ?? "")")
        }
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any]
    }

    private func raw(_ method: String, _ url: String, body: Any?, owner: Bool) async throws -> (Data, Int) {
        guard let target = URL(string: url) else { throw Failure.badResponse("bad URL \(url)") }
        var request = URLRequest(url: target)
        request.httpMethod = method
        request.timeoutInterval = 30
        if owner { request.setValue("Bearer owner", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.fragmentsAllowed])
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw Failure.unreachable("\(method) \(url): \(error.localizedDescription)")
        }
    }
}
