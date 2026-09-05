#!/bin/sh
# rstl-install.sh
# minimal arch installer with rstl.sway styling (pure ASCII)

set -u

# ---------------------------------------------------------------------------
# colors / styling
# ---------------------------------------------------------------------------
G='\033[38;2;106;168;79m'   # rstl green
D='\033[38;2;140;148;132m'  # dim grey-green
W='\033[97m'
B='\033[1m'
R='\033[0m'

WIDTH=44

# ruler of '='s
rule() {
  printf "${G}"
  i=0
  while [ "$i" -lt "$WIDTH" ]; do printf '='; i=$((i+1)); done
  printf "${R}\n"
}

# centred line; indistinguishable plain length so ANSI never skews alignment
center() {
  text="$1" color="$2"
  plain=$(printf '%b' "$text" | sed -e 's/\x1b\[[0-9;]*m//g')
  pad=$(( (WIDTH - ${#plain}) / 2 ))
  [ "$pad" -lt 0 ] && pad=0
  i=0
  printf '%b' "$color"
  while [ "$i" -lt "$pad" ]; do printf ' '; i=$((i+1)); done
  printf '%b%b\n' "$text" "$R"
}

clear_screen() { printf '\033[2J\033[H'; }

pause() {
  printf "${D}  [ enter ] ${R}"
  read _ || true
}

title() {
  clear_screen
  rule
  center "${B}${W}$1${R}" "$G"
  rule
  echo
}

# ---------------------------------------------------------------------------
# welcome
# ---------------------------------------------------------------------------
welcome() {
  clear_screen
  rule
  center "${B}${W}rstl.sway${R}" "$G"
  center "${D}minimal arch experience${R}" "$G"
  rule
  echo
  center "this installer will install" "$D"
  center "rstl.sway onto your system." "$D"
  echo
  pause
}

# ---------------------------------------------------------------------------
# network
# ---------------------------------------------------------------------------
network_check() {
  title "network"

  if ping -c1 archlinux.org >/dev/null 2>&1; then
    printf "${G}[ ok ]${R} %s\n" "internet connected"
    echo
    pause
  else
    printf "${D}[ -- ]${R} %s\n" "no internet detected."
    printf "${D}[ -- ]${R} %s\n" "launching nmtui..."
    echo
    nmtui
  fi
}

# ---------------------------------------------------------------------------
# install mode
# ---------------------------------------------------------------------------
choose_mode() {
  title "installation mode"
  printf "${W}  1)${R} ${G}full${R}      erase an entire disk and install\n"
  printf "${W}  2)${R} ${G}dual${R}      install beside an existing OS (free space)\n"
  echo
  printf "${W}  > ${R}"
  read MODE || exit 1
  case "$MODE" in
    1|full|Full)   INSTALL_MODE="full" ;;
    2|dual|Dual)   INSTALL_MODE="dual" ;;
    *) printf "${D}[ -- ]${R} %s\n" "invalid choice"; choose_mode ;;
  esac
}

# find the first unused partition number (>=1) on a disk
next_part_num() {
  num=0
  while :; do
    num=$((num+1))
    p="${DISK}${SUFFIX}${num}"
    [ -b "$p" ] || { echo "$num"; return 0; }
  done
}

# ---------------------------------------------------------------------------
# disk selection
# ---------------------------------------------------------------------------
disk_select() {
  title "select installation disk"

  detect_boot_mode

  lsblk -d -o NAME,SIZE,MODEL
  echo
  printf "${W}  disk${R} (e.g. ${D}nvme0n1${R}): "
  read DISK || exit 1
  DISK="/dev/${DISK}"

  # nvme / mmc / loop disks number their partitions with a 'p' (nvme0n1p1)
  case "$DISK" in
    *[0-9]) SUFFIX="p" ;;
    *)      SUFFIX=""  ;;
  esac

  echo
  printf "${G}  selected:${R} %s (%s)\n" "$DISK" "$BOOT_MODE"

  if [ "$INSTALL_MODE" = "dual" ]; then
    # show current partitions so the user picks the right disk
    lsblk "$DISK" -o NAME,SIZE,FSTYPE,MOUNTPOINTS 2>/dev/null || true
  fi

  echo
  if [ "$INSTALL_MODE" = "full" ]; then
    printf "${W}  type ${R}${G}YES${R}${W} to erase this disk: ${R}"
    read CONFIRM || exit 1
    [ "$CONFIRM" = "YES" ] || exit 1
  else
    printf "${W}  this installs into free space and will not touch other partitions.${R}\n"
    printf "${W}  type ${R}${G}YES${R}${W} to continue: ${R}"
    read CONFIRM || exit 1
    [ "$CONFIRM" = "YES" ] || exit 1
  fi
}

# ---------------------------------------------------------------------------
# pick / find the EFI system partition to reuse (UEFI dual-boot)
# ---------------------------------------------------------------------------
find_esp() {
  # print the first EFI / Windows ESP path on $DISK, if any
  lsblk -rno PATH,PARTTYPENAME "$DISK" 2>/dev/null | \
    awk '$2 ~ /EFI|Microsoft basic data/ { print $1; exit }'
}

# resolve targets according to the chosen install mode
setup_targets() {
  if [ "$INSTALL_MODE" = "full" ]; then
    PART1="${DISK}${SUFFIX}1"
    PART2="${DISK}${SUFFIX}2"
    return 0
  fi

  if [ "$BOOT_MODE" = "uefi" ]; then
    # reuse an existing ESP; refuse to proceed without one
    ESP_DEV=$(find_esp)
    if [ -n "$ESP_DEV" ]; then
      printf "  ${G}[ ok ]${R} %s\n" "reusing existing ESP ${ESP_DEV}"
    else
      printf "  ${D}[ -- ]${R} %s\n" "no EFI partition found on ${DISK}"
      printf "  ${D}[ -- ]${R} %s\n" "dual-boot UEFI needs an existing ESP to reuse"
      return 1
    fi
    PART1="$ESP_DEV"
    PART2="${DISK}${SUFFIX}$(next_part_num)"
  else
    # BIOS dual-boot: 2M bios-boot partition + root in free space
    BIOS_NUM=$(next_part_num)
    ROOT_NUM=$((BIOS_NUM+1))
    PART1="${DISK}${SUFFIX}${BIOS_NUM}"
    PART2="${DISK}${SUFFIX}${ROOT_NUM}"
  fi
}

# ---------------------------------------------------------------------------
# partition preview
# ---------------------------------------------------------------------------
partition_preview() {
  title "partition layout"
  if [ "$INSTALL_MODE" = "dual" ]; then
    if [ "$BOOT_MODE" = "uefi" ]; then
      printf "${D}  ROOT    new (in free space)${R}\n"
      printf "${D}  ESP     existing, reused${R}\n"
    else
      printf "${D}  BIOS    2M (new)${R}\n"
      printf "${D}  ROOT    new (in free space)${R}\n"
    fi
    echo
    printf "${D}  scheme:${R} dual-boot (other OS untouched)\n"
  elif [ "$BOOT_MODE" = "uefi" ]; then
    printf "${D}  EFI     512M${R}\n"
    printf "${D}  ROOT    remaining${R}\n"
    echo
    printf "${D}  scheme:${R} GPT / UEFI\n"
  else
    printf "${D}  ROOT    whole disk${R}\n"
    echo
    printf "${D}  scheme:${R} MBR / BIOS\n"
  fi
  printf "${D}  filesystem:${R} ext4\n"
  echo
  pause
}

# ---------------------------------------------------------------------------
# install helpers
# ---------------------------------------------------------------------------

# run a step, showing [ ok ] / [ -- ] based on exit status; command output
# streams to the terminal so pacstrap progress stays visible
step() {
  label="$1"
  shift
  printf "  ${B}${W}%s${R}\n" "$label"
  if "$@"; then
    printf "  ${D}%s${R}  ${G}[ ok ]${R}\n" "done"
  else
    printf "  ${D}%s${R}  ${D}[ -- ]${R}\n" "failed"
  fi
}

check_root() {
  [ "$(id -u)" -eq 0 ] || {
    printf "${D}[ -- ]${R} %s\n" "must be run as root (use the live ISO)"
    exit 1
  }
}

# UEFI if the firmware has mounted efivarfs; otherwise assume legacy BIOS/MBR
detect_boot_mode() {
  if [ -d /sys/firmware/efi ]; then
    BOOT_MODE=uefi
  else
    BOOT_MODE=bios
  fi
  printf "  ${W}boot mode${R}: %s\n" "$BOOT_MODE"
}

# ---------------------------------------------------------------------------
# prompt for hostname / timezone / user / passwords
# ---------------------------------------------------------------------------
ask_identity() {
  title "system identity"

  printf "  ${W}hostname${R} (${D}default: rstl${R}): "
  read HOSTNAME || true
  HOSTNAME="${HOSTNAME:-rstl}"

  printf "  ${W}timezone${R} (${D}default: UTC${R}): "
  read TIMEZONE || true
  TIMEZONE="${TIMEZONE:-UTC}"
  [ -f "/usr/share/zoneinfo/${TIMEZONE}" ] || TIMEZONE=UTC

  echo
  printf "  ${W}username${R}: "
  read USERNAME || exit 1
  : "${USERNAME:?username required}"

  echo
  printf "  ${W}root password${R}: "
  stty -echo  2>/dev/null
  read ROOT_PASS || exit 1
  stty echo 2>/dev/null; printf '\n'

  printf "  ${W}user password for ${USERNAME}${R}: "
  stty -echo 2>/dev/null
  read USER_PASS || exit 1
  stty echo 2>/dev/null; printf '\n'

  echo
  printf "  ${G}[ ok ]${R} %s\n" "username: ${USERNAME}, hostname: ${HOSTNAME}"
  echo
}

# ---------------------------------------------------------------------------
# install steps
# ---------------------------------------------------------------------------
partition_disk() {
  if [ "$INSTALL_MODE" = "full" ]; then
    # DOS labels linger on some disks; wipe both GPT + MBR
    sgdisk --zap-all "$DISK"
    dd if=/dev/zero of="$DISK" bs=512 count=34 conv=notrunc 2>/dev/null || true

    if [ "$BOOT_MODE" = "uefi" ]; then
      # GPT + 512M EFI partition + root filling the rest
      sgdisk --clear \
             --new=1:0:+512M --typecode=1:ef00 \
             --new=2:0:0    --typecode=2:8304 \
             "$DISK"
    else
      # MBR + single Linux root partition filling the whole disk
      printf 'label: dos\n,,L\n' | sfdisk --wipe always "$DISK"
    fi
  else
    # dual-boot: keep everything, add (an) rstl partition(s) in free space
    if [ "$BOOT_MODE" = "uefi" ]; then
      # only a root partition is created; the ESP is reused as-is
      n=$(next_part_num)
      sgdisk --largest-new="$n" --typecode="$n:8304" "$DISK"
    else
      # 2M bios-boot partition + root in free space
      bios=$(next_part_num)
      root=$((bios+1))
      sgdisk --new="${bios}:0:+2M" --typecode="${bios}:ef02" \
             --new="${root}:0:0"  --typecode="${root}:8304" \
             "$DISK"
    fi
  fi
}

format_fs() {
  if [ "$BOOT_MODE" = "uefi" ] && [ "$INSTALL_MODE" = "full" ]; then
    mkfs.fat -F32 "$PART1"
    mkfs.ext4 -F "$PART2"
  elif [ "$INSTALL_MODE" = "full" ]; then
    mkfs.ext4 -F "$PART1"
  else
    # dual-boot: only format the new root; ESP / bios-boot are not touched
    if [ "$BOOT_MODE" = "uefi" ]; then
      mkfs.ext4 -F "$PART2"
    else
      mkfs.ext4 -F "$PART2"
    fi
  fi
}

mount_fs() {
  if [ "$BOOT_MODE" = "uefi" ]; then
    if [ "$INSTALL_MODE" = "full" ]; then
      mount "$PART2" /mnt
    else
      # dual-boot: root is the new partition; ESP may be mounted elsewhere, free it
      umount "$PART1" >/dev/null 2>&1 || true
      mount "$PART2" /mnt
    fi
    mkdir -p /mnt/boot
    mount "$PART1" /mnt/boot
  else
    # BIOS: full mode root is partition 1; dual mode root is the 2nd new one
    if [ "$INSTALL_MODE" = "full" ]; then
      mount "$PART1" /mnt
    else
      mount "$PART2" /mnt
    fi
  fi
}

install_base() {
  pacstrap /mnt \
    base base-devel linux linux-headers linux-firmware amd-ucode \
    networkmanager dhcpcd sudo \
    grub efibootmgr \
    $(cat /tmp/rstl-packages 2>/dev/null) || return 1

  # boot-critical settings
  arch-chroot /mnt systemctl enable NetworkManager.service
  arch-chroot /mnt systemctl enable systemd-resolved.service
}

generate_fstab() {
  genfstab -U /mnt > /mnt/etc/fstab
  [ -s /mnt/etc/fstab ]
}

configure_system() {
  # locale
  printf 'en_US.UTF-8 UTF-8\n' > /mnt/etc/locale.gen
  arch-chroot /mnt locale-gen
  printf 'LANG=en_US.UTF-8\n' > /mnt/etc/locale.conf

  # time
  ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /mnt/etc/localtime
  printf '%s\n' "$TIMEZONE" > /mnt/etc/timezone

  # hostname + hosts
  printf '%s\n' "$HOSTNAME" > /mnt/etc/hostname
  printf '127.0.0.1   localhost\n::1         localhost\n' > /mnt/etc/hosts

  # bootloader (GRUB)
  if [ "$BOOT_MODE" = "uefi" ]; then
    arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --recheck --no-nvram
  else
    arch-chroot /mnt grub-install --target=i386-pc --recheck "$DISK"
  fi

  # detect other operating systems for the boot menu (dual-boot)
  if [ "$INSTALL_MODE" = "dual" ]; then
    arch-chroot /mnt /bin/sh -c 'echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub'
    arch-chroot /mnt os-prober || true
  fi

  arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
  arch-chroot /mnt mkinitcpio -P
}

create_user() {
  arch-chroot /mnt chpasswd <<EOF
root:${ROOT_PASS}
EOF

  arch-chroot /mnt useradd -m -G wheel,video,audio,storage,input "$USERNAME" >/dev/null 2>&1 || \
    arch-chroot /mnt usermod -m -aG wheel,video,audio,storage,input "$USERNAME"
  arch-chroot /mnt chpasswd <<EOF
${USERNAME}:${USER_PASS}
EOF

  # normal password-based sudo for wheel
  printf '%%wheel ALL=(ALL:ALL) ALL\n' > /mnt/etc/sudoers.d/10-installer
  chmod 440 /mnt/etc/sudoers.d/10-installer
}

install_dotfiles() {
  # where the dotfiles live in the live ISO
  LIVE_DOTFILES="/root/.config/rstl.sway"
  TARGET_NEW="/mnt/home/${USERNAME}/.config/rstl.sway"

  [ -d "$LIVE_DOTFILES" ] || return 1

  # drop a copy into the user's home, owned by them
  mkdir -p "/mnt/home/${USERNAME}/.config"
  cp -a "$LIVE_DOTFILES" "$TARGET_NEW"
  arch-chroot /mnt chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}/.config"

  [ -x "$TARGET_NEW/install.sh" ] || return 1

  # the dotfiles installer drives most of its work through sudo; grant wheel
  # NOPASSWD just for this one-time setup, then restore normal password sudo.
  printf '%%wheel ALL=(ALL:ALL) NOPASSWD: ALL\n' > /mnt/etc/sudoers.d/10-installer
  arch-chroot /mnt /bin/su - "$USERNAME" -c \
    "cd \$HOME/.config/rstl.sway && ./install.sh --yes"
  printf '%%wheel ALL=(ALL:ALL) ALL\n' > /mnt/etc/sudoers.d/10-installer
  chmod 440 /mnt/etc/sudoers.d/10-installer
}

install_system() {
  check_root
  title "installing rstl.sway"
  echo

  ask_identity

  # assembled once so the base install pulls the whole rstl.sway desktop
  cat >/tmp/rstl-packages <<'EOF'
sway
swaybg
rofi
mako
swaylock
swayidle
grim
slurp
wl-clipboard
clipse
awww
playerctl
brightnessctl
acpi
networkmanager
bluez
bluez-utils
pipewire
wireplumber
pipewire-pulse
pipewire-alsa
alsa-utils
libnotify
sound-theme-freedesktop
greetd
greetd-tuigreet
foot
fish
bat
eza
zoxide
jq
lf
fastfetch
neovim
git
curl
wget
unzip
ripgrep
fd
noto-fonts-emoji
xorg-xwayland
xdg-utils
xdg-desktop-portal-wlr
cronie
flac
mpg123
opus
libvorbis
speex
speexdsp
sbc
dav1d
libvpx
openh264
mesa
vulkan-icd-loader
ttf-jetbrains-mono-nerd-min
papirus-icon-theme-dark-only
phinger-cursors
rstlpk
dssd
xdg-desktop-portal-termfilechooser
yambar
EOF

  # dual-boot needs os-prober (+ ntfs-3g to read Windows)
  if [ "$INSTALL_MODE" = "dual" ]; then
    printf 'os-prober\nntfs-3g\n' >> /tmp/rstl-packages
  fi

  setup_targets || exit 1

  step "partitioning disk" partition_disk
  step "formatting filesystems" format_fs
  step "mounting filesystems" mount_fs
  step "installing base system" install_base
  step "generating fstab" generate_fstab
  step "configuring system" configure_system
  step "creating user account" create_user
  step "installing dotfiles" install_dotfiles

  echo
  umount -R /mnt 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# finish
# ---------------------------------------------------------------------------
finish() {
  title "installation complete"
  printf "${G}[ ok ]${R} %s\n" "packages installed"
  printf "${G}[ ok ]${R} %s\n" "bootloader configured"
  printf "${G}[ ok ]${R} %s\n" "rstl.sway configured"
  echo
  center "remove the usb before rebooting." "$D"
  echo

  printf "${W}  1)${R} reboot now\n"
  printf "${W}  2)${R} return to rstl-inst\n"
  echo
  printf "${W}  > ${R}"
  read choice || exit 0

  case "$choice" in
    1) sync; systemctl reboot ;;
    *) exit 0 ;;
  esac
}

welcome
network_check
choose_mode
disk_select
partition_preview
install_system
finish
