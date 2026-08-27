#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# AndroLaunch for Caelestia (Linux) Installer
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SCRIPT_DIR}/caelestia"
TARGET_DIR="${HOME}/.config/quickshell/caelestia"

echo "=== AndroLaunch for Caelestia Installer ==="
echo ""

# 1. Dependency checks
echo "Checking dependencies..."
MISSING_DEPS=()

if ! command -v adb &>/dev/null; then
    echo "[-] adb (android-tools) is not installed."
    MISSING_DEPS+=("android-tools")
else
    echo "[+] adb found: $(which adb)"
fi

if ! command -v scrcpy &>/dev/null; then
    echo "[-] scrcpy is not installed (required for screen mirroring)."
    MISSING_DEPS+=("scrcpy")
else
    echo "[+] scrcpy found: $(which scrcpy)"
fi

if ! command -v qs &>/dev/null && ! command -v caelestia &>/dev/null; then
    echo "[-] quickshell / caelestia not found in PATH."
fi

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    echo ""
    echo "Recommended packages to install: ${MISSING_DEPS[*]}"
    echo "  Fedora:   sudo dnf install ${MISSING_DEPS[*]}"
    echo "  Arch:     sudo pacman -S ${MISSING_DEPS[*]}"
    echo "  Ubuntu:   sudo apt install ${MISSING_DEPS[*]}"
    echo ""
fi

# 2. Check target directory
if [ ! -d "${TARGET_DIR}" ]; then
    echo "Error: Caelestia configuration not found at ${TARGET_DIR}"
    exit 1
fi

echo "Installing AndroLaunch components to ${TARGET_DIR}..."

# 3. Copy files
mkdir -p "${TARGET_DIR}/services" \
         "${TARGET_DIR}/utils" \
         "${TARGET_DIR}/components/widgets" \
         "${TARGET_DIR}/modules/bar/components/status" \
         "${TARGET_DIR}/modules/bar/popouts" \
         "${TARGET_DIR}/modules/sidebar" \
         "${TARGET_DIR}/modules/utilities/cards" \
         "${TARGET_DIR}/modules/nexus/pages/androlaunch"

cp -v "${SOURCE_DIR}/services/AndroLaunch.qml" "${TARGET_DIR}/services/"
cp -v "${SOURCE_DIR}/utils/QRCode.js" "${TARGET_DIR}/utils/"
cp -v "${SOURCE_DIR}/components/widgets/QRCodeView.qml" "${TARGET_DIR}/components/widgets/"
cp -v "${SOURCE_DIR}/modules/bar/components/BarAndroLaunch.qml" "${TARGET_DIR}/modules/bar/components/"
cp -v "${SOURCE_DIR}/modules/bar/components/status/AndroLaunchStatus.qml" "${TARGET_DIR}/modules/bar/components/status/"
cp -v "${SOURCE_DIR}/modules/bar/popouts/AndroLaunch.qml" "${TARGET_DIR}/modules/bar/popouts/"
cp -v "${SOURCE_DIR}/modules/bar/popouts/AndroLaunchPopout.qml" "${TARGET_DIR}/modules/bar/popouts/"
cp -v "${SOURCE_DIR}/modules/sidebar/AndroLaunchSidebarCard.qml" "${TARGET_DIR}/modules/sidebar/"
cp -v "${SOURCE_DIR}/modules/utilities/cards/AndroLaunchCard.qml" "${TARGET_DIR}/modules/utilities/cards/"
cp -v "${SOURCE_DIR}/modules/nexus/pages/AndroLaunchPage.qml" "${TARGET_DIR}/modules/nexus/pages/"
cp -v "${SOURCE_DIR}/modules/nexus/pages/androlaunch/"*.qml "${TARGET_DIR}/modules/nexus/pages/androlaunch/"

# 4. Patch registrations if needed
echo "Verifying service loader registration..."
if ! grep -q "AndroLaunch" "${TARGET_DIR}/modules/ServiceLoader.qml" 2>/dev/null; then
    sed -i '/Brightness;/a \        AndroLaunch;' "${TARGET_DIR}/modules/ServiceLoader.qml"
fi

echo "Verifying shell.json bar entry..."
SHELL_JSON="${HOME}/.config/caelestia/shell.json"
if [ -f "${SHELL_JSON}" ] && ! grep -q '"id": "androlaunch"' "${SHELL_JSON}"; then
    sed -i 's/"id": "media", "enabled": true },/& \n            { "id": "androlaunch", "enabled": true },/' "${SHELL_JSON}"
fi

# 5. Restart Caelestia shell
if command -v caelestia &>/dev/null; then
    echo "Reloading Caelestia Shell..."
    caelestia shell -k 2>/dev/null || true
    sleep 1
    caelestia shell -d
    echo "[+] Shell reloaded successfully."
fi

echo ""
echo "=== AndroLaunch successfully installed! ==="
echo "You can now control Android devices from the Taskbar, Sidebar, Utilities panel, and Nexus."
