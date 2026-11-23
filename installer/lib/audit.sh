#!/usr/bin/env bash
set -euo pipefail

# Distro detection & anti-bloat package/config audit for Paithosh.

detect_distro() {
    local id="" id_like="" pretty=""
    case "${PAITHOSH_MOCK_OS:-}" in
        arch)
            id="arch"; id_like=""; pretty="Arch Linux (Mock)" ;;
        fedora)
            id="fedora"; id_like=""; pretty="Fedora Linux 45 (Mock)" ;;
        debian)
            id="debian"; id_like=""; pretty="Debian GNU/Linux 13 (Mock)" ;;
        ubuntu)
            id="ubuntu"; id_like="debian"; pretty="Ubuntu 25.04 (Mock)" ;;
        *)
            if [[ -r /etc/os-release ]]; then
                # shellcheck disable=SC1091
                source /etc/os-release
                id="${ID:-unknown}"
                id_like="${ID_LIKE:-}"
                pretty="${PRETTY_NAME:-$id}"
            else
                id="unknown"
                pretty="Unknown Linux"
            fi ;;
    esac

    local family="unknown" pkg_mgr="unknown"
    case " $id $id_like " in
        *" arch "*|*" cachyos "*|*" endeavouros "*|*" manjaro "*)
            family="arch"
            if command -v paru >/dev/null 2>&1; then pkg_mgr="paru"
            elif command -v yay >/dev/null 2>&1; then pkg_mgr="yay"
            else pkg_mgr="pacman"
            fi
            ;;
        *" fedora "*|*" rhel "*|*" centos "*)
            family="fedora"
            if command -v dnf5 >/dev/null 2>&1; then pkg_mgr="dnf5"
            else pkg_mgr="dnf"
            fi
            ;;
        *" debian "*|*" ubuntu "*|*" pop "*|*" linuxmint "*)
            family="debian"
            pkg_mgr="apt"
            ;;
    esac

    printf '%s|%s|%s|%s\n' "$id" "$family" "$pkg_mgr" "$pretty"
}

# Maps specs -> distro packages with multi-mode probes and anti-bloat filtering.
audit_json() {
    IFS='|' read -r distro_id family pkg_mgr pretty_name <<<"$(detect_distro)"

    local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
    local hypr_dir="${config_home}/hypr"
    local hypr_exists=false
    local hypr_files=0
    local hypr_kind="none"
    local hypr_managed=false
    if [[ -d "$hypr_dir" ]]; then
        hypr_files=$(find -L "$hypr_dir" -maxdepth 3 -type f 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$hypr_files" -gt 0 || -L "$hypr_dir" ]]; then
            hypr_exists=true
        fi
        if [[ -f "$hypr_dir/hyprland.lua" || -f "$hypr_dir/config/autostart.lua" ]]; then
            hypr_kind="lua"
        elif [[ -f "$hypr_dir/hyprland.conf" ]]; then
            hypr_kind="conf"
        fi
        if [[ -f "$hypr_dir/.paithosh-manifest" || -f "$hypr_dir/.paithosh-sync-version" ]]; then
            hypr_managed=true
        fi
    elif [[ -L "$hypr_dir" ]]; then
        hypr_exists=true
    fi

    local hypr_lua_supported="unknown"
    if command -v Hyprland >/dev/null 2>&1; then
        local hypr_bin ldd_out
        hypr_bin="$(command -v Hyprland)"
        if ldd_out="$(ldd "$hypr_bin" 2>/dev/null)"; then
            if grep -qi 'liblua' <<<"$ldd_out"; then
                hypr_lua_supported="true"
            else
                hypr_lua_supported="false"
            fi
        fi
    fi

    local paithosh_dir="${config_home}/paithosh"
    local paithosh_exists=false
    [[ -d "$paithosh_dir" ]] && paithosh_exists=true

    local polkit_active=false
    if pgrep -f 'polkit.*agent|polkit-gnome|hyprpolkitagent|lxpolkit|mate-polkit|xfce-polkit' >/dev/null 2>&1; then
        polkit_active=true
    fi

    local -a specs=(
        "core|qs|bin:qs|Quickshell"
        "core|hyprctl|bin:hyprctl|Hyprland"
        "core|qt6-svg|glob:/usr/lib*/qt6/plugins/imageformats/libqsvg.so;/usr/lib/*/qt6/plugins/imageformats/libqsvg.so|Qt6 SVG Plugin (Icons)"
        "core|hyprlock|bin:hyprlock|Hyprlock"
        "core|python3|bin:python3|Python 3"
        "core|git|bin:git|Git"
        "wayland|grim|bin:grim|Grim (Screenshots)"
        "wayland|slurp|bin:slurp|Slurp (Region Select)"
        "wayland|wl-copy|bin:wl-copy|wl-clipboard"
        "wayland|cliphist|bin:cliphist|Cliphist (Clipboard)"
        "wayland|wf-recorder|bin:wf-recorder|wf-recorder (Screen Rec)"
        "wayland|xdph|glob:/usr/share/xdg-desktop-portal/portals/hyprland.portal|XDG Portal Hyprland"
        "wayland|portal-py|py:dbus_gi|File Portal Python Deps"
        "system|wpctl|bin:wpctl|WirePlumber (Audio)"
        "system|pw-play|bin:pw-play|PipeWire Utils (UI Sounds)"
        "system|pactl|bin:pactl|PulseAudio Utils"
        "system|brightnessctl|bin:brightnessctl|Brightnessctl"
        "system|nmcli|bin:nmcli|NetworkManager"
        "system|upower|glob:/usr/share/dbus-1/system-services/org.freedesktop.UPower.service|UPower (Battery)"
        "system|powerprofiles|glob:/usr/share/dbus-1/system-services/net.hadess.PowerProfiles.service;/usr/share/dbus-1/system-services/org.freedesktop.UPower.PowerProfiles.service|Power Profiles Daemon"
        "system|pkexec|bin:pkexec|Polkit (pkexec)"
        "system|polkit-agent|glob:/usr/bin/hyprpolkitagent;/usr/libexec/*polkit*agent*;/usr/libexec/*/*polkit*agent*;/usr/lib/*polkit*agent*;/usr/lib/*/*polkit*agent*;/usr/lib/*/libexec/*polkit*agent*|Polkit Auth Agent"
        "system|xdg-open|bin:xdg-open|XDG Utils"
        "system|unzip|bin:unzip|Unzip (Archives)"
        "system|lspci|bin:lspci|PCI Utils (GPU Info)"
        "system|gsettings-proxy|gsettings:org.gnome.system.proxy|GSettings Proxy Schemas"
        "system|gtk-launch|bin:gtk-launch|GTK Launch (App Binds)"
        "system|wg-quick|bin:wg-quick|WireGuard Tools (VPN)"
        "system|zenity|bin:zenity|Zenity (VPN Import)"
        "system|kdeconnect-cli|bin:kdeconnect-cli|KDE Connect (CLI)"
        "optional|ffmpeg|bin:ffmpeg|FFmpeg (Faststart MP4)"
        "optional|7z|bin:7z|7-Zip (.7z Archives)"
        "optional|playerctl|bin:playerctl|Playerctl (Media Keys)"
        "optional|font-opensans|font:Open Sans|Open Sans Font (UI)"
        "optional|font-jetbrains|font:JetBrains Mono|JetBrains Mono Font"
        "optional|btrfs|bin:btrfs|Btrfs Progs (Snapshots)"
        "optional|checkupdates|bin:checkupdates|Pacman Contrib (Updates)"
        "optional|notify-send|bin:notify-send|Libnotify"
    )

    python3 - "$distro_id" "$family" "$pkg_mgr" "$pretty_name" "$hypr_exists" "$hypr_files" "$hypr_kind" "$hypr_managed" "$hypr_lua_supported" "$paithosh_exists" "$polkit_active" "${specs[@]}" <<'PY'
import glob, json, shutil, subprocess, sys

distro_id, family, pkg_mgr, pretty, hypr_exists, hypr_files, hypr_kind, hypr_managed, hypr_lua_supported, paithosh_exists, polkit_active = sys.argv[1:12]
specs = sys.argv[12:]

def pkg_name(fam, mgr, item_id):
    if item_id == "qs":
        if fam == "arch":
            return "quickshell-git" if mgr in ("paru", "yay") else "quickshell"
        return {"fedora": "quickshell"}.get(fam, "")
    m = {
        "hyprctl": {"arch": "hyprland", "fedora": "hyprland", "debian": "hyprland"},
        "qt6-svg": {"arch": "qt6-svg", "fedora": "qt6-qtsvg", "debian": "qt6-svg-plugins"},
        "hyprlock": {"arch": "hyprlock", "fedora": "hyprlock", "debian": "hyprlock"},
        "python3": {"arch": "python", "fedora": "python3", "debian": "python3"},
        "git": {"arch": "git", "fedora": "git", "debian": "git"},
        "grim": {"arch": "grim", "fedora": "grim", "debian": "grim"},
        "slurp": {"arch": "slurp", "fedora": "slurp", "debian": "slurp"},
        "wl-copy": {"arch": "wl-clipboard", "fedora": "wl-clipboard", "debian": "wl-clipboard"},
        "cliphist": {"arch": "cliphist", "fedora": "cliphist", "debian": "cliphist"},
        "wf-recorder": {"arch": "wf-recorder", "fedora": "wf-recorder", "debian": "wf-recorder"},
        "xdph": {"arch": "xdg-desktop-portal-hyprland", "fedora": "xdg-desktop-portal-hyprland", "debian": "xdg-desktop-portal-hyprland"},
        "portal-py": {"arch": "python-dbus python-gobject", "fedora": "python3-dbus python3-gobject", "debian": "python3-dbus python3-gi"},
        "wpctl": {"arch": "wireplumber", "fedora": "wireplumber", "debian": "wireplumber"},
        "pw-play": {"arch": "pipewire", "fedora": "pipewire-utils", "debian": "pipewire-bin"},
        "pactl": {"arch": "libpulse", "fedora": "pulseaudio-utils", "debian": "pulseaudio-utils"},
        "brightnessctl": {"arch": "brightnessctl", "fedora": "brightnessctl", "debian": "brightnessctl"},
        "nmcli": {"arch": "networkmanager", "fedora": "NetworkManager", "debian": "network-manager"},
        "upower": {"arch": "upower", "fedora": "upower", "debian": "upower"},
        "powerprofiles": {"arch": "power-profiles-daemon", "fedora": "tuned-ppd", "debian": "power-profiles-daemon"},
        "pkexec": {"arch": "polkit", "fedora": "polkit", "debian": "pkexec"},
        "polkit-agent": {"arch": "hyprpolkitagent", "fedora": "hyprpolkitagent", "debian": "polkit-kde-agent-1"},
        "xdg-open": {"arch": "xdg-utils", "fedora": "xdg-utils", "debian": "xdg-utils"},
        "unzip": {"arch": "unzip", "fedora": "unzip", "debian": "unzip"},
        "lspci": {"arch": "pciutils", "fedora": "pciutils", "debian": "pciutils"},
        "gsettings-proxy": {"arch": "gsettings-desktop-schemas", "fedora": "gsettings-desktop-schemas", "debian": "libglib2.0-bin gsettings-desktop-schemas"},
        "gtk-launch": {"arch": "gtk3", "fedora": "gtk3", "debian": "libgtk-3-bin"},
        "wg-quick": {"arch": "wireguard-tools", "fedora": "wireguard-tools", "debian": "wireguard-tools"},
        "zenity": {"arch": "zenity", "fedora": "zenity", "debian": "zenity"},
        "ffmpeg": {"arch": "ffmpeg", "fedora": "ffmpeg-free", "debian": "ffmpeg"},
        "7z": {"arch": "7zip", "fedora": "7zip", "debian": "7zip"},
        "playerctl": {"arch": "playerctl", "fedora": "playerctl", "debian": "playerctl"},
        "font-opensans": {"arch": "ttf-opensans", "fedora": "open-sans-fonts"},
        "font-jetbrains": {"arch": "ttf-jetbrains-mono", "fedora": "jetbrains-mono-fonts-all", "debian": "fonts-jetbrains-mono"},
        "kdeconnect-cli": {"arch": "kdeconnect", "fedora": "kde-connect", "debian": "kdeconnect"},
        "btrfs": {"arch": "btrfs-progs", "fedora": "btrfs-progs", "debian": "btrfs-progs"},
        "checkupdates": {"arch": "pacman-contrib"},
        "notify-send": {"arch": "libnotify", "fedora": "libnotify", "debian": "libnotify-bin"},
    }
    return m.get(item_id, {}).get(fam, "")

_gsettings_schemas = None
def has_gsettings_schema(schema):
    global _gsettings_schemas
    if _gsettings_schemas is None:
        _gsettings_schemas = set()
        if shutil.which("gsettings"):
            try:
                out = subprocess.check_output(["gsettings", "list-schemas"], stderr=subprocess.DEVNULL, text=True, timeout=3)
                _gsettings_schemas = {ln.strip() for ln in out.splitlines() if ln.strip()}
            except Exception:
                pass
    return schema in _gsettings_schemas

_font_families = None
def has_font_family(family_name):
    global _font_families
    if _font_families is None:
        _font_families = set()
        if shutil.which("fc-list"):
            try:
                out = subprocess.check_output(["fc-list", ":", "family"], stderr=subprocess.DEVNULL, text=True, timeout=4)
                for ln in out.splitlines():
                    for part in ln.split(","):
                        p = part.strip().lower()
                        if p:
                            _font_families.add(p)
            except Exception:
                pass
    return family_name.lower() in _font_families

_dbus_gi_ok = None
def has_dbus_gi():
    global _dbus_gi_ok
    if _dbus_gi_ok is None:
        try:
            import dbus  # noqa: F401
            from gi.repository import GLib  # noqa: F401
            _dbus_gi_ok = True
        except Exception:
            _dbus_gi_ok = False
    return _dbus_gi_ok

def check_installed(probe):
    kind, arg = probe.split(":", 1)
    if kind == "bin":
        return shutil.which(arg) is not None
    if kind == "glob":
        return any(glob.glob(pat) for pat in arg.split(";"))
    if kind == "py" and arg == "dbus_gi":
        return has_dbus_gi()
    if kind == "gsettings":
        return has_gsettings_schema(arg)
    if kind == "font":
        return has_font_family(arg)
    return False

packages = []
for s in specs:
    group, item_id, probe, label = s.split("|", 3)
    pkg = pkg_name(family, pkg_mgr, item_id)
    if not pkg:
        continue  # Filtered out for this distro to avoid bloat
    packages.append({
        "id": item_id,
        "group": group,
        "bin": item_id,
        "pkg": pkg,
        "label": label,
        "installed": check_installed(probe),
    })

copr_enabled = False
if family == "fedora":
    for repo_path in glob.glob("/etc/yum.repos.d/*copr*[Hh]yprland*.repo"):
        try:
            with open(repo_path, "r", encoding="utf-8", errors="ignore") as rf:
                if "enabled=1" in rf.read():
                    copr_enabled = True
                    break
        except OSError:
            pass

copr_pkgs = {"quickshell", "hyprland", "hyprlock", "hyprpolkitagent", "xdg-desktop-portal-hyprland"}
copr_needed = (family == "fedora") and (not copr_enabled) and any(
    (not p["installed"]) and (p["pkg"] in copr_pkgs) for p in packages
)
aur_warning = (
    "No AUR helper (paru/yay) detected — quickshell-git requires AUR if 'quickshell' is unavailable in pacman."
    if (family == "arch" and pkg_mgr == "pacman")
    else ""
)
unsupported_note = (
    "Quickshell is not packaged in official Debian/Ubuntu apt repos — install/build Quickshell manually (https://quickshell.org)."
    if family == "debian"
    else ""
)

print(json.dumps({
    "distro": {
        "id": distro_id,
        "family": family,
        "pkgMgr": pkg_mgr,
        "pretty": pretty,
        "coprNeeded": copr_needed,
        "aurWarning": aur_warning,
        "unsupportedNote": unsupported_note,
    },
    "configs": {
        "hyprExists": hypr_exists == "true",
        "hyprFiles": int(hypr_files),
        "hyprConfigKind": hypr_kind,
        "hyprManagedByPaithosh": hypr_managed == "true",
        "hyprLuaSupported": (True if hypr_lua_supported == "true" else (False if hypr_lua_supported == "false" else None)),
        "paithoshExists": paithosh_exists == "true",
        "polkitAgentActive": polkit_active == "true",
    },
    "packages": packages,
}, indent=2))
PY
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if [[ "${1:-}" == "--json" ]]; then
        audit_json
    else
        detect_distro
    fi
fi
