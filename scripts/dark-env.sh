#!/bin/sh
# dark-env.sh — prioritize dark theme across toolkits, zero added packages.
#
# Sourced from rstl-first-login at session start (before sway is exec'd) so
# the exported variables reach sway and everything it spawns; also idempotently
# materializes toolkit config files on every login.
#
# Uses only themes shipped with the base toolkits:
#   GTK   -> GTK_THEME=Adwaita:dark         (Adwaita is built into gtk3/gtk4)
#            + gtk-3.0/4.0 settings.ini's    (gtk-application-prefer-dark-theme)
#   Qt5/6 -> QT_QPA_PLATFORMTHEME=gtk3      (libqgtk3 ships with qt base libs;
#            makes Qt adopt the GTK palette, which is then dark)

# ---------------------------------------------------------------------------
# session environment
# ---------------------------------------------------------------------------
[ -n "$HOME" ] || return 0 2>/dev/null || exit 0

export GTK_THEME="Adwaita:dark"

# Qt: use the GTK platform theme when the plugin ships with the qt install.
# Check the arch layout for both qt5 (/usr/lib/qt) and qt6 (/usr/lib/qt6).
if [ -e /usr/lib/qt/plugins/platformthemes/libqgtk3.so ] ||
   [ -e /usr/lib/qt6/plugins/platformthemes/libqgtk3.so ]; then
    export QT_QPA_PLATFORMTHEME="gtk3"
fi

# ---------------------------------------------------------------------------
# materialize per-user GTK config (read by GTK apps regardless of env)
# ---------------------------------------------------------------------------
mkdir -p "$HOME/.config/gtk-3.0" 2>/dev/null
cat > "$HOME/.config/gtk-3.0/settings.ini" <<'EOF'
[Settings]
gtk-theme-name=Adwaita
gtk-icon-theme-name=Adwaita
gtk-application-prefer-dark-theme=1
EOF

mkdir -p "$HOME/.config/gtk-4.0" 2>/dev/null
cat > "$HOME/.config/gtk-4.0/settings.ini" <<'EOF'
[Settings]
gtk-theme-name=Adwaita
gtk-icon-theme-name=Adwaita
gtk-application-prefer-dark-theme=1
EOF

# ---------------------------------------------------------------------------
# systemd user session + D-Bus activation (portals, user services, ...)
# ---------------------------------------------------------------------------
mkdir -p "$HOME/.config/environment.d" 2>/dev/null
cat > "$HOME/.config/environment.d/rstl-dark.conf" <<'EOF'
GTK_THEME=Adwaita:dark
QT_QPA_PLATFORMTHEME=gtk3
EOF