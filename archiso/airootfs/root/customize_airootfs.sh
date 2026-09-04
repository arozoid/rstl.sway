#!/bin/sh
# customize_airootfs.sh - post-install tweaks for the rstl.sway live/install
# medium, run by mkarchiso inside the chroot (deprecated hook, but still the
# supported way to run per-profile late steps on archiso v90).
#
#   1. Set the root password for the live/install session.
#   2. Apply the same size purge that install-min.sh step_8 does, so the live
#      image does not carry dev tooling / documentation / static libs.

set -eu

# ---- root password for the live session ----
# Applied after package install (instead of pre-seeding /etc/shadow, which
# caused a shadow.pacnew and could trip systemd-sysusers during pacstrap).
printf 'root:$6$6ab359rcnh4luAUK$Kbp52c9/NCKenOarW.YXr485qC5X2H.qjWWLn7bS1g/2dL3WRyOfm2uxXGxBiy2fE/kmSDQ9RwKOyERewTWLK/\n' | chpasswd -e

# ---- optional size purge (mirrors install-min.sh step_8) ----
# C/C++ headers (dev only)
rm -rf /usr/include
# static libraries (rarely needed at runtime)
find /usr/lib -type f -name "*.a" -delete 2>/dev/null || true
# pkg-config / linker data (dev only)
rm -rf /usr/lib/pkgconfig /usr/lib/ldscripts /usr/share/pkgconfig
# sanitizer libraries (dev/debug only)
rm -f /usr/lib/libasan.so* /usr/lib/libtsan.so*
# performance profiling tooling
rm -rf /usr/lib/gprofng*
# dev schemas/docs/licenses (functionally safe to drop)
rm -rf /usr/share/gir-1.0 /usr/share/gtk-doc /usr/share/vala /usr/share/licenses
# strip debug/unused symbols from binaries and shared libs
if command -v strip >/dev/null 2>&1; then
    find /usr/bin /usr/lib -type f \( -executable -o -name "*.so*" \) \
        -exec strip --strip-unneeded {} + 2>/dev/null || true
fi

exit 0