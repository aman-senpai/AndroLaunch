#!/usr/bin/env bash
# =============================================================================
# AndroLaunch for KDE Plasma (Fedora / Linux) installer
#
#   curl -fsSL https://raw.githubusercontent.com/aman-senpai/AndroLaunch/master/install.sh | bash
#
# Installs:
#   1. adb (android-tools), scrcpy and python3, if missing — scrcpy falls back to
#      the static build from the upstream release when the distro packages none
#      (Fedora 44), and that fallback is x86_64 only
#   2. the `androlaunch` backend CLI  -> ~/.local/bin/androlaunch
#   3. the Plasma 6 plasmoid         -> ~/.local/share/plasma/plasmoids/org.androlaunch.plasma
#   4. the widget into a panel (the "menubar"), unless --no-panel is given
#
# Options:
#   --skip-deps        Do not install missing adb / scrcpy / python3 packages
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

# Static scrcpy from the upstream release, used when the distro has no package
# for it (Fedora 44 ships none, and RPM Fusion carries none either).
UPSTREAM_SCRCPY_DIR="$HOME/.local/share/scrcpy"
UPSTREAM_SCRCPY_VERSION=""

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

# Where scrcpy lives: PATH first, then ~/.local/bin — the same order as the
# backend's find_scrcpy() in kde/bin/androlaunch.
scrcpy_path() {
    if command -v scrcpy >/dev/null 2>&1; then
        command -v scrcpy
    elif [ -x "$HOME/.local/bin/scrcpy" ]; then
        echo "$HOME/.local/bin/scrcpy"
    else
        return 1
    fi
}

usage() {
    # `curl … | bash` leaves the script without a readable path, so the text is
    # embedded instead of being re-read from this file's header.
    cat <<'USAGE'
AndroLaunch for KDE Plasma (Fedora / Linux) installer

  curl -fsSL https://raw.githubusercontent.com/aman-senpai/AndroLaunch/master/install.sh | bash

Installs adb (android-tools), scrcpy and python3 if missing, the `androlaunch`
backend CLI into ~/.local/bin, the Plasma 6 plasmoid and the panel widget.

Options:
  --skip-deps        Do not install missing adb / scrcpy / python3 packages
  --no-panel         Do not add the widget to the panel automatically
  --bin-dir PATH     Where to install the backend CLI (default: ~/.local/bin)
  --uninstall        Remove the plasmoid, the backend CLI and its state
  -h, --help         Show this help

Env:
  ANDROLAUNCH_REF    Git ref of the AndroLaunch repo to install (default: master)
USAGE
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
    Darwin) die "this installer is for KDE Plasma on Linux. On macOS use: brew tap aman-senpai/apps && brew install --cask androlaunch" ;;
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
    if [ -d "$UPSTREAM_SCRCPY_DIR" ] && [ -f "$BIN_DIR/scrcpy" ]; then
        rm -rf "$UPSTREAM_SCRCPY_DIR"
        rm -f "$BIN_DIR/scrcpy"
        ok "removed bundled scrcpy ($UPSTREAM_SCRCPY_DIR)"
    fi
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

# Fedora 44 ships no scrcpy package and RPM Fusion carries none either, so the
# static Linux build Genymobile publishes is used instead. Upstream publishes no
# Linux aarch64 build, so that case falls through to the warning.
fetch_upstream_scrcpy() {
    case "$(uname -m)" in
        x86_64|amd64) ;;
        *) return 1 ;;
    esac
    command -v sha256sum >/dev/null 2>&1 || return 1

    local ref ver asset base tmp dir
    ref="$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
        https://github.com/Genymobile/scrcpy/releases/latest 2>/dev/null)" || return 1
    ver="${ref##*/}"
    case "$ver" in
        v[0-9]*) ;;
        *) return 1 ;;
    esac

    asset="scrcpy-linux-x86_64-$ver.tar.gz"
    base="https://github.com/Genymobile/scrcpy/releases/download/$ver"
    tmp="$WORK/scrcpy-upstream"
    mkdir -p "$tmp"

    curl -fsSL --retry 3 --retry-delay 1 "$base/$asset" -o "$tmp/$asset" || return 1
    curl -fsSL --retry 3 --retry-delay 1 "$base/SHA256SUMS.txt" -o "$tmp/SHA256SUMS.txt" || return 1
    ( cd "$tmp" && awk -v a="$asset" '$2 == a' SHA256SUMS.txt | sha256sum -c - >/dev/null 2>&1 ) \
        || return 1

    tar -xzf "$tmp/$asset" -C "$tmp" || return 1
    dir="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d | head -n 1)"
    [ -n "$dir" ] && [ -x "$dir/scrcpy" ] || return 1

    rm -rf "$UPSTREAM_SCRCPY_DIR"
    mkdir -p "$UPSTREAM_SCRCPY_DIR" "$BIN_DIR"
    cp -a "$dir/." "$UPSTREAM_SCRCPY_DIR/"

    # scrcpy finds its scrcpy-server next to the real binary, so ~/.local/bin
    # gets a wrapper rather than a symlink.
    printf '#!/bin/sh\nexec "%s/scrcpy" "$@"\n' "$UPSTREAM_SCRCPY_DIR" > "$BIN_DIR/scrcpy"
    chmod 755 "$BIN_DIR/scrcpy"
    UPSTREAM_SCRCPY_VERSION="$ver"

    # The build links against libm/libudev/libc; if a library is missing it is
    # better to say so than to install a scrcpy that cannot start.
    if ! "$BIN_DIR/scrcpy" --version >/dev/null 2>&1; then
        warn "the downloaded scrcpy does not run (libudev missing?)"
    fi
}

# -----------------------------------------------------------------------------
# [2/6] Dependencies
# -----------------------------------------------------------------------------
step "2/6" "Dependencies (adb, scrcpy, python3)"

MISSING_DEPS=()
command -v adb >/dev/null 2>&1 || MISSING_DEPS+=(adb)
scrcpy_path >/dev/null 2>&1 || MISSING_DEPS+=(scrcpy)
command -v python3 >/dev/null 2>&1 || MISSING_DEPS+=(python3)

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

    # `${var:+word}` also expands for the string "0", so the package list is
    # built explicitly; this also keeps the loop's status 0 for any combination.
    local pkgs=()
    for pkg in "${MISSING_DEPS[@]}"; do
        case "$pkg" in
            adb)
                if [ "$pm" = "apt-get" ]; then pkgs+=(adb); else pkgs+=(android-tools); fi
                ;;
            python3)
                if [ "$pm" = "pacman" ]; then pkgs+=(python); else pkgs+=(python3); fi
                ;;
            *) pkgs+=("$pkg") ;;
        esac
    done

    # One unavailable package must not abort the whole transaction: dnf refuses
    # to install anything when a single argument has no match (Fedora 44 ships
    # no scrcpy package at all, which used to block adb as well), so the
    # packages are installed one by one.
    if [ "$pm" = "apt-get" ]; then
        run_privileged apt-get update -qq || true
    fi

    local failed=()
    local name
    for name in "${pkgs[@]}"; do
        echo "      installing $name ($pm)"
        case "$pm" in
            dnf)     run_privileged dnf install -y "$name" ;;
            apt-get) run_privileged apt-get install -y "$name" ;;
            pacman)  run_privileged pacman -Sy --noconfirm "$name" ;;
            zypper)  run_privileged zypper install -y "$name" ;;
            apk)     run_privileged apk add "$name" ;;
        esac || failed+=("$name")
    done

    # adb ships as `android-tools-adb` on older Debian/Ubuntu releases.
    if [ "$pm" = "apt-get" ] && ! command -v adb >/dev/null 2>&1; then
        run_privileged apt-get install -y android-tools-adb || failed+=(android-tools-adb)
    fi

    if [ "${#failed[@]}" -gt 0 ]; then
        warn "could not install: ${failed[*]}"
    fi
}

if [ "${#MISSING_DEPS[@]}" -eq 0 ]; then
    ok "adb: $(command -v adb)"
    ok "scrcpy: $(scrcpy_path)"
elif [ "$SKIP_DEPS" -eq 1 ]; then
    warn "missing: ${MISSING_DEPS[*]} (--skip-deps)"
else
    warn "missing: ${MISSING_DEPS[*]}"
    install_deps || true

    if ! scrcpy_path >/dev/null 2>&1 && fetch_upstream_scrcpy; then
        ok "scrcpy: $BIN_DIR/scrcpy (upstream static build $UPSTREAM_SCRCPY_VERSION)"
    fi

    for pkg in adb scrcpy python3; do
        case "$pkg" in
            scrcpy) path="$(scrcpy_path 2>/dev/null)" || path="" ;;
            *)      path="$(command -v "$pkg" 2>/dev/null)" || path="" ;;
        esac
        if [ -n "$path" ]; then
            ok "$pkg: $path"
        elif [ "$pkg" = "scrcpy" ]; then
            warn "scrcpy still missing - no distro package, and upstream publishes no Linux $(uname -m) build (see https://github.com/Genymobile/scrcpy/releases)"
        else
            warn "$pkg still missing - install it with your package manager"
        fi
    done
fi

# -----------------------------------------------------------------------------
# [3/6] Backend CLI
# -----------------------------------------------------------------------------
step "3/6" "Backend CLI"

command -v python3 >/dev/null 2>&1 || die "python3 is required (re-run without --skip-deps, or install python3)"

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
echo "Enable USB debugging on the phone, then plug it in (or use the Wireless tab for Wi-Fi)."
echo ""
echo "CLI:  $HELPER devices"
echo "      $HELPER state"
echo "      $HELPER mirror"
echo ""
