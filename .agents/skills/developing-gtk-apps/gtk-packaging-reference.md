# GTK Packaging Reference

Desktop files, AppStream metadata, Meson install rules, and Flatpak packaging for GTK 4/libadwaita apps. Everything here is distro-neutral: name build dependencies by their pkg-config/upstream name (`gtk4`, `libadwaita-1`, `blueprint-compiler`) and let the reader map them to their package manager.

## Desktop File (com.example.MyApp.desktop)

```ini
[Desktop Entry]
Name=My App
Comment=Does something useful
Exec=myapp
Icon=com.example.MyApp
Terminal=false
Type=Application
Categories=Utility;
StartupNotify=true
```

## AppStream Metadata (com.example.MyApp.metainfo.xml)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>com.example.MyApp</id>
  <name>My App</name>
  <summary>Does something useful</summary>
  <metadata_license>CC0-1.0</metadata_license>
  <project_license>GPL-3.0-or-later</project_license>
  <description>
    <p>Longer description of the app.</p>
  </description>
  <launchable type="desktop-id">com.example.MyApp.desktop</launchable>
  <url type="homepage">https://example.com</url>
  <content_rating type="oars-1.1"/>
  <releases>
    <release version="1.0.0" date="2024-01-01"/>
  </releases>
</component>
```

## Meson Build (meson.build)

**Vala apps:** the compiled-executable skeleton (project languages, dependencies, resources, blueprint) is in `vala-reference.md`; combine it with the install rules below.

**Python apps:**

```meson
project('myapp', version: '1.0.0')

python = import('python')
py_installation = python.find_installation('python3')

# Install Python files
install_subdir('myapp', install_dir: py_installation.get_install_dir())

# Install data files
install_data('data/com.example.MyApp.desktop',
  install_dir: get_option('datadir') / 'applications')
install_data('data/com.example.MyApp.metainfo.xml',
  install_dir: get_option('datadir') / 'metainfo')

# Compile schemas
gnome = import('gnome')
gnome.compile_schemas(build_by_default: true)
```

**Rust apps:** Meson owns the data install rules on this page unchanged and invokes `cargo build` from a `custom_target` for the binary. Start from GNOME Builder's Rust project template for the wiring — it maintains the cargo invocation, offline flags, and artifact copy that are easy to get subtly wrong by hand (trade-offs in `rust-reference.md`, Build).

## Flatpak Manifest (com.example.MyApp.json)

```json
{
    "app-id": "com.example.MyApp",
    "runtime": "org.gnome.Platform",
    "runtime-version": "50",
    "sdk": "org.gnome.Sdk",
    "command": "myapp",
    "finish-args": [
        "--share=ipc",
        "--socket=fallback-x11",
        "--socket=wayland",
        "--device=dri"
    ],
    "cleanup": [
        "/include",
        "/lib/pkgconfig",
        "*.a",
        "*.la"
    ],
    "modules": [
        {
            "name": "myapp",
            "buildsystem": "meson",
            "sources": [
                {
                    "type": "dir",
                    "path": "."
                }
            ]
        }
    ]
}
```

Track the current GNOME runtime version (`flatpak remote-ls flathub | grep org.gnome.Platform`). The Sdk includes `valac`, `blueprint-compiler`, and the GTK/libadwaita dev files, so a Vala app's manifest needs only the meson module above — no toolchain modules. Rust is not in the Sdk; see the Rust section below.

## Common Flatpak Permissions

| Permission | Arg | When Needed |
|------------|-----|-------------|
| Network access | `--share=network` | API calls, downloads |
| Home folder | `--filesystem=home` | User files (prefer portals) |
| Host files | `--filesystem=host` | File manager apps |
| Notifications | `--talk-name=org.freedesktop.Notifications` | System notifications |
| Secrets | `--talk-name=org.freedesktop.secrets` | Keyring access |
| Background | `--talk-name=org.freedesktop.portal.Background` | Background services |

## Build and Run Locally

```bash
# Build
flatpak-builder --user --install --force-clean build-dir com.example.MyApp.json

# Run
flatpak run com.example.MyApp

# Export bundle
flatpak build-bundle ~/.local/share/flatpak/repo myapp.flatpak com.example.MyApp
```

## Python Dependencies in Flatpak (Python branch only)

For apps with Python dependencies, add pip modules:

```json
{
    "modules": [
        {
            "name": "python-requests",
            "buildsystem": "simple",
            "build-commands": [
                "pip3 install --prefix=/app --no-deps ."
            ],
            "sources": [
                {
                    "type": "archive",
                    "url": "https://files.pythonhosted.org/packages/.../requests-2.31.0.tar.gz",
                    "sha256": "..."
                }
            ]
        },
        {
            "name": "myapp",
            "buildsystem": "meson",
            "sources": [
                {
                    "type": "dir",
                    "path": "."
                }
            ]
        }
    ]
}
```

Or use `flatpak-pip-generator` to generate module definitions:

```bash
# Generate module for requests and dependencies
flatpak-pip-generator requests
# Creates python3-requests.json to include in manifest
```

## Rust Toolchain and Crates in Flatpak (Rust branch only)

Two additions to the manifest: the Rust toolchain comes from an SDK extension, and the crate tree must be vendored because Flatpak builds run offline.

```json
{
    "sdk-extensions": ["org.freedesktop.Sdk.Extension.rust-stable"],
    "build-options": {
        "append-path": "/usr/lib/sdk/rust-stable/bin",
        "env": { "CARGO_HOME": "/run/build/myapp/cargo" }
    },
    "modules": [
        {
            "name": "myapp",
            "buildsystem": "meson",
            "sources": [
                { "type": "dir", "path": "." },
                "cargo-sources.json"
            ]
        }
    ]
}
```

Generate `cargo-sources.json` from the lockfile with `flatpak-cargo-generator` (from the flatpak-builder-tools repo); regenerate whenever `Cargo.lock` changes:

```bash
flatpak-cargo-generator Cargo.lock -o cargo-sources.json
```

## Icons

Install app icon at multiple sizes:

```meson
# data/meson.build
icon_sizes = ['16', '32', '48', '64', '128', '256', '512']

foreach size : icon_sizes
  install_data(
    'icons/hicolor/@0@x@0@/apps/com.example.MyApp.png'.format(size),
    install_dir: get_option('datadir') / 'icons' / 'hicolor' / '@0@x@0@'.format(size) / 'apps'
  )
endforeach

# Symbolic icon
install_data(
  'icons/hicolor/symbolic/apps/com.example.MyApp-symbolic.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'symbolic' / 'apps'
)
```

## GSettings Schema Installation

```meson
# data/meson.build
install_data(
  'com.example.MyApp.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)

gnome.post_install(glib_compile_schemas: true)
```

## Complete data/meson.build

```meson
# data/meson.build

# Desktop file
desktop_file = i18n.merge_file(
  input: 'com.example.MyApp.desktop.in',
  output: 'com.example.MyApp.desktop',
  type: 'desktop',
  po_dir: '../po',
  install: true,
  install_dir: get_option('datadir') / 'applications'
)

# Validate desktop file
desktop_utils = find_program('desktop-file-validate', required: false)
if desktop_utils.found()
  test('validate-desktop', desktop_utils, args: [desktop_file])
endif

# AppStream metadata
metainfo_file = i18n.merge_file(
  input: 'com.example.MyApp.metainfo.xml.in',
  output: 'com.example.MyApp.metainfo.xml',
  po_dir: '../po',
  install: true,
  install_dir: get_option('datadir') / 'metainfo'
)

# Validate AppStream
appstreamcli = find_program('appstreamcli', required: false)
if appstreamcli.found()
  test('validate-metainfo', appstreamcli, args: ['validate', '--no-net', metainfo_file])
endif

# GSettings schema
install_data(
  'com.example.MyApp.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)

# DBus service (if needed)
install_data(
  'com.example.MyApp.service',
  install_dir: get_option('datadir') / 'dbus-1' / 'services'
)
```

## Dependency and Runtime Versions Tools Get Wrong

**`dpkg-shlibdeps` only sees ELF symbols.** Runtime requirements with no
corresponding symbol are missed entirely — a stylesheet using CSS custom
properties needs GTK 4.16, but if the binary references no 4.16 symbol,
shlibdeps happily emits `libgtk-4-1 (>= 4.12)`. The package then installs
cleanly on 4.14 and renders unstyled. Raise the floors by hand to whatever your
*code and assets* actually require:

```sh
DEPS="$(dpkg-shlibdeps -O --ignore-missing-info usr/bin/myapp)"
DEPS="${DEPS#shlibs:Depends=}"
DEPS="$(printf '%s' "$DEPS" | sed -e 's/libgtk-4-1 ([^)]*)/libgtk-4-1 (>= 4.16)/')"
```

**The Flatpak rust SDK extension is versioned by the freedesktop base**, not by
the GNOME version — GNOME 50 sits on freedesktop 25.08. Read it rather than
hardcoding a number that rots one release later:

```sh
BASE="$(flatpak remote-info --show-metadata flathub org.gnome.Sdk//50 \
  | sed -n 's/^version = \([0-9][0-9]\.[0-9][0-9]\)$/\1/p' | head -1)"
flatpak install flathub "org.freedesktop.Sdk.Extension.rust-stable//$BASE"
```

**`DBusActivatable=true` requires a service file, or `flatpak build-export`
fails outright** with "Desktop file D-Bus activatable, but service file not
exported". The `Exec` path differs per packaging route — `/app/bin/…` inside a
Flatpak, `/usr/bin/…` for a distro package, `$HOME/.local/bin/…` for a user
install — so generate it per target rather than sharing one file.

**A Flatpak cannot ship a GNOME Shell extension**, and neither can a Snap. See
`gnome-shell-companion-reference.md` for the format comparison.
