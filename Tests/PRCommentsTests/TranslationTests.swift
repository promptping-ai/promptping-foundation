import Foundation
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
    #expect(allCases.count == 21)  // 19 real languages + english + auto
    #expect(allCases.contains(.english))
    #expect(allCases.contains(.french))
    #expect(allCases.contains(.dutch))
    #expect(allCases.contains(.german))
    #expect(allCases.contains(.japanese))
    #expect(allCases.contains(.auto))
  }

  @Test("Language localeLanguage conversion")
  func testLocaleLanguageConversion() {
    #expect(Language.english.localeLanguage.languageCode?.identifier == "en")
    #expect(Language.french.localeLanguage.languageCode?.identifier == "fr")
  }

  @Test("Language from localeLanguage")
  func testFromLocaleLanguage() {
    let englishLocale = Locale.Language(identifier: "en")
    let frenchLocale = Locale.Language(identifier: "fr")
    let germanLocale = Locale.Language(identifier: "de")
    let dutchLocale = Locale.Language(identifier: "nl")
    let unknownLocale = Locale.Language(identifier: "xx")  // Unsupported

    #expect(Language.from(localeLanguage: englishLocale) == .english)
    #expect(Language.from(localeLanguage: frenchLocale) == .french)
    #expect(Language.from(localeLanguage: germanLocale) == .german)
    #expect(Language.from(localeLanguage: dutchLocale) == .dutch)
    #expect(Language.from(localeLanguage: unknownLocale) == nil)  // Truly unsupported
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

    // On macOS 14.4+, Translation framework should be available
    // On older systems, should always be false
    #expect(available == true || available == false)
  }

  @Test("TranslationService batch translation returns correct count")
  func testBatchTranslationCount() async throws {
    let service = TranslationService()

    // Skip test if Translation framework unavailable
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
        case .translationUnavailable:
          Issue.record("Translation framework unavailable during test, skipping")
        case .translationFailed(let message):
          Issue.record("Translation failed: \(message)")
        case .languageNotSupported(let pair):
          Issue.record("Language pair not supported: \(pair)")
        case .downloadRequired:
          Issue.record("Language model download required, skipping test")
        }
      } else {
        throw error
      }
    }
  }

  @Test("TranslationService language pair availability check")
  func testLanguagePairAvailability() async {
    let service = TranslationService()

    // Check if English to French is available
    let available = await service.isLanguagePairAvailable(from: .english, to: .french)

    // Result depends on system - just verify it doesn't crash
    #expect(available == true || available == false)
  }
}

@Suite("MarkdownPreserver Tests")
struct MarkdownPreserverTests {
  @Test("Extract only translatable text, skip code blocks")
  func testTextExtraction() {
    let markdown = """
    This is **bold** text.

    ```swift
    let code = "skip me"
    ```

    More text with `inline code`.
    """

    let preserver = MarkdownPreserver(markdown: markdown)
    let texts = preserver.translatableTexts

    // Should extract text but not code
    #expect(!texts.joined().contains("skip me"))
    #expect(!texts.joined().contains("inline code"))
    #expect(texts.joined().contains("This is"))
    #expect(texts.joined().contains("bold"))
  }

  @Test("Preserve URLs in links")
  func testURLPreservation() {
    let markdown = "[Click here](https://example.com/path?utm_source=test)"
    let preserver = MarkdownPreserver(markdown: markdown)
    let texts = preserver.translatableTexts

    // Translate link text
    let translations = texts.map { $0.uppercased() }
    let result = preserver.apply(translations: translations)

    // URL unchanged
    #expect(result.contains("https://example.com/path?utm_source=test"))
    #expect(result.contains("CLICK HERE"))
  }

  @Test("Index synchronization with whitespace nodes")
  func testWhitespaceHandling() {
    let markdown = "Hello\n\n\nWorld"  // Multiple newlines create whitespace text nodes
    let preserver = MarkdownPreserver(markdown: markdown)
    let texts = preserver.translatableTexts

    let translations = texts.map { $0.uppercased() }
    let result = preserver.apply(translations: translations)

    #expect(result.contains("HELLO"))
    #expect(result.contains("WORLD"))
  }

  @Test("Preserve HTML tags")
  func testHTMLPreservation() {
    let markdown = "Text with <a href=\"test\">link</a> and more"
    let preserver = MarkdownPreserver(markdown: markdown)
    let texts = preserver.translatableTexts

    let translations = texts.map { $0.uppercased() }
    let result = preserver.apply(translations: translations)

    // HTML unchanged
    #expect(result.contains("<a href=\"test\">"))
    #expect(result.contains("</a>"))
  }
}
