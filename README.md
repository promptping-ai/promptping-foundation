# promptping-foundation

CLI tools for PR comments, version bumping, and daemon management.

## Tools

| Tool | Description | Platforms |
|------|-------------|-----------|
| `pr-comments` | View, reply, and resolve PR comments across GitHub/GitLab/Azure DevOps | macOS, Linux |
| `bump-version` | Semantic version bumping with Git integration | macOS, Linux |
| `install-daemon` | Install MCP servers with macOS launchd service management | macOS |

## Installation

### Option 1: Pre-built Binaries (Recommended)

Download the latest release from [GitHub Releases](https://github.com/promptping-ai/promptping-foundation/releases).

**macOS (Apple Silicon):**
```bash
VERSION="0.2.1"
curl -sL https://github.com/promptping-ai/promptping-foundation/releases/download/v${VERSION}/pr-comments-${VERSION}-macos-arm64.tar.gz | tar xz
sudo mv pr-comments/pr-comments /usr/local/bin/
```

**macOS (Intel):**
```bash
VERSION="0.2.1"
curl -sL https://github.com/promptping-ai/promptping-foundation/releases/download/v${VERSION}/pr-comments-${VERSION}-macos-x86_64.tar.gz | tar xz
sudo mv pr-comments/pr-comments /usr/local/bin/
```

**Linux:**
```bash
VERSION="0.2.1"
curl -sL https://github.com/promptping-ai/promptping-foundation/releases/download/v${VERSION}/pr-comments-${VERSION}-linux-x86_64.tar.gz | tar xz
sudo mv pr-comments/pr-comments /usr/local/bin/
```

### Option 2: Build from Source

Requires Swift 6.0+.

```bash
git clone https://github.com/promptping-ai/promptping-foundation.git
cd promptping-foundation
./install.sh
```

Or install individual tools:
```bash
swift package experimental-install --product pr-comments
swift package experimental-install --product bump-version
swift package experimental-install --product install-daemon
```

### GitHub Actions

Use pre-built binaries in your workflows without rebuilding:

```yaml
- name: Install pr-comments
  run: |
    VERSION="0.2.1"
    curl -sL https://github.com/promptping-ai/promptping-foundation/releases/download/v${VERSION}/pr-comments-${VERSION}-linux-x86_64.tar.gz | tar xz
    sudo mv pr-comments/pr-comments /usr/local/bin/

- name: View PR comments
  run: pr-comments ${{ github.event.pull_request.number }}
```

## Usage

### pr-comments

View and interact with PR comments across multiple providers.

```bash
# View PR comments
pr-comments 123

# View current branch's PR
pr-comments --current

# Show only unresolved threads
pr-comments 123 --unresolved

# Reply to a PR
pr-comments reply 123 -m "Thanks for the review!"

# Reply to a specific comment thread
pr-comments reply-to 123 <comment-id> -m "Fixed!"

# Resolve a thread
pr-comments resolve 123 <thread-id>

# Translate comments to English (macOS only)
pr-comments 123 --language en
```

**Supported Providers:**
- GitHub (via `gh` CLI)
- GitLab (via `glab` CLI)
- Azure DevOps (via `az` CLI)

### bump-version

Semantic version bumping with Git integration.

```bash
# Bump patch version (0.2.0 -> 0.2.1)
bump-version patch

# Bump minor version (0.2.1 -> 0.3.0)
bump-version minor

# Bump major version (0.3.0 -> 1.0.0)
bump-version major

# Create alpha prerelease
bump-version patch --prerelease alpha

# Create GitHub release
bump-version patch --release
```

### install-daemon

Install MCP servers with macOS launchd service management.

```bash
# Install daemon from current package
install-daemon

# Install with specific port
install-daemon --port 8080

# Uninstall daemon
install-daemon --uninstall

# Dry run (show what would happen)
install-daemon --dry-run
```

Requires a `daemon-config.json` in the package root. See [CLAUDE.md](./CLAUDE.md) for configuration details.

## Requirements

- **macOS 14+** or **Linux** (Ubuntu 22.04+)
- **Swift 6.0+** (for building from source)
- **gh CLI** (for GitHub integration)
- **glab CLI** (optional, for GitLab)
- **az CLI** (optional, for Azure DevOps)

## License

MIT
