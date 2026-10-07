# The Linux base on Wayland — 2026-10-07

Task 0.11 of `desktop-clients`. The frames prove one claim: the Linux base starts on a
Wayland compositor and draws its libadwaita window. They show no feature, because the base
holds none.

| Frame | What it shows |
| --- | --- |
| `base-light.png` | The window in the light style. The sidebar holds Home, Library and Downloads, and Home is selected. The content is the empty-state page with the StoryArc mark. |
| `base-dark.png` | The same window in the dark style. Only the colour scheme changed between the two runs. |

## How the frames were made

`apps/desktop-linux/scripts/wayland-capture.sh` builds the app in an `archlinux:latest`
container (GTK 4.24.1, libadwaita 1.10.0). It runs the app under `cage`, a wlroots
compositor, with the headless backend. Then `grim` captures the output through the
wlr-screencopy protocol.

- `GDK_BACKEND=wayland`, so a missing Wayland connection fails the run. The app cannot fall
  back to X11.
- `GSK_RENDERER=cairo` and `WLR_RENDERER=pixman`, because the container has no GPU. A desktop
  uses the GL or Vulkan renderer. These frames do not prove GPU rendering.
- `ADW_DEBUG_COLOR_SCHEME=prefer-dark` selects the dark style. A desktop sets it through the
  Settings portal.

The frames do not prove the GNOME, KDE Plasma, COSMIC or Hyprland compositors, the floor
distro (Ubuntu 24.04 builds the app in `container-build.sh`, but no frame shows it), or
fractional scaling. Those are later tasks.

To repeat:

```bash
apps/desktop-linux/scripts/wayland-capture.sh
```
