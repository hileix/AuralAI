//
//  AIResponseTokenBudget.swift
//  AuralAI
//

import Foundation

enum AIResponseTokenBudget {
    static let minimumResponseTokens = 1_024
    static let maximumResponseTokens = 8_192

    private static let responseTokenStep = 64
    private static let responseFormatOverhead = 192
    private static let responseExpansionNumerator = 11
    private static let responseExpansionDenominator = 2
    private static let minimumReasoningTokens = 768
    private static let reasoningExpansionMultiplier = 2
    private static let conservativeContextWindowTokens = 32_768
    private static let contextSafetyMarginTokens = 512
    private static let messageFormatOverheadTokens = 32

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

    static func maximumAllowedResponseTokens(for text: String, systemPrompt: String) -> Int? {
        let estimatedPromptTokens = estimatedTokenCount(for: systemPrompt)
            + estimatedTokenCount(for: text)
            + messageFormatOverheadTokens
        let availableResponseTokens = conservativeContextWindowTokens
            - estimatedPromptTokens
            - contextSafetyMarginTokens
        let roundedAvailableTokens = (availableResponseTokens / responseTokenStep)
            * responseTokenStep

        guard roundedAvailableTokens >= minimumResponseTokens else { return nil }
        return min(roundedAvailableTokens, maximumResponseTokens)
    }

    static func retryMaxTokens(after tokenLimit: Int, maximumAllowedTokens: Int) -> Int {
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
}
