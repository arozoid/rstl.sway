## manual install

prefer doing everything by hand? clone the repo first:

```bash
git clone https://github.com/arozoid/rstl.sway.git/ ~/.config/rstl.sway/
cd ~/.config/rstl.sway/
```

then install each package group below, skipping whatever you don't need:

### window manager / bar / launcher / notifications / lock screen

```bash
sudo pacman -S --needed sway swaybg rofi mako swaylock swayidle
sudo pacman -S --needed yay && yay -S --needed waybar-minimal-git
```

### screenshots / clipboard history

```bash
sudo pacman -S --needed grim slurp wl-clipboard cliphist
```

### wallpaper daemon + image tooling

```bash
sudo pacman -S --needed awww imagemagick
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
sudo pacman -S --needed pipewire wireplumber pipewire-pulse pipewire-alsa alsa-utils pulseaudio-utils pavucontrol
```

### notifications + password manager

```bash
sudo pacman -S --needed libnotify keepassxc sound-theme-freedesktop
```

### login manager

```bash
sudo pacman -S --needed greetd greetd-tuigreet
```

### terminal / shell / terminal file manager

```bash
sudo pacman -S --needed foot fish fastfetch bat eza zoxide jq lf
```

### editor

```bash
sudo pacman -S --needed neovim git curl wget unzip ripgrep fd make gcc
```

### fonts

```bash
sudo pacman -S --needed ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji
```

### wayland helpers

```bash
sudo pacman -S --needed xorg-xwayland xdg-utils xdg-desktop-portal-wlr
```

### misc CLI referenced by the dotfiles

```bash
sudo pacman -S --needed expac git cronie
```

### video / multimedia codec base

```bash
sudo pacman -S --needed ffmpeg gstreamer gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-libav mesa vulkan-icd-loader
```

### AUR

```bash
yay -S --needed waybar-minimal-git xdg-desktop-portal-termfilechooser
```

### symlink the configs

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

### post-install extras

- enable the login manager: `sudo systemctl enable greetd` (and mask `getty@tty1` so greetd takes over)
- drop your wallpaper at `~/Pictures/Wallpapers/wallpaper.jpg` or edit `~/.config/rstl.sway/wallpaper`
- battery alerts run via cronie — add `~/.config/rstl.sway/scripts/batt.sh` to your crontab (see step 6 of `install.sh`)
- `rstlpk` (our minimal polkit agent) — fetches from GitHub releases: `sudo rstlpk/install.sh`
