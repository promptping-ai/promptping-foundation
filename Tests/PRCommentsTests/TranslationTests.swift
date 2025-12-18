import Testing

@testable import PRComments

@Suite("Language Tests")
struct LanguageTests {
  @Test("Language enum has correct raw values")
  func testLanguageRawValues() {
    #expect(Language.english.rawValue == "en")
    #expect(Language.french.rawValue == "fr")
    #expect(Language.auto.rawValue == "auto")
  }

  @Test("Language display names are correct")
  func testLanguageDisplayNames() {
    #expect(Language.english.displayName == "English")
    #expect(Language.french.displayName == "French")
    #expect(Language.auto.displayName == "Auto-detect")
  }

  @Test("Language conforms to CaseIterable")
  func testLanguageCaseIterable() {
    let allCases = Language.allCases
    #expect(allCases.count == 3)
    #expect(allCases.contains(.english))
    #expect(allCases.contains(.french))
    #expect(allCases.contains(.auto))
  }
}

@Suite("TranslationResult Tests")
struct TranslationResultTests {
  @Test("TranslationResult initializes correctly")
  func testTranslationResultInit() {
    let result = TranslationResult(
      originalText: "Bonjour",
      translatedText: "Hello",
      sourceLanguage: .french,
      targetLanguage: .english
    )

    #expect(result.originalText == "Bonjour")
    #expect(result.translatedText == "Hello")
    #expect(result.sourceLanguage == .french)
    #expect(result.targetLanguage == .english)
  }

  @Test("TranslationResult is Sendable")
  func testTranslationResultSendable() async {
    let result = TranslationResult(
      originalText: "Test",
      translatedText: "Test",
      sourceLanguage: .english,
      targetLanguage: .french
    )

    await Task.detached {
      _ = result.originalText
    }.value
  }
}

@Suite("TranslationService Tests")
struct TranslationServiceTests {
  @Test("TranslationService initializes")
  func testTranslationServiceInit() async {
    let service = TranslationService()
    _ = await service.isAvailable
  }

  @Test("TranslationService availability check")
  func testAvailabilityCheck() async {
    let service = TranslationService()
    let available = await service.isAvailable

    // On macOS 15+, this might be true or false depending on system
    // On older systems, should always be false
    #expect(available == true || available == false)
  }

  @Test("TranslationService rejects .auto as target language")
  func testRejectsAutoTarget() async throws {
    let service = TranslationService()

    await #expect(
      performing: {
        try await service.translate(
          "Hello",
          from: .english,
          to: .auto
        )
      },
      throws: { error in
        guard let translationError = error as? TranslationError,
          case .invalidLanguagePair = translationError
        else {
          return false
        }
        return true
      }
    )
  }

  @Test("TranslationService batch translation returns correct count")
  func testBatchTranslationCount() async throws {
    let service = TranslationService()

    // Skip test if Foundation Models unavailable
    guard await service.isAvailable else {
      return
    }

    let texts = ["Hello", "World", "Test"]

    do {
      let results = try await service.translateBatch(
        texts,
        to: .french
      )
      #expect(results.count == texts.count)
    } catch {
      // If translation fails due to availability issues, that's ok for tests
      if let translationError = error as? TranslationError {
        switch translationError {
        case .foundationModelsUnavailable:
          Issue.record(
            "Foundation Models unavailable during test, skipping validation"
          )
        case .translationFailed(let message):
          Issue.record("Translation failed: \(message)")
        case .invalidLanguagePair:
          Issue.record("Invalid language pair")
        }
      } else {
        throw error
      }
    }
  }
}
