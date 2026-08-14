# rustle.nvim

## introduction

my personal fork of [kickstart.nvim](https://nvim-lua/kickstart.nvim/), a starting point for creating your own neovim configuration

## installation

### install neovim

rustle.nvim targets *only* the latest
['stable'](https://github.com/neovim/neovim/releases/tag/stable) and latest
['nightly'](https://github.com/neovim/neovim/releases/tag/nightly) of neovim.
if you are experiencing issues, please make sure you have at least the latest
stable version. Most likely, you want to install neovim via a [package
manager](https://github.com/neovim/neovim/blob/master/INSTALL.md#install-from-package).
to check your neovim version, run `nvim --version` and make sure it is not
below the latest
['stable'](https://github.com/neovim/neovim/releases/tag/stable) version. if
your chosen install method only gives you an outdated version of neovim, find
alternative [installation methods below](#alternative-neovim-installation-methods).

### install external dependencies

external requirements:
- basic utils: `git`, `make`, `unzip`, C compiler (`gcc`)
- [ripgrep](https://github.com/BurntSushi/ripgrep#installation),
  [fd-find](https://github.com/sharkdp/fd#installation)
- [tree-sitter CLI](https://github.com/tree-sitter/tree-sitter/blob/master/crates/cli/README.md#installation)
- clipboard tool (xclip/xsel/win32yank or other depending on the platform)
- a [nerd font](https://www.nerdfonts.com/): optional, provides various icons
  - if you have it set `vim.g.have_nerd_font` in `init.lua` to true
- emoji fonts (ubuntu only, and only if you want emoji!) `sudo apt install fonts-noto-color-emoji`
- language setup:
  - if you want to write typescript, you need `npm`
  - if you want to write golang, you will need `go`
  - etc.

> [!NOTE]
> see [install recipes](#Install-Recipes) for additional Windows and Linux specific notes
> and quick install snippets

### install rustle.nvim

> [!NOTE]
> [backup](#FAQ) your previous configuration (if any exists)

neovim's configurations are located under the following paths, depending on your OS:

| OS | PATH |
| :- | :--- |
| Linux, MacOS | `$XDG_CONFIG_HOME/nvim`, `~/.config/nvim` |
| Windows (cmd)| `%localappdata%\nvim\` |
| Windows (powershell)| `$env:LOCALAPPDATA\nvim\` |

#### clone rustle.nvim

<details><summary> Linux and Mac </summary>

```sh
git clone https://github.com/arozoid/rustle.nvim.git "${XDG_CONFIG_HOME:-$HOME/.config}"/nvim
```

</details>

<details><summary> Windows </summary>

if you're using `cmd.exe`:

```
git clone https://github.com/arozoid/rustle.nvim.git "%localappdata%\nvim"
```

if you're using `powershell.exe`

```
git clone https://github.com/arozoid/rustle.nvim.git "${env:LOCALAPPDATA}\nvim"
```

</details>

### post installation

start neovim

```sh
nvim
```

that's it! lazy will install all the plugins you have. use `:Lazy` to view
the current plugin status. hit `q` to close the window.

#### read the friendly documentation

read through the `init.lua` file in your configuration folder for more
information about extending and exploring neovim. that also includes
examples of adding popularly requested plugins.

> [!NOTE]
> for more information about a particular plugin, check its repository's documentation.


### getting started

[The Only Video You Need to Get Started with Neovim](https://youtu.be/m8C0Cq9Uv9o)

### FAQ

* what should i do if i already have a pre-existing neovim configuration?
  * you should back it up and then delete all associated files.
  * this includes your existing init.lua and the Neovim files in `~/.local`
    which can be deleted with `rm -rf ~/.local/share/nvim/`
* can I keep my existing configuration in parallel to kickstart?
  * yes! You can use [NVIM_APPNAME](https://neovim.io/doc/user/starting.html#%24NVIM_APPNAME)`=nvim-NAME`
    to maintain multiple configurations. for example, you can install the rustle.nvim
    configuration in `~/.config/nvim-rustle` and create an alias:
    ```
    alias nvim-rstl='NVIM_APPNAME="nvim-rustle" nvim'
    ```
    when you run neovim using `nvim-rstl` alias, it will use the alternative
    config directory and the matching local directory
    `~/.local/share/nvim-kickstart`. you can apply this approach to any neovim
    distribution that you would like to try out.
* what if i want to "uninstall" this configuration:
  * see [lazy.nvim uninstall](https://lazy.folke.io/usage#-uninstalling) information

### install recipes

below you can find OS specific install instructions for neovim and dependencies.

after installing all the dependencies, continue with the [Install Kickstart](#install-kickstart) step.

#### windows installation

<details><summary>windows with microsoft C++ build tools and CMake</summary>
installation may require installing build tools and updating the run command for `telescope-fzf-native`

see `telescope-fzf-native` documentation for [more details](https://github.com/nvim-telescope/telescope-fzf-native.nvim#installation)

this requires:

- install CMake and the microsoft C++ build tools on windows

```lua
{'nvim-telescope/telescope-fzf-native.nvim', build = 'cmake -S. -Bbuild -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release && cmake --install build --prefix build' }
```
</details>
<details><summary>windows with gcc/make using chocolatey</summary>
alternatively, one can install gcc and make which don't require changing the config,
the easiest way is to use choco:

1. install [chocolatey](https://chocolatey.org/install)
either follow the instructions on the page or use winget,
run in cmd as **admin**:
```
winget install --accept-source-agreements chocolatey.chocolatey
```

2. install all requirements using choco, exit the previous cmd and
open a new one so that choco path is set, and run in cmd as **admin**:
```
choco install -y neovim git ripgrep wget fd unzip gzip mingw make tree-sitter
```
</details>
<details><summary>WSL (Windows Subsystem for Linux)</summary>

```
wsl --install
wsl
sudo add-apt-repository ppa:neovim-ppa/unstable -y
sudo apt update
sudo apt install make gcc ripgrep fd-find tree-sitter-cli unzip git xclip neovim
```
</details>

#### linux install
<details><summary>ubuntu install steps</summary>

```
sudo add-apt-repository ppa:neovim-ppa/unstable -y
sudo apt update
sudo apt install make gcc ripgrep fd-find tree-sitter-cli unzip git xclip neovim
```
</details>
<details><summary>debian install steps</summary>

```
sudo apt update
sudo apt install make gcc ripgrep fd-find tree-sitter-cli unzip git xclip curl

# Now we install nvim
curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
sudo rm -rf /opt/nvim-linux-x86_64
sudo mkdir -p /opt/nvim-linux-x86_64
sudo chmod a+rX /opt/nvim-linux-x86_64
sudo tar -C /opt -xzf nvim-linux-x86_64.tar.gz

# make it available in /usr/local/bin, distro installs to /usr/bin
sudo ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/
```
</details>
<details><summary>fedora install steps</summary>

```
sudo dnf install -y gcc make git ripgrep fd-find tree-sitter-cli unzip neovim
```
</details>

<details><summary>arch install steps</summary>

```
sudo pacman -S --noconfirm --needed gcc make git ripgrep fd tree-sitter-cli unzip neovim
```
</details>

### alternative neovim installation methods

for some systems it is not unexpected that the [package manager installation
method](https://github.com/neovim/neovim/blob/master/INSTALL.md#install-from-package)
recommended by neovim is significantly behind. if that is the case for you,
pick one of the following methods that are known to deliver fresh neovim versions very quickly.
they have been picked for their popularity and because they make installing and updating
neovim to the latest versions easy. you can also find more detail about the
available methods being discussed
[here.](https://github.com/nvim-lua/kickstart.nvim/issues/1583).


<details><summary>bob</summary>

[bob](https://github.com/MordechaiHadad/bob) is a neovim version manager for
all platforms. simply install
[rustup](https://rust-lang.github.io/rustup/installation/other.html),
and run the following commands:

```bash
rustup default stable
rustup update stable
cargo install bob-nvim
bob use stable
```

</details>

<details><summary>homebrew</summary>

[homebrew](https://brew.sh) is a package manager popular on Mac and Linux.
simply install using [`brew install`](https://formulae.brew.sh/formula/neovim).

</details>

<details><summary>flatpak</summary>

flatpak is a package manager for applications that allows developers to package their applications
just once to make it available on all Linux systems. simply [install flatpak](https://flatpak.org/setup/)
and setup [flathub](https://flathub.org/setup) to [install neovim](https://flathub.org/apps/io.neovim.nvim).

</details>

<details><summary>asdf and mise-en-place</summary>

[asdf](https://asdf-vm.com/) and [mise](https://mise.jdx.dev/) are tool version managers,
mostly aimed towards project-specific tool versioning. however, both support managing tools
globally in the user-space as well:

<details><summary>mise</summary>

[install mise](https://mise.jdx.dev/getting-started.html), then run:

```bash
mise plugins install neovim
mise use neovim@stable
```

</details>

<details><summary>asdf</summary>

[install asdf](https://asdf-vm.com/guide/getting-started.html), then run:

```bash
asdf plugin add neovim
asdf install neovim stable
asdf set neovim stable --home
asdf reshim neovim
```

</details>

</details>
