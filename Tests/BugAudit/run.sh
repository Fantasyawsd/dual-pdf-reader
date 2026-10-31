#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p .build
sources=()
for source in Sources/*.swift; do
    [[ "$source" == "Sources/main.swift" ]] || sources+=("$source")
done
swiftc "${sources[@]}" Tests/BugAudit/main.swift \
    -target "$(uname -m)-apple-macos12.0" \
    -framework Cocoa -framework PDFKit -framework WebKit \
    -framework JavaScriptCore -framework UniformTypeIdentifiers \
    -o .build/BugAudit
.build/BugAudit
