## manual install

prefer doing everything by hand? clone the repo first:

```bash
git clone https://github.com/arozoid/rstl.sway.git/ ~/.config/rstl.sway/
cd ~/.config/rstl.sway/
git submodule update --init --depth 1 nvim
```

the `nvim` submodule carries the editor config you symlink at the end; without
that line the symlink below points at an empty directory.

upgrade your system:

```bash
sudo pacman -Syu
```

then install each package group below, skipping whatever you don't need:

### window manager / bar / launcher / notifications / lock screen

```bash
sudo pacman -S --needed sway swaybg rofi mako swaylock swayidle
```

### screenshots / clipboard history

```bash
sudo pacman -S --needed grim slurp wl-clipboard clipse
```

### wallpaper daemon + image tooling

```bash
sudo pacman -S --needed awww
```

### hardware / media keys

```bash
sudo pacman -S --needed playerctl brightnessctl light acpi
```

### network + bluetooth

```bash
sudo pacman -S --needed networkmanager bluez bluez-utils
```

### audio stack

```bash
sudo pacman -S --needed pipewire wireplumber pipewire-pulse pipewire-alsa alsa-utils pulseaudio-utils
```

### notifications + password manager

```bash
sudo pacman -S --needed libnotify dssd sound-theme-freedesktop
```

### login manager

```bash
sudo pacman -S --needed greetd greetd-tuigreet
```

### terminal / shell

```bash
sudo pacman -S --needed foot fish fastfetch bat eza zoxide jq
```

no terminal file manager is installed; the file chooser portal uses the first
of `superfile` (`spf`) / `rovr` / `lf` that it finds on your system. install
and configure the one you like (e.g. `rovr-bin` from rstl.repo, or `lf`)

### editor

```bash
sudo pacman -S --needed neovim git curl wget unzip ripgrep fd make gcc
```

### fonts

```bash
sudo pacman -S --needed noto-fonts-emoji
```

### wayland helpers

```bash
sudo pacman -S --needed xorg-xwayland xdg-utils xdg-desktop-portal-wlr
```

### misc CLI referenced by the dotfiles

```bash
sudo pacman -S --needed git cronie
```

### audio codecs

```bash
sudo pacman -S --needed flac mpg123 opus vorbis speex speexdsp sbc
```

### modern web video

```bash
sudo pacman -S --needed dav1d libvpx openh264 mesa vulkan-icd-loader
```

### rstl.repo 

```bash
printf '\n[rstl-repo]\nSigLevel = Optional TrustAll\nServer = https://arozoid.github.io/rstl.repo\n' \
| sudo tee -a /etc/pacman.conf >/dev/null
sudo pacman -Sy --needed \
  yambar xdg-desktop-portal-termfilechooser ttf-jetbrains-mono-nerd-min \
  papirus-icon-theme-dark-only notwaita-cursors-grey adwaita-cursors dssd
```

`notwaita-cursors-grey` is the default cursor package; `adwaita-cursors` is
installed as a fallback if notwaita isn't available. `hicolor-icon-theme` (the
base icon set) is pulled in automatically by other packages and doesn't need
explicit installation.

### symlink the configs

```bash
ln -s ~/.config/rstl.sway/sway     ~/.config/sway
ln -s ~/.config/rstl.sway/swaylock ~/.config/swaylock
ln -s ~/.config/rstl.sway/swayidle ~/.config/swayidle
ln -s ~/.config/rstl.sway/yambar   ~/.config/yambar
ln -s ~/.config/rstl.sway/rofi     ~/.config/rofi
ln -s ~/.config/rstl.sway/fish     ~/.config/fish
ln -s ~/.config/rstl.sway/foot     ~/.config/foot
ln -s ~/.config/rstl.sway/nvim     ~/.config/nvim
ln -s ~/.config/rstl.sway/mako     ~/.config/mako
ln -s ~/.config/rstl.sway/lf       ~/.config/lf
ln -s ~/.config/rstl.sway/rovr     ~/.config/rovr
sudo ln -s ~/.config/rstl.sway/greetd /etc/greetd
```

### post-install extras

- enable the login manager: `sudo systemctl enable greetd` (and mask `getty@tty1` so greetd takes over)
- first-login hook: greetd/tuigreet starts sway through `rstl-first-login`, so install it once:

  ```bash
  sudo install -Dm755 ~/.config/rstl.sway/scripts/first-login.sh /usr/local/bin/rstl-first-login
  ```
- drop your wallpaper at `~/Pictures/Wallpapers/wallpaper.jpg` or edit `~/.config/rstl.sway/wallpaper`
- battery alerts run via cronie. add `~/.config/rstl.sway/scripts/batt.sh` to your crontab (see step 6 of `install.sh`)
- `rstlpk` (our minimal polkit agent) fetches from GitHub releases: `sudo rstlpk/install.sh`

### settings you may want to change

`sway/config` holds the keybindings and the window rules; the settings live in
`sway/config.d/`, one file per topic, included in name order at the bottom of
`sway/config`:

| file | what is in it |
| --- | --- |
| `10-appearance.conf` | borders, gaps, client colors |
| `20-cursor.conf` | cursor theme (the size is computed by `scripts/auto-scale.sh`) |
| `25-displays.conf` | where per-output settings go, and why the scale is not hardcoded here |
| `30-input.conf` | mouse and focus behavior |
| `40-autostart.conf` | what runs at login and on every reload |

drop a file of your own next to them (`50-mine.conf`), and reload with
win+shift+c. `sway -C -c ~/.config/sway/config` checks a config without
starting a session.

the cursor theme is read from `20-cursor.conf` by `scripts/auto-scale.sh` (it
re-applies the theme with a runtime-computed size on every start and reload), so
`20-cursor.conf` is the only place the theme name is written down.

## updating

by hand, the two halves of what `bin/update.sh` does:

```bash
sudo pacman -Syu
git -C ~/.config/rstl.sway pull --ff-only
git -C ~/.config/rstl.sway submodule update --init --depth 1 nvim
```

then re-apply the dotfiles by hand (a `cp -a` of the repo over
`~/.config/rstl.sway`, minus `.git`, purging `sway/config`, `sway/config.d`,
`bin/`, the package lists and `.rstl-edition` first - see `copy_dotfiles` in
`bin/install.sh`, which is exactly what the installers do). packages you
installed by hand are not touched: the lists in `packages-install*.txt` are what
the installers install, and the ones listed there for your flavor are what
`rstl update` re-installs.
