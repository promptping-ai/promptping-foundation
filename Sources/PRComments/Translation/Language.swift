public enum Language: String, Sendable, CaseIterable {
  case english = "en"
  case french = "fr"
  case auto = "auto"

  public var displayName: String {
    switch self {
    case .english: return "English"
    case .french: return "French"
    case .auto: return "Auto-detect"
    }
  }
}
