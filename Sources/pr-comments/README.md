# pr-comments

A command-line tool for viewing GitHub PR comments in a readable format.

## Features

- 📝 View all PR comments including inline code review comments
- 🎨 Clean, emoji-based formatting for easy scanning
- ⚡ Fast and lightweight using the GitHub CLI
- 🔍 Supports current branch PR or specific PR numbers

## Installation

Install globally via Swift Package Manager:

```bash
swift package experimental-install --product pr-comments
```

## Usage

### View comments for a specific PR

```bash
pr-comments 29
```

### View comments for current branch's PR

```bash
pr-comments --current
```

### Include PR description/body

```bash
pr-comments 29 --with-body
```

### Specify repository

```bash
pr-comments 42 --repo owner/repo
```

## Output Format

The tool formats PR comments into easy-to-read sections:

### General Comments
```
💬 Comments (5)
────────────────────────────────────────────────────────────────────────────────
[1] @username • Dec 18, 2025 at 10:30 AM
Great work on this feature!
```

### Code Reviews
```
🔍 Reviews (2)
────────────────────────────────────────────────────────────────────────────────
[1] ✅ @reviewer • Dec 18, 2025 at 11:00 AM
Looks good overall!

  📝 Code Comments:

  📍 Sources/MyFile.swift:42
     Consider using let instead of var here
```

Review states are indicated with emojis:
- ✅ Approved
- ❌ Changes Requested
- 💭 Commented
- ⏳ Pending
- 🚫 Dismissed

## Requirements

- GitHub CLI (`gh`) must be installed and configured
- Swift 6.1 or later

## License

Part of the promptping-foundation package.
