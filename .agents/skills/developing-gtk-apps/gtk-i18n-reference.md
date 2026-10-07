# GTK Internationalization Reference

Internationalization (i18n) patterns for GTK 4/libadwaita apps using gettext. The workflow (POTFILES, .po files, Meson `i18n` module, desktop/metainfo merging) is language-neutral; only the in-code setup and string formatting differ per language.

## Project Structure

```
myapp/
├── po/
│   ├── POTFILES.in      # List of files to translate
│   ├── LINGUAS          # List of language codes
│   ├── myapp.pot        # Template (generated)
│   ├── de.po            # German translations
│   └── fr.po            # French translations
├── myapp/
│   └── __init__.py      # App code with _() calls
└── meson.build
```

## Setup with Meson

```meson
# meson.build
project('myapp', version: '1.0.0')

i18n = import('i18n')

# Define gettext domain (usually same as app ID)
gettext_package = 'com.example.MyApp'

# Process translations
subdir('po')

# Pass to app as compile-time constant
conf = configuration_data()
conf.set_quoted('GETTEXT_PACKAGE', gettext_package)
conf.set_quoted('LOCALEDIR', get_option('prefix') / get_option('localedir'))

configure_file(
    input: 'config.py.in',
    output: 'config.py',
    configuration: conf,
    install_dir: python_installation.get_install_dir() / 'myapp'
)
```

```meson
# po/meson.build
i18n.gettext(gettext_package, preset: 'glib')
```

## POTFILES.in

List all files containing translatable strings — source files in your language (`.py`, `.vala`, or `.rs`), UI files (`.blp`/`.ui`), and the desktop/metainfo templates:

```
# po/POTFILES.in
src/window.vala          # or myapp/window.py for Python
data/window.blp
data/com.example.MyApp.desktop.in
data/com.example.MyApp.metainfo.xml.in
```

## LINGUAS

List supported languages:

```
# po/LINGUAS
de
es
fr
pt_BR
```

## App Initialization (Vala)

Call early in `main()` (or `startup`), before any translated string is used:

```vala
int main (string[] args) {
    GLib.Intl.setlocale (GLib.LocaleCategory.ALL, "");
    GLib.Intl.bindtextdomain ("com.example.MyApp", LOCALEDIR);
    GLib.Intl.bind_textdomain_codeset ("com.example.MyApp", "UTF-8");
    GLib.Intl.textdomain ("com.example.MyApp");
    // _() is now available everywhere
    return new MyApp ().run (args);
}
```

Inject `LOCALEDIR` (and the gettext domain) as build constants via Meson `configure_file` producing a `config.vala` (`public const string LOCALEDIR = "...";`), mirroring the Python `config.py` below.

Usage — Vala formats with printf-style placeholders:

```vala
var title = _("My Application");
var msg = GLib.ngettext ("%u item selected", "%u items selected", n).printf (n);
```

String templates (`@"$count items"`) interpolate before translation — keep `%`-placeholders inside `_()`/`ngettext()` and apply `.printf()` to the translated string.

## App Initialization (Rust)

Gettext comes from the `gettext-rs` crate (`gettext-rs = { version = "0.7", features = ["gettext-system"] }`); call early in `main()`, before any translated string is used:

```rust
use gettextrs::{LocaleCategory, bind_textdomain_codeset, bindtextdomain, setlocale, textdomain};

setlocale(LocaleCategory::LcAll, "");
bindtextdomain("com.example.MyApp", LOCALEDIR).expect("bindtextdomain");
bind_textdomain_codeset("com.example.MyApp", "UTF-8").expect("codeset");
textdomain("com.example.MyApp").expect("textdomain");
```

Inject `LOCALEDIR` as a build constant (Meson `configure_file` producing a `config.rs`, mirroring the Python `config.py` below).

Usage — `format!` takes only literal format strings, so translated strings substitute named placeholders instead:

```rust
use gettextrs::{gettext, ngettext};

let title = gettext("My Application");
let msg = ngettext("{n} item selected", "{n} items selected", n)
    .replace("{n}", &n.to_string());
```

## App Initialization (Python)

```python
# myapp/__init__.py
import gettext
import locale
import os

# Import from generated config
from .config import GETTEXT_PACKAGE, LOCALEDIR

def setup_i18n():
    """Initialize internationalization."""
    # Set up locale
    locale.bindtextdomain(GETTEXT_PACKAGE, LOCALEDIR)
    locale.textdomain(GETTEXT_PACKAGE)

    # Set up gettext
    gettext.bindtextdomain(GETTEXT_PACKAGE, LOCALEDIR)
    gettext.textdomain(GETTEXT_PACKAGE)

    # Install _() globally
    gettext.install(GETTEXT_PACKAGE, LOCALEDIR)

# Call early in app startup
setup_i18n()
```

## Using Translations in Code (Python)

```python
# myapp/window.py
# After setup_i18n(), _() is available globally

class MainWindow(Adw.ApplicationWindow):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)

        # Simple strings
        self.set_title(_("My Application"))

        # Strings with variables (use format, not f-strings)
        toast = Adw.Toast(title=_("Deleted {count} items").format(count=5))

        # Plurals
        from gettext import ngettext
        message = ngettext(
            "{count} item selected",
            "{count} items selected",
            count
        ).format(count=count)

        # Context for disambiguation
        from gettext import pgettext
        # Same word, different meaning in context
        open_file = pgettext("file", "Open")  # Open a file
        open_door = pgettext("door", "Open")  # Open state
```

## Translating UI Files

**Blueprint:**
```blueprint
using Gtk 4.0;
using Adw 1;

template $MyWindow: Adw.ApplicationWindow {
  // Mark strings with C_() for context or _() for translation
  title: _("My Application");

  content: Adw.ToolbarView {
    [top]
    Adw.HeaderBar {
      [end]
      Gtk.Button {
        label: _("Add");
        tooltip-text: _("Add a new item");
      }
    }
  };
}
```

**XML UI files:**
```xml
<property name="label" translatable="yes">Add Item</property>
<property name="tooltip-text" translatable="yes" context="button">Open</property>
```

## Translating Desktop/Metainfo Files

**Desktop file (use .desktop.in):**
```ini
# data/com.example.MyApp.desktop.in
[Desktop Entry]
Name=My App
Comment=Does something useful
# These get extracted to .pot and translated
```

**Metainfo (use .metainfo.xml.in):**
```xml
<!-- data/com.example.MyApp.metainfo.xml.in -->
<component type="desktop-application">
  <name>My App</name>
  <summary>Does something useful</summary>
  <description>
    <p>Longer description of the app.</p>
  </description>
</component>
```

## Translation Workflow

```bash
# 1. Generate .pot template from sources
cd build
meson compile myapp-pot

# Or manually:
xgettext --files-from=po/POTFILES.in \
         --output=po/myapp.pot \
         --from-code=UTF-8 \
         --add-comments=Translators

# 2. Create new language file
msginit --input=po/myapp.pot \
        --output=po/de.po \
        --locale=de_DE.UTF-8

# 3. Update existing translations after code changes
msgmerge --update po/de.po po/myapp.pot

# 4. Compile translations (done automatically by meson)
msgfmt po/de.po --output=locale/de/LC_MESSAGES/myapp.mo
```

## Testing Translations

```bash
# Run app in specific language
LANGUAGE=de ./myapp

# Test right-to-left layouts
LANGUAGE=ar ./myapp

# Check for untranslated strings
# (strings still in English when running in German)
LANGUAGE=de G_MESSAGES_DEBUG=all ./myapp 2>&1 | grep -i untranslated
```

## Common i18n Mistakes

| Mistake | Fix |
|---------|-----|
| (Python) f-strings with _() | Use `_("...{var}...").format(var=val)` |
| (Vala) string templates with _() | Use `_("...%s...").printf(val)` |
| (Rust) `format!` around `gettext()` | Named placeholders + `.replace()` — `format!` needs a literal format string |
| Concatenating strings | Single _() call: `_("Hello, {name}!")` |
| Splitting sentences | Keep complete sentences in one _() |
| Hardcoded number format | Use `locale.format_string()` |
| Hardcoded date format | Use `GLib.DateTime` formatting |

```python
# WRONG - translators can't reorder
label = _("Hello") + ", " + name + "!"

# RIGHT - complete sentence
label = _("Hello, {name}!").format(name=name)

# WRONG - f-string evaluated before _()
toast = Adw.Toast(title=_(f"Deleted {count} items"))

# RIGHT - placeholder in translated string
toast = Adw.Toast(title=_("Deleted {count} items").format(count=count))
```

## Number and Date Formatting (Python shown; Vala uses `GLib.DateTime.format` the same way)

```python
import locale
from gi.repository import GLib

# Numbers - respect locale
locale.setlocale(locale.LC_ALL, '')
formatted = locale.format_string("%.2f", 1234.56, grouping=True)
# "1,234.56" in en_US, "1.234,56" in de_DE

# Dates with GLib
dt = GLib.DateTime.new_now_local()
formatted_date = dt.format("%x")  # Locale-appropriate date
formatted_time = dt.format("%X")  # Locale-appropriate time

# Full datetime
formatted = dt.format(_("%B %d, %Y at %H:%M"))
# Note: wrap format string in _() for translator flexibility
```

## Translator Comments

Add context for translators:

```python
# Translators: This appears in the header bar title
title = _("Documents")

# Translators: %d is the number of selected items
message = ngettext(
    "%d item selected",
    "%d items selected",
    count
) % count
```

These comments appear in the .po file to help translators understand context.
