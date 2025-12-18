import Foundation

#if canImport(Translation)
  import Translation
#endif

public enum TranslationError: Error, Sendable {
  case translationUnavailable
  case translationFailed(String)
  case languageNotSupported(String)
  case downloadRequired
}

/// Actor for local translation using Apple's Translation framework
///
/// Uses Apple's dedicated neural machine translation API (macOS 26+)
/// for efficient, offline translation between supported languages.
///
/// NOTE: This uses Translation.framework, NOT FoundationModels.
/// Translation has no context window limits and is purpose-built for this task.
///
/// References:
/// - https://developer.apple.com/documentation/translation
public actor TranslationService {
  public init() {}

  /// Check if Translation framework is available on this system
  public var isAvailable: Bool {
    #if canImport(Translation)
      if #available(macOS 26, iOS 26, *) {
        return true
      }
    #endif
    return false
  }

  /// Check if a specific language pair is available (and downloaded)
  public func isLanguagePairAvailable(
    from source: Language,
    to target: Language
  ) async -> Bool {
    #if canImport(Translation)
      if #available(macOS 26, iOS 26, *) {
        let availability = LanguageAvailability()
        let status = await availability.status(
          from: source.localeLanguage,
          to: target.localeLanguage
        )
        return status == .installed
      }
    #endif
    return false
  }

  /// Translate text from one language to another
  ///
  /// When sourceLanguage is `.auto`:
  /// - If target is English → assumes source is French
  /// - If target is French → assumes source is English
  public func translate(
    _ text: String,
    from sourceLanguage: Language = .auto,
    to targetLanguage: Language
  ) async throws(TranslationError) -> TranslationResult {
    #if canImport(Translation)
      guard #available(macOS 26, iOS 26, *) else {
        throw .translationUnavailable
      }

      do {
        // Determine source language
        // When auto-detecting:
        // - If target is English → defaults to French (for backward compatibility)
        // - If target is any other language → assumes English source (most common in tech)
        let effectiveSource: Language
        if sourceLanguage == .auto {
          switch targetLanguage {
          case .english:
            effectiveSource = .french  // Default for backward compatibility
          case .french, .dutch, .german, .spanish, .italian, .japanese, .korean,
               .portuguese, .russian, .chineseSimplified, .chineseTraditional,
               .arabic, .hindi, .indonesian, .polish, .thai, .turkish, .ukrainian, .vietnamese:
            effectiveSource = .english  // Most common: translate English content to other languages
          case .auto:
            effectiveSource = .english  // Fallback
          }
        } else {
          effectiveSource = sourceLanguage
        }

        // Check availability
        let availability = LanguageAvailability()
        let status = await availability.status(
          from: effectiveSource.localeLanguage,
          to: targetLanguage.localeLanguage
        )

        switch status {
        case .installed:
          break  // Good to go
        case .supported:
          throw TranslationError.downloadRequired
        case .unsupported:
          throw TranslationError.languageNotSupported(
            "\(effectiveSource.displayName) → \(targetLanguage.displayName)")
        @unknown default:
          throw TranslationError.translationFailed("Unknown availability status")
        }

        // Parse markdown and extract translatable text segments
        let preserver = MarkdownPreserver(markdown: text)
        let textsToTranslate = preserver.translatableTexts

        // If no translatable text, return original
        guard !textsToTranslate.isEmpty else {
          return TranslationResult(
            originalText: text,
            translatedText: text,
            sourceLanguage: effectiveSource,
            targetLanguage: targetLanguage
          )
        }

        // Create session and translate only the text segments
        let session = TranslationSession(
          installedSource: effectiveSource.localeLanguage,
          target: targetLanguage.localeLanguage
        )

        // Batch translate all text segments
        let requests = textsToTranslate.map { TranslationSession.Request(sourceText: $0) }
        let responses = try await session.translations(from: requests)
        let translatedTexts = responses.map { $0.targetText }

        // Apply translations back to original markdown structure
        let restoredText = preserver.apply(translations: translatedTexts)

        // Use actual detected source from first response
        let actualSource = responses.first.flatMap { Language.from(localeLanguage: $0.sourceLanguage) } ?? effectiveSource

        return TranslationResult(
          originalText: text,
          translatedText: restoredText,
          sourceLanguage: actualSource,
          targetLanguage: targetLanguage
        )
      } catch let error as TranslationError {
        throw error
      } catch {
        throw .translationFailed(error.localizedDescription)
      }
    #else
      throw .translationUnavailable
    #endif
  }

  /// Batch translate multiple texts efficiently
  ///
  /// Assumes source is opposite of target (French↔English)
  public func translateBatch(
    _ texts: [String],
    to targetLanguage: Language
  ) async throws(TranslationError) -> [TranslationResult] {
    #if canImport(Translation)
      guard #available(macOS 26, iOS 26, *) else {
        throw .translationUnavailable
      }

      guard !texts.isEmpty else { return [] }

      do {
        // Determine source language based on target
        // Assumes: English content → other languages, or other languages → English
        let effectiveSource: Language
        switch targetLanguage {
        case .english:
          effectiveSource = .french  // Default for backward compatibility
        case .french, .dutch, .german, .spanish, .italian, .japanese, .korean,
             .portuguese, .russian, .chineseSimplified, .chineseTraditional,
             .arabic, .hindi, .indonesian, .polish, .thai, .turkish, .ukrainian, .vietnamese:
          effectiveSource = .english  // Most common: translate English content to other languages
        case .auto:
          effectiveSource = .english  // Fallback
        }

        // Check availability
        let availability = LanguageAvailability()
        let status = await availability.status(
          from: effectiveSource.localeLanguage,
          to: targetLanguage.localeLanguage
        )

        switch status {
        case .installed:
          break
        case .supported:
          throw TranslationError.downloadRequired
        case .unsupported:
          throw TranslationError.languageNotSupported(
            "\(effectiveSource.displayName) → \(targetLanguage.displayName)")
        @unknown default:
          throw TranslationError.translationFailed("Unknown availability status")
        }

        // Parse markdown and extract translatable segments from each text
        let preservers = texts.map { MarkdownPreserver(markdown: $0) }

        // Collect all translatable segments with their indices
        var allSegments: [(textIndex: Int, segmentIndex: Int, text: String)] = []
        for (textIndex, preserver) in preservers.enumerated() {
          for (segmentIndex, unit) in preserver.translatableUnits.enumerated() {
            allSegments.append((textIndex, segmentIndex, unit.content))
          }
        }

        // If nothing to translate, return originals
        guard !allSegments.isEmpty else {
          return texts.map {
            TranslationResult(
              originalText: $0,
              translatedText: $0,
              sourceLanguage: effectiveSource,
              targetLanguage: targetLanguage
            )
          }
        }

        // Create session and batch translate all segments
        let session = TranslationSession(
          installedSource: effectiveSource.localeLanguage,
          target: targetLanguage.localeLanguage
        )

        let requests = allSegments.map { TranslationSession.Request(sourceText: $0.text) }
        let responses = try await session.translations(from: requests)

        // Group translations back by original text index
        var translationsByText: [[String]] = preservers.map { Array(repeating: "", count: $0.translatableUnits.count) }
        for (index, response) in responses.enumerated() {
          let segment = allSegments[index]
          translationsByText[segment.textIndex][segment.segmentIndex] = response.targetText
        }

        // Apply translations to each original
        return zip(zip(texts, preservers), translationsByText).map {
          (pair: (String, MarkdownPreserver), translations: [String]) in
          let (original, preserver) = pair
          let restoredText = preserver.apply(translations: translations)
          return TranslationResult(
            originalText: original,
            translatedText: restoredText,
            sourceLanguage: effectiveSource,
            targetLanguage: targetLanguage
          )
        }
      } catch let error as TranslationError {
        throw error
      } catch {
        throw .translationFailed(error.localizedDescription)
      }
    #else
      throw .translationUnavailable
    #endif
  }
}
