# local settings

Files in this directory are written by the ratl-based settings tools
(`bin/rstl-settings`, `bin/rstl-display`, `bin/rstl-wallpaper`,
`bin/rstl-input`, `bin/rstl-keys`, `bin/rstl-power`).

They are deliberately outside the repository-managed paths: the installers
purge and replace `sway/config`, `sway/config.d/`, and `bin/`, but they leave
this directory alone. That is what makes changes made in the settings dialogs
survive `bin/update.sh`.

`sway/config` includes `local/*.conf` after `sway/config.d/*.conf`, so the
generated files can override repository defaults without editing them.

The generated files are ignored by git; only this README is tracked.
