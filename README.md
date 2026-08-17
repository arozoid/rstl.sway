# rstl.sway

ultra lean & minimalistic sway config (based on arch linux) for those who want to make the most of their screen space (optimized for laptops)

![preview](./assets/images/preview.png)

the entire package installation size for the full desktop experience totals to about 959 MiB (ironically smaller than xfce tree). this setup includes but is not limited to:
- window manager
- minimal bar
- launcher
- notifications
- lf file manager
- lock screen
- screenshots
- clipboard history
- neovim text editor
- multimedia codecs
- audio protocols
- network manager
- login screen
and several more features, such as polkit + keepassxc keyring management + xdg portal integration.

## installation

installation is rather easy:

```bash
git clone https://github.com/arozoid/rstl.sway.git/ ~/.config/rstl.sway/
cd ~/.config/rstl.sway/
./install.sh
```

follow the steps to select what you wanna do and not do, and that's basically it.

### manual install

prefer doing everything by hand? clone the repo first:

```bash
git clone https://github.com/arozoid/rstl.sway.git/ ~/.config/rstl.sway/
cd ~/.config/rstl.sway/
```

then install each package group below, skipping whatever you don't need:

#### window manager / bar / launcher / notifications / lock screen

```bash
sudo pacman -S --needed sway swaybg rofi mako swaylock swayidle
sudo pacman -S --needed yay && yay -S --needed waybar-minimal-git
```

#### screenshots / clipboard history

```bash
sudo pacman -S --needed grim slurp wl-clipboard cliphist
```

#### wallpaper daemon + image tooling

```bash
sudo pacman -S --needed awww imagemagick
```

#### hardware / media keys

```bash
sudo pacman -S --needed playerctl brightnessctl light acpi
```

#### network + bluetooth

```bash
sudo pacman -S --needed networkmanager bluez bluez-utils
```

#### audio stack

```bash
sudo pacman -S --needed pipewire wireplumber pipewire-pulse pipewire-alsa alsa-utils pulseaudio-utils pavucontrol
```

#### notifications + polkit

```bash
sudo pacman -S --needed libnotify polkit sound-theme-freedesktop
```

#### login manager

```bash
sudo pacman -S --needed greetd greetd-tuigreet
```

#### terminal / shell / terminal file manager

```bash
sudo pacman -S --needed foot fish fastfetch bat eza zoxide jq lf
```

#### editor

```bash
sudo pacman -S --needed neovim git curl wget unzip ripgrep fd make gcc
```

#### fonts

```bash
sudo pacman -S --needed ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji
```

#### wayland helpers

```bash
sudo pacman -S --needed xorg-xwayland xdg-utils xdg-desktop-portal-wlr
```

#### misc CLI referenced by the dotfiles

```bash
sudo pacman -S --needed hwinfo expac gnu-netcat grub cronie
```

#### video / multimedia codec base

```bash
sudo pacman -S --needed ffmpeg gstreamer gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-libav mesa vulkan-icd-loader
```

#### AUR (optional)

```bash
yay -S --needed xdg-desktop-portal-termfilechooser   # or: paru -S --needed xdg-desktop-portal-termfilechooser
```

#### symlink the configs

```bash
ln -s ~/.config/rstl.sway/sway     ~/.config/sway
ln -s ~/.config/rstl.sway/swaylock ~/.config/swaylock
ln -s ~/.config/rstl.sway/swayidle ~/.config/swayidle
ln -s ~/.config/rstl.sway/waybar   ~/.config/waybar
ln -s ~/.config/rstl.sway/rofi     ~/.config/rofi
ln -s ~/.config/rstl.sway/fish     ~/.config/fish
ln -s ~/.config/rstl.sway/foot     ~/.config/foot
ln -s ~/.config/rstl.sway/nvim     ~/.config/nvim
ln -s ~/.config/rstl.sway/mako     ~/.config/mako
ln -s ~/.config/rstl.sway/lf       ~/.config/lf
sudo ln -s ~/.config/rstl.sway/greetd /etc/greetd
```

#### post-install extras

- enable the login manager: `sudo systemctl enable greetd` (and mask `getty@tty1` so greetd takes over)
- drop your wallpaper at `~/Pictures/Wallpapers/wallpaper.jpg` or edit `~/.config/rstl.sway/wallpaper`
- battery alerts run via cronie — add `~/.config/rstl.sway/scripts/batt.sh` to your crontab (see step 6 of `install.sh`)
- `rstlpk` (our minimal polkit agent) — fetches from GitHub releases: `sudo rstlpk/install.sh`

## programs

- awww: lightweight wallpaper daemon
- waybar-minimal-git (AUR): heavily customizable navigation bar
- sway: tiling window manager
- mako: lightweight notification daemon
- rofi: minimal and customizable launcher

---

- grim/slurp: screenshot tools
- wl-clipboard/cliphist: wayland clipboard
- greetd/tuigreet: ultra minimal greet program
- ttf-jetbrains-mono-nerd/noto-fonts-emoji: for terminal and other apps

---

- bluez/networkmanager: set up for minimal arch install
- ffmpeg/gstreamer/*: video / multimedia codec base
- pipewire/pavucontrol/*: audio stack
- keepassxc (optional): password manager
- rstlpk (this repo): our own minimal polkit auth agent (no gtk; prompt in foot)
- xdg-desktop-portal-termfilechooser (AUR): file pickers open in lf

---

- foot: fast, feature-rich terminal (rust)
- lf: terminal file manager (used by the file chooser portal)
- nvim: vim alternative
- fish: friendly interactive shell

## keybinds

- win+d: rofi launcher
- win+enter: foot terminal
- win+shift+s: screenshot to clipboard and Pictures/Screenshots/*
- win+backspace: power menu (3x2 grid, wlogout-style)

---

- win+f: fullscreen window
- win+e: split windows horizontally/vertically
- win+w: tabbed window layout
- win+space: float window

---

- win+shift+q: kill window
- win+hjkl/arrow keys: move between windows
- win+shift+hjkl/arrow keys: move focused window
- win+1-9: move to workspace 1-9
- win+shift+1-9: move focused window to workspace 1-9

---

- win+shift+r: resize mode
    - hjkl/arrow keys: directional window resize
    - win+escape/return: back to default mode
    - win+shift+r: back to default mode
    - mouse: manually resize windows

---

- keyboard f1-12 function keys: desktop actions (lower/higher brightness, keyboard backlight, volume, etc)
- win+r: reload config

## credits

[melatonia/meloworld-dotfiles](https://github.com/melatonia/meloworld-dotfiles) for various desktop sounds (usb connect/remove and chime startup) and the cozy wallpaper selection :3
