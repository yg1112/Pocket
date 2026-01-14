#!/bin/bash

# Pocket Project Setup Script
# This script sets up the development environment for Pocket

set -e

echo "🚀 Setting up Pocket project..."

# Check for required tools
check_tool() {
    if ! command -v $1 &> /dev/null; then
        echo "❌ $1 is not installed."
        return 1
    else
        echo "✅ $1 found"
        return 0
    fi
}

echo ""
echo "📦 Checking required tools..."

# Check Xcode
if ! xcode-select -p &> /dev/null; then
    echo "❌ Xcode Command Line Tools not installed"
    echo "   Run: xcode-select --install"
    exit 1
else
    echo "✅ Xcode Command Line Tools found"
fi

# Check XcodeGen (optional but recommended)
if check_tool xcodegen; then
    XCODEGEN_AVAILABLE=true
else
    XCODEGEN_AVAILABLE=false
    echo "   Install with: brew install xcodegen"
fi

# Check SwiftLint (optional)
if ! check_tool swiftlint; then
    echo "   Install with: brew install swiftlint"
fi

echo ""
echo "📁 Project structure:"
echo ""
find Pocket -type f -name "*.swift" | head -20
echo "..."

# Generate Xcode project if XcodeGen is available
if [ "$XCODEGEN_AVAILABLE" = true ]; then
    echo ""
    echo "🔧 Generating Xcode project with XcodeGen..."
    xcodegen generate
    echo "✅ Xcode project generated!"
else
    echo ""
    echo "⚠️  XcodeGen not available. To generate the Xcode project:"
    echo "   1. Install XcodeGen: brew install xcodegen"
    echo "   2. Run: xcodegen generate"
    echo ""
    echo "   Alternatively, create the project manually in Xcode:"
    echo "   1. Open Xcode"
    echo "   2. Create new iOS App project named 'Pocket'"
    echo "   3. Drag the Pocket folder contents into the project"
fi

echo ""
echo "📋 Next steps:"
echo "   1. Open Pocket.xcodeproj in Xcode"
echo "   2. Set your Development Team in project settings"
echo "   3. Add your Groq API key in Settings (or set GROQ_API_KEY env var)"
echo "   4. Build and run on an iPhone with Dynamic Island"
echo ""
echo "🎉 Setup complete!"
