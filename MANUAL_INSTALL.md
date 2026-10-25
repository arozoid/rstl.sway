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

apply the CachyOS pacman output settings (colors, `ILoveCandy`, verbose package tables, 10 parallel downloads):

```bash
sudo scripts/pacman-cachyos.sh
```

and link the yay config, if you use yay:

```bash
mkdir -p ~/.config
ln -sfn ~/.config/rstl.sway/yay ~/.config/yay
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
sudo pacman -S --needed playerctl brightnessctl light acpi power-profiles-daemon
```

`power-profiles-daemon` is optional: without it `rstl-power` hides the power-profile selector and still manages idle timers and the lid switch.

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

`dssd` is a freedesktop secret service. Skip it if GNOME Keyring, KWallet,
KeePassXC or another provider already provides `org.freedesktop.secrets`; two
providers conflict over the same D-Bus name (and usually the same service
file). The installers detect this and leave `dssd` out automatically.

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
and configure the one you like (e.g. `rovr` from rstl.repo, or `lf`)

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
  papirus-icon-theme-dark-only notwaita-cursors-grey adwaita-cursors dssd ratl
```

`dssd` is only listed to satisfy `org.freedesktop.secrets`; remove it from the
command if another secret service (GNOME Keyring, KWallet, KeePassXC, ...) is
already installed. The installers do this check automatically.

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
| `25-displays.conf` | per-output settings; an explicit `output <name> scale <n>` overrides the computed scale |
| `30-input.conf` | mouse and focus behavior |
| `40-autostart.conf` | what runs at login and on every reload |

drop a file of your own next to them (`50-mine.conf`), and reload with
win+shift+c. `sway -C -c ~/.config/sway/config` checks a config without
starting a session.

win+comma opens the ratl settings menu (`rstl rstl-settings` from a terminal).
the display, wallpaper, input, keyboard-shortcut and power dialogs write
generated overrides to `~/.config/rstl.sway/local/`, which `sway/config`
includes after `sway/config.d/`. the installers leave `local/` alone, so those
changes survive updates; delete a generated file to return to the repository
default. the files are git-ignored except for `local/README.md`.

the dialogs need an interactive terminal because ratl is a TUI. win+comma opens
them in foot; if you start a settings command without a terminal, it reopens
itself in foot when Wayland is available, and otherwise exits with a clear
message. the tools prefer `~/.local/bin/ratl` when it exists, so a locally
built ratl works even when foot's server has an older PATH. they need a ratl
build that draws on `/dev/tty` while its JSON result is captured; the old
0.1.0-1 package does not, so update ratl if the dialogs still report that they
need a terminal.

`rstl-wallpaper` previews images with ratl's true-colour image element (a ratl
build with image support; older versions fall back to a text-only preview and
still apply the wallpaper). `rstl-power` needs `swayidle` and `swaylock`; the power-profile
selector appears only when `power-profiles-daemon` is installed. display scale
choices match the 1.0–2.0 range accepted by `scripts/auto-scale.sh`.

the base edition does not install `awww`, `swayidle` or `swaylock`: display,
input and shortcut settings work there, but `rstl-wallpaper` saves the choice
without applying it and `rstl-power` reports that it is unavailable. install
those packages to enable wallpaper and power management on the base edition.

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
