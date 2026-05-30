#!/usr/bin/env python3
import json
import subprocess
import sys


DIRECTIONS = {"left", "right", "up", "down"}
EDGE_TOLERANCE = 4


def i3_msg(*args):
    return subprocess.check_output(["i3-msg", *args], text=True)


def rect_end(rect):
    return rect["x"] + rect["width"], rect["y"] + rect["height"]


def rect_center(rect):
    return (
        rect["x"] + rect["width"] / 2,
        rect["y"] + rect["height"] / 2,
    )


def overlap(a0, a1, b0, b1):
    return max(0, min(a1, b1) - max(a0, b0))


def collect_tiled_windows(root):
    windows = []
    focused_workspace = None

    def walk(node, workspace=None, floating=False):
        nonlocal focused_workspace

        if node.get("type") == "workspace":
            workspace = node

        if node.get("window") is not None and workspace is not None and not floating:
            window = {
                "id": node["id"],
                "focused": node.get("focused", False),
                "rect": node["rect"],
                "workspace_id": workspace.get("id"),
            }
            windows.append(window)
            if window["focused"]:
                focused_workspace = window["workspace_id"]

        for child in node.get("nodes", []):
            walk(child, workspace, floating)

        for child in node.get("floating_nodes", []):
            walk(child, workspace, True)

    walk(root)
    return windows, focused_workspace


def candidate_score(direction, current, candidate):
    cr = current["rect"]
    rr = candidate["rect"]
    cx, cy = rect_center(cr)
    rx, ry = rect_center(rr)
    cr_right, cr_bottom = rect_end(cr)
    rr_right, rr_bottom = rect_end(rr)

    if direction == "up":
        if rr_bottom > cr["y"] + EDGE_TOLERANCE:
            return None
        overlap_len = overlap(cr["x"], cr_right, rr["x"], rr_right)
        primary = max(0, cr["y"] - rr_bottom)
        cross = abs(cx - rx)
    elif direction == "down":
        if rr["y"] < cr_bottom - EDGE_TOLERANCE:
            return None
        overlap_len = overlap(cr["x"], cr_right, rr["x"], rr_right)
        primary = max(0, rr["y"] - cr_bottom)
        cross = abs(cx - rx)
    elif direction == "left":
        if rr_right > cr["x"] + EDGE_TOLERANCE:
            return None
        overlap_len = overlap(cr["y"], cr_bottom, rr["y"], rr_bottom)
        primary = max(0, cr["x"] - rr_right)
        cross = abs(cy - ry)
    else:
        if rr["x"] < cr_right - EDGE_TOLERANCE:
            return None
        overlap_len = overlap(cr["y"], cr_bottom, rr["y"], rr_bottom)
        primary = max(0, rr["x"] - cr_right)
        cross = abs(cy - ry)

    if overlap_len <= 0:
        return None

    return (primary, -overlap_len, cross)


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in DIRECTIONS:
        print("usage: swap-window.py left|right|up|down", file=sys.stderr)
        return 2

    direction = sys.argv[1]
    tree = json.loads(i3_msg("-t", "get_tree"))
    windows, focused_workspace = collect_tiled_windows(tree)
    current = next((window for window in windows if window["focused"]), None)
    if current is None:
        return 0

    same_workspace = [
        window
        for window in windows
        if window["workspace_id"] == focused_workspace and window["id"] != current["id"]
    ]
    scored = []
    for window in same_workspace:
        score = candidate_score(direction, current, window)
        if score is not None:
            scored.append((score, window))

    if not scored:
        return 0

    target = min(scored, key=lambda item: item[0])[1]
    subprocess.run(["i3-msg", "-q", f"swap container with con_id {target['id']}"], check=False)
    subprocess.run(["i3-msg", "-q", f"[con_id={current['id']}] focus"], check=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
