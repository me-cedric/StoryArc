# dmgbuild settings for the StoryArc disk image (design.md D6).
# make-dmg.sh runs: dmgbuild -s dmg-settings.py -D app=<StoryArc.app> -D background=<background.tiff> ...
# dmgbuild writes the .DS_Store itself, so no Finder session is needed on the runner.
import os.path

# dmgbuild injects `defines` and sets no __file__, so make-dmg.sh passes both paths.
app = defines["app"]  # noqa: F821

volume_name = "StoryArc"
# ULFO (lzfse) opens on macOS 10.11 and later; the app needs macOS 26.
format = "ULFO"
filesystem = "HFS+"

files = [app]
symlinks = {"Applications": "/Applications"}
hide_extensions = [os.path.basename(app)]

# Finder coordinates, origin top-left, the centre of each icon. background.tiff draws the
# arrow between these two points; change both together.
icon_locations = {
    os.path.basename(app): (180, 200),
    "Applications": (480, 200),
}

background = defines["background"]  # noqa: F821
window_rect = ((200, 120), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 128
text_size = 13
