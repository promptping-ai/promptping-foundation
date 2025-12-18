#!/bin/bash
# Setup script for code-search-mcp git hooks and direnv integration
#
# This script:
# 1. Configures git to use .githooks directory for hooks
# 2. Makes hooks executable
# 3. Sets up direnv (if installed)
#
# Usage: ./scripts/setup-code-search.sh

set -e

PROJECT_ROOT="$(git rev-parse --show-toplevel)"
HOOKS_DIR="$PROJECT_ROOT/.githooks"

echo "🔧 Setting up code-search-mcp integration..."

# Check for git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "❌ Error: Not a git repository"
  exit 1
fi

# Configure git to use .githooks directory
echo "📂 Configuring git hooks path..."
git config core.hooksPath .githooks
echo "   ✓ core.hooksPath set to .githooks"

# Make hooks executable
echo "🔐 Setting hook permissions..."
chmod +x "$HOOKS_DIR"/post-* 2>/dev/null || true
echo "   ✓ Hooks are executable"

# Set up direnv if available
if command -v direnv &> /dev/null; then
  echo "🌍 Setting up direnv..."
  direnv allow "$PROJECT_ROOT"
  echo "   ✓ direnv configured"
else
  echo "⚠️  direnv not found - environment variables won't auto-load"
  echo "   Install with: brew install direnv"
fi

# Check for code-search-mcp binary
BINARY="$HOME/.swiftpm/bin/code-search-mcp"
if [ -x "$BINARY" ]; then
  echo "✓ code-search-mcp found at $BINARY"

  # Optionally run initial index
  read -p "   Run initial index now? [y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "📚 Running initial index (this may take a moment)..."
    "$BINARY" index "$PROJECT_ROOT"
    echo "   ✓ Initial index complete"
  fi
else
  echo "⚠️  code-search-mcp not found at $BINARY"
  echo "   To install:"
  echo "     cd ~/Developer/code-search-mcp"
  echo "     swift package experimental-install"
fi

echo ""
echo "✅ Setup complete!"
echo ""
echo "Hooks will automatically re-index after:"
echo "  • git commit"
echo "  • git pull/merge"
echo "  • git checkout (branch switches)"
