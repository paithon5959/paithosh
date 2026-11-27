#!/usr/bin/env python3
"""End-to-end tests for Discord RPC yielding in discord-rpc.py."""

from __future__ import annotations

import importlib.util
import json
import os
import select
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time

SCRIPT_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "discord-rpc.py")

spec = importlib.util.spec_from_file_location("discord_rpc", SCRIPT_PATH)
assert spec and spec.loader
discord_rpc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(discord_rpc)


class MockDiscordServer:
    """Minimal Discord IPC Unix socket server that handles HANDSHAKE and SET_ACTIVITY."""

    def __init__(self, path: str) -> None:
        self.path = path
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.bind(path)
        self.sock.listen(8)
        self.sock.settimeout(0.2)
        self._stop = threading.Event()
        self._conns: list[socket.socket] = []
        self._lock = threading.Lock()
        self._thread = threading.Thread(target=self._serve, daemon=True)
        self._thread.start()

    def _serve(self) -> None:
        while not self._stop.is_set():
            try:
                conn, _ = self.sock.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            with self._lock:
                self._conns.append(conn)
            threading.Thread(target=self._handle, args=(conn,), daemon=True).start()

    def _handle(self, conn: socket.socket) -> None:
        conn.settimeout(0.5)
        try:
            while not self._stop.is_set():
                try:
                    hdr = conn.recv(8)
                except socket.timeout:
                    continue
                if not hdr or len(hdr) < 8:
                    break
                op, length = struct.unpack("<II", hdr)
                body = b""
                while len(body) < length:
                    chunk = conn.recv(length - len(body))
                    if not chunk:
                        break
                    body += chunk
                if op == discord_rpc.OP_CLOSE:
                    break
                reply = json.dumps({"cmd": "DISPATCH", "evt": "READY"}).encode("utf-8")
                conn.sendall(struct.pack("<II", discord_rpc.OP_FRAME, len(reply)) + reply)
        except OSError:
            pass
        finally:
            try:
                conn.close()
            except OSError:
                pass

    def close(self) -> None:
        self._stop.set()
        try:
            self.sock.close()
        except OSError:
            pass
        with self._lock:
            for c in self._conns:
                try:
                    c.close()
                except OSError:
                    pass
        if os.path.exists(self.path):
            os.unlink(self.path)


def wait_for_event(proc: subprocess.Popen, predicate, timeout: float = 5.0) -> dict:
    deadline = time.monotonic() + timeout
    assert proc.stdout is not None
    while time.monotonic() < deadline:
        rem = max(0.05, deadline - time.monotonic())
        ready, _, _ = select.select([proc.stdout], [], [], rem)
        if not ready:
            continue
        line = proc.stdout.readline()
        if not line:
            break
        ev = json.loads(line)
        if predicate(ev):
            return ev
    raise AssertionError("Timed out waiting for matching daemon event")


def test_count_ipc_connections() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        sock_path = os.path.join(tmp, "discord-ipc-0")
        srv = MockDiscordServer(sock_path)
        try:
            assert discord_rpc.count_ipc_connections([sock_path]) == 0
            c1 = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            c1.connect(sock_path)
            time.sleep(0.05)
            assert discord_rpc.count_ipc_connections([sock_path]) == 1

            c2 = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            c2.connect(sock_path)
            time.sleep(0.05)
            assert discord_rpc.count_ipc_connections([sock_path]) == 2

            c2.close()
            time.sleep(0.05)
            assert discord_rpc.count_ipc_connections([sock_path]) == 1

            c1.close()
            time.sleep(0.05)
            assert discord_rpc.count_ipc_connections([sock_path]) == 0
        finally:
            srv.close()


def test_daemon_yield_lifecycle() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        sock_path = os.path.join(tmp, "discord-ipc-0")
        cfg_path = os.path.join(tmp, "discord-rpc.json")
        srv = MockDiscordServer(sock_path)
        env = dict(os.environ, PAITHOSH_DISCORD_IPC_DIR=tmp)
        proc = subprocess.Popen(
            [sys.executable, SCRIPT_PATH, "--config-file", cfg_path, "--poll-interval", "0.2"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
        )
        ext: socket.socket | None = None
        try:
            assert proc.stdin is not None
            # 1. Initial config defaults to yieldToOtherRpc=True and connects
            cfg_ev = wait_for_event(proc, lambda e: e.get("type") == "config")
            assert cfg_ev["config"]["yieldToOtherRpc"] is True
            wait_for_event(proc, lambda e: e.get("connected") is True and e.get("yielding") is False)

            # 2. External RPC connects -> shell yields automatically
            ext = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            ext.connect(sock_path)
            wait_for_event(
                proc,
                lambda e: e.get("discord_running") is True
                and e.get("connected") is False
                and e.get("yielding") is True,
            )

            # 3. External RPC disconnects -> shell resumes automatically
            ext.close()
            ext = None
            wait_for_event(proc, lambda e: e.get("connected") is True and e.get("yielding") is False)

            # 4. Disable yieldToOtherRpc -> stays connected when external RPC connects
            proc.stdin.write(json.dumps({"cmd": "config", "config": {"yieldToOtherRpc": False}}) + "\n")
            proc.stdin.flush()
            wait_for_event(proc, lambda e: e.get("connected") is True and e.get("yielding") is False)

            ext = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            ext.connect(sock_path)
            time.sleep(0.8)
            assert proc.poll() is None
            with open(cfg_path, "r", encoding="utf-8") as f:
                saved = json.load(f)
            assert saved["yieldToOtherRpc"] is False

            # 5. Re-enable yieldToOtherRpc while external RPC is active -> yields immediately
            proc.stdin.write(json.dumps({"cmd": "config", "config": {"yieldToOtherRpc": True}}) + "\n")
            proc.stdin.flush()
            wait_for_event(
                proc,
                lambda e: e.get("discord_running") is True
                and e.get("connected") is False
                and e.get("yielding") is True,
            )
        finally:
            if ext is not None:
                ext.close()
            proc.terminate()
            proc.wait(timeout=3)
            srv.close()


if __name__ == "__main__":
    test_count_ipc_connections()
    test_daemon_yield_lifecycle()
    print("OK: all Discord RPC yield tests passed")
