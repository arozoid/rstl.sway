# ratl settings tools

The ratl-based desktop settings live here, separate from the general scripts
in `bin/`:

| script | what it changes |
| --- | --- |
| `rstl-settings` | the menu; also opens a category directly |
| `rstl-display` | output mode, scale and transform |
| `rstl-wallpaper` | wallpaper or solid colour, per output or for all outputs |
| `rstl-input` | keyboard layout/repeat and pointer/touchpad options |
| `rstl-keys` | top-level sway keybindings and new shortcuts |
| `rstl-power` | lock/blank/suspend timers, lid action and power profile |
| `rstl-changes` | merge a FRUGAL RAM overlay into the persistent profile |

`lib.sh` is sourced by all of them. It provides the shared forest-green ratl
theme, the `~/.local/bin/ratl` preference, the terminal guard, atomic writes,
and the confirm/sudo helpers.

`bin/rstl` searches both `bin/` and this directory, so the tools still run as
`rstl rstl-settings`, `rstl rstl-changes`, and so on. The installers purge and
replace this directory together with `bin/`; generated user state belongs in
`../local/`, which they leave alone.
