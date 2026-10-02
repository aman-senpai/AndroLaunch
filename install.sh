#!/usr/bin/env bash
# =============================================================================
# AndroLaunch for KDE Plasma (Fedora / Linux) installer
#
#   curl -fsSL https://raw.githubusercontent.com/aman-senpai/AndroLaunch/master/install.sh | bash
#
# Installs:
#   1. adb (android-tools) + scrcpy, if missing
#   2. the `androlaunch` backend CLI  -> ~/.local/bin/androlaunch
#   3. the Plasma 6 plasmoid         -> ~/.local/share/plasma/plasmoids/org.androlaunch.plasma
#   4. the widget into a panel (the "menubar"), unless --no-panel is given
#
# Options:
#   --skip-deps        Do not install missing adb / scrcpy packages
#   --no-panel         Do not add the widget to the panel automatically
#   --bin-dir PATH     Where to install the backend CLI (default: ~/.local/bin)
#   --uninstall        Remove the plasmoid, the backend CLI and its state
#   -h, --help         Show this help
#
# Env:
#   ANDROLAUNCH_REF    Git ref of the AndroLaunch repo to install (default: master)
# =============================================================================

set -euo pipefail

REPO="aman-senpai/AndroLaunch"
REF="${ANDROLAUNCH_REF:-master}"
PLUGIN_ID="org.androlaunch.plasma"
BIN_DIR="${ANDROLAUNCH_BIN_DIR:-$HOME/.local/bin}"
HELPER_NAME="androlaunch"
PLASMOID_ROOT="$HOME/.local/share/plasma/plasmoids"
PLASMOID_DIR="$PLASMOID_ROOT/$PLUGIN_ID"

SKIP_DEPS=0
ADD_TO_PANEL=1
UNINSTALL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

step() { echo -e "${BLUE}[$1]${NC} $2"; }
ok()   { echo -e "      ${GREEN}✓${NC} $1"; }
warn() { echo -e "      ${YELLOW}!${NC} $1"; }
fail() { echo -e "      ${RED}✗${NC} $1"; }
die()  { echo -e "${RED}Error:${NC} $1" >&2; exit 1; }

usage() {
    sed -n '3,21p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-deps) SKIP_DEPS=1; shift ;;
        --no-panel)  ADD_TO_PANEL=0; shift ;;
        --uninstall) UNINSTALL=1; shift ;;
        --bin-dir)
            [ $# -ge 2 ] || die "--bin-dir needs a path"
            BIN_DIR="$2"
            shift 2
            ;;
        -h|--help) usage ;;
        *) die "unknown option: $1 (try --help)" ;;
    esac
done

HELPER="$BIN_DIR/$HELPER_NAME"

echo -e "${CYAN}${BOLD}"
echo "============================================================"
echo "  AndroLaunch - KDE Plasma installer"
echo "============================================================"
echo -e "${NC}"

# -----------------------------------------------------------------------------
# Platform
# -----------------------------------------------------------------------------
case "$(uname -s)" in
    Linux) ;;
    Darwin) die "this installer is for KDE Plasma on Linux. On macOS use: brew tap aman-senpai/tap && brew install --cask androlaunch" ;;
    *) die "unsupported OS: $(uname -s) (Linux only)" ;;
esac

for bin in curl tar awk install; do
    command -v "$bin" >/dev/null 2>&1 || die "required tool missing: $bin"
done

if ! command -v kpackagetool6 >/dev/null 2>&1 && ! command -v kpackagetool5 >/dev/null 2>&1; then
    die "kpackagetool not found — install KDE Plasma first (this widget targets Plasma 6)"
fi
KPACKAGE="$(command -v kpackagetool6 || command -v kpackagetool5)"

# -----------------------------------------------------------------------------
# Uninstall
# -----------------------------------------------------------------------------
if [ "$UNINSTALL" -eq 1 ]; then
    echo -e "${BOLD}Removing AndroLaunch${NC}"

    if command -v gdbus >/dev/null 2>&1; then
        gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell \
            --method org.kde.PlasmaShell.evaluateScript '
            var ps = panels();
            for (var i = 0; i < ps.length; i++) {
                var ws = ps[i].widgets();
                for (var j = ws.length - 1; j >= 0; j--) {
                    if (ws[j].type === "org.androlaunch.plasma")
                        ws[j].remove();
                }
            }
            print("panel cleaned");' >/dev/null 2>&1 && ok "removed from panel" || warn "could not reach plasmashell"
    fi

    if "$KPACKAGE" -t Plasma/Applet -l 2>/dev/null | grep -qx "$PLUGIN_ID"; then
        "$KPACKAGE" -t Plasma/Applet -r "$PLUGIN_ID" && ok "removed plasmoid"
    else
        warn "plasmoid not installed"
    fi

    for icon in "$HOME/.local/share/icons/hicolor/256x256/apps/androlaunch.png"; do
        [ -f "$icon" ] && rm -f "$icon" && ok "removed $(basename "$icon")"
    done
    [ -f "$HELPER" ] && rm -f "$HELPER" && ok "removed $HELPER" || true
    [ -d "$HOME/.config/androlaunch" ] && rm -rf "$HOME/.config/androlaunch" && ok "removed stored device state" || true

    echo ""
    echo -e "${GREEN}Uninstalled${NC}"
    exit 0
fi

# -----------------------------------------------------------------------------
# [1/6] Payload
# -----------------------------------------------------------------------------
step "1/6" "Source"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/androlaunch.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

SELF="${BASH_SOURCE[0]:-}"
if [ -n "$SELF" ] && [ -f "$SELF" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$SELF")" && pwd)"
else
    SCRIPT_DIR=""
fi

PAYLOAD=""
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/kde/bin/$HELPER_NAME" ]; then
    PAYLOAD="$SCRIPT_DIR/kde"
    ok "using local checkout (${PAYLOAD})"
else
    TARBALL_URL="${ANDROLAUNCH_TARBALL:-https://codeload.github.com/${REPO}/tar.gz/refs/heads/${REF}}"
    echo "      downloading ${TARBALL_URL}"
    curl -fsSL --retry 3 --retry-delay 1 "$TARBALL_URL" -o "$WORK/repo.tar.gz" \
        || die "could not download AndroLaunch (${REF})"
    mkdir -p "$WORK/src"
    tar -xzf "$WORK/repo.tar.gz" -C "$WORK/src" || die "could not extract the archive"
    SRC_ROOT="$(find "$WORK/src" -maxdepth 1 -mindepth 1 -type d | head -n 1)"
    [ -n "$SRC_ROOT" ] && [ -f "$SRC_ROOT/kde/bin/$HELPER_NAME" ] || die "unexpected archive layout"
    PAYLOAD="$SRC_ROOT/kde"
    ok "fetched ${REPO}@${REF}"
fi

# -----------------------------------------------------------------------------
# [2/6] Dependencies
# -----------------------------------------------------------------------------
step "2/6" "Dependencies (adb, scrcpy)"

MISSING_DEPS=()
command -v adb >/dev/null 2>&1 || MISSING_DEPS+=(adb)
command -v scrcpy >/dev/null 2>&1 || MISSING_DEPS+=(scrcpy)

run_privileged() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
        return
    fi
    command -v sudo >/dev/null 2>&1 || return 1
    if [ -e /dev/tty ]; then
        sudo "$@" </dev/tty
    else
        sudo -n "$@"
    fi
}

install_deps() {
    local pm=""
    for candidate in dnf apt-get pacman zypper apk; do
        if command -v "$candidate" >/dev/null 2>&1; then
            pm="$candidate"
            break
        fi
    done
    [ -n "$pm" ] || return 1

    local want_scrcpy=0
    for pkg in "${MISSING_DEPS[@]}"; do
        [ "$pkg" = "scrcpy" ] && want_scrcpy=1
    done

    case "$pm" in
        dnf)
            echo "      sudo dnf install -y android-tools ${want_scrcpy:+scrcpy}"
            run_privileged dnf install -y android-tools ${want_scrcpy:+scrcpy}
            ;;
        apt-get)
            echo "      sudo apt-get install -y adb ${want_scrcpy:+scrcpy}"
            run_privileged apt-get update -qq || true
            run_privileged apt-get install -y adb || run_privileged apt-get install -y android-tools-adb
            [ "$want_scrcpy" -eq 1 ] && run_privileged apt-get install -y scrcpy
            ;;
        pacman)
            echo "      sudo pacman -S --noconfirm android-tools ${want_scrcpy:+scrcpy}"
            run_privileged pacman -Sy --noconfirm android-tools ${want_scrcpy:+scrcpy}
            ;;
        zypper)
            echo "      sudo zypper install -y android-tools ${want_scrcpy:+scrcpy}"
            run_privileged zypper install -y android-tools ${want_scrcpy:+scrcpy}
            ;;
        apk)
            echo "      sudo apk add android-tools ${want_scrcpy:+scrcpy}"
            run_privileged apk add android-tools ${want_scrcpy:+scrcpy}
            ;;
    esac
}

if [ "${#MISSING_DEPS[@]}" -eq 0 ]; then
    ok "adb: $(command -v adb)"
    ok "scrcpy: $(command -v scrcpy)"
elif [ "$SKIP_DEPS" -eq 1 ]; then
    warn "missing: ${MISSING_DEPS[*]} (--skip-deps)"
else
    warn "missing: ${MISSING_DEPS[*]}"
    install_deps || true
    for pkg in adb scrcpy; do
        if command -v "$pkg" >/dev/null 2>&1; then
            ok "$pkg: $(command -v "$pkg")"
        else
            warn "$pkg still missing - install manually (Fedora: sudo dnf install android-tools scrcpy)"
        fi
    done
fi

# -----------------------------------------------------------------------------
# [3/6] Backend CLI
# -----------------------------------------------------------------------------
step "3/6" "Backend CLI"

command -v python3 >/dev/null 2>&1 || die "python3 is required (install python3)"

install -D -m 755 "$PAYLOAD/bin/$HELPER_NAME" "$HELPER"
ok "installed $HELPER"

if ! version_json="$("$HELPER" call version 2>&1)"; then
    fail "the backend does not run:"
    echo "      $version_json"
    exit 1
fi
ok "backend responds ($(printf '%s' "$version_json" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p'))"

# -----------------------------------------------------------------------------
# [4/6] Plasmoid package
# -----------------------------------------------------------------------------
step "4/6" "KDE Plasma widget"

WAS_INSTALLED=0
if "$KPACKAGE" -t Plasma/Applet -l 2>/dev/null | grep -qx "$PLUGIN_ID"; then
    WAS_INSTALLED=1
    "$KPACKAGE" -t Plasma/Applet -u "$PAYLOAD/plasma" >/dev/null || die "could not upgrade the plasmoid"
    ok "upgraded $PLUGIN_ID"
else
    "$KPACKAGE" -t Plasma/Applet -i "$PAYLOAD/plasma" >/dev/null || die "could not install the plasmoid"
    ok "installed $PLUGIN_ID"
fi

# Plasma compiles QML to a disk cache; a stale entry keeps the previous version
# of the widget alive after an upgrade.
rm -rf "$HOME/.cache/plasmashell/qmlcache" 2>/dev/null || true

if [ ! -f "$PLASMOID_DIR/contents/config/main.xml" ]; then
    die "plasmoid config not found at $PLASMOID_DIR (installation incomplete)"
fi

# Point the widget at the backend we just installed (absolute path, works even
# when ~/.local/bin is not in the Plasma session PATH).
awk -v path="$HELPER" '
    /<entry name="helperPath"/ { inentry = 1 }
    inentry && /<default>/ { sub(/<default>.*<\/default>/, "<default>" path "</default>"); inentry = 0 }
    { print }
' "$PLASMOID_DIR/contents/config/main.xml" > "$WORK/main.xml" \
    && cat "$WORK/main.xml" > "$PLASMOID_DIR/contents/config/main.xml"
ok "widget configured to use $HELPER"

# The panel glyph ships inside the plasmoid; the app icon is installed as a themed icon
# so the widget explorer and notifications can use it.
install -D -m 644 "$PAYLOAD/plasma/contents/icons/androlaunch.png" \
    "$HOME/.local/share/icons/hicolor/256x256/apps/androlaunch.png"
ok "app icon installed"

# -----------------------------------------------------------------------------
# [5/6] Panel
# -----------------------------------------------------------------------------
step "5/6" "Panel"

if [ "$ADD_TO_PANEL" -eq 0 ]; then
    warn "skipped (--no-panel); add it from the widget explorer"
elif ! command -v gdbus >/dev/null 2>&1; then
    warn "gdbus not found; add the widget manually"
elif ! gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell \
        --method org.kde.PlasmaShell.evaluateScript 'print("probe")' >/dev/null 2>&1; then
    warn "plasmashell is not reachable; add the widget manually"
else
    panel_script='
    var ps = panels();
    if (ps.length === 0) {
        print("no-panel");
    } else {
        var target = null;
        for (var i = 0; i < ps.length; i++) {
            var types = "";
            var ws = ps[i].widgets();
            for (var j = 0; j < ws.length; j++)
                types += ws[j].type + " ";
            if (types.indexOf("org.kde.plasma.systemtray") >= 0) {
                target = ps[i];
                break;
            }
        }
        if (target === null)
            target = ps[0];

        var ws2 = target.widgets();
        var present = false;
        for (var k = 0; k < ws2.length; k++) {
            if (ws2[k].type === "org.androlaunch.plasma")
                present = true;
        }
        if (present) {
            print("already");
        } else {
            target.addWidget("org.androlaunch.plasma");
            print("added");
        }
    }'

    panel_result="$(gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell \
        --method org.kde.PlasmaShell.evaluateScript "$panel_script" 2>&1 || true)"

    case "$panel_result" in
        *added*)   ok "widget added to the panel" ;;
        *already*) ok "widget already in the panel" ;;
        *no-panel*) warn "no panel found; add the widget manually" ;;
        *)         warn "could not add the widget automatically (${panel_result#*(})" ;;
    esac
fi

# -----------------------------------------------------------------------------
# [6/6] Verify
# -----------------------------------------------------------------------------
step "6/6" "Verify"

problems=0

[ -x "$HELPER" ] || { fail "backend not executable: $HELPER"; problems=1; }
"$HELPER" call version >/dev/null 2>&1 || { fail "backend does not respond"; problems=1; }
"$KPACKAGE" -t Plasma/Applet -l 2>/dev/null | grep -qx "$PLUGIN_ID" || { fail "plasmoid not registered"; problems=1; }
[ -f "$PLASMOID_DIR/contents/icons/androlaunch-menubar.png" ] || { fail "panel glyph missing"; problems=1; }
for file in metadata.json contents/ui/main.qml contents/ui/Backend.qml contents/ui/FullRepresentation.qml \
            contents/icons/androlaunch.png contents/icons/androlaunch-menubar.png; do
    [ -f "$PLASMOID_DIR/$file" ] || { fail "missing $file"; problems=1; }
done

if [ "$problems" -eq 0 ]; then
    ok "all components present"
fi

echo ""
if [ "$problems" -ne 0 ]; then
    echo -e "${RED}${BOLD}Installed with problems${NC}"
    exit 1
fi

echo -e "${GREEN}${BOLD}Installed${NC}"
echo "  backend : $HELPER"
echo "  widget  : $PLASMOID_DIR"
echo ""
if [ "$ADD_TO_PANEL" -eq 0 ]; then
    echo "Add it to a panel: right-click the panel → Add Widgets → search \"AndroLaunch\"."
fi
echo -e "The ${BOLD}AndroLaunch${NC} icon appears in your panel: click it for device controls,"
echo "hover it for the current device and battery level."
if [ "$WAS_INSTALLED" -eq 1 ]; then
    echo ""
    echo -e "${YELLOW}Upgraded an existing install:${NC} restart the shell to pick up the new code:"
    echo "  systemctl --user restart plasma-plasmashell"
fi
echo ""
echo "Enable USB debugging on the phone, then plug it in (or use the Pair tab for Wi-Fi)."
echo ""
echo "CLI:  $HELPER devices"
echo "      $HELPER state"
echo "      $HELPER mirror"
echo ""
