#!/bin/bash

APP_NAME="StockTicker"
BUILD_DIR=".build/release"
OUTPUT_DIR="dist"
APP_BUNDLE="${OUTPUT_DIR}/${APP_NAME}.app"

# 0. Handle Versioning
if [ ! -f VERSION ]; then
    echo "1.0" > VERSION
fi

CURRENT_VERSION=$(cat VERSION)
# Split into array
IFS='.' read -r -a VERSION_PARTS <<< "$CURRENT_VERSION"
MAJOR="${VERSION_PARTS[0]}"
MINOR="${VERSION_PARTS[1]}"

# Increment Minor
NEW_MINOR=$((MINOR + 1))
NEW_VERSION="${MAJOR}.${NEW_MINOR}"

echo "Bumping version: ${CURRENT_VERSION} -> ${NEW_VERSION}"
echo "${NEW_VERSION}" > VERSION

# Update Swift Code (MenuBarManager.swift)
# Look for: menu.addItem(NSMenuItem(title: "Quit (vX.X)", ...
# We use sed to replace it.
sed -i '' "s/title: \"Quit (v.*)\"/title: \"Quit (v${NEW_VERSION})\"/" Sources/StockTickerApp/MenuBarManager.swift

# 1. Build release version
echo "Building Release version..."
swift build -c release

# 2. Create Directory Structure
echo "Creating App Bundle..."
# Clear old build to ensure freshness
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# 3. Copy Executable
cp "${BUILD_DIR}/StockTickerApp" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# 4. Create Info.plist
echo "Creating Info.plist..."
cat > "${APP_BUNDLE}/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.example.StockTickerApp</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleShortVersionString</key>
    <string>${NEW_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${NEW_MINOR}</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# 5. Remove quarantine (optional, for local testing)
# xattr -cr "${APP_BUNDLE}"

echo "Done! App is located at: ${APP_BUNDLE}"
echo "You can zip this folder to share it."
