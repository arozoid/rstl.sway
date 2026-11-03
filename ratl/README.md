# ratl settings pages

`bin/rstl-tune` opens the `ratl` settings interface, with the available categories listed in a dark green sidebar. Moving through the list previews each category; pressing Enter opens the selected page. Settings within a page can be changed using the usual keyboard and mouse controls.

| script | what it changes |
| --- | --- |
| `rstl-settings` | older settings menu, kept for existing shortcuts |
| `rstl-display` | output mode, scale and transform |
| `rstl-wallpaper` | wallpaper and solid colour, applied per output or across all outputs |
| `rstl-input` | keyboard layout and repeat rate, plus pointer and touchpad settings |
| `rstl-keys` | top-level Sway keybindings and additional shortcuts |
| `rstl-power` | lock, blank and suspend timers, lid action and power profile |
| `rstl-changes` | merge a FRUGAL RAM overlay into the persistent profile |
| `pages/<category>` | standalone launcher for each settings category |

`lib.sh` holds the shared bits used across the pages: Ratl's theme, terminal checks, dialog wrappers and system helpers. The smaller launchers under `pages/` use `pages-common.sh` for their common setup. Display, input, keybind, power and wallpaper each have their own scripts instead.

The installers copy this directory alongside the settings scripts. Anything generated for an individual user goes in `../local/`; the installers leave that directory untouched.
