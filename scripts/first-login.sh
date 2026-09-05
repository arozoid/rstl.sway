#!/bin/sh
# rstl-first-login — one-shot per-user setup + session launcher for rstl.sway.
#
# Invoked a few ways, all safe and idempotent:
#   - greetd/tuigreet session command:    tuigreet --cmd 'rstl-first-login sway'
#   - shell logins (via /etc/profile.d):  rstl-first-login
#   - sway autostart:                     exec_always rstl-first-login
#
# The per-user setup (materialize the desktop config, create the ~/.config
# symlinks, portals, wallpaper, user services) runs only on the FIRST login,
# guarded by ~/.config/rstl.sway/.first-login-done. When a trailing session
# command is given it runs via exec so the session process (e.g. sway) takes
# over cleanly; with no arguments the script just sets up and exits 0, so it
# may also be chained: `rstl-first-login && sway`.

MARKER="$HOME/.config/rstl.sway/.first-login-done"
CFG="$HOME/.config/rstl.sway"
SKEL="/etc/skel/.config/rstl.sway"
LOG="$HOME/.cache/rstl-first-login.log"

# ---------------------------------------------------------------------------
# guards: setup only makes sense for real users with a home
# ---------------------------------------------------------------------------
[ -n "$HOME" ] || exit 0
[ -d "$HOME" ] || exit 0
[ "$HOME" != "/root" ] || exit 0   # root (live ISO / admin) is scaffolded by the build
[ "$(id -u)" -ge 1000 ] || exit 0  # greeter and other system users

mkdir -p "$HOME/.cache"
exec >>"$LOG" 2>&1
echo "== rstl-first-login for $USER ($(date))"

if [ ! -f "$MARKER" ]; then

    # -----------------------------------------------------------------------
    # 1. materialize the desktop config for users created before /etc/skel
    # -----------------------------------------------------------------------
    if [ ! -d "$CFG" ]; then
        if [ -d "$SKEL" ]; then
            mkdir -p "$HOME/.config"
            cp -a "$SKEL" "$CFG" || echo "couldn't materialize $CFG from skeleton"
            chown -R "$(id -u):$(id -g)" "$CFG" 2>/dev/null || true
            echo "materialized $CFG from skeleton"
        else
            echo "no skeleton config, nothing to do"
        fi
    fi

    # -----------------------------------------------------------------------
    # 2. symlink the config directories to their expected paths
    # -----------------------------------------------------------------------
    for d in sway swaylock swayidle yambar rofi fish foot nvim mako lf rovr fastfetch; do
        [ -e "$CFG/$d" ] || continue
        [ -e "$HOME/.config/$d" ] && continue
        ln -s "$CFG/$d" "$HOME/.config/$d"
        echo "linked $HOME/.config/$d -> $CFG/$d"
    done

    # -----------------------------------------------------------------------
    # 3. file-chooser portal (termfilechooser, as the installer configures it)
    # -----------------------------------------------------------------------
    if [ -d "$CFG/portal" ] && [ ! -e "$HOME/.config/xdg-desktop-portal-termfilechooser" ]; then
        mkdir -p "$HOME/.config/xdg-desktop-portal-termfilechooser"
        cp -a "$CFG/portal/." "$HOME/.config/xdg-desktop-portal-termfilechooser/" 2>/dev/null || true
        chmod +x "$HOME/.config/xdg-desktop-portal-termfilechooser/"*.sh 2>/dev/null || true
    fi
    if [ ! -f "$HOME/.config/xdg-desktop-portal/portals.conf" ]; then
        mkdir -p "$HOME/.config/xdg-desktop-portal"
        printf '[preferred]\norg.freedesktop.impl.portal.FileChooser=termfilechooser\n' \
            > "$HOME/.config/xdg-desktop-portal/portals.conf"
    fi

    # -----------------------------------------------------------------------
    # 4. default wallpaper
    # -----------------------------------------------------------------------
    wp_dir="$HOME/Pictures/Wallpapers"
    wp_conf="$CFG/wallpaper"
    wp_file="$wp_dir/wallpaper.jpg"
    if [ ! -f "$wp_conf" ]; then
        mkdir -p "$wp_dir"
        printf '%s\n' "~/Pictures/Wallpapers/wallpaper.jpg" > "$wp_conf"
        echo "wrote default wallpaper config"
    fi
    if [ ! -f "$wp_file" ] && [ -f "$CFG/wallpapers/Kiki's Delievery Service.jpg" ]; then
        mkdir -p "$wp_dir"
        cp "$CFG/wallpapers/Kiki's Delievery Service.jpg" "$wp_file"
        echo "installed default wallpaper"
    fi

    # -----------------------------------------------------------------------
    # 5. done (user services like pipewire are enabled by the installer's
    #    step_8 — not here: inside a greetd-sourced profile there is no user
    #    systemd/dbus, so `systemctl --user` must not run in this path)
    # -----------------------------------------------------------------------
    mkdir -p "$(dirname "$MARKER")"
    touch "$MARKER"
    echo "rstl-first-login complete"

fi

# ---------------------------------------------------------------------------
# carry into the rest of the session (e.g. sway) when a command was given;
# with none, exit 0 so `... && sway` chains keep rolling too
# ---------------------------------------------------------------------------
[ $# -gt 0 ] || exit 0
exec "$@"