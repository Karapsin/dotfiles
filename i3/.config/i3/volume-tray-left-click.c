#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <unistd.h>

static int ignore_x_error(Display *display, XErrorEvent *event) {
  (void)display;
  (void)event;
  return 0;
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

static Window find_named_window(Display *display, Window root, const char *target_name) {
  Window root_return = 0;
  Window parent_return = 0;
  Window *children = NULL;
  unsigned int child_count = 0;
  Window found = 0;

  if (window_has_name(display, root, target_name)) {
    return root;
  }

  if (!XQueryTree(display, root, &root_return, &parent_return, &children, &child_count)) {
    return 0;
  }

  for (unsigned int i = 0; i < child_count && found == 0; i++) {
    found = find_named_window(display, children[i], target_name);
  }

  if (children != NULL) {
    XFree(children);
  }

  return found;
}

static int window_has_class(Display *display, Window window, const char *target_class) {
  XClassHint hint;
  int matches = 0;

  if (XGetClassHint(display, window, &hint) == 0) {
    return 0;
  }

  matches =
    (hint.res_name != NULL && strcmp(hint.res_name, target_class) == 0) ||
    (hint.res_class != NULL && strcmp(hint.res_class, target_class) == 0);

  if (hint.res_name != NULL) {
    XFree(hint.res_name);
  }
  if (hint.res_class != NULL) {
    XFree(hint.res_class);
  }

  return matches;
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

static void grab_left_click(Display *display, Window window) {
  const unsigned int masks[] = {
    0,
    LockMask,
    Mod2Mask,
    LockMask | Mod2Mask,
  };

  for (size_t i = 0; i < sizeof(masks) / sizeof(masks[0]); i++) {
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
  }

  XSelectInput(display, window, StructureNotifyMask | ButtonPressMask | ButtonReleaseMask);
  XSync(display, False);
}

static int pavucontrol_is_open(Display *display, Window root) {
  return find_class_window(display, root, "pavucontrol") != 0;
}

static void close_pavucontrol(void) {
  pid_t pid = fork();
  if (pid == 0) {
    setsid();
    execlp("i3-msg", "i3-msg", "-q", "[class=\"^pavucontrol$\"] kill", (char *)NULL);
    _exit(127);
  }
}

static void open_pavucontrol(void) {
  const char *home = getenv("HOME");
  const char *command = "/usr/bin/pavucontrol";
  char local_command[4096];

  if (home != NULL) {
    snprintf(local_command, sizeof(local_command), "%s/.local/bin/pavucontrol", home);
    if (access(local_command, X_OK) == 0) {
      command = local_command;
    }
  }

  pid_t pid = fork();
  if (pid == 0) {
    setsid();
    execl(command, command, "--tab=1", (char *)NULL);
    _exit(127);
  }
}

int main(void) {
  const char *target_name = "PulseAudio system tray";
  Display *display = XOpenDisplay(NULL);
  Window root;
  Window tray_window = 0;
  int x11_fd;
  int pavucontrol_open_on_press = 0;
  int left_press_seen = 0;

  if (display == NULL) {
    return 1;
  }

  signal(SIGCHLD, SIG_IGN);
  XSetErrorHandler(ignore_x_error);

  root = DefaultRootWindow(display);
  x11_fd = ConnectionNumber(display);

  for (;;) {
    if (tray_window == 0 || !window_has_name(display, tray_window, target_name)) {
      tray_window = find_named_window(display, root, target_name);
      if (tray_window != 0) {
        grab_left_click(display, tray_window);
      }
    }

    while (XPending(display) > 0) {
      XEvent event;
      XNextEvent(display, &event);

      if (event.type == DestroyNotify && event.xdestroywindow.window == tray_window) {
        tray_window = 0;
      } else if (event.type == ButtonPress &&
                 event.xbutton.window == tray_window &&
                 event.xbutton.button == Button1) {
        pavucontrol_open_on_press = pavucontrol_is_open(display, root);
        left_press_seen = 1;
      } else if (event.type == ButtonRelease &&
                 event.xbutton.window == tray_window &&
                 event.xbutton.button == Button1) {
        if (!left_press_seen) {
          pavucontrol_open_on_press = pavucontrol_is_open(display, root);
        }

        if (pavucontrol_open_on_press) {
          close_pavucontrol();
        } else {
          open_pavucontrol();
        }

        left_press_seen = 0;
        pavucontrol_open_on_press = 0;
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
