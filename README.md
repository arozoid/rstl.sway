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

ISO root filesystems are built as Artix Linux with runit. Their pacman
configuration enables Artix repositories, Arch compatibility through
`artix-archlinux-support`, ALHP x86-64-v2/v3/v4 repositories, and CachyOS
generic/v3/v4 repositories. The ALHP mirrorlist is shipped with the build
configuration; ALHP currently publishes x86-64 optimized repositories.

## installation

```bash
git clone https://github.com/arozoid/rstl.sway.git ~/.config/rstl.sway/
cd ~/.config/rstl.sway/
./bin/install
```

follow the installer prompts to select the features you want.

### editions

all editions use the same dotfiles and can be switched between at any time.

| edition | installer   | packages |
| ------- | ----------- | -------- |
| full    | `install`   | 58       |
| minimal | `minstall`  | 58       |
| base    | `binstall`  | 40       |

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
| `--root`              | install into `/root` (must already be root) |
| `--runit`             | manage services with runit instead of systemd (default on Void) |
| `--systemd`           | manage services with systemd (overrides the Void default) |
| `--help`              | show available options |

for root installations, pass `--root` to the installer itself:

```bash
sudo bin/install --root --yes
sudo bin/minstall --root --yes
sudo bin/binstall --root --yes
sudo bin/update.sh --root --yes
```

the distribution is detected from the package manager (`arch`, `artix`,
`fedora`, `void`) and recorded in `.rstl-edition`. on Void and Artix runit is
the default init system; `--systemd` overrides that, and `--runit` asks for
runit anywhere it is installed.

there is no `systemctl --user` under runit, so the installers skip per-user
services and write `sway/config.d/90-audio.conf`, which starts pipewire in the
sway session. WirePlumber and the PulseAudio interface are linked from the
distribution's example configs into `~/.config/pipewire/pipewire.conf.d`.

### updating

```bash
rstl update.sh
```

updates packages and dotfiles, then reapplies the installed edition. `--runit` /
`--systemd` override the recorded init system; everything else (edition,
program, firefox, distribution, init) is read from `.rstl-edition`, which the
installers rewrite on every run.

use `--help` to see additional options.

### the rstl command

`rstl` provides access to all scripts in `bin/`.

```bash
rstl install --yes
rstl update.sh
```

running `rstl` without arguments opens an interactive script picker. the
deprecated ratl settings tools in `ratl/` are not listed there, but still run by
name (`rstl rstl-settings`) until the replacement settings suite lands.

### building isos

the weekly ISOs are built by `.github/workflows/build-iso.yml`:

1. `mkrootfs-*.sh` builds a local rootfs through `rootfs-common.sh`.
2. `mkfrugal-rstl.sh` stages the selected flavor and assembles the frugal.
3. `mkfrugal-iso.sh` wraps the frugal into a bootable ISO.

the rootfs, CachyOS bootstrap, system upgrade and kernel install run once per
microarchitecture and are reused by the layered ISO jobs. downloaded pacman
packages are shared through `mkfrugal-rstl.sh --pkgcache DIR` (bind-mounted for
the build and removed before the image is assembled), and GitHub Actions caches
that directory plus the container's package cache. the CachyOS signing key is
imported from its keyring package instead of a keyserver.

remaining cost: every program configuration still installs its own package
layer, and each ISO job extracts the base rootfs once per configuration.
CachyOS mirrorlist 404s are harmless while another mirror serves the database;
they never bypass signature verification.

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
