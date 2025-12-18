import Foundation

#if canImport(Translation)
  import Translation
#endif

public enum Language: String, Sendable, CaseIterable {
  // Core languages (original)
  case english = "en"
  case french = "fr"
  case dutch = "nl"

  // Additional supported languages
  case arabic = "ar"
  case chineseSimplified = "zh"
  case chineseTraditional = "zh-TW"
  case german = "de"
  case hindi = "hi"
  case indonesian = "id"
  case italian = "it"
  case japanese = "ja"
  case korean = "ko"
  case polish = "pl"
  case portuguese = "pt"
  case russian = "ru"
  case spanish = "es"
  case thai = "th"
  case turkish = "tr"
  case ukrainian = "uk"
  case vietnamese = "vi"

  // Special case
  case auto = "auto"

  public var displayName: String {
    switch self {
    case .english: return "English"
    case .french: return "French"
    case .dutch: return "Dutch"
    case .arabic: return "Arabic"
    case .chineseSimplified: return "Chinese (Simplified)"
    case .chineseTraditional: return "Chinese (Traditional)"
    case .german: return "German"
    case .hindi: return "Hindi"
    case .indonesian: return "Indonesian"
    case .italian: return "Italian"
    case .japanese: return "Japanese"
    case .korean: return "Korean"
    case .polish: return "Polish"
    case .portuguese: return "Portuguese"
    case .russian: return "Russian"
    case .spanish: return "Spanish"
    case .thai: return "Thai"
    case .turkish: return "Turkish"
    case .ukrainian: return "Ukrainian"
    case .vietnamese: return "Vietnamese"
    case .auto: return "Auto-detect"
    }
  }

  /// Convert to Locale.Language for Translation framework
  /// Note: Uses en-GB for English as that's what Apple's translation models use
  public var localeLanguage: Locale.Language {
    switch self {
    case .english: return .init(identifier: "en-GB")
    case .french: return .init(identifier: "fr")
    case .dutch: return .init(identifier: "nl")
    case .arabic: return .init(identifier: "ar-AE")
    case .chineseSimplified: return .init(identifier: "zh")
    case .chineseTraditional: return .init(identifier: "zh-TW")
    case .german: return .init(identifier: "de")
    case .hindi: return .init(identifier: "hi")
    case .indonesian: return .init(identifier: "id")
    case .italian: return .init(identifier: "it")
    case .japanese: return .init(identifier: "ja")
    case .korean: return .init(identifier: "ko")
    case .polish: return .init(identifier: "pl")
    case .portuguese: return .init(identifier: "pt")
    case .russian: return .init(identifier: "ru")
    case .spanish: return .init(identifier: "es")
    case .thai: return .init(identifier: "th")
    case .turkish: return .init(identifier: "tr")
    case .ukrainian: return .init(identifier: "uk")
    case .vietnamese: return .init(identifier: "vi")
    case .auto: return .init(identifier: "en-GB")  // Fallback for auto
    }
  }

  /// Create Language from Locale.Language (used for detected languages)
  public static func from(localeLanguage: Locale.Language) -> Language? {
    guard let code = localeLanguage.languageCode?.identifier else { return nil }

    switch code {
    case "en": return .english
    case "fr": return .french
    case "nl": return .dutch
    case "ar": return .arabic
    case "zh":
      // Distinguish simplified vs traditional
      return localeLanguage.minimalIdentifier == "zh-TW" ? .chineseTraditional : .chineseSimplified
    case "de": return .german
    case "hi": return .hindi
    case "id": return .indonesian
    case "it": return .italian
    case "ja": return .japanese
    case "ko": return .korean
    case "pl": return .polish
    case "pt": return .portuguese
    case "ru": return .russian
    case "es": return .spanish
    case "th": return .thai
    case "tr": return .turkish
    case "uk": return .ukrainian
    case "vi": return .vietnamese
    default: return nil
    }
  }
}
