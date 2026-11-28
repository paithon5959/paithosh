#!/usr/bin/env python3
"""Unit tests for Paithosh XDG Portal AppChooser resolver."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

_SCRIPT_DIR = Path(__file__).resolve().parent
_MOD_PATH = _SCRIPT_DIR / "paithosh-file-portal.py"
_SPEC = importlib.util.spec_from_file_location("paithosh_file_portal", _MOD_PATH)
assert _SPEC and _SPEC.loader
portal = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(portal)


def _sample_apps() -> list[dict]:
    return [
        {
            "id": "com.brave.Browser",
            "name": "Brave",
            "genericName": "Web Browser",
            "comment": "Access the Internet",
            "icon": "com.brave.Browser",
            "wmClass": "brave-browser",
            "execBin": "brave",
            "category": "System",
            "mimeTypes": {
                "x-scheme-handler/http",
                "x-scheme-handler/https",
                "x-scheme-handler/ipfs",
                "x-scheme-handler/ipns",
            },
            "noDisplay": False,
        },
        {
            "id": "antigravity",
            "name": "Antigravity 2.0 Agent",
            "genericName": "Text Editor",
            "comment": "Experience liftoff (v2.0 Agent)",
            "icon": "antigravity",
            "wmClass": "Antigravity",
            "execBin": "antigravity",
            "category": "Dev",
            "mimeTypes": {"application/x-antigravity-workspace"},
            "noDisplay": False,
        },
        {
            "id": "discord",
            "name": "Discord",
            "genericName": "Internet Messenger",
            "comment": "Voice and text chat",
            "icon": "discord",
            "wmClass": "discord",
            "execBin": "discord",
            "category": "System",
            "mimeTypes": {"x-scheme-handler/discord"},
            "noDisplay": False,
        },
        {
            "id": "com.valvesoftware.Steam",
            "name": "Steam",
            "genericName": "Game Launcher",
            "comment": "Manage and play games",
            "icon": "steam",
            "wmClass": "steam",
            "execBin": "steam",
            "category": "Games",
            "mimeTypes": {"x-scheme-handler/steam", "x-scheme-handler/steamlink"},
            "noDisplay": False,
        },
        {
            "id": "jetbrainsd",
            "name": "JetBrains",
            "genericName": "",
            "comment": "",
            "icon": "jetbrains-toolbox",
            "wmClass": "",
            "execBin": "jetbrainsd",
            "category": "Dev",
            "mimeTypes": {"x-scheme-handler/jetbrains"},
            "noDisplay": True,
        },
        {
            "id": "app-a",
            "name": "Alpha Auth",
            "genericName": "Client",
            "comment": "Alpha client",
            "icon": "app-a",
            "wmClass": "alpha-client",
            "execBin": "alpha",
            "category": "Dev",
            "mimeTypes": {"x-scheme-handler/myapp"},
            "noDisplay": False,
        },
        {
            "id": "app-b",
            "name": "Beta Auth",
            "genericName": "Client",
            "comment": "Beta client",
            "icon": "app-b",
            "wmClass": "beta-client",
            "execBin": "beta",
            "category": "Dev",
            "mimeTypes": {"x-scheme-handler/myapp"},
            "noDisplay": False,
        },
    ]


def _sample_windows() -> list[dict]:
    return [
        {
            "address": "0x55cea9786e40",
            "cls": "brave-browser",
            "initialClass": "brave-browser",
            "title": "Sign In - Brave",
            "workspace": 3,
            "pid": 224705,
        },
        {
            "address": "0xabc",
            "cls": "antigravity",
            "initialClass": "antigravity",
            "title": "paithosh — Antigravity",
            "workspace": 1,
            "pid": 210772,
        },
    ]


def test_running_match_auto_focuses() -> None:
    res = portal.resolve_app_request(
        "com.brave.Browser",
        ["antigravity"],
        {
            "uri": "antigravity://callback?code=123",
            "content_type": "x-scheme-handler/antigravity",
        },
        _sample_apps(),
        _sample_windows(),
    )
    assert res["action"] == "auto_focus", res
    assert res["choice"] == "antigravity", res
    assert res["windowAddress"] == "0xabc", res


def test_single_installed_auto_launches() -> None:
    res = portal.resolve_app_request(
        "com.brave.Browser",
        ["discord"],
        {
            "uri": "discord://oauth2/authorize?code=xyz",
            "content_type": "x-scheme-handler/discord",
        },
        _sample_apps(),
        _sample_windows(),
    )
    assert res["action"] == "auto_launch", res
    assert res["choice"] == "discord", res
    assert res["windowAddress"] == "", res


def test_empty_choices_matches_installed_by_scheme() -> None:
    res = portal.resolve_app_request(
        "com.brave.Browser",
        [],
        {"uri": "steam://rungameid/570"},
        _sample_apps(),
        _sample_windows(),
    )
    assert res["action"] == "auto_launch", res
    assert res["choice"] == "com.valvesoftware.Steam", res

    wins = _sample_windows() + [
        {
            "address": "0xsteam",
            "cls": "steam",
            "initialClass": "steam",
            "title": "Steam",
            "workspace": 4,
            "pid": 333333,
        }
    ]
    res_running = portal.resolve_app_request(
        "com.brave.Browser",
        [],
        {"uri": "steam://rungameid/570"},
        _sample_apps(),
        wins,
    )
    assert res_running["action"] == "auto_focus", res_running
    assert res_running["choice"] == "com.valvesoftware.Steam", res_running
    assert res_running["windowAddress"] == "0xsteam", res_running


def test_caller_browser_excluded_for_custom_scheme() -> None:
    for uri in ("browser://test", "brave://test"):
        res = portal.resolve_app_request(
            "com.brave.Browser",
            [],
            {"uri": uri},
            _sample_apps(),
            _sample_windows(),
        )
        assert res["action"] == "choose", res
        assert res["noMatch"] is True, res
        assert res["choice"] == "", res


def test_nodisplay_handler_preserved_in_choices_hidden_in_browse() -> None:
    res = portal.resolve_app_request(
        "com.brave.Browser",
        ["jetbrainsd"],
        {
            "uri": "jetbrains://idea/login?token=abc",
            "content_type": "x-scheme-handler/jetbrains",
        },
        _sample_apps(),
        _sample_windows(),
    )
    assert res["action"] == "auto_launch", res
    assert res["choice"] == "jetbrainsd", res

    res_unknown = portal.resolve_app_request(
        "com.brave.Browser",
        [],
        {"uri": "unknown://oauth?code=1"},
        _sample_apps(),
        _sample_windows(),
    )
    assert res_unknown["action"] == "choose", res_unknown
    assert res_unknown["noMatch"] is True, res_unknown
    ids = [a["id"] for a in res_unknown["apps"]]
    assert "jetbrainsd" not in ids, ids


def test_no_match_returns_choose_with_no_match_flag() -> None:
    res = portal.resolve_app_request(
        "com.brave.Browser",
        [],
        {"uri": "uninstalledapp://auth?token=abc"},
        _sample_apps(),
        _sample_windows(),
    )
    assert res["action"] == "choose", res
    assert res["noMatch"] is True, res
    apps = res["apps"]
    assert len(apps) >= 5, apps
    running_flags = [a["running"] for a in apps]
    seen_false = False
    for flag in running_flags:
        if not flag:
            seen_false = True
        elif seen_false:
            raise AssertionError(f"Running apps must sort before non-running: {running_flags}")


def test_multiple_ambiguous_choices_returns_choose_unless_one_running() -> None:
    apps = _sample_apps()
    base_wins = _sample_windows()

    res_none = portal.resolve_app_request(
        "com.brave.Browser",
        ["app-a", "app-b"],
        {"uri": "myapp://login"},
        apps,
        base_wins,
    )
    assert res_none["action"] == "choose", res_none
    assert res_none["noMatch"] is False, res_none
    assert res_none["apps"][0]["recommended"] is True, res_none["apps"][0]
    assert res_none["apps"][1]["recommended"] is True, res_none["apps"][1]

    wins_b = base_wins + [
        {
            "address": "0xbeta",
            "cls": "beta-client",
            "initialClass": "beta-client",
            "title": "Beta Auth",
            "workspace": 2,
            "pid": 444444,
        }
    ]
    res_one_running = portal.resolve_app_request(
        "com.brave.Browser",
        ["app-a", "app-b"],
        {"uri": "myapp://login"},
        apps,
        wins_b,
    )
    assert res_one_running["action"] == "auto_focus", res_one_running
    assert res_one_running["choice"] == "app-b", res_one_running
    assert res_one_running["windowAddress"] == "0xbeta", res_one_running

    wins_both = wins_b + [
        {
            "address": "0xalpha",
            "cls": "alpha-client",
            "initialClass": "alpha-client",
            "title": "Alpha Auth",
            "workspace": 1,
            "pid": 555555,
        }
    ]
    res_last = portal.resolve_app_request(
        "com.brave.Browser",
        ["app-a", "app-b"],
        {"uri": "myapp://login", "last_choice": "app-a"},
        apps,
        wins_both,
    )
    assert res_last["action"] == "auto_focus", res_last
    assert res_last["choice"] == "app-a", res_last
    assert res_last["windowAddress"] == "0xalpha", res_last

    res_both_ambiguous = portal.resolve_app_request(
        "com.brave.Browser",
        ["app-a", "app-b"],
        {"uri": "myapp://login"},
        apps,
        wins_both,
    )
    assert res_both_ambiguous["action"] == "choose", res_both_ambiguous
    assert res_both_ambiguous["noMatch"] is False, res_both_ambiguous


def main() -> int:
    tests = [
        test_running_match_auto_focuses,
        test_single_installed_auto_launches,
        test_empty_choices_matches_installed_by_scheme,
        test_caller_browser_excluded_for_custom_scheme,
        test_nodisplay_handler_preserved_in_choices_hidden_in_browse,
        test_no_match_returns_choose_with_no_match_flag,
        test_multiple_ambiguous_choices_returns_choose_unless_one_running,
    ]
    for fn in tests:
        fn()
        print(f"PASS: {fn.__name__}")
    print(f"All {len(tests)} app chooser tests passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
