#!/usr/bin/env python3
"""XDG Desktop Portal FileChooser backend for Paithosh Quickshell."""

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

BUS_NAME = "org.freedesktop.impl.portal.desktop.paithosh"
OBJECT_PATH = "/org/freedesktop/portal/desktop"
FILE_CHOOSER_IFACE = "org.freedesktop.impl.portal.FileChooser"
REQUEST_IFACE = "org.freedesktop.impl.portal.Request"
PROPS_IFACE = "org.freedesktop.DBus.Properties"
SHELL_QML = str(Path(__file__).resolve().parent.parent / "shell.qml")
LOG_FILE = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", f"paithosh-file-portal-{os.getuid()}.log")

PORTAL_VERSION = dbus.UInt32(4)


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
    """Implements org.freedesktop.impl.portal.FileChooser using Quickshell PickerView."""

    def __init__(self, bus):
        super().__init__(bus, OBJECT_PATH)
        self._bus = bus
        self._active = {}

    @dbus.service.method(PROPS_IFACE, in_signature="ss", out_signature="v")
    def Get(self, interface_name, property_name):
        if interface_name == FILE_CHOOSER_IFACE and property_name == "version":
            return PORTAL_VERSION
        raise dbus.exceptions.DBusException(
            f"Unknown property {interface_name}.{property_name}",
            name="org.freedesktop.DBus.Error.InvalidArgs",
        )

    @dbus.service.method(PROPS_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface_name):
        if interface_name == FILE_CHOOSER_IFACE:
            return dbus.Dictionary({"version": PORTAL_VERSION}, signature="sv")
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

    def _start_picker(self, mode, handle, app_id, title, options, reply_cb):
        handle_str = str(handle)
        tmp_dir = tempfile.mkdtemp(prefix="paithosh-file-portal.")
        result_fifo = os.path.join(tmp_dir, "result.fifo")
        request_json = os.path.join(tmp_dir, "request.json")
        os.mkfifo(result_fifo)

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
            "resultPath": result_fifo,
        }
        with open(request_json, "w", encoding="utf-8") as f:
            json.dump(payload, f)

        log(f"Start {mode} handle={handle_str} app={app_id} folder={current_folder!r} name={current_name!r}")

        # Open FIFO O_RDWR | O_NONBLOCK so GLib watch never sees EOF before writer opens it
        fifo_fd = os.open(result_fifo, os.O_RDWR | os.O_NONBLOCK)
        state = {
            "finished": False,
            "tmp_dir": tmp_dir,
            "fifo_fd": fifo_fd,
            "watch_id": None,
            "buf": b"",
            "req_obj": None,
            "reply_cb": reply_cb,
        }
        self._active[handle_str] = state

        def finish(response_code: int, uris=None):
            if state["finished"]:
                return
            state["finished"] = True
            self._active.pop(handle_str, None)

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

            results = dbus.Dictionary({}, signature="sv")
            if response_code == 0 and uris:
                results["uris"] = dbus.Array(uris, signature="s")
            log(f"Finish handle={handle_str} code={response_code} uris={uris}")
            state["reply_cb"](dbus.UInt32(response_code), results)

        def on_close():
            subprocess.Popen(
                ["qs", "ipc", "-p", SHELL_QML, "call", "picker", "closeFromPortal"],
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
                    log(f"Invalid JSON from picker: {exc} ({line!r})")
                    finish(2)
                    return False

                if res.get("status") == "ok":
                    raw_paths = res.get("paths") or []
                    uris = []
                    for p in raw_paths:
                        if p:
                            try:
                                uris.append(path_to_uri(p))
                            except Exception as exc:
                                log(f"Bad path {p!r}: {exc}")
                    if uris:
                        finish(0, uris)
                    else:
                        finish(1)
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
            ["qs", "ipc", "-p", SHELL_QML, "call", "picker", "openFromPortal", request_json],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

        def on_ipc_exit(pid, wait_status):
            exit_code = os.waitstatus_to_exitcode(wait_status)
            if exit_code != 0 and not state["finished"]:
                err_out = proc.stderr.read().decode("utf-8", errors="replace").strip()
                log(f"qs ipc failed (code={exit_code}): {err_out}")
                finish(2)

        GLib.child_watch_add(proc.pid, on_ipc_exit)


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
