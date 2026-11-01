# ratl settings tools (deprecated)

These ratl-based desktop settings are **deprecated**. They are no longer listed
in the `rstl` menu and will be replaced by the new settings suite. They still
run when named directly (`rstl rstl-settings`, and the win+comma binding), so an
existing desktop keeps working until the replacement lands.

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

`bin/rstl` only lists scripts in `bin/`, but still resolves a bare name here, so
the tools run as `rstl rstl-settings`, `rstl rstl-changes`, and so on. The
installers purge and replace this directory together with `bin/`; generated
user state belongs in `../local/`, which they leave alone.
