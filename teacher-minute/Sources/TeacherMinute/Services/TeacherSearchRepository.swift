//
//  TeacherSearchRepository.swift
//  teacher-minute
//
//  Created by Codex on 10/05/2026.
//

import Foundation

struct TeacherSearchRequest: Encodable {
    let field: String
    let subfield: String
    let question: String
}

struct TeacherSearchResult {
    let statusCode: Int
    let responseText: String
}

@MainActor
protocol TeacherSearchRepository {
    func findTeachers(field: String, subfield: String, question: String) async throws -> TeacherSearchResult
}

@MainActor
final class CloudFunctionTeacherSearchRepository: TeacherSearchRepository {
    private let remoteConfigService: SettingsRemoteConfigService
    
    init(remoteConfigService: SettingsRemoteConfigService = .shared) {
        self.remoteConfigService = remoteConfigService
    }
    
    func findTeachers(field: String, subfield: String, question: String) async throws -> TeacherSearchResult {
        let baseURL = await remoteConfigService.fetchBaseURL()
        let endpointURL = baseURL.appendingPathComponent("findTeachers")
#if SKIP_BRIDGE
        return TeacherSearchResult(
            statusCode: 0,
            responseText: "Teacher search request is prepared for \(endpointURL.absoluteString)."
        )
#else
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            TeacherSearchRequest(
                field: field,
                subfield: subfield,
                question: question
            )
        )
        
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let responseText = String(data: data, encoding: .utf8) ?? ""
        
        guard (200..<300).contains(statusCode) else {
            throw TeacherSearchRepositoryError.requestFailed(statusCode: statusCode, responseText: responseText)
        }
        
        return TeacherSearchResult(statusCode: statusCode, responseText: responseText)
#endif
    }
}

enum TeacherSearchRepositoryError: LocalizedError {
    case requestFailed(statusCode: Int, responseText: String)
    
    var errorDescription: String? {
        switch self {
        case .requestFailed(let statusCode, let responseText):
            if responseText.isEmpty {
                return "Teacher search failed with status \(statusCode)."
            }
            return "Teacher search failed with status \(statusCode): \(responseText)"
        }
    }
}
