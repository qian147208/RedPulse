#!/bin/bash
# Build script for RedbookRefill
# Cleans build cache and attempts compilation
# Returns detailed output for analysis

set -e

PROJECT_ROOT="/Users/mac/Desktop/红书笔芯/RedbookRefill"
PROJECT_FILE="$PROJECT_ROOT/RedbookRefill.xcodeproj/project.pbxproj"

echo "============================================"
echo " RedbookRefill Build Script"
echo "============================================"
echo ""

# Step 1: Check environment
echo ">>> Checking Xcode environment..."
if xcodebuild -version &>/dev/null; then
    echo "✓ xcodebuild is available"
else
    echo "✗ xcodebuild NOT available (only CommandLineTools installed)"
    echo "  Active developer directory: $(xcode-select -p 2>&1)"
fi

# Step 2: Clean DerivedData (if xcodebuild available)
echo ""
echo ">>> Cleaning build artifacts..."

# Clean project-specific build products
if [ -d "$PROJECT_ROOT/build" ]; then
    echo "  Removing build/ directory..."
    rm -rf "$PROJECT_ROOT/build"
fi

# Clean DerivedData for this project
DERIVED_DATA_DIR="$HOME/Library/Developer/Xcode/DerivedData"
PROJECT_HASH=$(basename "$PROJECT_ROOT" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-zA-Z0-9]//g')

# Find derived data for this project
if [ -d "$DERIVED_DATA_DIR" ]; then
    FOUND=0
    for dd_dir in "$DERIVED_DATA_DIR"/$PROJECT_HASH-*; do
        if [ -d "$dd_dir" ]; then
            echo "  Removing DerivedData: $dd_dir"
            rm -rf "$dd_dir"
            FOUND=1
            break
        fi
    done
    if [ $FOUND -eq 0 ]; then
        echo "  No matching DerivedData found (this is fine)"
    fi
else
    echo "  DerivedData directory not found (this is fine)"
fi

# Clean scheme-derived caches
for cache_dir in "$PROJECT_ROOT/RedbookRefill.build/dyld" "$PROJECT_ROOT/RedbookRefill.build/debug"; do
    if [ -d "$cache_dir" ]; then
        rm -rf "$cache_dir"
    fi
done 2>/dev/null || true

echo ""
echo ">>> Starting compilation..."
echo "============================================"

# Try xcodebuild
if xcodebuild -version &>/dev/null; then
    echo "[xcodebuild mode]"
    # Get the first scheme
    SCHEME=$(head -1 "$PROJECT_FILE" | grep -oP 'PRODUCT_BUNDLE_IDENTIFIER = \K[^;]+' 2>/dev/null | head -1 || echo "")
    
    # Try to find scheme from pbxproj
    SCHEMES=$(grep -oP 'productRefGroup = .*; name = "(\S+)"; path = ' "$PROJECT_FILE" 2>/dev/null | head -1 || echo "")
    
    # Use the xcodeproj name as scheme (common convention)
    SCHEME="RedbookRefill"
    
    xcodebuild clean build \
        -project "$PROJECT_FILE" \
        -scheme "$SCHEME" \
        -destination "platform=macOS" \
        -configuration Debug \
        2>&1 | tee /tmp/build_output.log
    
    EXIT_CODE=${PIPESTATUS[0]}
else
    echo "[swiftc syntax check mode — xcodebuild unavailable]"
    echo ""
    
    # Syntax check all Swift files
    FILES=(
        "RedbookRefill/Features/Generate/GenerateView.swift"
        "RedbookRefill/Features/Generate/GenerateStepSections.swift"
        "RedbookRefill/Features/Generate/GenerateStepStep4Hint.swift"
        "RedbookRefill/Features/Generate/GenerateViewHelpers.swift"
        "RedbookRefill/Features/Result/ResultView.swift"
        "RedbookRefill/Features/Result/ResultEditorPanels.swift"
        "RedbookRefill/Features/Result/ResultLayoutHelpers.swift"
        "RedbookRefill/Features/Result/ResultRegenHelpers.swift"
        "RedbookRefill/ContentView.swift"
        "RedbookRefill/RedPulseApp.swift"
        "RedbookRefill/RootTabView.swift"
    )
    
    ALL_PASSED=true
    for f in "${FILES[@]}"; do
        filepath="$PROJECT_ROOT/$f"
        if [ -f "$filepath" ]; then
            result=$(swiftc -parse "$filepath" -target arm64-apple-macos26.0 2>&1)
            if [ $? -eq 0 ]; then
                echo "  ✓ $f"
            else
                echo "  ✗ $f"
                echo "$result" | sed 's/^/    /'
                ALL_PASSED=false
            fi
        else
            echo "  ? $f (file not found)"
        fi
    done
    
    echo ""
    if [ "$ALL_PASSED" = true ]; then
        echo "All files passed syntax check ✓"
    else
        echo "Some files failed syntax check ✗"
    fi
    
    # Save output
    if [ "$ALL_PASSED" = true ]; then
        echo "Syntax check passed" > /tmp/build_output.log
    else
        echo "Syntax check failed" > /tmp/build_output.log
    fi
fi

echo ""
echo "============================================"
echo " Build complete. Log saved to /tmp/build_output.log"
echo "============================================"

# Also check for any .swift files with common issues
echo ""
echo ">>> Scanning for common issues..."
cd "$PROJECT_ROOT"
for f in $(find RedbookRefill -name "*.swift" -type f); do
    if grep -qP '\\\\\\.' "$f" 2>/dev/null; then
        echo "  ⚠ Double backslash in $f"
    fi
    if grep -q 'import SwiftAudioKit' "$f" 2>/dev/null; then
        echo "  ⚠ import SwiftAudioKit in $f"
    fi
done
echo "  Done."
