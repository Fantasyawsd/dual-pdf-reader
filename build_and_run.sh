#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:---build}"
APP_NAME="DualPDFReader"
APP_BUNDLE="${APP_NAME}.app"
BUILD_DIR=".build"
MIN_MACOS="12.0"
TARGET="$(uname -m)-apple-macos${MIN_MACOS}"
case "$MODE" in
    --build|--test|--ui-test|--run|--debug|--logs|--verify) ;;
    *) echo "用法: $0 [--build|--test|--ui-test|--run|--debug|--logs|--verify]" >&2; exit 2 ;;
esac
mkdir -p "$BUILD_DIR" "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

SOURCES=(Sources/*.swift)
FRAMEWORKS=(-framework Cocoa -framework PDFKit -framework WebKit -framework JavaScriptCore -framework UniformTypeIdentifiers)

if [[ "$MODE" == "--test" || "$MODE" == "--ui-test" ]]; then
    TEST_SOURCES=()
    for source in "${SOURCES[@]}"; do
        [[ "$source" == "Sources/main.swift" ]] || TEST_SOURCES+=("$source")
    done
    if [[ "$MODE" == "--test" ]]; then
        swiftc "${TEST_SOURCES[@]}" Tests/FunctionalGapTests.swift Tests/P0SystemOpenTests.swift Tests/P0TransientLibraryTests.swift Tests/ReaderCoreTests.swift Tests/PDFWidthLayoutTests.swift Tests/main.swift -target "$TARGET" "${FRAMEWORKS[@]}" -o "$BUILD_DIR/RegressionTests"
        "$BUILD_DIR/RegressionTests"
    else
        swiftc "${TEST_SOURCES[@]}" Tests/LegacyUITests.swift Tests/UI/main.swift -target "$TARGET" "${FRAMEWORKS[@]}" -o "$BUILD_DIR/UITests"
        "$BUILD_DIR/UITests"
        Tests/BugAudit/run.sh
    fi
    exit 0
fi

swiftc "${SOURCES[@]}" -O -target "$TARGET" "${FRAMEWORKS[@]}" -o "$BUILD_DIR/$APP_NAME"
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Resources/* "$APP_BUNDLE/Contents/Resources/"
cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>com.local.DualPDFReader</string>
    <key>CFBundleName</key><string>DualPDF 双栏文献阅读器</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>2.2.0</string>
    <key>LSMinimumSystemVersion</key><string>${MIN_MACOS}</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>PDF Document</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.adobe.pdf</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>pdf</string>
            </array>
        </dict>
    </array>
</dict></plist>
EOF
SIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
if ! codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE"; then
    if [[ "$SIGN_IDENTITY" == "-" ]]; then
        exit 1
    fi
    echo "签名身份 ${SIGN_IDENTITY} 不可用，改用 ad-hoc 签名" >&2
    codesign --force --deep --sign - "$APP_BUNDLE"
fi
echo "构建成功: $PWD/$APP_BUNDLE（macOS ${MIN_MACOS}+）"

case "$MODE" in
    --run|--logs|--verify)
        /usr/bin/open -n "$APP_BUNDLE"
        if [[ "$MODE" == "--logs" ]]; then
            /usr/bin/log stream --info --style compact --predicate 'process == "DualPDFReader"'
        elif [[ "$MODE" == "--verify" ]]; then
            sleep 1
            pgrep -x "$APP_NAME" >/dev/null
        fi ;;
    --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
esac
