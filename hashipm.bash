#!/usr/bin/env bash

###############################################################################
# Copyright 2018 Elastic Byte
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
###############################################################################

set -eo pipefail; [[ $TRACE ]] && set -x

readonly NAME="hashipm"
readonly VERSION="0.6.3"
INSTALL_PATH="/usr/local/bin"

bash_version=${BASH_VERSION/.*}
sys_locale=${LANG:-C}
XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-${HOME}/.config}
#PATH=$PATH:/usr/xpg4/bin:/usr/sbin:/sbin:/usr/etc:/usr/libexec
reset='\e[0m'
shopt -s nocasematch

# Speed up script by not using unicode.
LC_ALL=C
LANG=C

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]" "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b"
    done
}

_version() {
    echo "$NAME v$VERSION"
    echo
}

_help() {
    echo "Usage: $NAME [--version] [--help] command [command-specific-args]"
    echo
    cat<<EOF | column -c2 -t -s,
    get <package>, Download and install package
EOF
}

_get() {
    local package=$1

    if [ -z "$package" ]; then
        echo "Argument <package> is required" 1>&2
        exit 4
    fi

    if [ -z "$HASHIPM_ROOT" ]; then
        echo "Environment variable '\$HASHIPM_ROOT' is not set" 1>&2
        exit 5
    fi

    local yaml_path="$HASHIPM_ROOT/packages/$package/index.yaml"

    if [ ! -f "$yaml_path" ]; then
        echo "Package '$package' not found" 1>&2
        exit 6
    fi

    local os
    #case "$OSTYPE" in
    case "$(uname -s)" in
        darwin*)  os="darwin" ;;
        freebsd*) os="freebsd" ;;
        netbsd*)  os="netbsd" ;;
        openbsd*) os="openbsd" ;;
        solaris*) os="solaris" ;;
        sunos*)  os="solaris" ;;
        cygwin*) os="windows" ;;
        CYGWIN*|MSYS*|MINGW*) os="windows" ;;
        windows*|win*|dos*) os="windows" ;;
        linux*)   os="linux" ;;
        GNU*)   os="linux" ;;
        ;;

        *BSD|DragonFly|Bitrig)
            : BSD
        ;;

        CYGWIN*|MSYS*|MINGW*)
            : Windows
        ;;

        *)
            printf '%s\n' "Unknown OS detected: '$(uname -s)', aborting..." >&2
            printf '%s\n' "Open an issue on GitHub to add support for your OS." >&2
            exit 1
        ;;
    esac
        
    if [ -z "$os" ]; then
        echo "Failed to determine the operating system" 1>&2
        exit 7
    fi

    local architecture
    case $(uname -m) in
        i386)   architecture="386" ;;
        i686)   architecture="386" ;;
        x86)   architecture="386" ;;
        x86_64) architecture="amd64" ;;
        s390*) architecture="s390x" ;;
        arm)    dpkg --print-architecture | grep -q "arm64" && architecture="arm64" || architecture="arm" ;;
        powerpc*) architecture="ppc64le" ;;
        *mipsle*) architecture="mipsle" ;;
        *mips64) architecture="mips64" ;;
        mips) architecture="mips" ;;
    esac
    
    if [ -z "$architecture" ]; then
        echo "Failed to determine the architecture" 1>&2
        exit 8
    fi

    if [ ! -x "$(command -v unzip)" ]; then
        echo "Missing required dependency 'unzip'" 1>&2
        exit 9
    fi

    #local version=$(curl --fail --silent --location "https://api.github.com/repos/hashicorp/$package/tags" |
    #    grep '"name":' |
    #    sed -E 's/.*"([^"]+)".*/\1/' |
    #    head -n 1 |
    #    tr -d 'v')
    local version=$(curl --fail --silent --location "https://checkpoint-api.hashicorp.com/v1/check/$package" |
    grep '"current_version":'
    )

    if [ -z "$version" ]; then
        echo "Failed to determine the latest version of '$package'" 1>&2
        exit 10
    fi

    source "$HASHIPM_ROOT"/lib/yaml.sh
    create_variables "$yaml_path"

    VARNAME="${package}_${os}_${architecture}"
    local download_url="${!VARNAME}"

    if [ -z "$download_url" ]; then
        echo "Failed to determine the download url for '$package' on ${os}/${architecture}" 1>&2
        exit 11
    fi

    local tmp_path="/tmp/$package-$version.zip"

    echo "Downloading $package ($version) from $download_url..."

    (curl --fail --silent --location "$download_url" > "$tmp_path") &
    spinner $!

    if [ ! -f "$tmp_path" ]; then
        echo "Failed downloading $package ($version) from $download_url to $tmp_path" 1>&2
        exit 12
    fi

    if [[ ! -d $INSTALL_PATH ]]; then
        INSTALL_PATH="/usr/bin"
    fi

    ((EUID)) && sudo_cmd="sudo"
    $sudo_cmd unzip -q -o "$tmp_path" -d $INSTALL_PATH

    echo "Installed $package ($version) into $INSTALL_PATH"

    rm -f "$tmp_path"
}

_main() {
    local cmd="$1"

    if [[ -z $cmd ]]; then
        _help 1>&2
        exit 3
    fi

    shift 1
    case "$cmd" in
        "get")
            _get "$@"
            ;;

        "--version")
            _version
            ;;

        "--help")
            _help
            ;;

        *)
            _help 1>&2
            exit 3
    esac
}

if [[ "$0" == "$BASH_SOURCE" ]]; then
    _main "$@"
fi
