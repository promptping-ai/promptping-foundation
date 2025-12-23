#!/bin/bash
# install-daemon.sh - Install daemon binaries with symlink setup
# Usage: ./Scripts/install-daemon.sh [--config daemon-config.json]
#
# This script installs pre-built binaries to the package's bin/ directory
# and prints instructions for creating symlinks to ~/.swiftpm/bin/

set -e

# Parse arguments
CONFIG_FILE="daemon-config.json"
while [[ $# -gt 0 ]]; do
  case $1 in
    --config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Validate config exists
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Error: $CONFIG_FILE not found"
  echo "Create a daemon-config.json with: name, serviceLabel, products, daemonProduct"
  exit 1
fi

# Parse config (requires jq)
if ! command -v jq &> /dev/null; then
  echo "Error: jq is required. Install with: brew install jq"
  exit 1
fi

NAME=$(jq -r '.name' "$CONFIG_FILE")
SERVICE_LABEL=$(jq -r '.serviceLabel' "$CONFIG_FILE")
PRODUCTS=$(jq -r '.products[]' "$CONFIG_FILE")
DAEMON_PRODUCT=$(jq -r '.daemonProduct // empty' "$CONFIG_FILE")
DEFAULT_PORT=$(jq -r '.defaultPort // 50052' "$CONFIG_FILE")

echo "═══════════════════════════════════════════════════════════"
echo "  Installing daemon: $NAME"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Create bin directory
mkdir -p bin

# Copy binaries from .build/release/
echo "Copying binaries to bin/..."
for product in $PRODUCTS; do
  if [[ -f ".build/release/$product" ]]; then
    cp ".build/release/$product" "bin/$product"
    chmod 755 "bin/$product"
    echo "  ✓ $product"
  else
    echo "  ✗ $product not found in .build/release/"
    echo "    Run 'swift build -c release' first"
    exit 1
  fi
done

# Generate plist if daemon product specified
if [[ -n "$DAEMON_PRODUCT" && "$DAEMON_PRODUCT" != "null" ]]; then
  SWIFTPM_BIN="$HOME/.swiftpm/bin"
  HOME_DIR="$HOME"

  cat > "bin/$SERVICE_LABEL.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$SERVICE_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$SWIFTPM_BIN/$DAEMON_PRODUCT</string>
        <string>--port</string>
        <string>$DEFAULT_PORT</string>
        <string>--log-level</string>
        <string>info</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>ProcessType</key>
    <string>Background</string>
    <key>StandardOutPath</key>
    <string>$HOME_DIR/Library/Logs/$NAME/daemon.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME_DIR/Library/Logs/$NAME/daemon.err</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$SWIFTPM_BIN:/usr/local/bin:/usr/bin:/bin</string>
        <key>HOME</key>
        <string>$HOME_DIR</string>
    </dict>
    <key>WorkingDirectory</key>
    <string>$HOME_DIR/.cache/$NAME</string>
</dict>
</plist>
EOF
  echo "  ✓ Generated $SERVICE_LABEL.plist"
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  SETUP INSTRUCTIONS (one-time)"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "Step 1: Create symlinks to ~/.swiftpm/bin/"
echo "  ln -sf \$(pwd)/bin/* ~/.swiftpm/bin/"
echo ""

if [[ -n "$DAEMON_PRODUCT" && "$DAEMON_PRODUCT" != "null" ]]; then
  echo "Step 2: Install LaunchAgent plist"
  echo "  mkdir -p ~/Library/Logs/$NAME"
  echo "  cp bin/$SERVICE_LABEL.plist ~/Library/LaunchAgents/"
  echo "  launchctl bootstrap gui/\$(id -u) ~/Library/LaunchAgents/$SERVICE_LABEL.plist"
  echo ""
fi

FIRST_PRODUCT=$(echo "$PRODUCTS" | head -1)
echo "Step 3: Add to ~/.claude/settings.json:"
cat << EOF
{
  "mcpServers": {
    "$NAME": {
      "command": "$FIRST_PRODUCT",
      "args": ["--log-level", "info"],
      "env": {
        "PATH": "$HOME/.swiftpm/bin:/usr/local/bin:/usr/bin:/bin"
      }
    }
  }
}
EOF
echo ""
echo "Future rebuilds will automatically update via symlinks!"
echo ""
