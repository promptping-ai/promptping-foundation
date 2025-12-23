# Git Hooks for code-search-mcp Integration

This directory contains git hooks that automatically re-index the codebase
for code-search-mcp when code changes.

## Available Hooks

- **post-commit**: Re-indexes after committing changes
- **post-merge**: Re-indexes after pulling/merging
- **post-checkout**: Re-indexes after switching branches

## Installation

### For Submodules (promptping-foundation in parent repo)

```bash
# Copy hooks to the submodule's git directory
cp .githooks/* ../.git/modules/promptping-foundation/hooks/
chmod +x ../.git/modules/promptping-foundation/hooks/post-*
```

### For Regular Git Repos

```bash
# Copy hooks to .git/hooks
cp .githooks/* .git/hooks/
chmod +x .git/hooks/post-*
```

### Using Git's core.hooksPath (Recommended)

```bash
# Configure git to use .githooks directory
git config core.hooksPath .githooks
chmod +x .githooks/post-*
```

## Requirements

- `code-search-mcp` binary must be in PATH
- Install: `swift build -c release && cp .build/release/code-search-mcp ~/.swiftpm/bin/`

## How It Works

Each hook runs `code-search-mcp` in the background after the git operation,
ensuring the search index stays up-to-date with your codebase changes.

Log files are written to `/tmp/code-search-mcp-*.log` for debugging.
