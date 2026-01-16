#!/bin/bash

# =============================================================================
# Build script for Pocket.app
# Supports: Development build, Signed build, and Notarized distribution
# =============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
APP_NAME="Pocket"
BUNDLE_ID="com.pocket.app"
SCHEME="Pocket"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
APP_PATH="/Applications/${APP_NAME}.app"

# Developer ID - Shared across all apps under same developer account
DEVELOPER_ID="${DEVELOPER_ID:-Developer ID Application: DZG Studio LLC (DRV5ZMT5U8)}"
TEAM_ID="${TEAM_ID:-DRV5ZMT5U8}"

# Notarization - Uses keychain profile (shared across apps)
NOTARY_PROFILE="${NOTARY_PROFILE:-ResoNotary}"

# Parse arguments
BUILD_MODE="dev"  # dev, signed, release
CLEAN_BUILD=false
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --dev) BUILD_MODE="dev" ;;
        --signed) BUILD_MODE="signed" ;;
        --release) BUILD_MODE="release" ;;
        --clean) CLEAN_BUILD=true ;;
        --help|-h)
            echo "Usage: $0 [--dev|--signed|--release] [--clean]"
            echo ""
            echo "Options:"
            echo "  --dev      Development build (no signing, default)"
            echo "  --signed   Signed build with Developer ID"
            echo "  --release  Full release build with signing + notarization"
            echo "  --clean    Clean build directory before building"
            echo ""
            echo "Environment variables (optional overrides):"
            echo "  DEVELOPER_ID   - Developer ID certificate (default: DZG Studio LLC)"
            echo "  TEAM_ID        - Apple Developer Team ID (default: DRV5ZMT5U8)"
            echo "  NOTARY_PROFILE - Keychain profile for notarization (default: ResoNotary)"
            echo ""
            echo "To create a dedicated notarization profile for Pocket:"
            echo "  xcrun notarytool store-credentials \"PocketNotary\" --apple-id \"your@email.com\" --team-id \"DRV5ZMT5U8\""
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Building ${APP_NAME} (${BUILD_MODE} mode)${NC}"
echo -e "${BLUE}========================================${NC}"

# Step 1: Clean if requested
if [[ "${CLEAN_BUILD}" == true ]]; then
    echo -e "\n${YELLOW}[1/7] Cleaning build directory...${NC}"
    rm -rf "${BUILD_DIR}"
    rm -rf ~/Library/Developer/Xcode/DerivedData/Pocket-*
    echo -e "${GREEN}Clean complete${NC}"
else
    echo -e "\n${YELLOW}[1/7] Skipping clean (use --clean to clean)${NC}"
fi

# Step 2: Build using xcodebuild
echo -e "\n${YELLOW}[2/7] Building with xcodebuild...${NC}"

# Determine code signing settings based on build mode
if [[ "${BUILD_MODE}" == "dev" ]]; then
    # Development build - sign to run locally
    SIGNING_ARGS=(
        CODE_SIGN_IDENTITY="-"
        CODE_SIGNING_REQUIRED=NO
        CODE_SIGNING_ALLOWED=NO
    )
else
    # Signed/Release build - use Developer ID
    SIGNING_ARGS=(
        CODE_SIGN_IDENTITY="${DEVELOPER_ID}"
        DEVELOPMENT_TEAM="${TEAM_ID}"
        CODE_SIGN_STYLE=Manual
    )
fi

xcodebuild \
    -project "${PROJECT_DIR}/Pocket.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -derivedDataPath "${BUILD_DIR}" \
    "${SIGNING_ARGS[@]}" \
    build

if [ $? -ne 0 ]; then
    echo -e "${RED}Build failed!${NC}"
    exit 1
fi
echo -e "${GREEN}Build successful${NC}"

# Step 3: Kill existing app
echo -e "\n${YELLOW}[3/7] Stopping existing app...${NC}"
killall "${APP_NAME}" 2>/dev/null || true
sleep 1

# Step 4: Remove old app from /Applications
echo -e "\n${YELLOW}[4/7] Removing old app from /Applications...${NC}"
rm -rf "${APP_PATH}"

# Step 5: Copy new app to /Applications
echo -e "\n${YELLOW}[5/7] Installing to /Applications...${NC}"
BUILT_APP="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"

if [ ! -d "${BUILT_APP}" ]; then
    echo -e "${RED}Error: Built app not found at ${BUILT_APP}${NC}"
    exit 1
fi

cp -R "${BUILT_APP}" "${APP_PATH}"

# Clear extended attributes
xattr -cr "${APP_PATH}"

echo -e "${GREEN}App installed to /Applications${NC}"

# Step 6: Code signing (for signed and release builds)
if [[ "${BUILD_MODE}" == "signed" || "${BUILD_MODE}" == "release" ]]; then
    echo -e "\n${YELLOW}[6/7] Code signing with Hardened Runtime...${NC}"

    if [ -z "${DEVELOPER_ID}" ]; then
        echo -e "${RED}Error: DEVELOPER_ID environment variable not set${NC}"
        echo "Find your identity with: security find-identity -v -p codesigning"
        echo "Then run: DEVELOPER_ID='Developer ID Application: ...' $0 --signed"
        exit 1
    fi

    # Sign the app with hardened runtime and entitlements
    codesign --force --deep --options runtime \
        --entitlements "${PROJECT_DIR}/Pocket/Pocket.entitlements" \
        --sign "${DEVELOPER_ID}" \
        "${APP_PATH}"

    # Verify signature
    codesign --verify --verbose "${APP_PATH}"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Code signing successful${NC}"
    else
        echo -e "${RED}Code signing verification failed${NC}"
        exit 1
    fi
else
    echo -e "\n${YELLOW}[6/7] Skipping code signing (dev build)...${NC}"
fi

# Step 7: Notarization (for release builds only)
if [[ "${BUILD_MODE}" == "release" ]]; then
    echo -e "\n${YELLOW}[7/7] Notarizing app...${NC}"

    # Create a zip for notarization
    NOTARIZE_ZIP="/tmp/${APP_NAME}-notarize.zip"
    rm -f "${NOTARIZE_ZIP}"
    ditto -c -k --keepParent "${APP_PATH}" "${NOTARIZE_ZIP}"

    # Submit for notarization using keychain profile
    echo "Submitting to Apple for notarization (using keychain profile: ${NOTARY_PROFILE})..."
    xcrun notarytool submit "${NOTARIZE_ZIP}" \
        --keychain-profile "${NOTARY_PROFILE}" \
        --wait

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Notarization successful${NC}"

        # Staple the notarization ticket to the app
        echo "Stapling notarization ticket..."
        xcrun stapler staple "${APP_PATH}"

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Stapling successful${NC}"
        else
            echo -e "${YELLOW}Warning: Stapling failed (app is still notarized)${NC}"
        fi
    else
        echo -e "${RED}Notarization failed${NC}"
        echo "If the keychain profile doesn't exist, create it with:"
        echo "  xcrun notarytool store-credentials \"${NOTARY_PROFILE}\" --apple-id \"your@email.com\" --team-id \"${TEAM_ID}\""
        exit 1
    fi

    # Clean up
    rm -f "${NOTARIZE_ZIP}"
else
    echo -e "\n${YELLOW}[7/7] Skipping notarization (not a release build)...${NC}"
fi

# Done!
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}  ${APP_NAME}.app installed to /Applications${NC}"
echo -e "${GREEN}========================================${NC}"

# Launch the app (dev builds only)
if [[ "${BUILD_MODE}" == "dev" ]]; then
    echo -e "\nLaunching app..."
    open "${APP_PATH}"
fi

echo ""
echo "Build mode: ${BUILD_MODE}"
if [[ "${BUILD_MODE}" == "release" ]]; then
    echo -e "${GREEN}App is signed and notarized - ready for distribution!${NC}"
    echo "Next: Create a DMG for distribution"
elif [[ "${BUILD_MODE}" == "signed" ]]; then
    echo -e "${YELLOW}App is signed but not notarized${NC}"
    echo "Run with --release for full distribution build"
fi
