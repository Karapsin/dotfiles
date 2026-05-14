#!/usr/bin/env python3

import sys

import gi

gi.require_version("Atspi", "2.0")
from gi.repository import Atspi


FOCUSED = Atspi.StateType.FOCUSED
ACTIVE = Atspi.StateType.ACTIVE
SHOWING = Atspi.StateType.SHOWING


def has_state(accessible, state):
    try:
        return accessible.get_state_set().contains(state)
    except Exception:
        return False


def children(accessible):
    try:
        count = accessible.get_child_count()
    except Exception:
        return

    for index in range(count):
        try:
            child = accessible.get_child_at_index(index)
        except Exception:
            continue
        if child is not None:
            yield child


def walk(accessible):
    stack = [accessible]
    while stack:
        current = stack.pop()
        yield current
        stack.extend(reversed(list(children(current))))


def subtree_has_focus(accessible):
    return any(has_state(node, FOCUSED) for node in walk(accessible))


def active_nemo_frame():
    desktop = Atspi.get_desktop(0)
    for app in children(desktop):
        try:
            app_name = app.get_name() or ""
        except Exception:
            continue

        if app_name.lower() != "nemo":
            continue

        showing_frames = []
        for node in walk(app):
            try:
                is_frame = node.get_role_name() == "frame"
            except Exception:
                continue
            if not is_frame or not has_state(node, SHOWING):
                continue
            if has_state(node, ACTIVE):
                return node
            showing_frames.append(node)

        if showing_frames:
            return showing_frames[0]

    return None


def nemo_file_views(frame):
    views = []
    for node in walk(frame):
        try:
            role = node.get_role_name()
            name = node.get_name() or ""
        except Exception:
            continue

        if role == "tree table" and name == "List View":
            views.append(node)

    return views


def main():
    frame = active_nemo_frame()
    if frame is None:
        return 1

    views = nemo_file_views(frame)
    if len(views) < 2:
        return 1

    focused_index = None
    for index, view in enumerate(views):
        if subtree_has_focus(view):
            focused_index = index
            break

    target_index = 0 if focused_index is None else (focused_index + 1) % len(views)
    return 0 if views[target_index].grab_focus() else 1


if __name__ == "__main__":
    sys.exit(main())
