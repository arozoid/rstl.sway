#!/bin/sh

# ============================================================
# Is a freedesktop secret service already provided?
#
# Exit 0 when something already covers org.freedesktop.secrets: GNOME
# Keyring, KWallet, KeePassXC, Bitwarden, 1Password, pass-secret-service, or
# a service file left by one of them. The installers use this to leave dssd
# out, because two providers fight over the same D-Bus name (and usually the
# same /usr/share/dbus-1/services file).
#
# dssd itself does not count as "something else": an existing dssd install
# may still be listed, which is a no-op for the package manager.
# ============================================================

set -u

pkg_installed() {
    if command -v pacman >/dev/null 2>&1; then
        pacman -Q "$1" >/dev/null 2>&1 && return 0
    fi
    if command -v rpm >/dev/null 2>&1; then
        rpm -q "$1" >/dev/null 2>&1 && return 0
    fi
    if command -v xbps-query >/dev/null 2>&1; then
        xbps-query -p pkgver "$1" >/dev/null 2>&1 && return 0
    fi
    return 1
}

# 1. an active owner on the current user bus. This catches anything that is
#    running now, even a provider we do not know by package name.
if command -v dbus-send >/dev/null 2>&1; then
    if dbus-send --session --reply-timeout=1000 \
        --dest=org.freedesktop.DBus --type=method_call --print-reply \
        /org/freedesktop/DBus \
        org.freedesktop.DBus.NameHasOwner string:org.freedesktop.secrets \
        2>/dev/null | grep -q 'boolean true'; then
        exit 0
    fi
fi
if command -v busctl >/dev/null 2>&1; then
    if busctl --user --no-pager call org.freedesktop.DBus /org/freedesktop/DBus \
        org.freedesktop.DBus NameHasOwner s org.freedesktop.secrets 2>/dev/null |
        grep -q 'b true'; then
        exit 0
    fi
fi

# 2. a session D-Bus service file from a provider other than dssd. This
#    catches installed-but-not-running providers, which would take the name
#    as soon as a client asks for it.
for file in \
    /usr/share/dbus-1/services/org.freedesktop.secrets.service \
    /usr/local/share/dbus-1/services/org.freedesktop.secrets.service \
    "${XDG_DATA_HOME:-${HOME:-/root}/.local/share}/dbus-1/services/org.freedesktop.secrets.service"
do
    [ -f "$file" ] || continue
    # dssd's own file (Exec=.../dssd) is not another provider
    if grep -qE '^[[:space:]]*Exec=([^[:space:]]*/)?dssd([[:space:]]|$)' "$file" 2>/dev/null; then
        continue
    fi
    exit 0
done

# 3. a known provider package is installed, even if its daemon is not
#    running and its service file is not where we looked.
for pkg in \
    gnome-keyring gnome-keyring-git \
    kwallet kwallet5 kwallet6 ksecretsservice \
    keepassxc keepassxc-git \
    bitwarden bitwarden-bin \
    1password 1password-bin \
    pass-secret-service
do
    if pkg_installed "$pkg"; then
        exit 0
    fi
done

exit 1
