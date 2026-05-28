#!/usr/bin/env python3
import calendar
import datetime as dt
import os
import sys

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, Gtk


DAYS = ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")


def env_int(name, default):
    try:
        value = int(os.environ.get(name, ""))
        return value if value >= 0 else default
    except ValueError:
        return default


def env_ui_int(name, default):
    resolved_name = name.replace("DOTFILES_UI_", "DOTFILES_UI_RESOLVED_", 1)
    return env_int(resolved_name, env_int(name, default))


def add_class(widget, class_name):
    widget.get_style_context().add_class(class_name)


class CalendarPopup(Gtk.Window):
    def __init__(self):
        super().__init__(title="Calendar")
        self.set_wmclass("gsimplecal", "Gsimplecal")
        self.set_decorated(False)
        self.set_keep_above(True)
        self.set_resizable(False)
        self.set_skip_pager_hint(True)
        self.set_skip_taskbar_hint(True)
        self.set_type_hint(Gdk.WindowTypeHint.POPUP_MENU)

        self.today = dt.date.today()
        self.selected = self.today
        self.year = self.today.year
        self.month = self.today.month

        self.connect("destroy", Gtk.main_quit)
        self.connect("key-press-event", self.on_key_press)

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        add_class(root, "polybar-calendar")
        self.add(root)

        root.pack_start(self.build_header(), False, False, 0)

        self.grid = Gtk.Grid()
        self.grid.set_column_homogeneous(True)
        self.grid.set_row_homogeneous(True)
        self.grid.set_column_spacing(0)
        self.grid.set_row_spacing(0)
        root.pack_start(self.grid, False, False, 0)

        self.render()

    def build_header(self):
        header = Gtk.Box(
            orientation=Gtk.Orientation.HORIZONTAL,
            spacing=env_ui_int("DOTFILES_UI_CALENDAR_HEADER_SPACING", 5),
        )
        add_class(header, "polybar-calendar-header")

        prev_month = self.nav_button("<", self.shift_month, -1)
        next_month = self.nav_button(">", self.shift_month, 1)
        prev_year = self.nav_button("<", self.shift_year, -1)
        next_year = self.nav_button(">", self.shift_year, 1)

        self.month_label = Gtk.Label()
        self.month_label.set_xalign(0.0)
        add_class(self.month_label, "polybar-calendar-title")

        self.year_label = Gtk.Label()
        self.year_label.set_xalign(1.0)
        add_class(self.year_label, "polybar-calendar-title")

        header.pack_start(prev_month, False, False, 0)
        header.pack_start(self.month_label, True, True, 0)
        header.pack_start(next_month, False, False, 0)
        header.pack_start(prev_year, False, False, env_ui_int("DOTFILES_UI_CALENDAR_YEAR_NAV_GAP", 8))
        header.pack_start(self.year_label, False, False, 0)
        header.pack_start(next_year, False, False, 0)

        return header

    def nav_button(self, label, callback, delta):
        button = Gtk.Button(label=label)
        add_class(button, "polybar-calendar-nav")
        button.set_relief(Gtk.ReliefStyle.NONE)
        button.set_can_focus(False)
        button.connect("clicked", lambda _button: callback(delta))
        return button

    def render(self):
        for child in self.grid.get_children():
            self.grid.remove(child)

        self.month_label.set_text(calendar.month_name[self.month])
        self.year_label.set_text(str(self.year))

        for column, day_name in enumerate(DAYS):
            label = Gtk.Label(label=day_name)
            add_class(label, "polybar-calendar-weekday")
            self.grid.attach(label, column, 0, 1, 1)

        weeks = calendar.Calendar(firstweekday=calendar.MONDAY).monthdatescalendar(
            self.year,
            self.month,
        )
        while len(weeks) < 6:
            start = weeks[-1][-1] + dt.timedelta(days=1)
            weeks.append([start + dt.timedelta(days=offset) for offset in range(7)])
        weeks = weeks[:6]

        for row, week in enumerate(weeks, start=1):
            for column, day in enumerate(week):
                self.grid.attach(self.day_cell(day), column, row, 1, 1)

        self.grid.show_all()

    def day_cell(self, day):
        event_box = Gtk.EventBox()
        event_box.set_visible_window(True)
        add_class(event_box, "polybar-calendar-day")

        if day.month != self.month:
            add_class(event_box, "other-month")
        if day == self.today:
            add_class(event_box, "today")
        if day == self.selected:
            add_class(event_box, "selected")

        label = Gtk.Label(label=str(day.day))
        event_box.add(label)
        event_box.connect("button-press-event", self.select_day, day)
        return event_box

    def select_day(self, _widget, _event, day):
        self.selected = day
        self.year = day.year
        self.month = day.month
        self.render()
        return True

    def shift_month(self, delta):
        month_index = self.month - 1 + delta
        self.year += month_index // 12
        self.month = month_index % 12 + 1
        self.selected = self.clamp_selected_day()
        self.render()

    def shift_year(self, delta):
        self.year += delta
        self.selected = self.clamp_selected_day()
        self.render()

    def clamp_selected_day(self):
        last_day = calendar.monthrange(self.year, self.month)[1]
        return dt.date(self.year, self.month, min(self.selected.day, last_day))

    def on_key_press(self, _widget, event):
        key = Gdk.keyval_name(event.keyval)
        if key in ("Escape", "q"):
            self.destroy()
            return True
        if key == "Left":
            self.shift_month(-1)
            return True
        if key == "Right":
            self.shift_month(1)
            return True
        if key == "Up":
            self.shift_year(-1)
            return True
        if key == "Down":
            self.shift_year(1)
            return True
        return False


def main():
    window = CalendarPopup()
    window.show_all()
    Gtk.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
