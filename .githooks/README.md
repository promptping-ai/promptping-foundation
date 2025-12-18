# Git Hooks for code-search-mcp Integration

This directory contains git hooks that automatically re-index the codebase
for code-search-mcp when code changes.

## Quick Setup (Recommended)

```bash
./scripts/setup-code-search.sh
```

This script handles everything:
- Configures git to use `.githooks/` directory
- Sets proper permissions
- Configures direnv (if installed)
- Optionally runs initial index

## Available Hooks

| Hook | Triggers On | Purpose |
|------|-------------|---------|
| `post-commit` | After committing | Re-index committed changes |
| `post-merge` | After pull/merge | Re-index merged code |
| `post-checkout` | After branch switch | Re-index branch-specific code |

## Manual Installation

### Using Git's core.hooksPath (Recommended)

```bash
git config core.hooksPath .githooks
chmod +x .githooks/post-*
```

### For Submodules

```bash
# Copy hooks to the submodule's git directory
cp .githooks/post-* ../.git/modules/promptping-foundation/hooks/
chmod +x ../.git/modules/promptping-foundation/hooks/post-*
```

### For Regular Repos (Alternative)

```bash
cp .githooks/post-* .git/hooks/
chmod +x .git/hooks/post-*
```

## Requirements

- **code-search-mcp** binary at `~/.swiftpm/bin/code-search-mcp`
- Install: `swift package experimental-install` in code-search-mcp repo

## How It Works

Each hook runs `code-search-mcp index` in the background after the git operation,
ensuring the search index stays up-to-date with your codebase changes.

### Concurrency Protection

Hooks use a lock file (`.git/code-search-mcp.lock`) to prevent concurrent
indexing jobs. If an index is already running, subsequent triggers skip
gracefully with a message.

### Logging

Logs are written to `.git/code-search-mcp.log` (not committed to repo).
Check this file for debugging:

```bash
tail -f .git/code-search-mcp.log
```

## When code-search-mcp is Not Installed

If the binary is not found:
- Hooks print a warning message but **do not block** git operations
- Git operations complete normally
- Run `./scripts/setup-code-search.sh` to see installation instructions

```
⚠️  code-search-mcp not found at /Users/you/.swiftpm/bin/code-search-mcp
    Run: ./scripts/setup-code-search.sh
```

## Troubleshooting

### Hooks not running
```bash
# Verify hooks path is configured
git config core.hooksPath

# Should output: .githooks
```

### Index not updating
```bash
# Check if binary exists
ls -la ~/.swiftpm/bin/code-search-mcp

# Check logs for errors
cat .git/code-search-mcp.log

# Remove stale lock file if needed
rm -f .git/code-search-mcp.lock
```

### Testing hooks manually
```bash
# Trigger post-commit hook
.githooks/post-commit
```
