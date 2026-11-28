#!/usr/bin/env bash
set -euo pipefail

# Distro detection & anti-bloat package/config audit for Paithosh.

has_active_polkit_agent() {
    local uid
    uid="$(id -u)"
    pgrep -u "$uid" -x 'hyprpolkitagent|lxpolkit|xfce-polkit' >/dev/null 2>&1 && return 0
    pgrep -u "$uid" -f '(^|/)(hyprpolkitagent|polkit-gnome-authentication-agent-1|polkit-kde-authentication-agent-1|polkit-mate-authentication-agent-1|lxpolkit|xfce-polkit)($|[[:space:]])' >/dev/null 2>&1
}

fedora_hypr_copr_enabled() {
    local repo_path
    shopt -s nullglob
    for repo_path in /etc/yum.repos.d/*.repo; do
        if grep -Eiq 'lionheartp(/|:)hyprland' "$repo_path" && grep -qs '^enabled=1' "$repo_path"; then
            shopt -u nullglob
            return 0
        fi
    done
    shopt -u nullglob
    return 1
}

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
        unknown)
            id="unknown"; id_like=""; pretty="Unknown Linux (Mock)" ;;
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
    if has_active_polkit_agent; then
        polkit_active=true
    fi

    local sudo_not_required=false
    if [[ "$EUID" -eq 0 ]] || sudo -n true 2>/dev/null; then
        sudo_not_required=true
    fi

    local copr_enabled_flag=false
    if [[ "$family" == "fedora" ]] && fedora_hypr_copr_enabled; then
        copr_enabled_flag=true
    fi

    local -a specs=(
        "core|qs|bin:qs,quickshell|Quickshell"
        "core|hyprctl|bin:hyprctl|Hyprland"
        "core|hyprcursor|bin:hyprcursor-util|Hyprcursor (Custom Cursors)"
        "core|cursor-render|py:cairo_rsvg|Cursor Renderer (Cairo/Rsvg)"
        "core|pillow|py:pillow|Wallpaper Color Engine (Pillow)"
        "core|qt6-svg|glob:/usr/lib*/qt6/plugins/imageformats/libqsvg.so;/usr/lib/*/qt6/plugins/imageformats/libqsvg.so|Qt6 SVG Plugin (Icons)"
        "core|qt6-multimedia|glob:/usr/lib*/qt6/qml/QtMultimedia/libquickmultimediaplugin.so;/usr/lib/*/qt6/qml/QtMultimedia/libquickmultimediaplugin.so|Qt6 Multimedia (Video Viewer)"
        "core|qt6ct|bin:qt6ct|Qt6CT (Qt6 Theme Sync)"
        "core|qt5ct|bin:qt5ct|Qt5CT (Qt5 Theme Sync)"
        "core|adw-gtk3|glob:/usr/share/themes/adw-gtk3-dark/gtk-3.0/gtk.css;/usr/local/share/themes/adw-gtk3-dark/gtk-3.0/gtk.css|adw-gtk3 (GTK3 Theme Sync)"
        "core|xdg-portal-gtk|glob:/usr/share/xdg-desktop-portal/portals/gtk.portal|XDG Portal GTK (Theme Sync)"
        "core|gsettings-proxy|gsettings:org.gnome.desktop.interface|GSettings Schemas (GTK Sync & Proxy)"
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
        "system|polkit-agent|exec:/usr/bin/hyprpolkitagent;/usr/libexec/hyprpolkitagent;/usr/lib/hyprpolkitagent;/usr/libexec/kf6/polkit-kde-authentication-agent-1;/usr/libexec/polkit-kde-authentication-agent-1;/usr/lib/*/libexec/polkit-kde-authentication-agent-1;/usr/lib/polkit-kde-authentication-agent-1;/usr/libexec/polkit-gnome-authentication-agent-1;/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1;/usr/bin/lxpolkit;/usr/libexec/polkit-mate-authentication-agent-1;/usr/libexec/xfce-polkit|Polkit Auth Agent"
        "system|xdg-open|bin:xdg-open|XDG Utils"
        "system|unzip|bin:unzip|Unzip (Archives)"
        "system|lspci|bin:lspci|PCI Utils (GPU Info)"
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

    python3 - "$distro_id" "$family" "$pkg_mgr" "$pretty_name" "$hypr_exists" "$hypr_files" "$hypr_kind" "$hypr_managed" "$hypr_lua_supported" "$paithosh_exists" "$polkit_active" "$sudo_not_required" "$copr_enabled_flag" "${specs[@]}" <<'PY'
import glob, json, os, shutil, subprocess, sys

distro_id, family, pkg_mgr, pretty, hypr_exists, hypr_files, hypr_kind, hypr_managed, hypr_lua_supported, paithosh_exists, polkit_active, sudo_not_required, copr_enabled_flag = sys.argv[1:14]
specs = sys.argv[14:]
is_mock = bool(os.environ.get("PAITHOSH_MOCK_OS"))

def has_pacman_pkg(name):
    if not shutil.which("pacman"):
        return False
    return subprocess.run(["pacman", "-Si", name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0

def fedora_uses_rpmfusion_ffmpeg():
    if shutil.which("rpm"):
        if subprocess.run(["rpm", "-q", "ffmpeg-libs"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
            return True
    for rp in glob.glob("/etc/yum.repos.d/*rpmfusion-free*.repo"):
        try:
            with open(rp, "r", encoding="utf-8", errors="ignore") as rf:
                if "enabled=1" in rf.read():
                    return True
        except OSError:
            pass
    return False

def pkg_name(fam, mgr, item_id):
    if item_id == "qs":
        if fam == "arch":
            if not is_mock and has_pacman_pkg("quickshell"):
                return "quickshell"
            return "quickshell-git" if mgr in ("paru", "yay") else "quickshell"
        return {"fedora": "quickshell"}.get(fam, "")
    if item_id == "ffmpeg" and fam == "fedora":
        return "ffmpeg" if (not is_mock and fedora_uses_rpmfusion_ffmpeg()) else "ffmpeg-free"
    m = {
        "hyprctl": {"arch": "hyprland", "fedora": "hyprland", "debian": "hyprland"},
        "hyprcursor": {"arch": "hyprcursor", "fedora": "hyprcursor", "debian": "hyprcursor-util"},
        "cursor-render": {"arch": "python-cairo librsvg python-gobject", "fedora": "python3-cairo librsvg2 python3-gobject", "debian": "python3-cairo gir1.2-rsvg-2.0 python3-gi"},
        "pillow": {"arch": "python-pillow", "fedora": "python3-pillow", "debian": "python3-pillow"},
        "qt6-svg": {"arch": "qt6-svg", "fedora": "qt6-qtsvg", "debian": "qt6-svg-plugins"},
        "qt6-multimedia": {"arch": "qt6-multimedia qt6-multimedia-ffmpeg", "fedora": "qt6-qtmultimedia", "debian": "qml6-module-qtmultimedia"},
        "qt6ct": {"arch": "qt6ct", "fedora": "qt6ct", "debian": "qt6ct"},
        "qt5ct": {"arch": "qt5ct", "fedora": "qt5ct", "debian": "qt5ct"},
        "adw-gtk3": {"arch": "adw-gtk-theme", "fedora": "adw-gtk3-theme"},
        "xdg-portal-gtk": {"arch": "xdg-desktop-portal-gtk", "fedora": "xdg-desktop-portal-gtk", "debian": "xdg-desktop-portal-gtk"},
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

_cairo_rsvg_ok = None
def has_cairo_rsvg():
    global _cairo_rsvg_ok
    if _cairo_rsvg_ok is None:
        try:
            import cairo  # noqa: F401
            import gi
            gi.require_version("Rsvg", "2.0")
            from gi.repository import Rsvg  # noqa: F401
            _cairo_rsvg_ok = True
        except Exception:
            _cairo_rsvg_ok = False
    return _cairo_rsvg_ok

_pillow_ok = None
def has_pillow():
    global _pillow_ok
    if _pillow_ok is None:
        try:
            from PIL import Image  # noqa: F401
            _pillow_ok = True
        except Exception:
            _pillow_ok = False
    return _pillow_ok

def check_installed(probe):
    kind, arg = probe.split(":", 1)
    if kind == "bin":
        return any(shutil.which(b) is not None for b in arg.split(","))
    if kind == "glob":
        return any(glob.glob(pat) for pat in arg.split(";"))
    if kind == "exec":
        for pat in arg.split(";"):
            for p in glob.glob(pat):
                bn = os.path.basename(p)
                if "polkit-agent-helper" in bn or ".so" in bn:
                    continue
                if os.path.isfile(p) and os.access(p, os.X_OK):
                    return True
        return False
    if kind == "py" and arg == "dbus_gi":
        return has_dbus_gi()
    if kind == "py" and arg == "cairo_rsvg":
        return has_cairo_rsvg()
    if kind == "py" and arg == "pillow":
        return has_pillow()
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
        "required": (group == "core"),
        "bin": item_id,
        "pkg": pkg,
        "label": label,
        "installed": check_installed(probe),
    })

copr_enabled = (copr_enabled_flag == "true")
copr_pkgs = {"quickshell", "hyprland", "hyprcursor", "hyprlock", "hyprpolkitagent", "xdg-desktop-portal-hyprland"}
copr_needed = (family == "fedora") and (not copr_enabled) and any(
    (not p["installed"]) and (p["pkg"] in copr_pkgs) for p in packages
)
aur_warning = (
    "No AUR helper (paru/yay) detected — quickshell-git requires AUR if 'quickshell' is unavailable in pacman."
    if (family == "arch" and pkg_mgr == "pacman")
    else ""
)
if family == "debian":
    unsupported_note = "Quickshell is not packaged in official Debian/Ubuntu apt repos — install/build Quickshell manually (https://quickshell.org)."
elif family == "unknown":
    unsupported_note = "Unsupported distro/package manager — automatic package installation is unavailable; install dependencies manually."
else:
    unsupported_note = ""

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
        "sudoNotRequired": sudo_not_required == "true",
    },
    "packages": packages,
}, indent=2))
PY
}

verify_installed_packages() {
    local -a tokens=()
    local raw_arg tok
    set -f
    for raw_arg in "$@"; do
        IFS=', ' read -r -a _parts <<< "$raw_arg"
        for tok in ${_parts[@]+"${_parts[@]}"}; do
            [[ -n "$tok" ]] && tokens+=("$tok")
        done
    done
    set +f

    if [[ ${#tokens[@]} -eq 0 ]]; then
        return 0
    fi

    for tok in "${tokens[@]}"; do
        if [[ "$tok" == *font* || "$tok" == ttf-* ]] && command -v fc-cache >/dev/null 2>&1; then
            fc-cache -f >/dev/null 2>&1 || true
            break
        fi
    done

    local json_out
    json_out="$(audit_json)"

    python3 - "$json_out" "${tokens[@]}" <<'PY'
import json, shutil, subprocess, sys

data = json.loads(sys.argv[1])
tokens = sys.argv[2:]
mgr = (data.get("distro") or {}).get("pkgMgr", "unknown")
specs = data.get("packages") or []

tok_to_specs = {}
for p in specs:
    for t in str(p.get("pkg") or "").split():
        tok_to_specs.setdefault(t, []).append(p)

def db_has_pkg(token):
    if mgr in ("dnf", "dnf5") and shutil.which("rpm"):
        return subprocess.run(["rpm", "-q", "--whatprovides", token], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
    if mgr in ("pacman", "paru", "yay") and shutil.which("pacman"):
        return subprocess.run(["pacman", "-T", token], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
    if mgr == "apt" and shutil.which("dpkg-query"):
        res = subprocess.run(["dpkg-query", "-W", "-f=${Status}\n", token], capture_output=True, text=True)
        return res.returncode == 0 and "install ok installed" in (res.stdout or "")
    return None

failures = []
for tok in tokens:
    matched = tok_to_specs.get(tok, [])
    failed_probes = [p["label"] for p in matched if not p.get("installed")]
    db_ok = db_has_pkg(tok)

    if failed_probes:
        reasons = ", ".join(failed_probes)
        if db_ok is False:
            failures.append(f"{tok} (missing in {mgr} DB & probe failed: {reasons})")
        else:
            failures.append(f"{tok} (probe failed: {reasons})")
    elif db_ok is False:
        # On Debian/Ubuntu, allow virtual packages if a matching spec probe explicitly passed
        if not (mgr == "apt" and matched):
            failures.append(f"{tok} (not installed in {mgr} DB)")

if failures:
    print(f"[paithosh] Package verification failed ({len(failures)}/{len(tokens)}): " + "; ".join(failures), file=sys.stderr)
    sys.exit(1)

print(f"[paithosh] Verified {len(tokens)} installed package(s).")
PY
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if [[ "${1:-}" == "--json" ]]; then
        audit_json
    elif [[ "${1:-}" == "--verify-pkgs" ]]; then
        shift
        verify_installed_packages "$@"
    else
        detect_distro
    fi
fi
