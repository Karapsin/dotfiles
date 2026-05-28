#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#ifdef HAVE_XINPUT2
#include <X11/extensions/XInput2.h>
#endif
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/select.h>
#include <unistd.h>

enum target_match_mode {
  MATCH_TARGET_NAME,
  MATCH_TARGET_CLASS,
};

enum click_mode {
  CLICK_MODE_GRAB,
  CLICK_MODE_RAW,
};

struct tray_click_config {
  enum target_match_mode target_mode;
  enum click_mode click_mode;
  const char *target_value;
  const char *app_class;
  const char *open_command;
  const char *close_command;
};

static int last_x_error_code = 0;

static int record_x_error(Display *display, XErrorEvent *event) {
  (void)display;
  last_x_error_code = event->error_code;
  return 0;
}

static void clear_x_error(void) {
  last_x_error_code = 0;
}

static int sync_x_error(Display *display) {
  int error_code;

  XSync(display, False);
  error_code = last_x_error_code;
  last_x_error_code = 0;

  return error_code;
}

static void drain_x_errors(Display *display) {
  clear_x_error();
  XSync(display, False);
  clear_x_error();
}

static void usage(const char *program) {
  fprintf(
    stderr,
    "Usage: %s [--click-mode grab|raw] (--target-name NAME|--target-class CLASS) --app-class CLASS --open-command COMMAND --close-command COMMAND\n",
    program
  );
}

static int set_option(const char **field, const char *value) {
  if (*field != NULL || value == NULL || value[0] == '\0') {
    return 0;
  }

  *field = value;
  return 1;
}

static int parse_args(int argc, char **argv, struct tray_click_config *config) {
  int target_seen = 0;

  memset(config, 0, sizeof(*config));
  config->click_mode = CLICK_MODE_GRAB;

  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--target-name") == 0 || strcmp(argv[i], "--target-class") == 0) {
      if (target_seen || i + 1 >= argc || argv[i + 1][0] == '\0') {
        return 0;
      }

      config->target_mode =
        strcmp(argv[i], "--target-name") == 0 ? MATCH_TARGET_NAME : MATCH_TARGET_CLASS;
      config->target_value = argv[++i];
      target_seen = 1;
    } else if (strcmp(argv[i], "--click-mode") == 0) {
      if (i + 1 >= argc) {
        return 0;
      }

      i++;
      if (strcmp(argv[i], "grab") == 0) {
        config->click_mode = CLICK_MODE_GRAB;
      } else if (strcmp(argv[i], "raw") == 0) {
        config->click_mode = CLICK_MODE_RAW;
      } else {
        return 0;
      }
    } else if (strcmp(argv[i], "--app-class") == 0) {
      if (i + 1 >= argc || !set_option(&config->app_class, argv[++i])) {
        return 0;
      }
    } else if (strcmp(argv[i], "--open-command") == 0) {
      if (i + 1 >= argc || !set_option(&config->open_command, argv[++i])) {
        return 0;
      }
    } else if (strcmp(argv[i], "--close-command") == 0) {
      if (i + 1 >= argc || !set_option(&config->close_command, argv[++i])) {
        return 0;
      }
    } else {
      return 0;
    }
  }

  return target_seen &&
         config->app_class != NULL &&
         config->open_command != NULL &&
         config->close_command != NULL;
}

static int window_has_name(Display *display, Window window, const char *target_name) {
  char *name = NULL;
  int matches = 0;

  if (XFetchName(display, window, &name) > 0 && name != NULL) {
    matches = strcmp(name, target_name) == 0;
    XFree(name);
  }

  return matches;
}

static int class_hint_matches(const char *actual, const char *expected) {
  return actual != NULL && strcasecmp(actual, expected) == 0;
}

static int window_has_class(Display *display, Window window, const char *target_class) {
  XClassHint hint;
  int matches = 0;

  if (XGetClassHint(display, window, &hint) == 0) {
    return 0;
  }

  matches =
    class_hint_matches(hint.res_name, target_class) ||
    class_hint_matches(hint.res_class, target_class);

  if (hint.res_name != NULL) {
    XFree(hint.res_name);
  }
  if (hint.res_class != NULL) {
    XFree(hint.res_class);
  }

  return matches;
}

static int window_has_atom_value(
  Display *display,
  Window window,
  const char *property_name,
  const char *value_name
) {
  Atom property = XInternAtom(display, property_name, True);
  Atom expected_value = XInternAtom(display, value_name, True);
  Atom actual_type = None;
  int actual_format = 0;
  unsigned long item_count = 0;
  unsigned long bytes_after = 0;
  unsigned char *data = NULL;
  int matches = 0;

  if (property == None || expected_value == None) {
    return 0;
  }

  if (XGetWindowProperty(
        display,
        window,
        property,
        0,
        32,
        False,
        XA_ATOM,
        &actual_type,
        &actual_format,
        &item_count,
        &bytes_after,
        &data
      ) != Success) {
    return 0;
  }

  if (actual_type == XA_ATOM && actual_format == 32 && data != NULL) {
    Atom *atoms = (Atom *)data;
    for (unsigned long i = 0; i < item_count; i++) {
      if (atoms[i] == expected_value) {
        matches = 1;
        break;
      }
    }
  }

  if (data != NULL) {
    XFree(data);
  }

  return matches;
}

static int window_is_popup_menu(Display *display, Window window) {
  return window_has_atom_value(
    display,
    window,
    "_NET_WM_WINDOW_TYPE",
    "_NET_WM_WINDOW_TYPE_POPUP_MENU"
  );
}

static int window_matches_target(
  Display *display,
  Window window,
  const struct tray_click_config *config
) {
  if (window_is_popup_menu(display, window)) {
    return 0;
  }

  if (config->target_mode == MATCH_TARGET_NAME) {
    return window_has_name(display, window, config->target_value);
  }

  return window_has_class(display, window, config->target_value);
}

static Window find_matching_window(
  Display *display,
  Window root,
  const struct tray_click_config *config
) {
  Window root_return = 0;
  Window parent_return = 0;
  Window *children = NULL;
  unsigned int child_count = 0;
  Window found = 0;

  if (window_matches_target(display, root, config)) {
    return root;
  }

  if (!XQueryTree(display, root, &root_return, &parent_return, &children, &child_count)) {
    return 0;
  }

  for (unsigned int i = 0; i < child_count && found == 0; i++) {
    found = find_matching_window(display, children[i], config);
  }

  if (children != NULL) {
    XFree(children);
  }

  return found;
}

static Window find_class_window(Display *display, Window root, const char *target_class) {
  Window root_return = 0;
  Window parent_return = 0;
  Window *children = NULL;
  unsigned int child_count = 0;
  Window found = 0;

  if (window_has_class(display, root, target_class)) {
    return root;
  }

  if (!XQueryTree(display, root, &root_return, &parent_return, &children, &child_count)) {
    return 0;
  }

  for (unsigned int i = 0; i < child_count && found == 0; i++) {
    found = find_class_window(display, children[i], target_class);
  }

  if (children != NULL) {
    XFree(children);
  }

  return found;
}

static const char *target_mode_option(const struct tray_click_config *config) {
  return config->target_mode == MATCH_TARGET_NAME ? "--target-name" : "--target-class";
}

static void report_no_matching_window(
  const char *program,
  const struct tray_click_config *config
) {
  fprintf(
    stderr,
    "%s: no window matching %s \"%s\"; retrying\n",
    program,
    target_mode_option(config),
    config->target_value
  );
}

static int grab_left_click(Display *display, Window window) {
  const unsigned int masks[] = {
    0,
    LockMask,
    Mod2Mask,
    LockMask | Mod2Mask,
  };
  int failed_grabs = 0;

  for (size_t i = 0; i < sizeof(masks) / sizeof(masks[0]); i++) {
    drain_x_errors(display);
    XGrabButton(
      display,
      Button1,
      masks[i],
      window,
      False,
      ButtonPressMask | ButtonReleaseMask,
      GrabModeAsync,
      GrabModeAsync,
      None,
      None
    );
    if (sync_x_error(display) != 0) {
      failed_grabs++;
    }
  }

  drain_x_errors(display);
  XSelectInput(display, window, StructureNotifyMask | ButtonPressMask | ButtonReleaseMask);
  (void)sync_x_error(display);

  return failed_grabs;
}

static void monitor_window_lifecycle(Display *display, Window window) {
  drain_x_errors(display);
  XSelectInput(display, window, StructureNotifyMask);
  (void)sync_x_error(display);
}

static int managed_app_is_open(
  Display *display,
  Window root,
  const struct tray_click_config *config
) {
  return find_class_window(display, root, config->app_class) != 0;
}

static void run_command(const char *command) {
  pid_t pid = fork();
  if (pid == 0) {
    setsid();
    execlp("sh", "sh", "-c", command, (char *)NULL);
    _exit(127);
  }
}

static void clear_left_click_state(int *app_open_on_press, int *left_press_seen) {
  *left_press_seen = 0;
  *app_open_on_press = 0;
}

static void handle_left_press(
  Display *display,
  Window root,
  const struct tray_click_config *config,
  int *app_open_on_press,
  int *left_press_seen
) {
  *app_open_on_press = managed_app_is_open(display, root, config);
  *left_press_seen = 1;
}

static void handle_left_release(
  Display *display,
  Window root,
  const struct tray_click_config *config,
  int *app_open_on_press,
  int *left_press_seen
) {
  if (!*left_press_seen) {
    *app_open_on_press = managed_app_is_open(display, root, config);
  }

  if (*app_open_on_press) {
    run_command(config->close_command);
  } else {
    run_command(config->open_command);
  }

  clear_left_click_state(app_open_on_press, left_press_seen);
}

static int enable_raw_click_events(Display *display, Window root, int *xi_opcode) {
#ifdef HAVE_XINPUT2
  int xi_event;
  int xi_error;
  int major = 2;
  int minor = 0;
  unsigned char mask[(XI_LASTEVENT + 7) / 8] = {0};
  XIEventMask event_mask;

  if (!XQueryExtension(display, "XInputExtension", xi_opcode, &xi_event, &xi_error)) {
    fprintf(stderr, "tray-left-click: XInput extension is unavailable\n");
    return 0;
  }

  if (XIQueryVersion(display, &major, &minor) != Success) {
    fprintf(stderr, "tray-left-click: XInput2 raw click mode is unavailable\n");
    return 0;
  }

  XISetMask(mask, XI_RawButtonPress);
  XISetMask(mask, XI_RawButtonRelease);

  event_mask.deviceid = XIAllMasterDevices;
  event_mask.mask_len = sizeof(mask);
  event_mask.mask = mask;

  drain_x_errors(display);
  XISelectEvents(display, root, &event_mask, 1);
  if (sync_x_error(display) != 0) {
    fprintf(stderr, "tray-left-click: failed to select XInput2 raw button events\n");
    return 0;
  }

  return 1;
#else
  (void)display;
  (void)root;
  (void)xi_opcode;
  fprintf(stderr, "tray-left-click: raw click mode was requested, but XInput2 support was not built in\n");
  return 0;
#endif
}

#ifdef HAVE_XINPUT2
static int query_root_pointer(Display *display, Window root, int *root_x, int *root_y) {
  Window root_return;
  Window child_return;
  int window_x;
  int window_y;
  unsigned int mask;

  return XQueryPointer(
    display,
    root,
    &root_return,
    &child_return,
    root_x,
    root_y,
    &window_x,
    &window_y,
    &mask
  );
}

static int window_root_rect(
  Display *display,
  Window root,
  Window window,
  int *root_x,
  int *root_y,
  unsigned int *width,
  unsigned int *height
) {
  XWindowAttributes attributes;
  Window child_return;

  if (!XGetWindowAttributes(display, window, &attributes)) {
    return 0;
  }
  if (attributes.map_state != IsViewable || attributes.width <= 0 || attributes.height <= 0) {
    return 0;
  }
  if (!XTranslateCoordinates(display, window, root, 0, 0, root_x, root_y, &child_return)) {
    return 0;
  }

  *width = (unsigned int)attributes.width;
  *height = (unsigned int)attributes.height;
  return 1;
}

static int point_is_inside_window(
  Display *display,
  Window root,
  Window window,
  int point_x,
  int point_y
) {
  int window_x;
  int window_y;
  unsigned int width;
  unsigned int height;

  if (!window_root_rect(display, root, window, &window_x, &window_y, &width, &height)) {
    return 0;
  }

  return point_x >= window_x &&
         point_y >= window_y &&
         point_x < window_x + (int)width &&
         point_y < window_y + (int)height;
}

static void handle_raw_left_button(
  Display *display,
  Window root,
  Window tray_window,
  const struct tray_click_config *config,
  int evtype,
  int *app_open_on_press,
  int *left_press_seen
) {
  int pointer_x;
  int pointer_y;
  int inside_target;

  if (tray_window == 0 || !query_root_pointer(display, root, &pointer_x, &pointer_y)) {
    if (evtype == XI_RawButtonRelease) {
      clear_left_click_state(app_open_on_press, left_press_seen);
    }
    return;
  }

  inside_target = point_is_inside_window(display, root, tray_window, pointer_x, pointer_y);
  if (evtype == XI_RawButtonPress) {
    if (inside_target) {
      handle_left_press(display, root, config, app_open_on_press, left_press_seen);
    } else {
      clear_left_click_state(app_open_on_press, left_press_seen);
    }
  } else if (evtype == XI_RawButtonRelease) {
    if (inside_target) {
      handle_left_release(display, root, config, app_open_on_press, left_press_seen);
    } else {
      clear_left_click_state(app_open_on_press, left_press_seen);
    }
  }
}

static int handle_xinput_event(
  Display *display,
  XEvent *event,
  int xi_opcode,
  Window root,
  Window tray_window,
  const struct tray_click_config *config,
  int *app_open_on_press,
  int *left_press_seen
) {
  XIRawEvent *raw_event;
  int evtype;

  if (event->type != GenericEvent || event->xcookie.extension != xi_opcode) {
    return 0;
  }
  if (!XGetEventData(display, &event->xcookie)) {
    return 1;
  }

  evtype = event->xcookie.evtype;
  raw_event = (XIRawEvent *)event->xcookie.data;
  if ((evtype == XI_RawButtonPress || evtype == XI_RawButtonRelease) &&
      raw_event != NULL &&
      raw_event->detail == Button1) {
    handle_raw_left_button(
      display,
      root,
      tray_window,
      config,
      evtype,
      app_open_on_press,
      left_press_seen
    );
  }

  XFreeEventData(display, &event->xcookie);
  return 1;
}
#endif

int main(int argc, char **argv) {
  struct tray_click_config config;
  Display *display;
  Window root;
  Window tray_window = 0;
  int x11_fd;
  int app_open_on_press = 0;
  int left_press_seen = 0;
  int target_missing_reported = 0;
  int xi_opcode = -1;

  if (!parse_args(argc, argv, &config)) {
    usage(argv[0]);
    return 2;
  }

  display = XOpenDisplay(NULL);
  if (display == NULL) {
    return 1;
  }

  signal(SIGCHLD, SIG_IGN);
  XSetErrorHandler(record_x_error);

  root = DefaultRootWindow(display);
  x11_fd = ConnectionNumber(display);

  if (config.click_mode == CLICK_MODE_RAW &&
      !enable_raw_click_events(display, root, &xi_opcode)) {
    return 1;
  }

  for (;;) {
    if (tray_window == 0 || !window_matches_target(display, tray_window, &config)) {
      tray_window = find_matching_window(display, root, &config);
      if (tray_window != 0) {
        target_missing_reported = 0;
        if (config.click_mode == CLICK_MODE_GRAB) {
          int failed_grabs = grab_left_click(display, tray_window);
          if (failed_grabs > 0) {
            fprintf(
              stderr,
              "%s: %d left-click grab(s) failed for window 0x%lx\n",
              argv[0],
              failed_grabs,
              (unsigned long)tray_window
            );
          }
        } else {
          monitor_window_lifecycle(display, tray_window);
        }
      } else if (!target_missing_reported) {
        report_no_matching_window(argv[0], &config);
        target_missing_reported = 1;
      }
    }

    while (XPending(display) > 0) {
      XEvent event;
      XNextEvent(display, &event);

#ifdef HAVE_XINPUT2
      if (config.click_mode == CLICK_MODE_RAW &&
          handle_xinput_event(
            display,
            &event,
            xi_opcode,
            root,
            tray_window,
            &config,
            &app_open_on_press,
            &left_press_seen
          )) {
        continue;
      }
#endif

      if (event.type == DestroyNotify && event.xdestroywindow.window == tray_window) {
        tray_window = 0;
        clear_left_click_state(&app_open_on_press, &left_press_seen);
      } else if (event.type == ButtonPress &&
                 config.click_mode == CLICK_MODE_GRAB &&
                 event.xbutton.window == tray_window &&
                 event.xbutton.button == Button1) {
        handle_left_press(display, root, &config, &app_open_on_press, &left_press_seen);
      } else if (event.type == ButtonRelease &&
                 config.click_mode == CLICK_MODE_GRAB &&
                 event.xbutton.window == tray_window &&
                 event.xbutton.button == Button1) {
        handle_left_release(display, root, &config, &app_open_on_press, &left_press_seen);
      }
    }

    fd_set fds;
    struct timeval timeout;

    FD_ZERO(&fds);
    FD_SET(x11_fd, &fds);
    timeout.tv_sec = 1;
    timeout.tv_usec = 0;

    select(x11_fd + 1, &fds, NULL, NULL, &timeout);
  }
}
