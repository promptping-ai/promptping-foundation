# Markdown-Preserving Translation with swift-markdown

## Goal
Fix translation to properly preserve markdown structure using Apple's `swift-markdown` AST parser instead of regex hacks.

## Current Problem
Translation.framework translates ALL text, mangling:
- URLs (`utm_source` → `Utm_source` with spaces)
- Code blocks (translating code!)
- HTML tags
- Technical terms in backticks

## Solution: AST-Based Translation

Following the pattern from `~/.claude/skills/swift-markdown/references/translation-preservation.md`:

1. **Parse**: `Document(parsing: source)` → AST
2. **Extract**: `TextNodeExtractor: MarkupWalker` → collects only `Text` nodes
3. **Translate**: Batch translate the plain strings
4. **Replace**: `TextNodeReplacer: MarkupRewriter` → swap in translations
5. **Format**: `MarkupFormatter` → back to markdown string

**Why This Works:**
- Code blocks (`CodeBlock`), inline code (`InlineCode`), URLs (`link.destination`), HTML (`InlineHTML`, `HTMLBlock`) are separate node types
- Only `Text` nodes contain translatable content
- Structure preserved automatically by AST

## Files to Modify

| File | Action |
|------|--------|
| **`Package.swift`** | ✅ Already has `swift-markdown` dependency |
| **`Sources/PRComments/Translation/MarkdownPreserver.swift`** | Rewrite using AST approach |
| **`Sources/PRComments/Translation/TranslationService.swift`** | Use new `MarkdownPreserver` API |
| **`Tests/PRCommentsTests/TranslationTests.swift`** | Add tests for markdown preservation |

## Implementation Details

### 1. MarkdownPreserver.swift (Complete Rewrite)

Replace regex approach with AST-based approach from skill file:

```swift
import Foundation
import Markdown

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

struct TextNodeExtractor: MarkupWalker {
  var units: [MarkdownPreserver.TranslatableUnit] = []
  private var index = 0

  mutating func visitText(_ text: Text) {
    let trimmed = text.string.trimmingCharacters(in: .whitespaces)
    if !trimmed.isEmpty {
      units.append(MarkdownPreserver.TranslatableUnit(
        index: index,
        content: text.string
      ))
    }
    index += 1
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

struct TextNodeReplacer: MarkupRewriter {
  let translations: [Int: String]
  private var currentIndex = 0

  mutating func visitText(_ text: Text) -> Markup? {
    defer { currentIndex += 1 }

    if let translated = translations[currentIndex] {
      return Text(translated)
    }
    return text
  }
}
```

**Key Differences from Old Regex Approach:**
- No manual regex patterns for URLs, code blocks, HTML
- No placeholder `⟦N⟧` system
- No string range manipulation
- Structure preserved automatically by AST
- Code/HTML/URLs never visited (different node types)

### 2. TranslationService.swift (Minor Update)

The `translate()` and `translateBatch()` methods already use `MarkdownPreserver` correctly. Just verify the API matches:

```swift
// Already correct:
let preserver = MarkdownPreserver(text: text)
let textsToTranslate = preserver.translatableTexts

// Translate texts...

// Already correct:
let restoredText = preserver.apply(translations: translatedTexts)
```

**No changes needed** - the existing code already uses the right API pattern.

### 3. Tests

Add test in `TranslationTests.swift`:

```swift
@Test("Markdown preservation with code blocks")
func testMarkdownPreservation() {
  let markdown = """
  This is **bold** text.

  ```swift
  let code = "unchanged"
  ```

  [Link text](https://example.com)
  """

  let preserver = MarkdownPreserver(markdown: markdown)
  let texts = preserver.translatableTexts

  // Should extract only translatable text
  #expect(texts.count == 2)  // "This is " + "bold" + " text." and "Link text"
  #expect(!texts.contains(where: { $0.contains("code") }))

  // Simulate translation (uppercase)
  let translations = texts.map { $0.uppercased() }
  let result = preserver.apply(translations: translations)

  // Code block should be unchanged
  #expect(result.contains("let code = \"unchanged\""))

  // URL should be unchanged
  #expect(result.contains("https://example.com"))

  // Text should be translated
  #expect(result.contains("THIS IS"))
  #expect(result.contains("BOLD"))
}
```

## Execution Plan

1. ✅ Package.swift already has `swift-markdown` dependency (added earlier)
2. **Rewrite** `MarkdownPreserver.swift` with AST approach
3. **Verify** `TranslationService.swift` uses correct API (likely no changes)
4. **Add** markdown preservation test
5. **Build & Test**
6. **Commit** with message documenting AST approach

## Verification

```bash
swift build
swift test
swift run pr-comments view 41 -l en | head -100
```

Expected: URLs intact, code blocks unchanged, text translated.
