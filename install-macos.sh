#!/bin/bash

# Exit script on command failure
set -e

DATE=$(date +%s)
BASE_DIR=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)
BACKUP_DIR=$BASE_DIR/.backup

# Common bash variables and functions
source $BASE_DIR/bash_functions

function heading {
    echo -e "\n${underline}$@${normal}"
}

function backup_and_symlink {
    local src_path=$1
    local dst_link=$2
    if [[ -e $dst_link && ! -L $dst_link ]]; then
        local backup_path=${BACKUP_DIR}/$(basename $src_path)-$(basename $dst_link)-${DATE}
        warn "File or directory exists at $dst_link - backing up to $backup_path"
        mv $dst_link $backup_path
    fi
    info "Symlinking $dst_link -> $src_path"
    ln -snf $src_path $dst_link
}

function brew_install {
    local package=$1
    if ! brew list $package > /dev/null 2>&1; then
        info Installing $package
        brew install $package
    fi
    info $package installed
}

function brew_check_and_upgrade_version {
    local package=$1
    local version=$2
    if ! brew list --versions -l $package | grep -E " $version(_[0-9])?( .+)?\$" > /dev/null; then
        local stable_version=$(brew info --json $package | jq -r '.[0].versions.stable')
        if [[ "$stable_version" != "$version" ]]; then
            error $package $version not available as a stable version via HomeBrew
            exit 1
        fi
        if brew list $package > /dev/null 2>&1; then
            info Upgrading $package
            brew upgrade $package
        else
            info Installing $package
            brew install $package
        fi
    fi
    info $package $version installed
}

function create_ruby_env {
    local rubyversion=$1
    local rubypatchlevel=$2
    local depsfile=$3

    # Install Ruby version
    if ! rvm list strings | grep "^ruby-$rubyversion\$" > /dev/null; then
        # https://stackoverflow.com/questions/37336573/unable-to-require-openssl-install-openssl-and-rebuild-ruby-preferred-or-use-n
        local openssldir=$(brew --prefix openssl)
        info Installing Ruby $rubyversion
        rvm install $rubyversion -l $rubypatchlevel --with-openssl-dir=$openssldir
    fi

    # Install/update gem dependencies
    info Updating Ruby dependencies
    rvm $rubyversion \do gem install --file $depsfile
}

heading "Install Xcode tools and Homebrew"
if ! 'xcode-select' -p > /dev/null 2>&1; then
    'xcode-select' --install
fi
if ! command -v brew > /dev/null 2>&1; then
    ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
fi

heading "Create common directories"
for d in .bin .profile.d .bash_profile.d .config; do
    info Creating $HOME/$d
    mkdir -p $HOME/$d
done

heading "Install common packages"
for p in bash-completion git jq htop sqlite zlib; do
    brew_install $p
done

heading "Install Bash config"
backup_and_symlink $BASE_DIR/bash/profile $HOME/.profile
backup_and_symlink $BASE_DIR/bash/bash_profile $HOME/.bash_profile
backup_and_symlink $BASE_DIR/bash/virtualenvify.sh $HOME/.bin/virtualenvify

heading "Install ssh config"
mkdir -p $HOME/.ssh
chmod 700 $HOME/.ssh
backup_and_symlink $BASE_DIR/ssh/config $HOME/.ssh/config
backup_and_symlink $BASE_DIR/ssh/bash_profile_macos $HOME/.bash_profile.d/00-ssh

heading "Install tig"
TIG_VERSION=2.4.1
brew_check_and_upgrade_version tig $TIG_VERSION

heading "Install Git config"
backup_and_symlink $BASE_DIR/git/gitconfig $HOME/.gitconfig
backup_and_symlink $BASE_DIR/git/gitignore $HOME/.gitignore
for f in $BASE_DIR/git/bin/*; do
    backup_and_symlink $f /usr/local/bin/$(basename $f)
done

heading "Install Neovim"
NVIM_VERSION=0.3.4
NVIM_INSTALL_PATH="$HOME/nvim-${NVIM_VERSION}-osx64"
if ! nvim --version 2>/dev/null | grep "v$NVIM_VERSION" > /dev/null; then
    NVIM_DOWNLOAD_PATH="$(mktemp -d)/nvim-macos-${NVIM_VERSION}.tar.gz"
    NVIM_INSTALL_SYMLINK="$HOME/nvim-osx64"
    NVIM_RELEASE_URL="https://github.com/neovim/neovim/releases/download/v${NVIM_VERSION}/nvim-macos.tar.gz"

    info Downloading and unzipping NVIM v$NVIM_VERSION to $NVIM_INSTALL_PATH
    curl -sL -o $NVIM_DOWNLOAD_PATH $NVIM_RELEASE_URL
    temp_dir=$(mktemp -d)
    tar -C $temp_dir -xf $NVIM_DOWNLOAD_PATH
    rm -rf $NVIM_INSTALL_PATH
    mv $temp_dir/nvim-osx64 $NVIM_INSTALL_PATH
    backup_and_symlink $NVIM_INSTALL_PATH $NVIM_INSTALL_SYMLINK
fi
backup_and_symlink $NVIM_INSTALL_PATH/bin/nvim /usr/local/bin/nvim
info "NVIM v$NVIM_VERSION installed"

heading "Install Vim/Neovim config"
backup_and_symlink $BASE_DIR/vim/init.vim $HOME/.vimrc
backup_and_symlink $BASE_DIR/vim $HOME/.vim
backup_and_symlink $BASE_DIR/vim $HOME/.config/nvim
# Ensure plugin submodules have been initialized (none of the status lines should be prefixed with
# '-')
if git submodule status | grep "^-" > /dev/null; then
    git submodule update --init
fi

heading "Install AWS config"
backup_and_symlink $BASE_DIR/aws $HOME/.aws

heading "Install RVM"
if ! rvm --version > /dev/null 2>&1; then
    RVM_RELEASE_URL="https://get.rvm.io"

    # https://rvm.io/rvm/install
    info Installing RVM from $RVM_RELEASE_URL
    export rvm_ignore_dotfiles=yes
    curl -sSL $RVM_RELEASE_URL | bash -s stable
fi

heading "Install RVM config"
backup_and_symlink $BASE_DIR/rvm/profile $HOME/.profile.d/10-rvm

heading "Install Ruby versions"
# Install Ruby 2.3.7 with required Neovim dependencies and set as default
create_ruby_env 2.3.7 456 $BASE_DIR/vim/rubyenv/ruby2.3.7-gem.deps.rb
rvm alias create default 2.3.7

heading "Install Pyenv"
PYENV_VERSION=1.2.9
brew_check_and_upgrade_version pyenv $PYENV_VERSION
brew_install pyenv-virtualenv

heading "Install PyEnv config"
backup_and_symlink $BASE_DIR/pyenv/profile $HOME/.profile.d/20-pyenv

# To install: https://github.com/jigish/slate#installing-slate
heading "Install Slate config"
backup_and_symlink $BASE_DIR/slate/slate.js $HOME/.slate.js

heading "Install Tmux"
TMUX_VERSION=2.8
brew_check_and_upgrade_version tmux $TMUX_VERSION

heading "Install Tmux config"
backup_and_symlink $BASE_DIR/tmux/tmux.conf $HOME/.tmux.conf
mkdir -p $HOME/.tmux
backup_and_symlink $BASE_DIR/tmux/plugins $HOME/.tmux/plugins

heading "Install Yamllint config"
backup_and_symlink $BASE_DIR/yamllint $HOME/.config/yamllint

heading "Install Flake8 config"
backup_and_symlink $BASE_DIR/flake8/config $HOME/.config/flake8

heading "Install eslint config"
backup_and_symlink $BASE_DIR/eslint/eslintrc $HOME/.eslintrc

heading "Install htop config"
backup_and_symlink $BASE_DIR/htop $HOME/.config/htop

heading "Install Docker"
if ! docker version > /dev/null 2>&1; then
    DOCKER_DOWNLOAD_PATH="$(mktemp -d)/Docker.dmg"
    DOCKER_RELEASE_URL="https://download.docker.com/mac/stable/Docker.dmg"
    DOCKER_MOUNT_PATH="$(mktemp -d)/Docker_Volume"

    info Downloading Docker OSX image
    curl -sL -o $DOCKER_DOWNLOAD_PATH $DOCKER_RELEASE_URL

    info Mounting image and installing Docker application
    hdiutil attach $DOCKER_DOWNLOAD_PATH -nobrowse -noautoopen -mountpoint $DOCKER_MOUNT_PATH
    cp -r $DOCKER_MOUNT_PATH/Docker.app /Applications
    hdiutil detach $DOCKER_MOUNT_PATH

    info Starting Docker daemon
    open --hide --background -a Docker
fi
until command -v docker > /dev/null 2>&1; do
    echo "Waiting for Docker installation..."
    sleep 2
done
DOCKER_VERSION=$(echo $(docker system info | grep Server.Version | cut -d: -f2))
info "Docker $DOCKER_VERSION installed"
