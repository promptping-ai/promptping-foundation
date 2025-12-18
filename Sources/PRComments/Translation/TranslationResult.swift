public struct TranslationResult: Sendable {
  public let originalText: String
  public let translatedText: String
  public let sourceLanguage: Language
  public let targetLanguage: Language

  public init(
    originalText: String,
    translatedText: String,
    sourceLanguage: Language,
    targetLanguage: Language
  ) {
    self.originalText = originalText
    self.translatedText = translatedText
    self.sourceLanguage = sourceLanguage
    self.targetLanguage = targetLanguage
  }
}
