---
name: edgeprompt-release
description: Complete release workflow for EdgePrompt MCP server including version bump, testing, tagging, and publication
---

# EdgePrompt Release Process

This skill documents the complete release workflow for EdgePrompt, ensuring consistent and reliable releases.

## Quick Reference

```bash
# Full release in one flow
./bump-version.sh X.Y.Z && swift test && git add . && \
git commit -m "chore: Release vX.Y.Z" && git tag vX.Y.Z && \
./install.sh && git push && git push origin vX.Y.Z
```

## Pre-Release Checklist

### 1. Verify Clean State
```bash
git status              # Should be clean or only expected changes
git pull origin main    # Ensure up to date
swift test              # All tests passing
```

### 2. Review Changes Since Last Release
```bash
git log --oneline $(git describe --tags --abbrev=0)..HEAD
```

## Release Steps

### Step 1: Version Bump

Use the automated bump script (handles all locations):

```bash
./bump-version.sh X.Y.Z
```

**What it updates:**
- `.claude-plugin/plugin.json` - Plugin manifest version
- `Sources/EdgePrompt/EdgePrompt.swift` - CLI --version output
- `Sources/EdgePrompt/Resources/agent-knowledge.json` - Regenerated automatically

**Version format:**
- Release: `X.Y.Z` (e.g., `0.18.0`)
- Alpha: `X.Y.Z-alpha.N` (e.g., `0.18.0-alpha.1`)
- Beta: `X.Y.Z-beta.N` (e.g., `0.18.0-beta.1`)

### Step 2: Update CHANGELOG

Add release notes to `CHANGELOG.md`:

```markdown
## [X.Y.Z] - YYYY-MM-DD - Release Title

### Added
- New features...

### Changed
- Modifications...

### Fixed
- Bug fixes...
```

### Step 3: Run Tests

```bash
swift test 2>&1 | tee test-results-$(date +%Y%m%d-%H%M%S).log
```

**Expected:** All tests pass (600+ tests)

### Step 4: Commit and Tag

```bash
git add .
git commit -m "$(cat <<'EOF'
chore: Release vX.Y.Z - Release Title

Summary of changes:
- Feature 1
- Feature 2

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"

git tag vX.Y.Z
```

### Step 5: Build and Install

```bash
./install.sh
```

**Verifies:**
- Agent knowledge regenerated
- Release build succeeds
- Binary installed to `~/.swiftpm/bin/edgeprompt`
- Resource bundle copied

### Step 6: Verify Installation

```bash
edgeprompt --version                    # Should show X.Y.Z
echo '{"jsonrpc":"2.0","method":"tools/list","id":1}' | edgeprompt | jq '.result.tools | length'  # Should be 12
```

### Step 7: Push Release

```bash
git push origin main
git push origin vX.Y.Z
```

### Step 8: Create GitHub Release (Optional)

```bash
gh release create vX.Y.Z \
  --title "vX.Y.Z - Release Title" \
  --notes "Release notes here..."
```

## Post-Release

### Verify MCP Server

```bash
# Test discover_agents
echo '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"discover_agents","arguments":{}},"id":2}' | edgeprompt | jq '.result.content[0].text' | head -20
```

### Update Marketplace (if applicable)

The marketplace uses symlinks, so updates are automatic after push.

## Troubleshooting

### Tests Failing
```bash
# Run specific test suite
swift test --filter AgentSkillsTests
```

### Version Mismatch
```bash
# Check all version locations
grep -h '"version"' .claude-plugin/plugin.json
grep 'version:' Sources/EdgePrompt/EdgePrompt.swift
```

### Agent Knowledge Out of Date
```bash
# Manually regenerate
swift Scripts/generate-agent-knowledge.swift ./agents ./Sources/EdgePrompt/Resources/agent-knowledge.json
```

## PR Workflow (Feature Branches)

**Important:** Use alpha versions for PRs, not release versions!

```bash
# Create feature branch
git checkout -b feature/my-feature

# Bump to alpha
./bump-version.sh 0.19.0-alpha.1

# Work on feature...

# Create PR
gh pr create --fill

# After merge, bump to release on main
git checkout main && git pull
./bump-version.sh 0.19.0
git commit -am "chore: Release v0.19.0"
git tag v0.19.0
git push && git push origin v0.19.0
```

## Version History

| Version | Date | Highlights |
|---------|------|------------|
| 0.18.0 | 2025-11-26 | Swift Format, Azure DevOps MCP |
| 0.17.0 | 2025-11-25 | Skills Restoration |
| 0.16.0 | 2025-11-23 | RAG System Hardening |
