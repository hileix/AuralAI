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

    private static let minimumResponseTokens = 1_024
    private static let maximumResponseTokens = 8_192
    private static let responseTokenStep = 64
    private static let responseFormatOverhead = 192
    private static let responseExpansionNumerator = 11
    private static let responseExpansionDenominator = 2
    private static let minimumReasoningTokens = 768
    private static let reasoningExpansionMultiplier = 2
    private static let conservativeContextWindowTokens = 32_768
    private static let contextSafetyMarginTokens = 512
    private static let messageFormatOverheadTokens = 32

    private init() {}

    func improveText(
        _ text: String,
        onPartialResponse: ((String) async -> Void)? = nil
    ) async throws -> String {
        let settings = GrammarSettings.shared

        switch settings.apiMode {
        case .openAICompatible:
            return try await improveTextWithOpenAICompatibleAPI(
                text,
                settings: settings,
                onPartialResponse: onPartialResponse
            )
        case .direct:
            return try await improveTextWithDirectAPI(
                text,
                settings: settings,
                onPartialResponse: onPartialResponse
            )
        }
    }

    private func improveTextWithOpenAICompatibleAPI(
        _ text: String,
        settings: GrammarSettings,
        onPartialResponse: ((String) async -> Void)?,
        maxTokens: Int? = nil,
        canRetryAfterTruncation: Bool = true
    ) async throws -> String {
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

        let maximumAllowedResponseTokens = try Self.maximumAllowedResponseTokens(
            for: text,
            systemPrompt: settings.systemPrompt
        )
        let responseTokenLimit = min(
            maxTokens ?? Self.dynamicMaxTokens(for: text),
            maximumAllowedResponseTokens
        )
        let body: [String: Any] = [
            "model": settings.modelName,
            "messages": [
                ["role": "system", "content": settings.systemPrompt],
                ["role": "user", "content": text]
            ],
            "max_tokens": responseTokenLimit,
            "stream": onPartialResponse != nil
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            if let onPartialResponse {
                return try await performStreamingRequest(
                    request,
                    parseCompletedResponse: parseOpenAIResponse,
                    onPartialResponse: onPartialResponse
                )
            }

            let data = try await performRequest(request)
            return try parseOpenAIResponse(data)
        } catch GrammarAIError.responseTruncatedBeforeContent
            where canRetryAfterTruncation && responseTokenLimit < maximumAllowedResponseTokens {
            return try await improveTextWithOpenAICompatibleAPI(
                text,
                settings: settings,
                onPartialResponse: onPartialResponse,
                maxTokens: Self.retryMaxTokens(
                    after: responseTokenLimit,
                    maximumAllowedTokens: maximumAllowedResponseTokens
                ),
                canRetryAfterTruncation: false
            )
        }
    }

    private func improveTextWithDirectAPI(
        _ text: String,
        settings: GrammarSettings,
        onPartialResponse: ((String) async -> Void)?,
        maxTokens: Int? = nil,
        canRetryAfterTruncation: Bool = true
    ) async throws -> String {
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

        let maximumAllowedResponseTokens = try Self.maximumAllowedResponseTokens(
            for: text,
            systemPrompt: settings.systemPrompt
        )
        let responseTokenLimit = min(
            maxTokens ?? Self.dynamicMaxTokens(for: text),
            maximumAllowedResponseTokens
        )
        let body: [String: Any] = [
            "anthropic_version": "vertex-2023-10-16",
            "max_tokens": responseTokenLimit,
            "system": settings.systemPrompt,
            "stream": onPartialResponse != nil,
            "messages": [
                ["role": "user", "content": text]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            if let onPartialResponse {
                return try await performStreamingRequest(
                    request,
                    parseCompletedResponse: parseDirectResponse,
                    onPartialResponse: onPartialResponse
                )
            }

            let data = try await performRequest(request)
            return try parseDirectResponse(data)
        } catch GrammarAIError.responseTruncatedBeforeContent
            where canRetryAfterTruncation && responseTokenLimit < maximumAllowedResponseTokens {
            return try await improveTextWithDirectAPI(
                text,
                settings: settings,
                onPartialResponse: onPartialResponse,
                maxTokens: Self.retryMaxTokens(
                    after: responseTokenLimit,
                    maximumAllowedTokens: maximumAllowedResponseTokens
                ),
                canRetryAfterTruncation: false
            )
        }
    }

    private func parseOpenAIResponse(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first else {
            throw GrammarAIError.parseError
        }

        let responseText = (firstChoice["message"] as? [String: Any])?["content"] as? String
        guard let responseText, !responseText.isEmpty else {
            if firstChoice["finish_reason"] as? String == "length" {
                throw GrammarAIError.responseTruncatedBeforeContent
            }
            throw GrammarAIError.parseError
        }

        return responseText
    }

    private func parseDirectResponse(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GrammarAIError.parseError
        }

        let responseText = (json["content"] as? [[String: Any]])?.first?["text"] as? String
        guard let responseText, !responseText.isEmpty else {
            if json["stop_reason"] as? String == "max_tokens" {
                throw GrammarAIError.responseTruncatedBeforeContent
            }
            throw GrammarAIError.parseError
        }

        return responseText
    }

    private func performStreamingRequest(
        _ request: URLRequest,
        parseCompletedResponse: (Data) throws -> String,
        onPartialResponse: (String) async -> Void
    ) async throws -> String {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GrammarAIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let data = try await collectData(from: bytes)
            if httpResponse.statusCode == 401 {
                throw GrammarAIError.authExpired
            }
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw GrammarAIError.apiError(statusCode: httpResponse.statusCode, body: body)
        }

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        guard contentType.contains("text/event-stream") else {
            let data = try await collectData(from: bytes)
            let completedResponse = try parseCompletedResponse(data)
            await onPartialResponse(completedResponse)
            return completedResponse
        }

        var accumulatedResponse = ""
        var lastDeliveredResponse = ""
        var lastDeliveryTime = Date.distantPast
        var finishReason: String?

        for try await line in bytes.lines {
            try Task.checkCancellation()

            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedLine.hasPrefix("data:") else {
                // DeepSeek sends blank lines or SSE comments while a request waits in its queue.
                continue
            }

            let payload = String(trimmedLine.dropFirst(5))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !payload.isEmpty, payload != "[DONE]",
                  let data = payload.data(using: .utf8) else {
                continue
            }

            if let eventFinishReason = Self.streamingFinishReason(from: data) {
                finishReason = eventFinishReason
            }

            guard let delta = Self.streamingTextDelta(from: data),
                  !delta.isEmpty else {
                continue
            }

            accumulatedResponse += delta

            if Date().timeIntervalSince(lastDeliveryTime) >= 0.08 {
                await onPartialResponse(accumulatedResponse)
                lastDeliveredResponse = accumulatedResponse
                lastDeliveryTime = Date()
            }
        }

        guard !accumulatedResponse.isEmpty else {
            if finishReason == "length" || finishReason == "max_tokens" {
                throw GrammarAIError.responseTruncatedBeforeContent
            }
            throw GrammarAIError.parseError
        }

        if accumulatedResponse != lastDeliveredResponse {
            await onPartialResponse(accumulatedResponse)
        }

        return accumulatedResponse
    }

    static func streamingTextDelta(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let delta = firstChoice["delta"] as? [String: Any],
           let content = delta["content"] as? String {
            return content
        }

        if let delta = json["delta"] as? [String: Any],
           let text = delta["text"] as? String {
            return text
        }

        return nil
    }

    static func streamingFinishReason(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let choices = json["choices"] as? [[String: Any]],
           let finishReason = choices.first?["finish_reason"] as? String {
            return finishReason
        }

        if let delta = json["delta"] as? [String: Any],
           let stopReason = delta["stop_reason"] as? String {
            return stopReason
        }

        return nil
    }

    static func dynamicMaxTokens(for text: String) -> Int {
        let estimatedInputTokens = estimatedTokenCount(for: text)
        let visibleResponseTokens = responseFormatOverhead
            + (estimatedInputTokens * responseExpansionNumerator
                + responseExpansionDenominator - 1) / responseExpansionDenominator
        let reasoningTokens = max(
            minimumReasoningTokens,
            estimatedInputTokens * reasoningExpansionMultiplier
        )
        let requestedTokens = visibleResponseTokens + reasoningTokens
        let roundedTokens = ((requestedTokens + responseTokenStep - 1) / responseTokenStep)
            * responseTokenStep
        return min(max(roundedTokens, minimumResponseTokens), maximumResponseTokens)
    }

    static func maximumAllowedResponseTokens(for text: String, systemPrompt: String) throws -> Int {
        let estimatedPromptTokens = estimatedTokenCount(for: systemPrompt)
            + estimatedTokenCount(for: text)
            + messageFormatOverheadTokens
        let availableResponseTokens = conservativeContextWindowTokens
            - estimatedPromptTokens
            - contextSafetyMarginTokens
        let roundedAvailableTokens = (availableResponseTokens / responseTokenStep)
            * responseTokenStep

        guard roundedAvailableTokens >= minimumResponseTokens else {
            throw GrammarAIError.inputTooLong
        }

        return min(roundedAvailableTokens, maximumResponseTokens)
    }

    private static func retryMaxTokens(
        after tokenLimit: Int,
        maximumAllowedTokens: Int
    ) -> Int {
        min(tokenLimit * 2, maximumAllowedTokens)
    }

    private static func estimatedTokenCount(for text: String) -> Int {
        var cjkCharacters = 0
        var alphanumericCharacters = 0
        var punctuationCharacters = 0
        var otherCharacters = 0

        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                continue
            }

            if isCJK(scalar) {
                cjkCharacters += 1
            } else if CharacterSet.alphanumerics.contains(scalar) {
                alphanumericCharacters += 1
            } else if CharacterSet.punctuationCharacters.contains(scalar) {
                punctuationCharacters += 1
            } else {
                otherCharacters += 1
            }
        }

        let estimatedTokens = cjkCharacters
            + (alphanumericCharacters + 3) / 4
            + (punctuationCharacters + 1) / 2
            + otherCharacters
        return max(estimatedTokens, 1)
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF,
             0x4E00...0x9FFF,
             0xF900...0xFAFF,
             0x20000...0x2FA1F:
            return true
        default:
            return false
        }
    }

    private func collectData(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            data.append(byte)
        }
        return data
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
        parseResponse(from: response, fallbackToRawResponse: true)
    }

    func parsePartialResponse(from response: String) -> GrammarAIResponse? {
        let parsed = parseResponse(from: response, fallbackToRawResponse: false)
        guard parsed.translation != nil || parsed.errors != nil || !parsed.options.isEmpty else {
            return nil
        }
        return parsed
    }

    private func parseResponse(from response: String, fallbackToRawResponse: Bool) -> GrammarAIResponse {
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
        if options.isEmpty && fallbackToRawResponse {
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
    case inputTooLong
    case responseTruncatedBeforeContent
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
        case .inputTooLong:
            return "The selected text and system prompt are too long for one request"
        case .responseTruncatedBeforeContent:
            return "The response token limit was reached before the answer was generated"
        case .parseError:
            return "Failed to parse API response"
        }
    }
}
