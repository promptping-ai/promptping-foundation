#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Installing promptping-foundation tools...${NC}"
echo ""

# Check Swift is available
if ! command -v swift &> /dev/null; then
    echo -e "${RED}Error: Swift is not installed or not in PATH${NC}"
    echo "Please install Swift from https://swift.org/download/"
    exit 1
fi

SWIFT_VERSION=$(swift --version 2>&1 | head -1)
echo -e "Using: ${SWIFT_VERSION}"
echo ""

# Tools to install
TOOLS=("pr-comments" "bump-version" "install-daemon")

# Build in release mode first
echo -e "${YELLOW}Building in release mode...${NC}"
swift build -c release

# Install each tool
for tool in "${TOOLS[@]}"; do
    echo ""
    echo -e "${YELLOW}Installing ${tool}...${NC}"

    # Remove existing binary if present
    if [ -f "$HOME/.swiftpm/bin/$tool" ]; then
        rm -f "$HOME/.swiftpm/bin/$tool"
        echo "  Removed existing installation"
    fi

    # Install via SPM
    swift package experimental-install --product "$tool"

    # Verify installation
    if [ -f "$HOME/.swiftpm/bin/$tool" ]; then
        echo -e "  ${GREEN}✅ Installed successfully${NC}"
    else
        echo -e "  ${RED}❌ Installation failed${NC}"
        exit 1
    fi
done

echo ""
echo -e "${GREEN}✅ All tools installed to ~/.swiftpm/bin/${NC}"
echo ""
echo "Make sure ~/.swiftpm/bin is in your PATH:"
echo "  export PATH=\"\$HOME/.swiftpm/bin:\$PATH\""
echo ""
echo "Available commands:"
echo "  pr-comments  - View, reply, and resolve PR comments"
echo "  bump-version - Semantic version bumping with Git integration"
echo "  install-daemon - Install MCP servers with launchd"
