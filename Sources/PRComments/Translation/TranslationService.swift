import Foundation

#if canImport(FoundationModels)
  import FoundationModels
#endif

public enum TranslationError: Error, Sendable {
  case foundationModelsUnavailable
  case translationFailed(String)
  case invalidLanguagePair
}

/// Actor for local translation using Apple Foundation Models
///
/// Uses Apple's on-device Foundation Models framework (macOS 26+) for privacy-first,
/// offline translation between French and English.
///
/// References:
/// - https://developer.apple.com/documentation/foundationmodels
/// - https://www.createwithswift.com/exploring-the-foundation-models-framework/
public actor TranslationService {
  public init() {}

  /// Check if Foundation Models translation is available
  public var isAvailable: Bool {
    #if canImport(FoundationModels)
      if #available(macOS 26, *) {
        return SystemLanguageModel.default.isAvailable
      }
    #endif
    return false
  }

  public func translate(
    _ text: String,
    from sourceLanguage: Language = .auto,
    to targetLanguage: Language
  ) async throws(TranslationError) -> TranslationResult {
    #if canImport(FoundationModels)
      guard #available(macOS 26, *) else {
        throw .foundationModelsUnavailable
      }

      guard isAvailable else {
        throw .foundationModelsUnavailable
      }

      // Validate language pair
      guard targetLanguage != .auto else {
        throw .invalidLanguagePair
      }

      // Build translation prompt
      let promptText = buildTranslationPrompt(
        text: text,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage
      )

      do {
        // Create a language model session
        let session = LanguageModelSession()

        // Create prompt
        let prompt = Prompt(promptText)

        // Generate translation using the session
        let response = try await session.respond(to: prompt)

        // Clean up the result (remove any extra formatting)
        let cleanedText = cleanTranslationResult(response.content)

        // Determine actual source language
        let actualSource =
          sourceLanguage == .auto
          ? detectSourceLanguage(text, targetLanguage: targetLanguage)
          : sourceLanguage

        return TranslationResult(
          originalText: text,
          translatedText: cleanedText,
          sourceLanguage: actualSource,
          targetLanguage: targetLanguage
        )
      } catch {
        throw TranslationError.translationFailed(error.localizedDescription)
      }
    #else
      throw .foundationModelsUnavailable
    #endif
  }

  public func translateBatch(
    _ texts: [String],
    to targetLanguage: Language
  ) async throws(TranslationError) -> [TranslationResult] {
    var results: [TranslationResult] = []

    for text in texts {
      let result = try await translate(text, to: targetLanguage)
      results.append(result)
    }

    return results
  }

  // MARK: - Private Helpers

  private func buildTranslationPrompt(
    text: String,
    sourceLanguage: Language,
    targetLanguage: Language
  ) -> String {
    let sourceLang =
      sourceLanguage == .auto
      ? "auto-detected language" : sourceLanguage.displayName
    let targetLang = targetLanguage.displayName

    return """
      Translate the following text from \(sourceLang) to \(targetLang).
      Preserve markdown formatting, code blocks (```), file paths, URLs, and @mentions exactly as they appear.
      Only translate the natural language text.

      Text to translate:
      \(text)

      Translation:
      """
  }

  private func cleanTranslationResult(_ text: String) -> String {
    // Remove common model artifacts
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

    // Remove "Translation:" prefix if present
    if trimmed.lowercased().hasPrefix("translation:") {
      return trimmed.dropFirst("translation:".count)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    return trimmed
  }

  private func detectSourceLanguage(
    _ text: String,
    targetLanguage: Language
  ) -> Language {
    // Simple heuristic: if target is English, assume source is French and vice versa
    // In production, you could use NLLanguageRecognizer for more accuracy
    switch targetLanguage {
    case .english:
      return .french
    case .french:
      return .english
    case .auto:
      return .english  // Default fallback
    }
  }
}
