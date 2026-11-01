# rstl.sway · ~800 MiB distro

ultra lean & minimalistic sway desktop for arch linux, designed to make the most of your screen space while keeping essential desktop features and resource usage low, especially on laptops.



## features

- **window manager:** sway
- **status bar:** yambar
- **launcher:** rofi
- **notifications:** mako
- **file managers:** spf / rovr
- **audio:** pipewire / wiremix
- **bluetooth:** bluetui
- **networking:** networkmanager / nmtui
- **clipboard:** clipse
- **calculator:** eva
- **emoji picker:** latuicon
- **lock screen:** swaylock
- **screenshots:** grim / slurp
- **terminal:** foot
- **editors:** neovim / micro
- **login:** greetd / tuigreet
- **browser:** firefox (optional)
- **app picker:** [rstl-pick](https://github.com/arozoid/rstl-pick)

also includes multimedia codecs, polkit authentication, secret service and xdg portal integration.

the full desktop adds approximately 800 MiB over a bare arch installation, with a total installed rootfs of around 1 GiB.

## installation

```bash
git clone https://github.com/arozoid/rstl.sway.git ~/.config/rstl.sway/
cd ~/.config/rstl.sway/
./bin/install.sh
```

follow the installer prompts to select the features you want.

### editions

all editions use the same dotfiles and can be switched between at any time.

| edition | installer         | packages |
| ------- | ----------------- | -------- |
| full    | `install.sh`      | 58       |
| minimal | `install-min.sh`  | 58       |
| base    | `install-base.sh` | 40       |

- **full:** complete desktop with editor and extras.
- **minimal:** desktop without editor and extras.
- **base:** minimal desktop without editor, lock screen, idle management or clipboard daemon.

package lists can be edited directly in `packages-install*.txt`.

all installers support:

| flag                  | description            |
| --------------------- | ---------------------- |
| `--yes`, `-y`         | skip prompts           |
| `--program vim/mouse` | select program edition |
| `--firefox`           | install firefox        |
| `--no-firefox`        | skip firefox           |
| `--no-cleanup`        | skip package cleanup   |
| `--root`              | install into `/root`   |
| `--help`              | show available options |

for root installations, use the corresponding wrappers:

```bash
bin/install-root.sh --yes
bin/install-min-root.sh --yes
bin/install-base-root.sh --yes
```

### updating

```bash
rstl update.sh
```

updates packages and dotfiles, then reapplies the installed edition.

use `--help` to see additional options.

### the rstl command

`rstl` provides access to all scripts in `bin/`.

```bash
rstl install.sh --yes
rstl update.sh
```

running `rstl` without arguments opens an interactive script picker.

## configuration

sway configuration is stored in `sway/`.

| file                          | description                        |
| ----------------------------- | ---------------------------------- |
| `config`                      | main configuration and keybindings |
| `config.d/10-appearance.conf` | appearance and window borders      |
| `config.d/20-cursor.conf`     | cursor theme                       |
| `config.d/25-displays.conf`   | display configuration              |
| `config.d/30-input.conf`      | keyboard and pointer settings      |
| `config.d/40-autostart.conf`  | startup applications               |

custom configuration can be added through additional files in `config.d/`.

## programs

additional programs and packages include:

- **desktop:** sway, yambar, rofi, mako, awww
- **terminal:** foot, zsh
- **editors:** neovim, micro
- **file management:** superfile, rovr, lf
- **audio:** pipewire, wiremix
- **bluetooth:** bluez, bluetui
- **networking:** networkmanager
- **clipboard:** wl-clipboard, clipse
- **fonts:** jetbrains mono nerd, noto emoji
- **icons:** papirus dark, hicolor
- **security:** dssd, rstlpk
- **portals:** xdg-desktop-portal-termfilechooser
- **utilities:** eva, latuicon

some packages are provided through [rstl.repo](https://github.com/arozoid/rstl.repo).

## keybindings

| shortcut                  | action                    |
| ------------------------- | ------------------------- |
| `win+d`                   | application launcher      |
| `win+enter`               | terminal                  |
| `win+shift+s`             | screenshot                |
| `win+backspace`           | power menu                |
| `win+o`                   | app picker                |
| `win+f`                   | fullscreen                |
| `win+e`                   | split windows             |
| `win+w`                   | tabbed layout             |
| `win+space`               | floating window           |
| `win+shift+q`             | close window              |
| `win+hjkl` / arrows       | switch windows            |
| `win+shift+hjkl` / arrows | move windows              |
| `win+1-9`                 | switch workspace          |
| `win+shift+1-9`           | move window to workspace  |
| `win+r`                   | resize mode               |
| `win+lmb`                 | move window               |
| `win+rmb`                 | resize window             |
| `win+shift+c`             | reload sway configuration |

function keys `f1-f12` control brightness, volume and other hardware features.

## credits

- [melatonia/meloworld-dotfiles](https://github.com/melatonia/meloworld-dotfiles) for the startup sound and default wallpaper.
- [firstrib](https://gitlab.com/firstrib/firstrib) for the initrd and frugal installation scripts.
- [cachyos](https://cachyos.org) for the kernel and linux-cachyos-bore base used by [rstl.linuz](https://github.com/arozoid/rstl.linuz).
- 
