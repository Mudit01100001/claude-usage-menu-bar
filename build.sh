#!/bin/bash
set -e

echo "=== Building Claude Usage macOS Menu Bar App ==="

# Clean previous build
echo "Cleaning old build files..."
rm -rf ClaudeUsage ClaudeUsage.app

# Find macOS SDK path
echo "Locating macOS SDK..."
SDK_PATH=$(xcrun --show-sdk-path --sdk macosx)
echo "SDK Path: $SDK_PATH"

# Compile Swift files
echo "Compiling Swift source files..."
swiftc -O \
       -sdk "$SDK_PATH" \
       -target arm64-apple-macosx13.0 \
       KeychainHelper.swift AppState.swift SettingsView.swift main.swift \
       -o ClaudeUsage

# Create .app bundle structure
echo "Creating application bundle structure..."
mkdir -p ClaudeUsage.app/Contents/MacOS

# Move executable inside bundle
mv ClaudeUsage ClaudeUsage.app/Contents/MacOS/

# Copy Info.plist inside bundle
if [ -f Info.plist ]; then
    cp Info.plist ClaudeUsage.app/Contents/
    echo "Copied Info.plist successfully."
else
    echo "Warning: Info.plist not found! Skipping copy."
fi

# Ensure executable permissions
chmod +x ClaudeUsage.app/Contents/MacOS/ClaudeUsage

echo "=== Build Complete! Created ClaudeUsage.app ==="
echo "You can launch the app with: open ClaudeUsage.app"
