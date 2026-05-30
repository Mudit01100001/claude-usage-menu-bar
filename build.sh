#!/bin/bash
set -e

echo "=== Building Claude Usage macOS Menu Bar App & Widget ==="

# Clean previous build
echo "Cleaning old build files..."
rm -rf ClaudeUsage ClaudeUsage.app

# Find macOS SDK path
echo "Locating macOS SDK..."
SDK_PATH=$(xcrun --show-sdk-path --sdk macosx)
echo "SDK Path: $SDK_PATH"

# Compile main App Swift files
echo "Compiling main App Swift source files..."
swiftc -O \
       -sdk "$SDK_PATH" \
       -target arm64-apple-macosx14.0 \
       KeychainHelper.swift AppState.swift SettingsView.swift main.swift \
       -o ClaudeUsage

# Create .app bundle structure
echo "Creating application bundle structure..."
mkdir -p ClaudeUsage.app/Contents/MacOS
mkdir -p ClaudeUsage.app/Contents/PlugIns/ClaudeUsageWidget.appex/Contents/MacOS

# Move main executable inside bundle
mv ClaudeUsage ClaudeUsage.app/Contents/MacOS/

# Copy main Info.plist inside bundle
if [ -f Info.plist ]; then
    cp Info.plist ClaudeUsage.app/Contents/
    echo "Copied Info.plist successfully."
else
    echo "Warning: Info.plist not found! Skipping copy."
fi

# Ensure main executable permissions
chmod +x ClaudeUsage.app/Contents/MacOS/ClaudeUsage

# Compile Widget Extension Swift files
echo "Compiling Widget Extension Swift source files..."
swiftc -O \
       -sdk "$SDK_PATH" \
       -target arm64-apple-macosx14.0 \
       -parse-as-library \
       ClaudeUsageWidget.swift \
       -o ClaudeUsage.app/Contents/PlugIns/ClaudeUsageWidget.appex/Contents/MacOS/ClaudeUsageWidget

# Copy Widget-Info.plist inside extension bundle
if [ -f Widget-Info.plist ]; then
    cp Widget-Info.plist ClaudeUsage.app/Contents/PlugIns/ClaudeUsageWidget.appex/Contents/Info.plist
    echo "Copied Widget-Info.plist successfully."
else
    echo "Error: Widget-Info.plist not found!"
    exit 1
fi

# Ensure extension executable permissions
chmod +x ClaudeUsage.app/Contents/PlugIns/ClaudeUsageWidget.appex/Contents/MacOS/ClaudeUsageWidget

# Clean up resource forks and Finder info (detritus) that prevent codesigning
echo "Cleaning bundle metadata..."
xattr -cr ClaudeUsage.app

# Code signing (Hierarchical order: inner plugins first, then outer app bundle)
echo "Signing Widget extension..."
codesign --force --sign - --entitlements widget.entitlements ClaudeUsage.app/Contents/PlugIns/ClaudeUsageWidget.appex

# Clean up resource forks/metadata on the outer directories created during the widget signing process
# (Do NOT use -r to prevent invalidating the inner widget's signature)
echo "Cleaning signed metadata..."
xattr -c ClaudeUsage.app/Contents/PlugIns/ClaudeUsageWidget.appex 2>/dev/null || true
xattr -c ClaudeUsage.app 2>/dev/null || true

echo "Signing main App bundle..."
codesign --force --sign - ClaudeUsage.app

echo "=== Build Complete! Created ClaudeUsage.app ==="
echo "You can launch the app with: open ClaudeUsage.app"
