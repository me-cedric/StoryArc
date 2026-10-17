#!/usr/bin/env python3
"""A settings portal for the headless walks: owns org.freedesktop.portal.Desktop on the
session bus and answers org.freedesktop.portal.Settings for org.freedesktop.appearance,
the way xdg-desktop-portal does on a desktop. The container has no portal, and the app
reads the system accent (task 2.35e) and libadwaita reads the colour scheme from it.

  PORTAL_ACCENT=0.2,0.5,0.9   the accent-color triple; unset means no accent is set
  PORTAL_COLOR_SCHEME=1       0 none, 1 prefer dark, 2 prefer light
  PORTAL_CONTRAST=0           0 normal, 1 high
"""
import os
import sys

from gi.repository import Gio, GLib

NODE = """
<node>
  <interface name="org.freedesktop.portal.Settings">
    <method name="Read"><arg type="s" name="namespace" direction="in"/><arg type="s" name="key" direction="in"/><arg type="v" name="value" direction="out"/></method>
    <method name="ReadOne"><arg type="s" name="namespace" direction="in"/><arg type="s" name="key" direction="in"/><arg type="v" name="value" direction="out"/></method>
    <method name="ReadAll"><arg type="as" name="namespaces" direction="in"/><arg type="a{sa{sv}}" name="value" direction="out"/></method>
    <signal name="SettingChanged"><arg type="s" name="namespace"/><arg type="s" name="key"/><arg type="v" name="value"/></signal>
    <property name="version" type="u" access="read"/>
  </interface>
</node>
"""


def values():
    out = {
        "color-scheme": GLib.Variant("u", int(os.environ.get("PORTAL_COLOR_SCHEME", "0"))),
        "contrast": GLib.Variant("u", int(os.environ.get("PORTAL_CONTRAST", "0"))),
    }
    accent = os.environ.get("PORTAL_ACCENT")
    if accent:
        r, g, b = (float(part) for part in accent.split(","))
        out["accent-color"] = GLib.Variant("(ddd)", (r, g, b))
    return out


def on_call(connection, sender, path, interface, method, parameters, invocation):
    if method in ("Read", "ReadOne"):
        namespace, key = parameters.unpack()
        value = values().get(key) if namespace == "org.freedesktop.appearance" else None
        if value is None:
            invocation.return_dbus_error("org.freedesktop.portal.Error.NotFound", f"{namespace} {key}")
            return
        # `Read` answers a variant holding the value, as the portal does.
        invocation.return_value(GLib.Variant("(v)", (GLib.Variant("v", value),)))
    elif method == "ReadAll":
        invocation.return_value(GLib.Variant("(a{sa{sv}})", ({"org.freedesktop.appearance": values()},)))
    else:
        invocation.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod", method)


def on_get_property(connection, sender, path, interface, name):
    return GLib.Variant("u", 2) if name == "version" else None


def on_bus(connection, name):
    info = Gio.DBusNodeInfo.new_for_xml(NODE).interfaces[0]
    connection.register_object("/org/freedesktop/portal/desktop", info, on_call, on_get_property, None)
    print("fake settings portal up", flush=True)


Gio.bus_own_name(
    Gio.BusType.SESSION,
    "org.freedesktop.portal.Desktop",
    Gio.BusNameOwnerFlags.NONE,
    on_bus,
    None,
    lambda *_: sys.exit("could not own org.freedesktop.portal.Desktop"),
)
GLib.MainLoop().run()
