//
//  TranslationService.swift
//  AuralAI
//

import Foundation

final class TranslationService {
    static let shared = TranslationService()

    private init() {}

    func translate(_ text: String) async throws -> TranslationResult {
        let settings = TranslationSettings.shared
        let response: String

        switch settings.apiMode {
        case .openAICompatible:
            response = try await translateWithOpenAICompatibleAPI(text, settings: settings)
        case .direct:
            response = try await translateWithDirectAPI(text, settings: settings)
        }

        return try parseResponse(response, originalText: text)
    }

    func parseResponse(_ response: String, originalText: String) throws -> TranslationResult {
        let trimmedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["翻译：", "翻译:", "Translation:"]
        let translatedText = prefixes.first(where: { trimmedResponse.hasPrefix($0) })
            .map { String(trimmedResponse.dropFirst($0.count)).trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? trimmedResponse

        guard !translatedText.isEmpty else { throw TranslationError.parseError }

        return TranslationResult(
            originalText: originalText.trimmingCharacters(in: .whitespacesAndNewlines),
            translatedText: translatedText
        )
    }

    private func translateWithOpenAICompatibleAPI(
        _ text: String,
        settings: TranslationSettings,
        maxTokens: Int? = nil,
        canRetryAfterTruncation: Bool = true
    ) async throws -> String {
        let maximumAllowedTokens = try Self.maximumAllowedResponseTokens(
            for: text,
            systemPrompt: settings.systemPrompt
        )
        let responseTokenLimit = min(
            maxTokens ?? max(Self.dynamicMaxTokens(for: text), settings.maxTokens),
            maximumAllowedTokens
        )
        let request = try makeRequest(
            settings: settings,
            body: [
                "model": settings.modelName,
                "messages": [
                    ["role": "system", "content": settings.systemPrompt],
                    ["role": "user", "content": text]
                ],
                "max_tokens": responseTokenLimit,
                "stream": false
            ]
        )
        do {
            return try parseOpenAIResponse(try await performRequest(request))
        } catch TranslationError.responseTruncated
            where canRetryAfterTruncation && responseTokenLimit < maximumAllowedTokens {
            return try await translateWithOpenAICompatibleAPI(
                text,
                settings: settings,
                maxTokens: AIResponseTokenBudget.retryMaxTokens(
                    after: responseTokenLimit,
                    maximumAllowedTokens: maximumAllowedTokens
                ),
                canRetryAfterTruncation: false
            )
        }
    }

    private func translateWithDirectAPI(
        _ text: String,
        settings: TranslationSettings,
        maxTokens: Int? = nil,
        canRetryAfterTruncation: Bool = true
    ) async throws -> String {
        let maximumAllowedTokens = try Self.maximumAllowedResponseTokens(
            for: text,
            systemPrompt: settings.systemPrompt
        )
        let responseTokenLimit = min(
            maxTokens ?? max(Self.dynamicMaxTokens(for: text), settings.maxTokens),
            maximumAllowedTokens
        )
        let request = try makeRequest(
            settings: settings,
            body: [
                "anthropic_version": "vertex-2023-10-16",
                "max_tokens": responseTokenLimit,
                "system": settings.systemPrompt,
                "stream": false,
                "messages": [
                    ["role": "user", "content": text]
                ]
            ]
        )
        do {
            return try parseDirectResponse(try await performRequest(request))
        } catch TranslationError.responseTruncated
            where canRetryAfterTruncation && responseTokenLimit < maximumAllowedTokens {
            return try await translateWithDirectAPI(
                text,
                settings: settings,
                maxTokens: AIResponseTokenBudget.retryMaxTokens(
                    after: responseTokenLimit,
                    maximumAllowedTokens: maximumAllowedTokens
                ),
                canRetryAfterTruncation: false
            )
        }
    }

    func parseOpenAIResponse(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first else {
            throw TranslationError.parseError
        }
        if firstChoice["finish_reason"] as? String == "length" {
            throw TranslationError.responseTruncated
        }
        guard let responseText = (firstChoice["message"] as? [String: Any])?["content"] as? String,
              !responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationError.parseError
        }
        return responseText
    }

    func parseDirectResponse(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranslationError.parseError
        }
        if json["stop_reason"] as? String == "max_tokens" {
            throw TranslationError.responseTruncated
        }
        guard let responseText = (json["content"] as? [[String: Any]])?.first?["text"] as? String,
              !responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationError.parseError
        }
        return responseText
    }

    private func makeRequest(
        settings: TranslationSettings,
        body: [String: Any]
    ) throws -> URLRequest {
        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !apiKey.isEmpty else { throw TranslationError.missingAPIKey }
        guard let url = URL(string: endpoint) else { throw TranslationError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func dynamicMaxTokens(for text: String) -> Int {
        AIResponseTokenBudget.dynamicMaxTokens(for: text)
    }

    static func maximumAllowedResponseTokens(for text: String, systemPrompt: String) throws -> Int {
        guard let tokenLimit = AIResponseTokenBudget.maximumAllowedResponseTokens(
            for: text,
            systemPrompt: systemPrompt
        ) else {
            throw TranslationError.inputTooLong
        }
        return tokenLimit
    }

    private func performRequest(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }
        if httpResponse.statusCode == 401 {
            throw TranslationError.authExpired
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw TranslationError.apiError(statusCode: httpResponse.statusCode, body: body)
        }
        return data
    }
}

enum TranslationError: LocalizedError {
    case invalidURL
    case invalidResponse
    case missingAPIKey
    case authExpired
    case apiError(statusCode: Int, body: String)
    case inputTooLong
    case responseTruncated
    case parseError

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .missingAPIKey:
            return "API key is required"
        case .authExpired:
            return "Auth token expired, please retry"
        case .apiError(let statusCode, let body):
            return "API error \(statusCode): \(body.prefix(200))"
        case .inputTooLong:
            return "The selected text and system prompt are too long for one request"
        case .responseTruncated:
            return "The translation was truncated by the response token limit"
        case .parseError:
            return "Failed to parse translation response"
        }
    }
}
