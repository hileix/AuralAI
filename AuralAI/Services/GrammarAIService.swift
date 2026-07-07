//
//  GrammarAIService.swift
//  AuralAI
//

import Foundation

struct GrammarAIResponse {
    let translation: String?
    let errors: String?
    let options: [String]
}

final class GrammarAIService {
    static let shared = GrammarAIService()

    private init() {}

    func improveText(_ text: String) async throws -> String {
        let settings = GrammarSettings.shared

        switch settings.apiMode {
        case .openAICompatible:
            return try await improveTextWithOpenAICompatibleAPI(text, settings: settings)
        case .direct:
            return try await improveTextWithDirectAPI(text, settings: settings)
        }
    }

    private func improveTextWithOpenAICompatibleAPI(_ text: String, settings: GrammarSettings) async throws -> String {
        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !apiKey.isEmpty else {
            throw GrammarAIError.missingAPIKey
        }

        guard let url = URL(string: endpoint) else {
            throw GrammarAIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": settings.modelName,
            "messages": [
                ["role": "system", "content": settings.systemPrompt],
                ["role": "user", "content": text]
            ],
            "max_tokens": settings.maxTokens,
            "stream": false
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await performRequest(request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let responseText = message["content"] as? String else {
            throw GrammarAIError.parseError
        }

        return responseText
    }

    private func improveTextWithDirectAPI(_ text: String, settings: GrammarSettings) async throws -> String {
        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !apiKey.isEmpty else {
            throw GrammarAIError.missingAPIKey
        }

        guard let url = URL(string: endpoint) else {
            throw GrammarAIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "anthropic_version": "vertex-2023-10-16",
            "max_tokens": settings.maxTokens,
            "system": settings.systemPrompt,
            "messages": [
                ["role": "user", "content": text]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await performRequest(request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let responseText = firstBlock["text"] as? String else {
            throw GrammarAIError.parseError
        }

        return responseText
    }

    private func performRequest(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GrammarAIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw GrammarAIError.authExpired
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw GrammarAIError.apiError(statusCode: httpResponse.statusCode, body: body)
        }

        return data
    }

    func parseResponse(from response: String) -> GrammarAIResponse {
        var translation: String?
        var errors: String?
        var options: [String] = []

        var currentField: String?
        var currentValue = ""

        let prefixMap: [(field: String, prefixes: [String])] = [
            ("translation", ["翻译：", "翻译:"]),
            ("errors", ["错误：", "错误:"]),
            ("option", ["选项1：", "选项1:", "选项2：", "选项2:", "选项3：", "选项3:"]),
            ("improved", ["改进：", "改进:"])
        ]

        func commitField() {
            let value = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, let field = currentField else { return }
            switch field {
            case "translation":
                translation = value
            case "errors":
                errors = value
            case "option", "improved":
                options.append(value)
            default:
                break
            }
        }

        for line in response.components(separatedBy: .newlines) {
            var matched = false
            for (field, prefixes) in prefixMap {
                for prefix in prefixes where line.hasPrefix(prefix) {
                    commitField()
                    currentField = field
                    currentValue = String(line.dropFirst(prefix.count))
                    matched = true
                    break
                }
                if matched { break }
            }
            if !matched && currentField != nil {
                currentValue += "\n" + line
            }
        }
        commitField()

        if errors == "无" {
            errors = nil
        }
        if options.isEmpty {
            options = [response.trimmingCharacters(in: .whitespacesAndNewlines)]
        }

        return GrammarAIResponse(translation: translation, errors: errors, options: options)
    }
}

enum GrammarAIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case missingAPIKey
    case authExpired
    case apiError(statusCode: Int, body: String)
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
        case .apiError(let code, let body):
            return "API error \(code): \(body.prefix(200))"
        case .parseError:
            return "Failed to parse API response"
        }
    }
}
