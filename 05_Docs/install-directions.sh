#!/bin/bash
#
# Directions Plugin Installer
# Installs Directions as a Claude Code plugin with hooks and commands
#

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$HOME/.claude/plugins/local/directions"
COMMANDS_DIR="$HOME/.claude/commands"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"

echo "Installing Directions plugin..."
echo ""

# Create directories
mkdir -p "$(dirname "$PLUGIN_DIR")"
mkdir -p "$COMMANDS_DIR"

# Symlink plugin
if [ -L "$PLUGIN_DIR" ]; then
    echo "Updating existing plugin symlink..."
    rm "$PLUGIN_DIR"
elif [ -d "$PLUGIN_DIR" ]; then
    echo "Warning: $PLUGIN_DIR exists as a directory. Backing up..."
    mv "$PLUGIN_DIR" "$PLUGIN_DIR.backup.$(date +%Y%m%d)"
fi

ln -sf "$SCRIPT_DIR" "$PLUGIN_DIR"
echo "✓ Plugin symlinked to $PLUGIN_DIR"

# Copy commands
cp "$SCRIPT_DIR/commands/"*.md "$COMMANDS_DIR/"
echo "✓ Commands copied to $COMMANDS_DIR"

# Handle CLAUDE.md
if [ -f "$CLAUDE_MD" ]; then
    echo ""
    echo "Found existing ~/.claude/CLAUDE.md"
    echo "You may want to manually merge changes from CLAUDE-GLOBAL-TEMPLATE.md"
    echo "Template location: $SCRIPT_DIR/CLAUDE-GLOBAL-TEMPLATE.md"
else
    cp "$SCRIPT_DIR/CLAUDE-GLOBAL-TEMPLATE.md" "$CLAUDE_MD"
    echo "✓ Created $CLAUDE_MD from template"
    echo ""
    echo "⚠️  Edit ~/.claude/CLAUDE.md to set your local paths:"
    echo "   - Local master: $SCRIPT_DIR"
fi

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "1. Restart Claude Code for hooks to take effect"
echo "2. Run /directions to see all available commands"
echo ""
