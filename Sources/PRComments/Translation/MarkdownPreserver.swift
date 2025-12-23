import Foundation
import Markdown

/// Extracts translatable text from markdown using AST-based parsing
///
/// Uses swift-markdown to parse the markdown AST and identify Text nodes
/// that should be translated while automatically preserving code blocks,
/// inline code, URLs, and HTML.
public struct MarkdownPreserver: Sendable {
  /// The original markdown source
  public let originalMarkdown: String

  /// Text segments extracted for translation
  public let translatableUnits: [TranslatableUnit]

  public struct TranslatableUnit: Sendable {
    let index: Int
    let content: String
  }

  /// Parse markdown and extract Text nodes
  public init(markdown: String) {
    self.originalMarkdown = markdown

    let document = Document(parsing: markdown)
    var extractor = TextNodeExtractor()
    extractor.visit(document)
    self.translatableUnits = extractor.units
  }

  /// Get plain strings for batch translation
  public var translatableTexts: [String] {
    translatableUnits.map(\.content)
  }

  /// Apply translations back to markdown
  ///
  /// - Parameter translations: Array of translated strings matching translatableTexts order
  /// - Returns: Original markdown with text replaced, structure preserved
  public func apply(translations: [String]) -> String {
    // Build replacement map
    var replacements: [Int: String] = [:]
    for (i, unit) in translatableUnits.enumerated() {
      guard i < translations.count else { break }
      replacements[unit.index] = translations[i]
    }

    // Parse, replace, format
    let document = Document(parsing: originalMarkdown)
    var replacer = TextNodeReplacer(translations: replacements)
    guard let newDocument = replacer.visit(document) else {
      return originalMarkdown  // Fallback on error
    }

    var formatter = MarkupFormatter()
    formatter.visit(newDocument)
    return formatter.result
  }
}

// MARK: - Text Node Extractor (MarkupWalker)

/// Walks the markdown AST and collects Text nodes for translation
struct TextNodeExtractor: MarkupWalker {
  var units: [MarkdownPreserver.TranslatableUnit] = []
  var index = 0  // Track index during traversal

  mutating func visitText(_ text: Text) {
    defer { index += 1 }  // ALWAYS increment to match TextNodeReplacer

    let trimmed = text.string.trimmingCharacters(in: .whitespaces)
    if !trimmed.isEmpty {
      units.append(
        MarkdownPreserver.TranslatableUnit(
          index: index,
          content: text.string
        ))
    }
  }

  mutating func defaultVisit(_ markup: Markup) {
    descendInto(markup)
  }

  // Skip code - these methods prevent descent
  mutating func visitCodeBlock(_ codeBlock: CodeBlock) {}
  mutating func visitInlineCode(_ inlineCode: InlineCode) {}
  mutating func visitInlineHTML(_ html: InlineHTML) {}
  mutating func visitHTMLBlock(_ html: HTMLBlock) {}
}

// MARK: - Text Node Replacer (MarkupRewriter)

/// Rewrites the markdown AST with translated Text nodes
struct TextNodeReplacer: MarkupRewriter {
  let translations: [Int: String]
  var currentIndex = 0  // Track index during traversal

  mutating func visitText(_ text: Text) -> Markup? {
    defer { currentIndex += 1 }

    if let translated = translations[currentIndex] {
      return Text(translated)
    }
    return text
  }
}
