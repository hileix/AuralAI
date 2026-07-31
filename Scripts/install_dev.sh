#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PROJECT_PATH="${PROJECT_PATH:-${ROOT_DIR}/AuralAI.xcodeproj}"
SCHEME="${SCHEME:-AuralAI}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${ROOT_DIR}/.build/AuralAIDevDerivedData}"
INSTALL_PATH="${INSTALL_PATH:-/Applications/AuralAI Dev.app}"
BUNDLE_ID="com.xiaolei.AuralAI.dev"
APP_NAME="AuralAI Dev"
BUILT_APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Release/${APP_NAME}.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
LAUNCH_JOB_LABEL="com.xiaolei.AuralAI.dev.launch"

echo "Building ${APP_NAME}.app..."
xcodebuild \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    -destination "platform=macOS" \
    PRODUCT_BUNDLE_IDENTIFIER="${BUNDLE_ID}" \
    PRODUCT_NAME="${APP_NAME}" \
    INFOPLIST_KEY_CFBundleDisplayName="${APP_NAME}" \
    INFOPLIST_KEY_CFBundleName="${APP_NAME}" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    ENABLE_DEBUG_DYLIB=NO \
    REGISTER_WITH_LAUNCH_SERVICES=NO \
    build

if [[ ! -d "${BUILT_APP_PATH}" ]]; then
    echo "Build succeeded but app was not found at: ${BUILT_APP_PATH}" >&2
    exit 1
fi

ACTUAL_BUNDLE_ID="$(defaults read "${BUILT_APP_PATH}/Contents/Info" CFBundleIdentifier)"
if [[ "${ACTUAL_BUNDLE_ID}" != "${BUNDLE_ID}" ]]; then
    echo "Unexpected bundle identifier: ${ACTUAL_BUNDLE_ID}" >&2
    exit 1
fi

codesign --verify --deep --strict "${BUILT_APP_PATH}"
if codesign -d --entitlements :- "${BUILT_APP_PATH}" 2>&1 | grep -q "com.apple.security.get-task-allow"; then
    echo "Refusing to install a build with get-task-allow enabled." >&2
    exit 1
fi
if codesign -d --entitlements :- "${BUILT_APP_PATH}" 2>&1 | grep -q "com.apple.security.app-sandbox"; then
    echo "Refusing to install a sandboxed build because system-wide Accessibility APIs require an unsandboxed app." >&2
    exit 1
fi

echo "Stopping the installed development app..."
launchctl remove "${LAUNCH_JOB_LABEL}" 2>/dev/null || true
pkill -TERM -x "${APP_NAME}" 2>/dev/null || true
for _ in {1..20}; do
    if ! pgrep -x "${APP_NAME}" >/dev/null; then
        break
    fi
    sleep 0.1
done

echo "Installing to ${INSTALL_PATH}..."
mkdir -p "${INSTALL_PATH}"
rsync --archive --delete "${BUILT_APP_PATH}/" "${INSTALL_PATH}/"
codesign --verify --deep --strict "${INSTALL_PATH}"
"${LSREGISTER}" -u "${BUILT_APP_PATH}" >/dev/null 2>&1 || true
"${LSREGISTER}" -f "${INSTALL_PATH}"

echo "Launching ${APP_NAME}..."
launchctl submit \
    -l "${LAUNCH_JOB_LABEL}" \
    -- "${INSTALL_PATH}/Contents/MacOS/${APP_NAME}"

cat <<EOF

Installed ${APP_NAME} with bundle identifier ${BUNDLE_ID}.
The build uses Release code generation without the get-task-allow or App Sandbox entitlements.

If macOS does not trust this build yet, toggle ${APP_NAME} off and on once in:
System Settings > Privacy & Security > Accessibility
EOF
