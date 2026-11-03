# ratl settings pages

`bin/rstl-tune` is the Ratl settings frontend. It presents the categories in a
dark green sidebar next to each settings panel. Radio navigation previews a
category while moving; press Enter to commit and open it. Other controls use
their normal keyboard and mouse interactions.

| script | what it changes |
| --- | --- |
| `rstl-settings` | legacy menu retained for older shortcuts |
| `rstl-display` | output mode, scale and transform |
| `rstl-wallpaper` | wallpaper or solid colour, per output or for all outputs |
| `rstl-input` | keyboard layout/repeat and pointer/touchpad options |
| `rstl-keys` | top-level sway keybindings and new shortcuts |
| `rstl-power` | lock/blank/suspend timers, lid action and power profile |
| `rstl-changes` | merge a FRUGAL RAM overlay into the persistent profile |
| `pages/<category>` | launch each standalone settings category |

`lib.sh` provides Ratl's shared theme, terminal guard, dialog wrappers, and
system helpers. `pages-common.sh` contains helpers for the smaller category
launchers under `pages/`; the display, input, keybind, power, and wallpaper
pages remain standalone scripts.

The installers copy this directory with the settings scripts. Generated user
state belongs in `../local/`, which they leave alone.
