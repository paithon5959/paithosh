#!/usr/bin/env python3
"""XDG Desktop Portal FileChooser backend for Paithosh Quickshell."""

import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import urllib.parse
from pathlib import Path

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import Gio, GLib

try:
    from gi.repository import GioUnix

    DesktopAppInfo = GioUnix.DesktopAppInfo
except ImportError:
    DesktopAppInfo = Gio.DesktopAppInfo

BUS_NAME = "org.freedesktop.impl.portal.desktop.paithosh"
OBJECT_PATH = "/org/freedesktop/portal/desktop"
FILE_CHOOSER_IFACE = "org.freedesktop.impl.portal.FileChooser"
APP_CHOOSER_IFACE = "org.freedesktop.impl.portal.AppChooser"
REQUEST_IFACE = "org.freedesktop.impl.portal.Request"
PROPS_IFACE = "org.freedesktop.DBus.Properties"
SHELL_QML = str(Path(__file__).resolve().parent.parent / "shell.qml")
LOG_FILE = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", f"paithosh-file-portal-{os.getuid()}.log")

PORTAL_VERSION = dbus.UInt32(4)
APP_CHOOSER_VERSION = dbus.UInt32(2)

_WEB_SCHEMES = {"http", "https", "ipfs", "ipns"}
_GENERIC_TOKENS = {
    "app",
    "application",
    "browser",
    "client",
    "desktop",
    "env",
    "flatpak",
    "handler",
    "launcher",
    "main",
    "open",
    "python",
    "python3",
    "sh",
    "bash",
    "ui",
}
_SAFE_MIME_RE = re.compile(r"^[a-zA-Z0-9.+_-]+/[a-zA-Z0-9.+_-]+$")
_SAFE_ADDR_RE = re.compile(r"^0x[0-9a-fA-F]+$")


def log(msg: str) -> None:
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(f"{msg}\n")
    except OSError:
        pass


def decode_byte_array(val) -> str:
    if not val:
        return ""
    try:
        raw = bytes(int(b) for b in val)
        return raw.rstrip(b"\x00").decode("utf-8", errors="replace")
    except Exception:
        return ""


def path_to_uri(path_str: str) -> str:
    p = Path(path_str).expanduser()
    if not p.is_absolute():
        p = Path.home() / p
    return p.as_uri()


def normalize_desktop_id(raw_id: str) -> str:
    s = str(raw_id or "").strip()
    if s.endswith(".desktop"):
        s = s[:-8]
    return s


def _norm_token(value: str) -> str:
    return re.sub(r"[^a-z0-9._-]", "", str(value or "").strip().lower())


def extract_scheme(uri: str, content_type: str = "") -> str:
    ct = str(content_type or "").strip().lower()
    if ct.startswith("x-scheme-handler/"):
        scheme = ct[len("x-scheme-handler/"):].strip()
        if scheme:
            return scheme
    u = str(uri or "").strip()
    if u:
        try:
            parsed = urllib.parse.urlsplit(u)
            if parsed.scheme:
                return parsed.scheme.lower()
        except Exception:
            pass
    return ""


def extract_exec_bin(exec_line: str) -> str:
    raw = str(exec_line or "").strip()
    if not raw:
        return ""
    try:
        tokens = shlex.split(raw)
    except ValueError:
        tokens = raw.split()

    idx = 0
    while idx < len(tokens):
        tok = tokens[idx]
        if tok in ("env", "/usr/bin/env"):
            idx += 1
            continue
        if "=" in tok and not tok.startswith(("/", "-", "=")):
            idx += 1
            continue
        break
    if idx >= len(tokens):
        return ""

    head = os.path.basename(tokens[idx])
    if head == "flatpak" and idx + 1 < len(tokens) and tokens[idx + 1] == "run":
        app_id = ""
        for arg in tokens[idx + 2:]:
            if arg.startswith("--command="):
                cmd_val = arg.split("=", 1)[1].strip()
                if cmd_val:
                    return os.path.basename(cmd_val)
            elif not arg.startswith("-") and not arg.startswith("@") and not arg.startswith("%"):
                if not app_id:
                    app_id = arg
        return app_id
    return head


def map_app_category(categories: str) -> str:
    cats = str(categories or "").lower()
    if not cats:
        return "System"
    if "game" in cats:
        return "Games"
    if "development" in cats or "ide" in cats:
        return "Dev"
    if "audio" in cats or "video" in cats or "music" in cats:
        return "Media"
    return "System"


def fallback_svg_for_app(category: str, app_id: str) -> str:
    aid = str(app_id or "").lower()
    if "kitty" in aid or "terminal" in aid or "konsole" in aid:
        return "terminal"
    if "dolphin" in aid or "files" in aid or "thunar" in aid:
        return "folder"
    if "brave" in aid or "firefox" in aid or "chrom" in aid:
        return "globe"
    if category == "Media":
        return "music"
    if category == "Dev":
        return "code"
    return "external-link"


def app_info_to_dict(info) -> dict | None:
    if info is None:
        return None
    try:
        raw_id = info.get_id() or ""
    except Exception:
        return None
    app_id = normalize_desktop_id(raw_id)
    if not app_id:
        return None

    name = ""
    try:
        name = info.get_display_name() or info.get_name() or app_id
    except Exception:
        name = app_id

    generic_name = ""
    comment = ""
    icon_name = ""
    wm_class = ""
    exec_line = ""
    categories = ""
    mime_types = set()
    no_display = False

    try:
        if hasattr(info, "get_generic_name"):
            generic_name = info.get_generic_name() or ""
    except Exception:
        pass
    try:
        comment = info.get_description() or ""
    except Exception:
        pass
    try:
        icon = info.get_icon()
        if icon is not None:
            icon_name = icon.to_string() or ""
    except Exception:
        pass
    try:
        if hasattr(info, "get_startup_wm_class"):
            wm_class = info.get_startup_wm_class() or ""
    except Exception:
        pass
    try:
        exec_line = info.get_commandline() or info.get_executable() or ""
    except Exception:
        pass
    try:
        if hasattr(info, "get_categories"):
            categories = info.get_categories() or ""
    except Exception:
        pass
    try:
        if hasattr(info, "get_supported_types"):
            mime_types = {str(m).lower() for m in (info.get_supported_types() or ()) if m}
    except Exception:
        pass
    try:
        if hasattr(info, "get_nodisplay"):
            no_display = bool(info.get_nodisplay())
    except Exception:
        pass

    return {
        "id": app_id,
        "name": str(name),
        "genericName": str(generic_name),
        "comment": str(comment),
        "icon": str(icon_name),
        "wmClass": str(wm_class),
        "execBin": extract_exec_bin(exec_line),
        "category": map_app_category(categories),
        "mimeTypes": mime_types,
        "noDisplay": no_display,
    }


def list_installed_apps() -> list[dict]:
    apps = []
    seen = set()
    try:
        all_infos = Gio.AppInfo.get_all()
    except Exception as exc:
        log(f"Gio.AppInfo.get_all failed: {exc}")
        return apps

    for info in all_infos:
        d = app_info_to_dict(info)
        if not d or d["id"] in seen:
            continue
        seen.add(d["id"])
        apps.append(d)
    return apps


def load_desktop_app(desktop_id: str) -> dict | None:
    norm = normalize_desktop_id(desktop_id)
    if not norm:
        return None
    try:
        info = DesktopAppInfo.new(norm + ".desktop")
        return app_info_to_dict(info)
    except Exception:
        return None


def list_running_windows() -> list[dict]:
    try:
        proc = subprocess.run(
            ["hyprctl", "clients", "-j"],
            capture_output=True,
            text=True,
            timeout=1.5,
            check=False,
        )
        if proc.returncode != 0 or not proc.stdout.strip():
            return []
        raw_clients = json.loads(proc.stdout)
        if not isinstance(raw_clients, list):
            return []
    except Exception:
        return []

    wins = []
    for c in raw_clients:
        if not isinstance(c, dict) or not c.get("mapped", True):
            continue
        addr = str(c.get("address") or "").strip()
        if not addr:
            continue
        ws = c.get("workspace")
        ws_id = int(ws.get("id", 0)) if isinstance(ws, dict) and str(ws.get("id", "")).lstrip("-").isdigit() else 0
        wins.append(
            {
                "address": addr,
                "cls": str(c.get("class") or ""),
                "initialClass": str(c.get("initialClass") or ""),
                "title": str(c.get("title") or ""),
                "workspace": ws_id,
                "pid": int(c.get("pid") or 0),
            }
        )
    return wins


def match_window_to_app(app: dict, windows: list[dict]) -> dict | None:
    if not app or not windows:
        return None
    app_id = normalize_desktop_id(app.get("id", "")).lower()
    last_dns = app_id.rsplit(".", 1)[-1] if "." in app_id else app_id
    wm_class = str(app.get("wmClass") or "").strip().lower()
    exec_bin = str(app.get("execBin") or "").strip().lower()

    wm_clean = _norm_token(wm_class)
    app_id_clean = _norm_token(app_id)
    last_dns_clean = _norm_token(last_dns)
    exec_clean = _norm_token(exec_bin)

    best_win = None
    best_score = 0

    for w in windows:
        cls = str(w.get("cls") or "").strip().lower()
        init_cls = str(w.get("initialClass") or "").strip().lower()
        if not cls and not init_cls:
            continue

        raw_pair = {t for t in (cls, init_cls) if t}
        win_tokens = set(raw_pair)
        for t in raw_pair:
            if "." in t:
                win_tokens.add(t.rsplit(".", 1)[-1])
        win_clean = {_norm_token(t) for t in win_tokens if _norm_token(t)}

        score = 0
        if (wm_class and wm_class in raw_pair) or (app_id and app_id in raw_pair):
            score = 100
        elif (wm_clean and wm_clean in win_clean) or (app_id_clean and app_id_clean in win_clean):
            score = 85
        elif exec_clean and exec_clean not in _GENERIC_TOKENS and exec_clean in win_clean:
            score = 70
        elif last_dns_clean and last_dns_clean not in _GENERIC_TOKENS and last_dns_clean in win_clean:
            score = 60

        if score > best_score:
            best_score = score
            best_win = w

    return best_win


def format_caller_label(caller_app_id: str, installed_apps: list[dict]) -> str:
    norm = normalize_desktop_id(caller_app_id)
    if not norm:
        return "Application"
    for a in installed_apps:
        if normalize_desktop_id(a.get("id", "")).lower() == norm.lower():
            return str(a.get("name") or norm)
    tail = norm.rsplit(".", 1)[-1] if "." in norm else norm
    if tail.lower() in _GENERIC_TOKENS and "." in norm:
        parts = [p for p in norm.split(".") if p and p.lower() not in _GENERIC_TOKENS]
        if parts:
            tail = parts[-1]
    return tail.capitalize() if tail.islower() else tail


def _serialize_app_choice(app: dict, win: dict | None, recommended: bool) -> dict:
    return {
        "id": app["id"],
        "name": app.get("name") or app["id"],
        "genericName": app.get("genericName") or "",
        "comment": app.get("comment") or "",
        "icon": app.get("icon") or "",
        "category": app.get("category") or "System",
        "fallbackSvg": fallback_svg_for_app(app.get("category") or "System", app["id"]),
        "recommended": bool(recommended),
        "running": win is not None,
        "windowAddress": win.get("address", "") if win else "",
        "windowClass": win.get("cls", "") if win else "",
        "windowTitle": win.get("title", "") if win else "",
        "windowWorkspace": int(win.get("workspace", 0)) if win else 0,
    }


def resolve_app_request(
    caller_app_id: str,
    choices: list[str],
    options: dict,
    installed_apps: list[dict],
    running_windows: list[dict],
    app_loader=None,
) -> dict:
    opts = options or {}
    uri = str(opts.get("uri", "") or "")
    content_type = str(opts.get("content_type", "") or "")
    filename = str(opts.get("filename", "") or "")
    last_choice = normalize_desktop_id(str(opts.get("last_choice", "") or ""))
    scheme = extract_scheme(uri, content_type)
    is_web_scheme = scheme in _WEB_SCHEMES
    is_scheme_request = bool(scheme) and scheme != "file"
    caller_norm = normalize_desktop_id(caller_app_id)
    caller_label = format_caller_label(caller_app_id, installed_apps)

    apps_by_id = {}
    apps_by_lower = {}
    win_by_id = {}
    for app in installed_apps:
        aid = normalize_desktop_id(app.get("id", ""))
        if not aid:
            continue
        norm_app = dict(app, id=aid)
        apps_by_id[aid] = norm_app
        apps_by_lower[aid.lower()] = norm_app
        win_by_id[aid] = match_window_to_app(norm_app, running_windows)

    def ensure_app(raw_cid: str) -> dict | None:
        cid = normalize_desktop_id(raw_cid)
        if not cid:
            return None
        found = apps_by_id.get(cid) or apps_by_lower.get(cid.lower())
        if found is None and app_loader is not None:
            loaded = app_loader(cid)
            if loaded:
                aid = normalize_desktop_id(loaded.get("id", cid))
                found = dict(loaded, id=aid)
                apps_by_id[aid] = found
                apps_by_lower[aid.lower()] = found
                win_by_id[aid] = match_window_to_app(found, running_windows)
        return found

    candidates = []
    candidate_ids = set()

    if choices:
        for raw_c in choices:
            app = ensure_app(str(raw_c))
            if not app or app["id"] in candidate_ids:
                continue
            if is_scheme_request and not is_web_scheme and caller_norm and app["id"].lower() == caller_norm.lower():
                continue
            candidates.append(app)
            candidate_ids.add(app["id"])
    elif is_scheme_request:
        scheme_mime = f"x-scheme-handler/{scheme}"
        scheme_base = scheme.split("-", 1)[0] if "-" in scheme else ""
        scheme_tokens = {scheme}
        if len(scheme_base) >= 3 and scheme_base not in _GENERIC_TOKENS:
            scheme_tokens.add(scheme_base)

        for app in apps_by_id.values():
            aid = app["id"]
            if not is_web_scheme and caller_norm and aid.lower() == caller_norm.lower():
                continue
            mimes = {str(m).lower() for m in (app.get("mimeTypes") or ())}
            matched = scheme_mime in mimes
            if not matched and not is_web_scheme and not app.get("noDisplay", False):
                last_dns = aid.lower().rsplit(".", 1)[-1] if "." in aid else aid.lower()
                app_tokens = {aid.lower()}
                if last_dns and last_dns not in _GENERIC_TOKENS:
                    app_tokens.add(last_dns)
                for field in ("wmClass", "execBin", "name"):
                    tok = _norm_token(app.get(field, ""))
                    if tok and tok not in _GENERIC_TOKENS:
                        app_tokens.add(tok)
                if app_tokens & scheme_tokens:
                    matched = True
            if matched and aid not in candidate_ids:
                candidates.append(app)
                candidate_ids.add(aid)

    running_candidates = [a for a in candidates if win_by_id.get(a["id"]) is not None]

    chosen_app = None
    chosen_win = None
    action = "choose"

    if len(running_candidates) == 1:
        chosen_app = running_candidates[0]
        chosen_win = win_by_id[chosen_app["id"]]
        action = "auto_focus"
    elif len(running_candidates) > 1 and last_choice:
        for a in running_candidates:
            if a["id"].lower() == last_choice.lower():
                chosen_app = a
                chosen_win = win_by_id[a["id"]]
                action = "auto_focus"
                break
    elif len(running_candidates) == 0 and len(candidates) == 1:
        chosen_app = candidates[0]
        chosen_win = None
        action = "auto_launch"

    serialized = []
    for a in candidates:
        serialized.append(_serialize_app_choice(a, win_by_id.get(a["id"]), True))
    for a in apps_by_id.values():
        if a["id"] in candidate_ids or a.get("noDisplay", False):
            continue
        serialized.append(_serialize_app_choice(a, win_by_id.get(a["id"]), False))
    serialized.sort(key=lambda item: (not item["recommended"], not item["running"], item["name"].lower()))

    return {
        "action": action,
        "choice": chosen_app["id"] if chosen_app else "",
        "appName": (chosen_app.get("name") or chosen_app["id"]) if chosen_app else "",
        "windowAddress": chosen_win.get("address", "") if chosen_win else "",
        "uri": uri,
        "scheme": scheme,
        "contentType": content_type,
        "filename": filename,
        "callerApp": caller_label,
        "noMatch": len(candidates) == 0,
        "lastChoice": last_choice,
        "apps": serialized,
    }


class PortalRequest(dbus.service.Object):
    """Represents an in-flight org.freedesktop.impl.portal.Request."""

    def __init__(self, bus, object_path: str, on_close):
        super().__init__(bus, object_path)
        self._on_close = on_close

    @dbus.service.method(REQUEST_IFACE, in_signature="", out_signature="")
    def Close(self):
        log(f"Request.Close called on {self._object_path}")
        if self._on_close:
            self._on_close()


class FileChooserPortal(dbus.service.Object):
    """Implements org.freedesktop.impl.portal.FileChooser & AppChooser via Quickshell."""

    def __init__(self, bus):
        super().__init__(bus, OBJECT_PATH)
        self._bus = bus
        self._active = {}
        self._active_app = {}

    @dbus.service.method(PROPS_IFACE, in_signature="ss", out_signature="v")
    def Get(self, interface_name, property_name):
        if interface_name == FILE_CHOOSER_IFACE and property_name == "version":
            return PORTAL_VERSION
        if interface_name == APP_CHOOSER_IFACE and property_name == "version":
            return APP_CHOOSER_VERSION
        raise dbus.exceptions.DBusException(
            f"Unknown property {interface_name}.{property_name}",
            name="org.freedesktop.DBus.Error.InvalidArgs",
        )

    @dbus.service.method(PROPS_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface_name):
        if interface_name == FILE_CHOOSER_IFACE:
            return dbus.Dictionary({"version": PORTAL_VERSION}, signature="sv")
        if interface_name == APP_CHOOSER_IFACE:
            return dbus.Dictionary({"version": APP_CHOOSER_VERSION}, signature="sv")
        return dbus.Dictionary({}, signature="sv")

    @dbus.service.method(
        FILE_CHOOSER_IFACE,
        in_signature="osssa{sv}",
        out_signature="ua{sv}",
        async_callbacks=("reply_cb", "error_cb"),
    )
    def OpenFile(self, handle, app_id, parent_window, title, options, reply_cb, error_cb):
        self._start_picker("upload", handle, app_id, title, options, reply_cb)

    @dbus.service.method(
        FILE_CHOOSER_IFACE,
        in_signature="osssa{sv}",
        out_signature="ua{sv}",
        async_callbacks=("reply_cb", "error_cb"),
    )
    def SaveFile(self, handle, app_id, parent_window, title, options, reply_cb, error_cb):
        self._start_picker("download", handle, app_id, title, options, reply_cb)

    @dbus.service.method(
        FILE_CHOOSER_IFACE,
        in_signature="osssa{sv}",
        out_signature="ua{sv}",
        async_callbacks=("reply_cb", "error_cb"),
    )
    def SaveFiles(self, handle, app_id, parent_window, title, options, reply_cb, error_cb):
        self._start_picker("download", handle, app_id, title, options, reply_cb)

    def _open_fifo_dialog(
        self,
        prefix: str,
        handle_str: str,
        ipc_target: str,
        payload: dict,
        active_map: dict,
        on_ok,
        reply_cb,
        extra_state: dict | None = None,
    ):
        tmp_dir = tempfile.mkdtemp(prefix=prefix)
        result_fifo = os.path.join(tmp_dir, "result.fifo")
        request_json = os.path.join(tmp_dir, "request.json")
        os.mkfifo(result_fifo)

        payload["resultPath"] = result_fifo
        with open(request_json, "w", encoding="utf-8") as f:
            json.dump(payload, f)

        # Open FIFO O_RDWR | O_NONBLOCK so GLib watch never sees EOF before writer opens it
        fifo_fd = os.open(result_fifo, os.O_RDWR | os.O_NONBLOCK)
        state = {
            "finished": False,
            "tmp_dir": tmp_dir,
            "fifo_fd": fifo_fd,
            "watch_id": None,
            "buf": b"",
            "req_obj": None,
        }
        if extra_state:
            state.update(extra_state)
        active_map[handle_str] = state

        def finish(response_code: int, results_dict=None):
            if state["finished"]:
                return
            state["finished"] = True
            active_map.pop(handle_str, None)

            if state["watch_id"] is not None:
                GLib.source_remove(state["watch_id"])
                state["watch_id"] = None
            try:
                os.close(state["fifo_fd"])
            except OSError:
                pass
            if state["req_obj"] is not None:
                try:
                    state["req_obj"].remove_from_connection()
                except Exception:
                    pass
            shutil.rmtree(state["tmp_dir"], ignore_errors=True)

            results = results_dict if results_dict is not None else dbus.Dictionary({}, signature="sv")
            log(f"Finish {ipc_target} handle={handle_str} code={response_code}")
            reply_cb(dbus.UInt32(response_code), results)

        def on_close():
            subprocess.Popen(
                ["qs", "ipc", "-p", SHELL_QML, "call", ipc_target, "closeFromPortal"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            finish(2)

        state["req_obj"] = PortalRequest(self._bus, handle_str, on_close)

        def on_fifo_ready(fd, condition):
            if condition & GLib.IO_IN:
                try:
                    chunk = os.read(fd, 65536)
                except BlockingIOError:
                    return True
                if chunk:
                    state["buf"] += chunk
                    if b"\n" not in state["buf"]:
                        return True
                text = state["buf"].decode("utf-8", errors="replace").strip()
                if not text:
                    finish(1)
                    return False
                line = text.splitlines()[0]
                try:
                    res = json.loads(line)
                except Exception as exc:
                    log(f"Invalid JSON from {ipc_target}: {exc} ({line!r})")
                    finish(2)
                    return False

                if res.get("status") == "ok":
                    on_ok(res, finish)
                else:
                    finish(1)
                return False

            if condition & (GLib.IO_ERR | GLib.IO_HUP):
                finish(2)
                return False
            return True

        state["watch_id"] = GLib.io_add_watch(
            fifo_fd, GLib.IO_IN | GLib.IO_ERR | GLib.IO_HUP, on_fifo_ready
        )

        proc = subprocess.Popen(
            ["qs", "ipc", "-p", SHELL_QML, "call", ipc_target, "openFromPortal", request_json],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

        def on_ipc_exit(pid, wait_status):
            exit_code = os.waitstatus_to_exitcode(wait_status)
            err_out = ""
            try:
                if proc.stderr:
                    err_out = proc.stderr.read().decode("utf-8", errors="replace").strip()
            finally:
                for stream in (proc.stdout, proc.stderr):
                    if stream:
                        try:
                            stream.close()
                        except OSError:
                            pass
            if exit_code != 0 and not state["finished"]:
                log(f"qs ipc {ipc_target} failed (code={exit_code}): {err_out}")
                finish(2)

        GLib.child_watch_add(proc.pid, on_ipc_exit)

    def _start_picker(self, mode, handle, app_id, title, options, reply_cb):
        handle_str = str(handle)
        current_folder = decode_byte_array(options.get("current_folder"))
        current_file = decode_byte_array(options.get("current_file"))
        current_name = str(options.get("current_name", ""))

        if not current_folder and current_file:
            current_folder = os.path.dirname(current_file)
            if not current_name:
                current_name = os.path.basename(current_file)

        parsed_filters = []
        raw_filters = options.get("filters")
        if raw_filters:
            try:
                for filt in raw_filters:
                    if not filt or len(filt) < 2:
                        continue
                    label = str(filt[0])
                    pats = []
                    for item in filt[1]:
                        if item and len(item) >= 2:
                            pats.append({"kind": int(item[0]), "pattern": str(item[1])})
                    parsed_filters.append({"label": label, "patterns": pats})
            except Exception as exc:
                log(f"Failed to parse portal filters: {exc}")

        payload = {
            "mode": mode,
            "title": str(title or ("Save File" if mode == "download" else "Open File")),
            "appId": str(app_id or ""),
            "acceptLabel": str(options.get("accept_label", "")),
            "multiple": bool(options.get("multiple", False)),
            "directory": bool(options.get("directory", False)),
            "currentFolder": current_folder,
            "currentName": current_name,
            "filters": parsed_filters,
        }

        log(f"Start {mode} handle={handle_str} app={app_id} folder={current_folder!r} name={current_name!r}")

        def on_ok(res, finish):
            raw_paths = res.get("paths") or []
            uris = []
            for p in raw_paths:
                if p:
                    try:
                        uris.append(path_to_uri(p))
                    except Exception as exc:
                        log(f"Bad path {p!r}: {exc}")
            if uris:
                results = dbus.Dictionary({"uris": dbus.Array(uris, signature="s")}, signature="sv")
                finish(0, results)
            else:
                finish(1)

        self._open_fifo_dialog(
            "paithosh-file-portal.",
            handle_str,
            "picker",
            payload,
            self._active,
            on_ok,
            reply_cb,
        )

    def _focus_and_notify(self, window_address: str, message: str) -> None:
        proc = subprocess.Popen(
            ["qs", "ipc", "-p", SHELL_QML, "call", "appchooser", "focusAndNotify", window_address, message],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )

        def on_exit(pid, wait_status):
            exit_code = os.waitstatus_to_exitcode(wait_status)
            if proc.stderr:
                try:
                    proc.stderr.close()
                except OSError:
                    pass
            if exit_code != 0 and _SAFE_ADDR_RE.match(window_address):
                subprocess.Popen(
                    ["hyprctl", "dispatch", f"hl.dsp.focus({{ window = 'address:{window_address}' }})"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )

        GLib.child_watch_add(proc.pid, on_exit)

    def _notify_status(self, message: str) -> None:
        if not message:
            return
        subprocess.Popen(
            ["qs", "ipc", "-p", SHELL_QML, "call", "paithosh", "notifyStatus", message],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    @dbus.service.method(
        APP_CHOOSER_IFACE,
        in_signature="ossasa{sv}",
        out_signature="ua{sv}",
        async_callbacks=("reply_cb", "error_cb"),
    )
    def ChooseApplication(self, handle, app_id, parent_window, choices, options, reply_cb, error_cb):
        handle_str = str(handle)
        caller_id = str(app_id or "")
        choice_list = [str(c) for c in (choices or ())]
        opts = {str(k): options[k] for k in (options or {})}
        activation_token = str(opts.get("activation_token", "") or "")

        installed = list_installed_apps()
        windows = list_running_windows()
        resolved = resolve_app_request(
            caller_id,
            choice_list,
            opts,
            installed,
            windows,
            app_loader=load_desktop_app,
        )

        log(
            f"ChooseApplication handle={handle_str} app={caller_id!r} choices={choice_list} "
            f"scheme={resolved['scheme']!r} action={resolved['action']} choice={resolved['choice']!r}"
        )

        def build_results(choice_id: str) -> dbus.Dictionary:
            results = dbus.Dictionary({"choice": dbus.String(choice_id)}, signature="sv")
            if activation_token:
                results["activation_token"] = dbus.String(activation_token)
            return results

        if resolved["action"] == "auto_focus":
            reply_cb(dbus.UInt32(0), build_results(resolved["choice"]))
            self._focus_and_notify(resolved["windowAddress"], f"Switched to {resolved['appName']}")
            return

        if resolved["action"] == "auto_launch":
            reply_cb(dbus.UInt32(0), build_results(resolved["choice"]))
            self._notify_status(f"Opening {resolved['appName']}…")
            return

        payload = {
            "uri": resolved["uri"],
            "scheme": resolved["scheme"],
            "contentType": resolved["contentType"],
            "filename": resolved["filename"],
            "callerApp": resolved["callerApp"],
            "noMatch": resolved["noMatch"],
            "lastChoice": resolved["lastChoice"],
            "apps": resolved["apps"],
        }

        def on_ok(res, finish):
            choice = normalize_desktop_id(str(res.get("choice") or ""))
            if not choice or "/" in choice or ".." in choice:
                finish(1)
                return
            ct = resolved["contentType"]
            if res.get("remember") and ct and _SAFE_MIME_RE.match(ct):
                subprocess.Popen(
                    ["xdg-mime", "default", f"{choice}.desktop", ct],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
            finish(0, build_results(choice))

        self._open_fifo_dialog(
            "paithosh-app-chooser.",
            handle_str,
            "appchooser",
            payload,
            self._active_app,
            on_ok,
            reply_cb,
            extra_state={"caller_id": caller_id, "options": opts},
        )

    @dbus.service.method(APP_CHOOSER_IFACE, in_signature="oas", out_signature="")
    def UpdateChoices(self, handle, choices):
        handle_str = str(handle)
        state = self._active_app.get(handle_str)
        if not state or state.get("finished"):
            return
        choice_list = [str(c) for c in (choices or ())]
        resolved = resolve_app_request(
            state.get("caller_id", ""),
            choice_list,
            state.get("options") or {},
            list_installed_apps(),
            list_running_windows(),
            app_loader=load_desktop_app,
        )
        choices_json = os.path.join(state["tmp_dir"], "choices.json")
        with open(choices_json, "w", encoding="utf-8") as f:
            json.dump({"apps": resolved["apps"], "noMatch": resolved["noMatch"]}, f)
        subprocess.Popen(
            ["qs", "ipc", "-p", SHELL_QML, "call", "appchooser", "updateChoices", choices_json],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    _name = dbus.service.BusName(BUS_NAME, bus)
    _portal = FileChooserPortal(bus)
    log(f"Started {BUS_NAME} at {OBJECT_PATH}")
    loop = GLib.MainLoop()
    loop.run()


if __name__ == "__main__":
    sys.exit(main())
