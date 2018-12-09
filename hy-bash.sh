################################################################################
# HY-BASH
# is based on LIQUID PROMPT
################################################################################


################################################################################
# LIQUID PROMPT
# An intelligent and non-intrusive prompt for Bash and zsh
################################################################################


# Licensed under the AGPL version 3
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

###########
# AUTHORS #
###########

# Alex Prengère     <alexprengere@gmail.com>      # Untracked git files
# Anthony Gelibert  <anthony.gelibert@me.com>     # Several fix
# Aurelien Requiem  <aurelien@requiem.fr>         # Major clean refactoring, variable path length, error codes, several bugfixes.
# Brendan Fahy      <bmfahy@gmail.com>            # Postfix variable
# Clément Mathieu   <clement@unportant.info>      # Bazaar support
# David Loureiro    <david.loureiro@sysfera.com>  # Small portability fix
# Étienne Deparis   <etienne@depar.is>            # Fossil support
# Florian Le Frioux <florian@lefrioux.fr>         # Use ± mark when root in VCS dir.
# François Schmidts <francois.schmidts@gmail.com> # Initial PROMPT_DIRTRIM support
# Frédéric Lepied   <flepied@gmail.com>           # Python virtual env
# Jonas Bengtsson   <jonas.b@gmail.com>           # Git remotes fix
# Joris Dedieu      <joris@pontiac3.nfrance.com>  # Portability framework, FreeBSD support, bugfixes.
# Joris Vaillant    <joris.vaillant@gmail.com>    # Small git fix
# Luc Didry         <luc@fiat-tux.fr>             # ZSH port, several fix
# Ludovic Rousseau  <ludovic.rousseau@gmail.com>  # Lot of bugfixes.
# Markus Dreseler   <github@dreseler.de>          # Runtime of last command
# Nicolas Lacourte  <nicolas@dotinfra.fr>         # Screen title
# nojhan            <nojhan@gmail.com>            # Original author.
# Olivier Mengué    <dolmen@cpan.org>             # Major optimizations, refactorings everywhere; current maintainer
# Poil              <poil@quake.fr>               # Speed improvements
# Rolf Morel        <rolfmorel@gmail.com>         # "Shorten path" refactoring and fixes
# Thomas Debesse    <thomas.debesse@gmail.com>    # Fix columns use.
# Yann 'Ze' Richard <ze@nbox.org>                 # Do not fail on missing commands.
# Austen Adler      <stonewareslord@gmail.com>    # ZSH runtime

# See the README.md file for a summary of features.

# Issue #161: do not load if not an interactive shell
test -z "$TERM" -o "x$TERM" = xdumb && return

# Check for recent enough version of bash.
if test -n "${BASH_VERSION-}" -a -n "$PS1" ; then
    bash=${BASH_VERSION%.*}; bmajor=${bash%.*}; bminor=${bash#*.}
    if (( bmajor < 3 || ( bmajor == 3 && bminor < 2 ) )); then
        unset bash bmajor bminor
        return
    fi

    unset bash bmajor bminor

    _LP_SHELL_bash=true
    _LP_SHELL_zsh=false
    _LP_OPEN_ESC="\["
    _LP_CLOSE_ESC="\]"

    _LP_USER_SYMBOL="\u"
    _LP_HOST_SYMBOL="\h"
    _LP_FQDN_SYMBOL="\H"
    _LP_TIME_SYMBOL="\t"
    _LP_MARK_SYMBOL='\$'
    _LP_PWD_SYMBOL="\\w"
    _LP_DIR_SYMBOL="\\W"

    _LP_FIRST_INDEX=0
    _LP_PERCENT='%'    # must be escaped on zsh
    _LP_BACKSLASH='\\' # must be escaped on bash

    # Escape the given strings
    # Must be used for all strings injected in PS1 that may comes from remote sources,
    # like $PWD, VCS branch names...
    _lp_escape()
    {
        echo -nE "${1//\\/\\\\}"
    }

    # Disable the DEBUG trap used by the RUNTIME feature
    # (in case we are reloading LP in the same shell after disabling
    # the feature in .liquidpromptrc)
    # FIXME this doesn't seem to work :(
    [[ -n "${LP_ENABLE_RUNTIME-}" ]] && trap - DEBUG
elif test -n "${ZSH_VERSION-}" ; then
    _LP_SHELL_bash=false
    _LP_SHELL_zsh=true
    _LP_OPEN_ESC="%{"
    _LP_CLOSE_ESC="%}"

    _LP_USER_SYMBOL="%n"
    _LP_HOST_SYMBOL="%m"
    _LP_FQDN_SYMBOL="%M"
    _LP_TIME_SYMBOL="%*"
    _LP_MARK_SYMBOL='%(!.#.%%)'
    _LP_PWD_SYMBOL="%~"
    _LP_DIR_SYMBOL="%1~"

    _LP_FIRST_INDEX=1
    _LP_PERCENT='%%'
    _LP_BACKSLASH="\\"

    _lp_escape()
    {
        arg="${1//\\/\\\\}"
        echo -nE "${arg//\%/$_LP_PERCENT}"
    }

    # For ZSH, autoload required functions
    autoload -Uz add-zsh-hook

    # Disable previous hooks as options that set them
    # may have changed
    {
        add-zsh-hook -d precmd  _lp_set_prompt
        add-zsh-hook -d preexec _lp_runtime_before
        add-zsh-hook -d precmd  _lp_runtime_after
    } >/dev/null
else
    echo "liquidprompt: shell not supported" >&2
    return
fi


# Store $2 (or $?) as a true/false value in variable named $1
# $? is propagated
#   _lp_bool foo 5
#   => foo=false
#   _lp_bool foo 0
#   => foo=true
_lp_bool()
{
    local res=${2:-$?}
    if (( res )); then
        eval $1=false
    else
        eval $1=true
    fi
    return $res
}

# Save $IFS as we want to restore the default value at the beginning of the
# prompt function
_LP_IFS="$IFS"


###############
# OS specific #
###############

# LP_OS detection, default to Linux
case $(uname) in
    FreeBSD)   LP_OS=FreeBSD ;;
    DragonFly) LP_OS=FreeBSD ;;
    OpenBSD)   LP_OS=OpenBSD ;;
    Darwin)    LP_OS=Darwin  ;;
    SunOS)     LP_OS=SunOS   ;;
    *)         LP_OS=Linux   ;;
esac

# Get cpu count
case "$LP_OS" in
    Linux)   _lp_CPUNUM=$( nproc 2>/dev/null || \grep -c '^[Pp]rocessor' /proc/cpuinfo ) ;;
    FreeBSD|Darwin|OpenBSD) _lp_CPUNUM=$( sysctl -n hw.ncpu ) ;;
    SunOS)   _lp_CPUNUM=$( kstat -m cpu_info | \grep -c "module: cpu_info" ) ;;
esac

# Extended regexp patterns for sed
# GNU/BSD sed
_LP_SED_EXTENDED=r
[[ "$LP_OS" = Darwin ]] && _LP_SED_EXTENDED=E


# get current load
case "$LP_OS" in
    Linux)
        _lp_cpu_load () {
            local eol
            read lp_cpu_load eol < /proc/loadavg
        }
        ;;
    FreeBSD|Darwin|OpenBSD)
        _lp_cpu_load () {
            local bol eol
            # If you have problems with syntax coloring due to the following
            # line, do this: ln -s liquidprompt liquidprompt.bash
            # and edit liquidprompt.bash
            read bol lp_cpu_load eol <<<"$( LC_ALL=C sysctl -n vm.loadavg )"
        }
        ;;
    SunOS)
        _lp_cpu_load () {
            read lp_cpu_load <<<"$( LC_ALL=C uptime | sed 's/.*load average: *\([0-9.]*\).*/\1/' )"
        }
esac


#################
# CONFIGURATION #
#################

# The following code is run just once. But it is encapsulated in a function
# to benefit of 'local' variables.
#
# What we do here:
# 1. Setup variables that can be used by the user: the "API" of Liquid Prompt
#    for config/theme. Those variables are local to the function.
#    In practice, this is only color variables.
# 2. Setup default values
# 3. Load the configuration
_lp_source_config()
{

    # TermInfo feature detection
    local ti_sgr0="$( { tput sgr0 || tput me ; } 2>/dev/null )"
    local ti_bold="$( { tput bold || tput md ; } 2>/dev/null )"
    local ti_setaf
    local ti_setab
    if tput setaf 0 >/dev/null 2>&1; then
        ti_setaf() { tput setaf "$1" ; }
    elif tput AF 0 >/dev/null 2>&1; then
        # FreeBSD
        ti_setaf() { tput AF "$1" ; }
    elif tput AF 0 0 0 >/dev/null 2>&1; then
        # OpenBSD
        ti_setaf() { tput AF "$1" 0 0 ; }
    else
        echo "liquidprompt: terminal $TERM not supported" >&2
        ti_setaf () { : ; }
    fi
    if tput setab 0 >/dev/null 2>&1; then
        ti_setab() { tput setab "$1" ; }
    elif tput AB 0 >/dev/null 2>&1; then
        # FreeBSD
        ti_setab() { tput AB "$1" ; }
    elif tput AB 0 0 0 >/dev/null 2>&1; then
        # OpenBSD
        ti_setab() { tput AB "$1" 0 0 ; }
    else
        echo "liquidprompt: terminal $TERM not supported" >&2
        ti_setab() { : ; }
    fi

    # Colors: variables are local so they will have a value only
    # during config loading and will not conflict with other values
    # with the same names defined by the user outside the config.
    local BOLD="${_LP_OPEN_ESC}${ti_bold}${_LP_CLOSE_ESC}"

    local BLACK="${_LP_OPEN_ESC}$(ti_setaf 0)${_LP_CLOSE_ESC}"
    local BOLD_GRAY="${_LP_OPEN_ESC}${ti_bold}$(ti_setaf 0)${_LP_CLOSE_ESC}"
    local WHITE="${_LP_OPEN_ESC}$(ti_setaf 7)${_LP_CLOSE_ESC}"
    local BOLD_WHITE="${_LP_OPEN_ESC}${ti_bold}$(ti_setaf 7)${_LP_CLOSE_ESC}"

    local RED="${_LP_OPEN_ESC}$(ti_setaf 1)${_LP_CLOSE_ESC}"
    local BOLD_RED="${_LP_OPEN_ESC}${ti_bold}$(ti_setaf 1)${_LP_CLOSE_ESC}"
    local WARN_RED="${_LP_OPEN_ESC}$(ti_setaf 0 ; ti_setab 1)${_LP_CLOSE_ESC}"
    local CRIT_RED="${_LP_OPEN_ESC}${ti_bold}$(ti_setaf 7 ; ti_setab 1)${_LP_CLOSE_ESC}"
    local DANGER_RED="${_LP_OPEN_ESC}${ti_bold}$(ti_setaf 3 ; ti_setab 1)${_LP_CLOSE_ESC}"

    local GREEN="${_LP_OPEN_ESC}$(ti_setaf 2)${_LP_CLOSE_ESC}"
    local BOLD_GREEN="${_LP_OPEN_ESC}${ti_bold}$(ti_setaf 2)${_LP_CLOSE_ESC}"

    local YELLOW="${_LP_OPEN_ESC}$(ti_setaf 3)${_LP_CLOSE_ESC}"
    local BOLD_YELLOW="${_LP_OPEN_ESC}${ti_bold}$(ti_setaf 3)${_LP_CLOSE_ESC}"

    local BLUE="${_LP_OPEN_ESC}$(ti_setaf 4)${_LP_CLOSE_ESC}"
    local BOLD_BLUE="${_LP_OPEN_ESC}${ti_bold}$(ti_setaf 4)${_LP_CLOSE_ESC}"

    local PURPLE="${_LP_OPEN_ESC}$(ti_setaf 5)${_LP_CLOSE_ESC}"
    local PINK="${_LP_OPEN_ESC}${ti_bold}$(ti_setaf 5)${_LP_CLOSE_ESC}"

    local CYAN="${_LP_OPEN_ESC}$(ti_setaf 6)${_LP_CLOSE_ESC}"
    local BOLD_CYAN="${_LP_OPEN_ESC}${ti_bold}$(ti_setaf 6)${_LP_CLOSE_ESC}"

    # NO_COL is special: it will be used at runtime, not just during config loading
    NO_COL="${_LP_OPEN_ESC}${ti_sgr0}${_LP_CLOSE_ESC}"

    # compute the hash of the hostname
    # and get the corresponding number in [1-6] (red,green,yellow,blue,purple or cyan)
    # FIXME Add more formats (bold? 256 colors?)
    # cksum is separated with tab on SunOS, space on others
    local cksum="$(hostname | cksum)"
    LP_COLOR_HOST_HASH="${_LP_OPEN_ESC}$(ti_setaf $(( 1 + ${cksum%%[ 	]*} % 6 )) )${_LP_CLOSE_ESC}"

    unset ti_sgr0 ti_bold
    unset -f ti_setaf ti_setab


    # Default values (globals)
    LP_BATTERY_THRESHOLD=${LP_BATTERY_THRESHOLD:-75}
    LP_LOAD_THRESHOLD=${LP_LOAD_THRESHOLD:-60}
    LP_TEMP_THRESHOLD=${LP_TEMP_THRESHOLD:-60}
    LP_RUNTIME_THRESHOLD=${LP_RUNTIME_THRESHOLD:-2}
    LP_PATH_LENGTH=${LP_PATH_LENGTH:-35}
    LP_PATH_KEEP=${LP_PATH_KEEP:-2}
    LP_PATH_DEFAULT="${LP_PATH_DEFAULT:-$_LP_PWD_SYMBOL}"
    LP_HOSTNAME_ALWAYS=${LP_HOSTNAME_ALWAYS:-0}
    LP_USER_ALWAYS=${LP_USER_ALWAYS:-1}
    LP_PERCENTS_ALWAYS=${LP_PERCENTS_ALWAYS:-1}
    LP_PS1=${LP_PS1:-""}
    LP_PS1_PREFIX=${LP_PS1_PREFIX:-""}
    LP_PS1_POSTFIX=${LP_PS1_POSTFIX:-""}

    LP_ENABLE_PERM=${LP_ENABLE_PERM:-1}
    LP_ENABLE_SHORTEN_PATH=${LP_ENABLE_SHORTEN_PATH:-1}
    LP_ENABLE_PROXY=${LP_ENABLE_PROXY:-1}
    LP_ENABLE_TEMP=${LP_ENABLE_TEMP:-1}
    LP_ENABLE_JOBS=${LP_ENABLE_JOBS:-1}
    LP_ENABLE_LOAD=${LP_ENABLE_LOAD:-1}
    LP_ENABLE_BATT=${LP_ENABLE_BATT:-1}
    LP_ENABLE_GIT=${LP_ENABLE_GIT:-1}
    LP_ENABLE_SVN=${LP_ENABLE_SVN:-1}
    LP_ENABLE_VCSH=${LP_ENABLE_VCSH:-1}
    LP_ENABLE_FOSSIL=${LP_ENABLE_FOSSIL:-1}
    LP_ENABLE_HG=${LP_ENABLE_HG:-1}
    LP_ENABLE_BZR=${LP_ENABLE_BZR:-1}
    LP_ENABLE_TIME=${LP_ENABLE_TIME:-0}
    LP_ENABLE_RUNTIME=${LP_ENABLE_RUNTIME:-1}
    LP_ENABLE_VIRTUALENV=${LP_ENABLE_VIRTUALENV:-1}
    LP_ENABLE_SCLS=${LP_ENABLE_SCLS:-1}
    LP_ENABLE_VCS_ROOT=${LP_ENABLE_VCS_ROOT:-0}
    LP_ENABLE_TITLE=${LP_ENABLE_TITLE:-0}
    LP_ENABLE_SCREEN_TITLE=${LP_ENABLE_SCREEN_TITLE:-0}
    LP_ENABLE_SSH_COLORS=${LP_ENABLE_SSH_COLORS:-0}
    LP_ENABLE_FQDN=${LP_ENABLE_FQDN:-0}
    # LP_DISABLED_VCS_PATH="${LP_DISABLED_VCS_PATH}"
    LP_ENABLE_SUDO=${LP_ENABLE_SUDO:-0}

    LP_MARK_DEFAULT="${LP_MARK_DEFAULT:-$_LP_MARK_SYMBOL}"
    LP_MARK_BATTERY="${LP_MARK_BATTERY:-"⌁"}"
    LP_MARK_ADAPTER="${LP_MARK_ADAPTER:-"⏚"}"
    LP_MARK_LOAD="${LP_MARK_LOAD:-"⌂"}"
    LP_MARK_TEMP="${LP_MARK_TEMP:-"θ"}"
    LP_MARK_PROXY="${LP_MARK_PROXY:-"↥"}"
    LP_MARK_HG="${LP_MARK_HG:-"☿"}"
    LP_MARK_SVN="${LP_MARK_SVN:-"‡"}"
    LP_MARK_GIT="${LP_MARK_GIT:-"±"}"
    LP_MARK_VCSH="${LP_MARK_VCSH:-"|"}"
    LP_MARK_FOSSIL="${LP_MARK_FOSSIL:-"⌘"}"
    LP_MARK_BZR="${LP_MARK_BZR:-"⚯"}"
    LP_MARK_DISABLED="${LP_MARK_DISABLED:-"⌀"}"
    LP_MARK_UNTRACKED="${LP_MARK_UNTRACKED:-"*"}"
    LP_MARK_STASH="${LP_MARK_STASH:-"+"}"
    LP_MARK_BRACKET_OPEN="${LP_MARK_BRACKET_OPEN:-"["}"
    LP_MARK_BRACKET_CLOSE="${LP_MARK_BRACKET_CLOSE:-"]"}"
    LP_MARK_SHORTEN_PATH="${LP_MARK_SHORTEN_PATH:-" … "}"
    LP_MARK_PREFIX="${LP_MARK_PREFIX:-" "}"
    LP_MARK_PERM="${LP_MARK_PERM:-":"}"

    LP_COLOR_PATH=${LP_COLOR_PATH:-$BOLD}
    LP_COLOR_PATH_ROOT=${LP_COLOR_PATH_ROOT:-$BOLD_YELLOW}
    LP_COLOR_PROXY=${LP_COLOR_PROXY:-$BOLD_BLUE}
    LP_COLOR_JOB_D=${LP_COLOR_JOB_D:-$YELLOW}
    LP_COLOR_JOB_R=${LP_COLOR_JOB_R:-$BOLD_YELLOW}
    LP_COLOR_JOB_Z=${LP_COLOR_JOB_Z:-$BOLD_YELLOW}
    LP_COLOR_ERR=${LP_COLOR_ERR:-$PURPLE}
    LP_COLOR_MARK=${LP_COLOR_MARK:-$BOLD}
    LP_COLOR_MARK_ROOT=${LP_COLOR_MARK_ROOT:-$BOLD_RED}
    LP_COLOR_MARK_SUDO=${LP_COLOR_MARK_SUDO:-$LP_COLOR_MARK_ROOT}
    LP_COLOR_USER_LOGGED=${LP_COLOR_USER_LOGGED:-""}
    LP_COLOR_USER_ALT=${LP_COLOR_USER_ALT:-$BOLD}
    LP_COLOR_USER_ROOT=${LP_COLOR_USER_ROOT:-$BOLD_YELLOW}
    LP_COLOR_HOST=${LP_COLOR_HOST:-""}
    LP_COLOR_SSH=${LP_COLOR_SSH:-$BLUE}
    LP_COLOR_SU=${LP_COLOR_SU:-$BOLD_YELLOW}
    LP_COLOR_TELNET=${LP_COLOR_TELNET:-$WARN_RED}
    LP_COLOR_X11_ON=${LP_COLOR_X11_ON:-$GREEN}
    LP_COLOR_X11_OFF=${LP_COLOR_X11_OFF:-$YELLOW}
    LP_COLOR_WRITE=${LP_COLOR_WRITE:-$GREEN}
    LP_COLOR_NOWRITE=${LP_COLOR_NOWRITE:-$RED}
    LP_COLOR_UP=${LP_COLOR_UP:-$GREEN}
    LP_COLOR_COMMITS=${LP_COLOR_COMMITS:-$YELLOW}
    LP_COLOR_COMMITS_BEHIND=${LP_COLOR_COMMITS_BEHIND:-$BOLD_RED}
    LP_COLOR_CHANGES=${LP_COLOR_CHANGES:-$RED}
    LP_COLOR_DIFF=${LP_COLOR_DIFF:-$PURPLE}
    LP_COLOR_CHARGING_ABOVE=${LP_COLOR_CHARGING_ABOVE:-$GREEN}
    LP_COLOR_CHARGING_UNDER=${LP_COLOR_CHARGING_UNDER:-$YELLOW}
    LP_COLOR_DISCHARGING_ABOVE=${LP_COLOR_DISCHARGING_ABOVE:-$YELLOW}
    LP_COLOR_DISCHARGING_UNDER=${LP_COLOR_DISCHARGING_UNDER:-$RED}
    LP_COLOR_TIME=${LP_COLOR_TIME:-$BLUE}
    LP_COLOR_IN_MULTIPLEXER=${LP_COLOR_IN_MULTIPLEXER:-$BOLD_BLUE}
    LP_COLOR_RUNTIME=${LP_COLOR_RUNTIME:-$YELLOW}
    LP_COLOR_VIRTUALENV=${LP_COLOR_VIRTUALENV:-$CYAN}

    if [[ -z "${LP_COLORMAP-}" ]]; then
        LP_COLORMAP=(
            ""               # 0
            "$GREEN"         # 1
            "$BOLD_GREEN"    # 2
            "$YELLOW"        # 3
            "$BOLD_YELLOW"   # 4
            "$RED"           # 5
            "$BOLD_RED"      # 6
            "$WARN_RED"      # 7
            "$CRIT_RED"      # 8
            "$DANGER_RED"    # 9
        )
    fi

    # Debugging flags
    LP_DEBUG_TIME=${LP_DEBUG_TIME:-0}


    local configfile

    # Default config file may be the XDG standard ~/.config/liquidpromptrc,
    # but heirloom dotfile has priority.

    if [[ -f "$HOME/.liquidpromptrc" ]]; then
        configfile="$HOME/.liquidpromptrc"
    else
        local first
        local search
        # trailing ":" is so that ${search#*:} always removes something
        search="${XDG_CONFIG_HOME:-"$HOME/.config"}:${XDG_CONFIG_DIRS:-/etc/xdg}:"
        while [[ -n "$search" ]]; do
            first="${search%%:*}"
            search="${search#*:}"
            if [[ -f "$first/liquidpromptrc" ]]; then
                configfile="$first/liquidpromptrc"
                break
            fi
        done
    fi

    if [[ -n "$configfile" ]]; then
        source "$configfile"
    elif [[ -f "/etc/liquidpromptrc" ]]; then
        source "/etc/liquidpromptrc"
    fi

    # Delete this code in version 1.11
    if [[ -n "${LP_COLORMAP_1-}" ]]; then
        echo "liquidprompt: LP_COLORMAP_x variables are deprecated. Update your theme to use LP_COLORMAP array." >&2
        LP_COLORMAP=(
            "$LP_COLORMAP_0"
            "$LP_COLORMAP_1"
            "$LP_COLORMAP_2"
            "$LP_COLORMAP_3"
            "$LP_COLORMAP_4"
            "$LP_COLORMAP_5"
            "$LP_COLORMAP_6"
            "$LP_COLORMAP_7"
            "$LP_COLORMAP_8"
            "$LP_COLORMAP_9"
        )
        unset LP_COLORMAP_0 LP_COLORMAP_1 LP_COLORMAP_2 LP_COLORMAP_3 LP_COLORMAP_4 \
              LP_COLORMAP_5 LP_COLORMAP_6 LP_COLORMAP_7 LP_COLORMAP_8 LP_COLORMAP_9
    fi
}
# do source config files
_lp_source_config
unset -f _lp_source_config

# Disable feature if the tool is not installed
_lp_require_tool()
{
    (( LP_ENABLE_$1 )) && { command -v $2 >/dev/null || eval LP_ENABLE_$1=0 ; }
}

_lp_require_tool GIT git
_lp_require_tool SVN svn
_lp_require_tool FOSSIL fossil
_lp_require_tool HG hg
_lp_require_tool BZR bzr

if [[ "$LP_OS" = Darwin ]]; then
    _lp_require_tool BATT pmset
else
    _lp_require_tool BATT acpi
fi

unset -f _lp_require_tool

if (( LP_ENABLE_JOBS )); then
    typeset -i _LP_ENABLE_DETACHED_SESSION _LP_ENABLE_SCREEN _LP_ENABLE_TMUX
    command -v screen >/dev/null ; _LP_ENABLE_SCREEN=!$?
    command -v tmux >/dev/null   ; _LP_ENABLE_TMUX=!$?
    (( _LP_ENABLE_DETACHED_SESSIONS = ( _LP_ENABLE_SCREEN || _LP_ENABLE_TMUX ) ))
fi

# Use standard path symbols inside Midnight Commander
[[ -n "${MC_SID-}" ]] && LP_ENABLE_SHORTEN_PATH=0

# If we are running in a terminal multiplexer, brackets are colored
if [[ "$TERM" == screen* ]]; then
    LP_BRACKET_OPEN="${LP_COLOR_IN_MULTIPLEXER}${LP_MARK_BRACKET_OPEN}${NO_COL}"
    LP_BRACKET_CLOSE="${LP_COLOR_IN_MULTIPLEXER}${LP_MARK_BRACKET_CLOSE}${NO_COL}"
    (( LP_ENABLE_TITLE = LP_ENABLE_TITLE && LP_ENABLE_SCREEN_TITLE ))
    LP_TITLE_OPEN="$(printf '\033k')"
    # "\e\" but on bash \ must be escaped
    LP_TITLE_CLOSE="$(printf '\033%s' "$_LP_BACKSLASH")"
else
    LP_BRACKET_OPEN="${LP_MARK_BRACKET_OPEN}"
    LP_BRACKET_CLOSE="${LP_MARK_BRACKET_CLOSE}"
    LP_TITLE_OPEN="$(printf '\e]0;')"
    LP_TITLE_CLOSE="$(printf '\a')"
fi

[[ "_$TERM" == _linux* ]] && LP_ENABLE_TITLE=0

# update_terminal_cwd is a shell function available on MacOS X Lion that
# will update an icon of the directory displayed in the title of the terminal
# window.
# See http://hints.macworld.com/article.php?story=20110722211753852
if [[ "${TERM_PROGRAM-}" == Apple_Terminal ]] && command -v update_terminal_cwd >/dev/null; then
    _LP_TERM_UPDATE_DIR=update_terminal_cwd
    # Remove "update_terminal_cwd; " that has been add by Apple in /et/bashrc.
    # See issue #196
    PROMPT_COMMAND="${PROMPT_COMMAND//update_terminal_cwd; /}"
else
    _LP_TERM_UPDATE_DIR=:
fi

# Default value for LP_PERM when LP_ENABLE_PERM is 0
LP_PERM=${LP_MARK_PERM}   # without color

# Same as bash '\l', but inlined as a constant as the value will not change
# during the shell's life
LP_TTYN="$(basename -- "$(tty)" 2>/dev/null)"



###############
# Who are we? #
###############
command -v _lp_sudo_check >/dev/null && unset -f _lp_sudo_check

# Yellow for root, bold if the user is not the login one, else no color.
if (( EUID != 0 )); then  # if user is not root
    # if user is not login user
    if [[ "${USER}" != "$(logname 2>/dev/null || echo "$LOGNAME")" ]]; then
        LP_USER="${LP_COLOR_USER_ALT}${_LP_USER_SYMBOL}${NO_COL}"
    elif (( LP_USER_ALWAYS )); then
        LP_USER="${LP_COLOR_USER_LOGGED}${_LP_USER_SYMBOL}${NO_COL}"
    else
        LP_USER=""
    fi
    # "sudo -n" is only supported from sudo 1.7.0
    if (( LP_ENABLE_SUDO )) \
            && command -v sudo >/dev/null \
            && LC_MESSAGES=C sudo -V | GREP_OPTIONS= \grep -qE '^Sudo version (1(\.([789]\.|[1-9][0-9])|[0-9])|[2-9])'
    then
        LP_COLOR_MARK_NO_SUDO="$LP_COLOR_MARK"
        # Test the code with the commands:
        #   sudo id   # sudo, enter your credentials
        #   sudo -K   # revoke your credentials
        _lp_sudo_check()
        {
            if sudo -n true 2>/dev/null; then
                LP_COLOR_MARK=$LP_COLOR_MARK_SUDO
            else
                LP_COLOR_MARK=$LP_COLOR_MARK_NO_SUDO
            fi
        }
    fi
else # root!
    LP_USER="${LP_COLOR_USER_ROOT}${_LP_USER_SYMBOL}${NO_COL}"
    LP_COLOR_MARK="${LP_COLOR_MARK_ROOT}"
    LP_COLOR_PATH="${LP_COLOR_PATH_ROOT}"
    # Disable VCS info for all paths
    if (( ! LP_ENABLE_VCS_ROOT )); then
        LP_DISABLED_VCS_PATH=/
        LP_MARK_DISABLED="$LP_MARK_DEFAULT"
    fi
fi

# Empty _lp_sudo_check if root or sudo disabled
if ! command -v _lp_sudo_check >/dev/null; then
    _lp_sudo_check() { :; }
fi


#################
# Where are we? #
#################

_lp_connection()
{
    if [[ -n "${SSH_CLIENT-}${SSH2_CLIENT-}${SSH_TTY-}" ]]; then
        echo ssh
    else
        # tmux: see GH #304
        # TODO check on *BSD
        local whoami="$(LC_ALL=C who am i)"
        local sess_parent="$(ps -o comm= -p $PPID 2> /dev/null)"
        if [[ x"$whoami" != *'('* || x"$whoami" = *'(:'* || x"$whoami" = *'(tmux'* ]]; then
            echo lcl  # Local
        elif [[ "$sess_parent" = "su" || "$sess_parent" = "sudo" ]]; then
            echo su   # Remote su/sudo
        else
            echo tel  # Telnet
        fi
    fi
}

# Put the hostname if not locally connected
# color it in cyan within SSH, and a warning red if within telnet
# else display the host without color
# The connection is not expected to change from inside the shell, so we
# build this just once
LP_HOST=""

# Only process hostname elements if we haven't turned them off
if (( LP_HOSTNAME_ALWAYS != -1 )); then

    [[ -r /etc/debian_chroot ]] && LP_HOST="($(< /etc/debian_chroot))"

    # Which host symbol should we use?
    if (( LP_ENABLE_FQDN )); then
        LP_HOST_SYMBOL="${_LP_FQDN_SYMBOL}"
    else
        LP_HOST_SYMBOL="${_LP_HOST_SYMBOL}"
    fi

    # If we are connected with a X11 support
    if [[ -n "$DISPLAY" ]]; then
        LP_HOST="${LP_COLOR_X11_ON}${LP_HOST}@${NO_COL}"
    else
        LP_HOST="${LP_COLOR_X11_OFF}${LP_HOST}@${NO_COL}"
    fi

    case "$(_lp_connection)" in
    lcl)
        if (( LP_HOSTNAME_ALWAYS )); then
            LP_HOST+="${LP_COLOR_HOST}${LP_HOST_SYMBOL}${NO_COL}"
        else
            # FIXME do we want to display the chroot if local?
            LP_HOST="" # no hostname if local
        fi
        ;;
    ssh)
        # If we want a different color for each host
        (( LP_ENABLE_SSH_COLORS )) && LP_COLOR_SSH="$LP_COLOR_HOST_HASH"
        LP_HOST+="${LP_COLOR_SSH}${LP_HOST_SYMBOL}${NO_COL}"
        ;;
    su)
        LP_HOST+="${LP_COLOR_SU}${LP_HOST_SYMBOL}${NO_COL}"
        ;;
    tel)
        LP_HOST+="${LP_COLOR_TELNET}${LP_HOST_SYMBOL}${NO_COL}"
        ;;
    *)
        LP_HOST+="${LP_HOST_SYMBOL}" # defaults to no color
        ;;
    esac

fi

# Useless now, so undefine
unset -f _lp_connection


_lp_get_home_tilde_collapsed()
{
    local tilde="~"
    echo "${PWD/#$HOME/$tilde}"
}

# Shorten the path of the current working directory
# * Show only the current directory
# * Show as much of the cwd path as possible, if shortened display a
#   leading mark, such as ellipses, to indicate that part is missing
# * show at least LP_PATH_KEEP leading dirs and current directory
_lp_shorten_path()
{

    if (( ! LP_ENABLE_SHORTEN_PATH )); then
        # We are not supposed to come here often as this case is already
        # optimized at install time
        LP_PWD="${LP_COLOR_PATH}${LP_PATH_DEFAULT}$NO_COL"
        return
    fi

    local ret=

    local p="$(_lp_get_home_tilde_collapsed)"
    local mask="${LP_MARK_SHORTEN_PATH}"
    local -i max_len=$(( ${COLUMNS:-80} * LP_PATH_LENGTH / 100 ))

    if (( LP_PATH_KEEP == -1 )); then
        # only show the current directory, excluding any parent dirs
        ret="${p##*/}" # discard everything up to and including the last slash
        [[ "${ret}" == "" ]] && ret="/" # if in root directory
    elif (( ${#p} <= max_len )); then
        ret="${p}"
    elif (( LP_PATH_KEEP == 0 )); then
        # len is over max len, show as much of the tail as is allowed
        ret="${p##*/}" # show at least complete current directory
        p="${p:0:${#p} - ${#ret}}"
        ret="${mask}${p:${#p} - (${max_len} - ${#ret} - ${#mask})}${ret}"
    else
        # len is over max len, show at least LP_PATH_KEEP leading dirs and
        # current directory
        local tmp="${p//\//}"
        local -i delims=$(( ${#p} - ${#tmp} ))

        for (( dir=0; dir < LP_PATH_KEEP; dir++ )); do
            (( dir == delims )) && break

            local left="${p#*/}"
            local name="${p:0:${#p} - ${#left}}"
            p="${left}"
            ret+="${name%/}/"
        done

        if (( delims <= LP_PATH_KEEP )); then
            # no dirs between LP_PATH_KEEP leading dirs and current dir
            ret+="${p##*/}"
        else
            local base="${p##*/}"

            p="${p:0:${#p} - ${#base}}"

            [[ ${ret} != "/" ]] && ret="${ret%/}" # strip trailing slash

            local -i len_left=$(( max_len - ${#ret} - ${#base} - ${#mask} ))

            ret+="${mask}${p:${#p} - ${len_left}}${base}"
        fi
    fi
    # Escape special chars
    LP_PWD="${LP_COLOR_PATH}$(_lp_escape "$ret")$NO_COL"
}

if (( LP_ENABLE_SHORTEN_PATH )); then
    if (( LP_PATH_KEEP == -1 )); then
        # _lp_shorten_path becomes a noop
        _lp_shorten_path()
        {
            :
        }
        # Will never change
        LP_PWD="${LP_COLOR_PATH}${_LP_DIR_SYMBOL}$NO_COL"
    fi
else
    # Will never change
    LP_PWD="${LP_COLOR_PATH}${LP_PATH_DEFAULT}$NO_COL"

    if $_LP_SHELL_bash && [[ -n "$PROMPT_DIRTRIM" ]]; then
        unset -f _lp_shorten_path
        alias _lp_shorten_path=_lp_set_dirtrim
    fi
fi


# In Bash shells, PROMPT_DIRTRIM is the number of directories to keep at the end
# of the displayed path (if "\w" is present in the PS1 var).
# Liquid Prompt can calculate this number under two conditions, path shortening
# must be disabled and PROMPT_DIRTRIM must be already set.
_lp_set_dirtrim() {
    local p="$(_lp_get_home_tilde_collapsed)"
    local -i max_len="${COLUMNS:-80}*$LP_PATH_LENGTH/100"
    local -i dt=0

    if (( ${#p} > max_len )); then
        local q="/${p##*/}"
        local show="$q"
        # +3 because of the ellipsis: "..."
        while (( ${#show}+3 < max_len )); do
            (( dt++ ))
            p="${p%$q}"
            q="/${p##*/}"
            show="$q$show"
        done
        (( dt == 0 )) && dt=1
    fi
    PROMPT_DIRTRIM=$dt
    # For debugging
    # echo PROMPT_DIRTRIM=$PROMPT_DIRTRIM >&2
}



################
# Related jobs #
################

# Display the count of each if non-zero:
# - detached screens sessions and/or tmux sessions running on the host
# - attached running jobs (started with $ myjob &)
# - attached stopped jobs (suspended with Ctrl-Z)
_lp_jobcount_color()
{
    (( LP_ENABLE_JOBS )) || return

    local ret=""
    local -i r s

    # Count detached sessions
    if (( _LP_ENABLE_DETACHED_SESSIONS )); then
        local -i detached=0
        (( _LP_ENABLE_SCREEN )) && detached=$(screen -ls 2> /dev/null | \grep -c '[Dd]etach[^)]*)$')
        (( _LP_ENABLE_TMUX )) && detached+=$(tmux list-sessions 2> /dev/null | \grep -cv 'attached')
        (( detached > 0 )) && ret+="${LP_COLOR_JOB_D}${detached}d${NO_COL}"
    fi

    # Count running jobs
    if (( r = $(jobs -r | wc -l) )); then
        [[ -n "$ret" ]] && ret+='/'
        ret+="${LP_COLOR_JOB_R}${r}&${NO_COL}"
    fi

    # Count stopped jobs
    if (( s = $(jobs -s | wc -l) )); then
        [[ -n "$ret" ]] && ret+='/'
        ret+="${LP_COLOR_JOB_Z}${s}z${NO_COL}"
    fi

    echo -nE "$ret"
}



######################
# VCS branch display #
######################

_lp_are_vcs_enabled()
{
    [[ -z "$LP_DISABLED_VCS_PATH" ]] && return 0
    $_LP_SHELL_zsh && setopt local_options && setopt sh_word_split
    local path
    local IFS=:
    for path in $LP_DISABLED_VCS_PATH; do
        [[ "$PWD" == *"$path"* ]] && return 1
    done
    return 0
}

# GIT #

# Get the branch name of the current directory
_lp_git_branch()
{
    (( LP_ENABLE_GIT )) || return

    \git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return

    local branch
    # Recent versions of Git support the --short option for symbolic-ref, but
    # not 1.7.9 (Ubuntu 12.04)
    if branch="$(\git symbolic-ref -q HEAD)"; then
        _lp_escape "${branch#refs/heads/}"
    else
        # In detached head state, use commit instead
        # No escape needed
        \git rev-parse --short -q HEAD
    fi
}


# Display additional information if HEAD is in merging, rebasing
# or cherry-picking state
_lp_git_head_status() {
    local gitdir
    gitdir="$(\git rev-parse --git-dir 2>/dev/null)"
    if [[ -f "${gitdir}/MERGE_HEAD" ]]; then
        echo " MERGING"
    elif [[ -d "${gitdir}/rebase-apply" || -d "${gitdir}/rebase-merge" ]]; then
        echo " REBASING"
    elif [[ -f "${gitdir}/CHERRY_PICK_HEAD" ]]; then
        echo " CHERRY-PICKING"
    fi
}

# Set a color depending on the branch state:
# - green if the repository is up to date
# - yellow if there is some commits not pushed
# - red if there is changes to commit
#
# Add the number of pending commits and the impacted lines.
_lp_git_branch_color()
{
    (( LP_ENABLE_GIT )) || return

    local branch
    branch="$(_lp_git_branch)"
    if [[ -n "$branch" ]]; then

        local end
        end="${LP_COLOR_CHANGES}$(_lp_git_head_status)${NO_COL}"

        if LC_ALL=C \git status --porcelain 2>/dev/null | \grep -q '^??'; then
            end="$LP_COLOR_CHANGES$LP_MARK_UNTRACKED$end"
        fi

        # Show if there is a git stash
        if \git rev-parse --verify -q refs/stash >/dev/null; then
            end="$LP_COLOR_COMMITS$LP_MARK_STASH$end"
        fi

        local remote
        remote="$(\git config --get branch.${branch}.remote 2>/dev/null)"

        local has_commit=""
        local commit_ahead
        local commit_behind
        if [[ -n "$remote" ]]; then
            local remote_branch
            remote_branch="$(\git config --get branch.${branch}.merge)"
            if [[ -n "$remote_branch" ]]; then
                remote_branch=${remote_branch/refs\/heads/refs\/remotes\/$remote}
                commit_ahead="$(\git rev-list --count $remote_branch..HEAD 2>/dev/null)"
                commit_behind="$(\git rev-list --count HEAD..$remote_branch 2>/dev/null)"
                if [[ "$commit_ahead" -ne "0" && "$commit_behind" -ne "0" ]]; then
                    has_commit="${LP_COLOR_COMMITS}+$commit_ahead${NO_COL}/${LP_COLOR_COMMITS_BEHIND}-$commit_behind${NO_COL}"
                elif [[ "$commit_ahead" -ne "0" ]]; then
                    has_commit="${LP_COLOR_COMMITS}$commit_ahead${NO_COL}"
                elif [[ "$commit_behind" -ne "0" ]]; then
                    has_commit="${LP_COLOR_COMMITS_BEHIND}-$commit_behind${NO_COL}"
                fi
            fi
        fi

        local ret
        local shortstat # only to check for uncommitted changes
        shortstat="$(LC_ALL=C \git diff --shortstat HEAD 2>/dev/null)"

        if [[ -n "$shortstat" ]]; then
            local u_stat # shorstat of *unstaged* changes
            u_stat="$(LC_ALL=C \git diff --shortstat 2>/dev/null)"
            u_stat=${u_stat/*changed, /} # removing "n file(s) changed"

            local i_lines # inserted lines
            if [[ "$u_stat" = *insertion* ]]; then
                i_lines=${u_stat/ inser*}
            else
                i_lines=0
            fi

            local d_lines # deleted lines
            if [[ "$u_stat" = *deletion* ]]; then
                d_lines=${u_stat/*\(+\), }
                d_lines=${d_lines/ del*/}
            else
                d_lines=0
            fi

            local has_lines
            has_lines="+$i_lines/-$d_lines"

            if [[ -n "$has_commit" ]]; then
                # Changes to commit and commits to push
                ret="${LP_COLOR_CHANGES}${branch}${NO_COL}(${LP_COLOR_DIFF}$has_lines${NO_COL},$has_commit)"
            else
                ret="${LP_COLOR_CHANGES}${branch}${NO_COL}(${LP_COLOR_DIFF}$has_lines${NO_COL})" # changes to commit
            fi
        elif [[ -n "$has_commit" ]]; then
            # some commit(s) to push
            if [[ "$commit_behind" -gt "0" ]]; then
                ret="${LP_COLOR_COMMITS_BEHIND}${branch}${NO_COL}($has_commit)"
            else
                ret="${LP_COLOR_COMMITS}${branch}${NO_COL}($has_commit)"
            fi
        else
            ret="${LP_COLOR_UP}${branch}" # nothing to commit or push
        fi
        echo -nE "$ret$end"
    fi
}

# Search upwards through a directory structure looking for a file/folder with
# the given name.  Used to avoid invoking 'hg' and 'bzr'.
_lp_upwards_find()
{
    local dir
    dir="$PWD"
    while [[ -n "$dir" ]]; do
        [[ -d "$dir/$1" ]] && return 0
        dir="${dir%/*}"
    done
    return 1
}

# MERCURIAL #

# Get the branch name of the current directory
_lp_hg_branch()
{
    (( LP_ENABLE_HG )) || return

    # First do a simple search to avoid having to invoke hg -- at least on my
    # machine, the python startup causes a noticeable hitch when changing
    # directories.
    _lp_upwards_find .hg || return

    # We found an .hg folder, so we need to invoke hg and see if we're actually
    # in a repository.

    local branch
    branch="$(hg branch 2>/dev/null)"

    (( $? == 0 )) && _lp_escape "$branch"
}

# Set a color depending on the branch state:
# - green if the repository is up to date
# - red if there is changes to commit
# - TODO: yellow if there is some commits not pushed
_lp_hg_branch_color()
{
    (( LP_ENABLE_HG )) || return

    local branch
    local ret
    branch="$(_lp_hg_branch)"
    if [[ -n "$branch" ]]; then

        local has_untracked
        has_untracked=
        if hg status -u 2>/dev/null | \grep -q '^?' >/dev/null ; then
            has_untracked="$LP_COLOR_CHANGES$LP_MARK_UNTRACKED"
        fi

        # Count local commits waiting for a push
        #
        # Unfortunately this requires contacting the remote, so this is always slow
        # => disabled  https://github.com/nojhan/liquidprompt/issues/217
        local -i commits
        #commits=$(hg outgoing --no-merges ${branch} 2>/dev/null | \grep -c '\(^changeset\:\)')
        commits=0

        # Check if there is some uncommitted stuff
        if [[ -z "$(hg status --quiet -n)" ]]; then
            if (( commits > 0 )); then
                # some commit(s) to push
                ret="${LP_COLOR_COMMITS}${branch}${NO_COL}(${LP_COLOR_COMMITS}$commits${NO_COL})${has_untracked}${NO_COL}"
            else
                # nothing to commit or push
                ret="${LP_COLOR_UP}${branch}${has_untracked}${NO_COL}"
            fi
        else
            local has_lines
            # Parse the last line of the diffstat-style output
            has_lines="$(hg diff --stat 2>/dev/null | sed -n '$ s!^.*, \([0-9]*\) .*, \([0-9]*\).*$!+\1/-\2!p')"
            if (( commits > 0 )); then
                # Changes to commit and commits to push
                ret="${LP_COLOR_CHANGES}${branch}${NO_COL}(${LP_COLOR_DIFF}$has_lines${NO_COL},${LP_COLOR_COMMITS}$commits${NO_COL})${has_untracked}${NO_COL}"
            else
                ret="${LP_COLOR_CHANGES}${branch}${NO_COL}(${LP_COLOR_DIFF}$has_lines${NO_COL})${has_untracked}${NO_COL}" # changes to commit
            fi
        fi
        echo -nE "$ret"
    fi
}

# SUBVERSION #

# Get the branch name of the current directory
# For the first level of the repository, gives the repository name
_lp_svn_branch()
{
    (( LP_ENABLE_SVN )) || return

    local root=
    local url=
    eval "$(LC_ALL=C svn info 2>/dev/null | sed -n 's/^URL: \(.*\)/url="\1"/p;s/^Repository Root: \(.*\)/root="\1"/p' )"
    [[ -z "${root-}" ]] && return

    # Make url relative to root
    url="${url:${#root}}"
    if [[ "$url" == */trunk* ]]; then
        echo -n trunk
    elif [[ "$url" == */branches/?* ]]; then
        url="${url##*/branches/}"
        _lp_escape "${url%/*}"
    elif [[ "$url" == */tags/?* ]]; then
        url="${url##*/tags/}"
        _lp_escape "${url%/*}"
    else
        _lp_escape "${root##*/}"
    fi
}

# Set a color depending on the branch state:
# - green if the repository is clean
#   (use $LP_SVN_STATUS_OPTIONS to define what that means with
#    the --depth option of 'svn status')
# - red if there is changes to commit
# Note that, due to subversion way of managing changes,
# informations are only displayed for the CURRENT directory.
_lp_svn_branch_color()
{
    (( LP_ENABLE_SVN )) || return

    local branch
    branch="$(_lp_svn_branch)"
    if [[ -n "$branch" ]]; then
        local changes
        changes=$(( $(svn status ${LP_SVN_STATUS_OPTIONS-} | \grep -c -v "?") ))
        if (( changes == 0 )); then
            echo -nE "${LP_COLOR_UP}${branch}${NO_COL}"
        else
            echo -nE "${LP_COLOR_CHANGES}${branch}${NO_COL}(${LP_COLOR_DIFF}$changes${NO_COL})" # changes to commit
        fi
    fi
}


# FOSSIL #

# Get the tag name of the current directory
_lp_fossil_branch()
{
    (( LP_ENABLE_FOSSIL )) || return
    local branch
    branch=$(fossil branch list 2>/dev/null | sed -n -$_LP_SED_EXTENDED 's/^\*\s+(\w*)$/\1/p')
    if [[ -n "$branch" ]]; then
        echo -nE "$branch"
    elif fossil info &>/dev/null ; then
        echo -n "no-branch"
    fi
}

# Set a color depending on the branch state:
# - green if the repository is clean
# - red if there is changes to commit
# - yellow if the branch has no tag name
#
# Add the number of impacted files with a
# + when files are ADDED or EDITED
# - when files are DELETED
_lp_fossil_branch_color()
{
    (( LP_ENABLE_FOSSIL )) || return

    local branch
    branch="$(_lp_fossil_branch)"

    if [[ -n "$branch" ]]; then
        local -i C2E # Modified files (added or edited)
        local C2A # Extras files
        local ret
        C2E=$(fossil changes | wc -l)
        C2A=$(fossil extras | wc -l)
        ret=$(fossil diff -i -v | awk '
            /^(\+[^+])|(\+$)/ { plus+=1 }
            /^(-[^-])|(-$)/ { minus+=1 }
            END {
                total=""
                if (plus>0) {
                    total="+"plus
                    if(minus>0) total=total"/"
                }
                if (minus>0) {
                    total=total"-"minus
                }
                print total
            }')

        if (( C2E > 0 )); then
            [[ -n "$ret" ]] && ret+=" in "
            ret="(${LP_COLOR_DIFF}${ret}${C2E}${NO_COL})"
        fi

        if (( C2A > 0 )); then
            C2A="$LP_COLOR_CHANGES$LP_MARK_UNTRACKED"
        else
            C2A=""
        fi

        if [[ "$branch" = "no-tag" ]]; then
            # Warning, your branch has no tag name !
            branch="${LP_COLOR_COMMITS}$branch${NO_COL}$ret${LP_COLOR_COMMITS}$C2A${NO_COL}"
        elif (( C2E == 0 )); then
            # All is up-to-date
            branch="${LP_COLOR_UP}$branch$C2A${NO_COL}"
        else
            # There're some changes to commit
            branch="${LP_COLOR_CHANGES}$branch${NO_COL}$ret${LP_COLOR_CHANGES}$C2A${NO_COL}"
        fi
        echo -nE "$branch"
    fi
}

# Bazaar #

# Get the branch name of the current directory
_lp_bzr_branch()
{
    (( LP_ENABLE_BZR )) || return

    # First do a simple search to avoid having to invoke bzr -- at least on my
    # machine, the python startup causes a noticeable hitch when changing
    # directories.
    _lp_upwards_find .bzr || return

    # We found an .bzr folder, so we need to invoke bzr and see if we're
    # actually in a repository.

    local branch
    branch="$(bzr nick 2> /dev/null)"
    (( $? != 0 )) && return
    _lp_escape "$branch"
}


# Set a color depending on the branch state:
# - green if the repository is up to date
# - red if there is changes to commit
# - TODO: yellow if there is some commits not pushed
#
# Add the number of pending commits and the impacted lines.
_lp_bzr_branch_color()
{
    (( LP_ENABLE_BZR )) || return

    # First do a simple search to avoid having to invoke bzr -- at least on my
    # machine, the python startup causes a noticeable hitch when changing
    # directories.
    _lp_upwards_find .bzr || return

    # We found an .bzr folder, so we need to invoke bzr and see if we're
    # actually in a repository.

    local output
    output="$(bzr version-info --check-clean --custom --template='{branch_nick} {revno} {clean}' 2> /dev/null)"
    (( $? != 0 )) && return
    $_LP_SHELL_zsh && setopt local_options && setopt sh_word_split
    local tuple
    tuple=($output)
    $_LP_SHELL_zsh && unsetopt sh_word_split
    local branch=${tuple[_LP_FIRST_INDEX+0]}
    local revno=${tuple[_LP_FIRST_INDEX+1]}
    local clean=${tuple[_LP_FIRST_INDEX+2]}
    local ret=

    if [[ -n "$branch" ]]; then
        if (( clean == 0 )); then
            ret="${LP_COLOR_CHANGES}${branch}${NO_COL}(${LP_COLOR_COMMITS}$revno${NO_COL})"
        else
            ret="${LP_COLOR_UP}${branch}${NO_COL}(${LP_COLOR_COMMITS}$revno${NO_COL})"
        fi

    fi
    echo -nE "$ret"
}


####################
# Wifi link status #
####################
_lp_wifi()
{
    # Linux
    sed -n '3s/^ *[^ ]*  *[^ ]*  *\([0-9]*\).*/\1/p' /proc/net/wireless
}

##################
# Battery status #
##################

# Get the battery status in percent
# returns 0 (and battery level) if battery is discharging and under threshold
# returns 1 (and battery level) if battery is discharging and above threshold
# returns 2 (and battery level) if battery is charging but under threshold
# returns 3 (and battery level) if battery is charging and above threshold
# returns 4 if no battery support
case "$LP_OS" in
    Linux)
    _lp_battery()
    {
        (( LP_ENABLE_BATT )) || return 4
        local acpi
        acpi="$(acpi --battery 2>/dev/null)"
        # Extract the battery load value in percent
        # First, remove the beginning of the line...
        local bat="${acpi#Battery *, }"
        bat="${bat%%%*}" # remove everything starting at '%'

        if [[ -z "${bat}" ]]; then
            # no battery level found
            return 4
        fi
        echo -nE "$bat"
        # discharging
        if [[ "$acpi" == *"Discharging"* ]]; then
            # under => 0, above => 1
            return $(( bat > LP_BATTERY_THRESHOLD ))
        # charging
        else
            # under => 2, above => 3
            return $(( 1 + ( bat > LP_BATTERY_THRESHOLD ) ))
        fi
    }
    ;;
    Darwin)
    _lp_battery()
    {
        (( LP_ENABLE_BATT )) || return 4
        local percent batt_status
        eval "$(pmset -g batt | sed -n 's/^ -InternalBattery[^	 ]*[	 ]\([0-9]*[0-9]\)%; \([^;]*\).*$/percent=\1 batt_status='\'\\2\'/p)"
        case "$batt_status" in
            charged | "")
            return 4
            ;;
            discharging)
                echo -nE "$percent"
                # under => 0, above => 1
                return $(( percent > LP_BATTERY_THRESHOLD ))
            ;;
            *)  # "charging", "AC attached"
                echo -nE "$percent"
                # under => 2, above => 3
                return $(( 1 + ( percent > LP_BATTERY_THRESHOLD ) ))
            ;;
        esac
    }
    ;;
esac

# Compute a gradient of background/foreground colors depending on the battery status
# Display:
# a  green ⏚ if the battery is charging    and above threshold
# a yellow ⏚ if the battery is charging    and under threshold
# a yellow ⌁ if the battery is discharging but above threshold
# a    red ⌁ if the battery is discharging and above threshold
_lp_battery_color()
{
    (( LP_ENABLE_BATT )) || return

    local mark=$LP_MARK_BATTERY
    local chargingmark=$LP_MARK_ADAPTER
    local -i bat ret
    bat="$(_lp_battery)"
    ret=$?

    if (( ret == 4 || bat == 100 )); then
        # no battery support or battery full: nothing displayed
        :
    elif (( ret == 3 && bat != 100 )); then
        # charging and above threshold and not 100%
        # green ⏚
        echo -nE "${LP_COLOR_CHARGING_ABOVE}$chargingmark${NO_COL}"
    elif (( ret == 2 )); then
        # charging but under threshold
        # yellow ⏚
        echo -nE "${LP_COLOR_CHARGING_UNDER}$chargingmark${NO_COL}"
    elif (( ret == 1 )); then
        # discharging but above threshold
        # yellow ⌁
        echo -nE "${LP_COLOR_DISCHARGING_ABOVE}$mark${NO_COL}"
    # discharging and under threshold
    else
        local res
        res="${LP_COLOR_DISCHARGING_UNDER}${mark}${NO_COL}"

        if (( LP_PERCENTS_ALWAYS )); then
            local -i idx
            if   (( bat <=  0 )); then
                idx=0
            elif (( bat <=  5 )); then         #  5
                idx=9
            elif (( bat <= 10 )); then         #  5
                idx=8
            elif (( bat <= 20 )); then         # 10
                idx=7
            elif (( bat <= 30 )); then         # 10
                idx=6
            elif (( bat <= 40 )); then         # 10
                idx=5
            elif (( bat <= 50 )); then         # 10
                idx=4
            elif (( bat <= 65 )); then         # 15
                idx=3
            elif (( bat <= 80 )); then         # 15
                idx=2
            elif (( bat < 100 )); then         # 20
                idx=1
            else # >= 100
                idx=0
            fi

            res+="${LP_COLORMAP[idx+_LP_FIRST_INDEX]}${bat}$_LP_PERCENT${NO_COL}"
        fi # LP_PERCENTS_ALWAYS
        echo -nE "${res}"
    fi
}

_lp_color_map() {
    # Default scale: 0..100
    # Custom scale: 0..$2
    local -i scale idx
    scale=${2:-100}
    # Transform the value to a 0..${#COLOR_MAP} scale
    idx=_LP_FIRST_INDEX+100*$1/scale/${#LP_COLORMAP[*]}
    echo -nE "${LP_COLORMAP[idx]}"
}

###########################
# runtime of last command #
###########################

_LP_RUNTIME_LAST_SECONDS=$SECONDS

_lp_runtime()
{
    if (( LP_ENABLE_RUNTIME && _LP_RUNTIME_SECONDS >= LP_RUNTIME_THRESHOLD ))
    then
        echo -nE "${LP_COLOR_RUNTIME}"
        # display runtime seconds as days, hours, minutes, and seconds
        (( _LP_RUNTIME_SECONDS >= 86400 )) && echo -n $((_LP_RUNTIME_SECONDS / 86400))d
        (( _LP_RUNTIME_SECONDS >= 3600 )) && echo -n $((_LP_RUNTIME_SECONDS % 86400 / 3600))h
        (( _LP_RUNTIME_SECONDS >= 60 )) && echo -n $((_LP_RUNTIME_SECONDS % 3600 / 60))m
        echo -n $((_LP_RUNTIME_SECONDS % 60))"s${NO_COL}"
    fi
    :
}

if (( LP_ENABLE_RUNTIME )); then
    if $_LP_SHELL_zsh; then
        _lp_runtime_before() {
          _LP_RUNTIME_LAST_SECONDS=$SECONDS
        }
        _lp_runtime_after() {
            if [[ -n "$_LP_RUNTIME_LAST_SECONDS" ]]; then
                (( _LP_RUNTIME_SECONDS=SECONDS-_LP_RUNTIME_LAST_SECONDS ))
                unset _LP_RUNTIME_LAST_SECONDS
            fi
        }

        add-zsh-hook preexec _lp_runtime_before
        add-zsh-hook precmd  _lp_runtime_after
    else
        _lp_runtime_before()
        {
            # For debugging
            #echo "XXX $BASH_COMMAND"

            # If the previous command was just the refresh of the prompt,
            # reset the counter
            if (( _LP_RUNTIME_SKIP )); then
                _LP_RUNTIME_SECONDS=-1 _LP_RUNTIME_LAST_SECONDS=$SECONDS
            else
                # Compute number of seconds since program was started
                (( _LP_RUNTIME_SECONDS=SECONDS-_LP_RUNTIME_LAST_SECONDS ))
            fi

            # If the command to run is the prompt, we'll have to ignore it
            [[ "$BASH_COMMAND" != "$PROMPT_COMMAND" ]]
            _LP_RUNTIME_SKIP=$?
        }

        _LP_RUNTIME_SKIP=0
        # _lp_runtime_before gets called just before bash executes a command,
        # including $PROMPT_COMMAND
        trap _lp_runtime_before DEBUG
    fi
fi

###############
# System load #
###############

# Compute a gradient of background/forground colors depending on the battery status
_lp_load_color()
{
    # Colour progression is important ...
    #   bold gray -> bold green -> bold yellow -> bold red ->
    #   black on red -> bold white on red
    #
    # Then we have to choose the values at which the colours switch, with
    # anything past yellow being pretty important.

    (( LP_ENABLE_LOAD )) || return

    local lp_cpu_load
    # Get value (OS-specific) into lp_cpu_load
    _lp_cpu_load

    lp_cpu_load=${lp_cpu_load/./}   # Remove '.'
    lp_cpu_load=${lp_cpu_load#0}    # Remove leading '0'
    lp_cpu_load=${lp_cpu_load#0}    # Remove leading '0', again (ex: 0.09)
    local -i load=${lp_cpu_load:-0}/$_lp_CPUNUM

    if (( load > LP_LOAD_THRESHOLD )); then
        local ret="$(_lp_color_map $load)${LP_MARK_LOAD}"

        if (( LP_PERCENTS_ALWAYS )); then
            ret+="${load}${_LP_PERCENT}"
        fi
        echo -nE "${ret}${NO_COL}"
    fi
}

######################
# System temperature #
######################

# Will set _LP_TEMP_FUNCTION so the temperature monitoring feature use an
# available command.
if (( LP_ENABLE_TEMP )); then

    # Backends for TEMP. Each backend must return the result in $temperature.

    # Implementation using lm-sensors
    _lp_temp_sensors()
    {
        # Return the hottest system temperature we get through the sensors command
        # Only the integer part is retained
        local -i i
        for i in $(sensors -u |
                sed -n 's/^  temp[0-9][0-9]*_input: \([0-9]*\)\..*$/\1/p'); do
            (( $i > ${temperature:-0} )) && temperature=i
        done
    }

    # Implementation using 'acpi -t'
    _lp_temp_acpi()
    {
        local -i i
        # Only the integer part is retained
        for i in $(LC_ALL=C acpi -t |
                sed 's/.* \(-\?[0-9]*\)\.[0-9]* degrees C$/\1/p'); do
            (( $i > ${temperature:-0} )) && temperature=i
        done
    }

    # Dynamic selection of backend
    _lp_temp_detect()
    {
        local -i temperature
        local cmd

        # Global variable
        unset _LP_TEMP_FUNCTION

        for cmd
        do
            command -v $cmd >/dev/null || continue

            _LP_TEMP_FUNCTION=_lp_temp_$cmd
            # Check that we can retrieve temperature at least once
            $_LP_TEMP_FUNCTION 2>/dev/null
            # If $temperature is set, success!
            [[ -n "$temperature" ]] && return 0
            unset -f $_LP_TEMP_FUNCTION
            unset _LP_TEMP_FUNCTION
        done
        return 1
    }

    # Try each _lp_temp method
    # If no function worked, disable the feature
    _lp_temp_detect acpi sensors || LP_ENABLE_TEMP=0
    unset -f _lp_temp_detect
fi


# Will display the numeric value as we get through the _LP_TEMP_FUNCTION
# and colorize it through _lp_color_map.
_lp_temperature()
{
    (( LP_ENABLE_TEMP )) || return

    local -i temperature
    temperature=0
    $_LP_TEMP_FUNCTION
    (( temperature >= LP_TEMP_THRESHOLD )) && \
        echo -nE "${LP_MARK_TEMP}$(_lp_color_map $temperature 120)$temperature°${NO_COL}"
}

##########
# DESIGN #
##########


# Sed expression using extended regexp to match terminal
# escape sequences with their wrappers
if $_LP_SHELL_bash; then
    _LP_CLEAN_ESC='\\\[([^\]+|\\[^]])*\\\]'
else
    _LP_CLEAN_ESC='%\{([^%]+|%[^}])*%\}'
fi

# Remove all colors and escape characters of the given string and return a pure text
_lp_as_text()
{
    # Remove all terminal sequences that we wrapped with $_LP_OPEN_ESC and
    # $_LP_CLOSE_ESC.
    echo -nE "$1" | sed -$_LP_SED_EXTENDED "s,$_LP_CLEAN_ESC,,g"
}

_lp_title()
{
    (( LP_ENABLE_TITLE )) || return

    # Get the current computed prompt as pure text
    echo -nE "${_LP_OPEN_ESC}${LP_TITLE_OPEN}"
    _lp_as_text "$1"
    echo -nE "${LP_TITLE_CLOSE}${_LP_CLOSE_ESC}"
}

# Set the prompt mark to ± if git, to ☿ if mercurial, to ‡ if subversion
# to # if root and else $
_lp_smart_mark()
{
    local mark
    case "$LP_VCS_TYPE" in
    git)      mark="$LP_MARK_GIT"             ;;
    git-svn)  mark="$LP_MARK_GIT$LP_MARK_SVN" ;;
    git-vcsh) mark="$LP_MARK_VCSH$LP_MARK_GIT$LP_MARK_VCSH";;
    hg)       mark="$LP_MARK_HG"              ;;
    svn)      mark="$LP_MARK_SVN"             ;;
    fossil)   mark="$LP_MARK_FOSSIL"          ;;
    bzr)      mark="$LP_MARK_BZR"             ;;
    disabled) mark="$LP_MARK_DISABLED"        ;;
    *)        mark="$LP_MARK_DEFAULT"         ;;
    esac
    echo -nE "${mark}${NO_COL}"
}

# insert a space on the right
_lp_sr()
{
    [[ -n "$1" ]] && echo -nE "$1 "
}

# insert a space on the left
_lp_sl()
{
    [[ -n "$1" ]] && echo -nE " $1"
}

# insert two space, before and after
_lp_sb()
{
    [[ -n "$1" ]] && echo -nE " $1 "
}

###################
# CURRENT TIME    #
###################

# LP_TIME is set colored, with a space on the right side
if (( LP_ENABLE_TIME )); then
    if (( LP_TIME_ANALOG )); then
        typeset -i _LP_CLOCK_PREV=-1
        # The targeted unicode characters are the "CLOCK FACE" ones
        # They are located in the codepages between:
        #     U+1F550 (ONE OCLOCK) and U+1F55B (TWELVE OCLOCK), for the plain hours
        #     U+1F55C (ONE-THIRTY) and U+1F567 (TWELVE-THIRTY), for the thirties
        # Generated with:
        # perl -C -E 'say join("", map {chr(0x1F550+$_)." ".chr(0x1F55C+$_)." "} 0..11)'
        _LP_CLOCK=(🕐 🕜 🕑 🕝 🕒 🕞 🕓 🕟 🕔 🕠 🕕 🕡 🕖 🕢 🕗 🕣 🕘 🕤 🕙 🕥 🕚 🕦 🕛 🕧 )

        _lp_time()
        {
            # %I: "00".."12"  %M: "00".."59"
            # Bash interprets a '0' prefix as octal
            # so we have to clean that
            local hhmm="$(date "+hh=%I mm=%M")"
            # hh:  1..12  mm: 0..59
            local -i hh mm clock
            eval ${hhmm//=0/=}  # Line split for zsh
            # clock: 0 .. 25
            #   1:00..1:14 -> 0
            #   1:15..1:44 -> 1
            #   1:45..2:15 -> 2
            #   ...
            #   12:15..12:44 -> 23
            #   12:45..12:59 -> 0
            if (( ( clock=((hh*60+mm-45)/30)%24 ) != _LP_CLOCK_PREV )); then
                # There is a space just after the clock char because the glyph
                # width is twice usual glyphs
                LP_TIME="${LP_COLOR_TIME}${_LP_CLOCK[clock+_LP_FIRST_INDEX]} ${NO_COL} "
                _LP_CLOCK_PREV=clock
            fi
        }
    else
        # Never changes
        LP_TIME="${LP_COLOR_TIME}${_LP_TIME_SYMBOL}${NO_COL} "
        _lp_time() { : ; }
    fi
else
    LP_TIME=""
    _lp_time() { : ; }
fi


########################
# Construct the prompt #
########################


_lp_set_prompt()
{
    # Display the return value of the last command, if different from zero
    # As this get the last returned code, it should be called first
    local -i err=$?
    if (( err != 0 )); then
        LP_ERR=" $LP_COLOR_ERR$err$NO_COL"
    else
        LP_ERR=''     # Hidden
    fi

    # Reset IFS to its default value to avoid strange behaviors
    # (in case the user is playing with the value at the prompt)
    local IFS="$_LP_IFS"
    local GREP_OPTIONS=

    # bash: execute the old prompt hook
    eval "$LP_OLD_PROMPT_COMMAND"

    # left of main prompt: space at right
    LP_JOBS="$(_lp_sr "$(_lp_jobcount_color)")"
    LP_TEMP="$(_lp_sr "$(_lp_temperature)")"
    LP_LOAD="$(_lp_sr "$(_lp_load_color)")"
    LP_BATT="$(_lp_sr "$(_lp_battery_color)")"
    _lp_time
    _lp_sudo_check

    # in main prompt: no space
    if [[ "$LP_ENABLE_PROXY,${http_proxy-}" = 1,?* ]]; then
        LP_PROXY="$LP_COLOR_PROXY$LP_MARK_PROXY$NO_COL"
    else
        LP_PROXY=
    fi

    # Display the current Python virtual environment, if available
    if [[ "$LP_ENABLE_VIRTUALENV,${VIRTUAL_ENV-}${CONDA_DEFAULT_ENV-}" = 1,?* ]]; then
        if [[ -n "${VIRTUAL_ENV-}" ]]; then
            LP_VENV=" [${LP_COLOR_VIRTUALENV}${VIRTUAL_ENV##*/}${NO_COL}]"
        else
            LP_VENV=" [${LP_COLOR_VIRTUALENV}${CONDA_DEFAULT_ENV##*/}${NO_COL}]"
        fi
    else
        LP_VENV=
    fi

    # Display the current software collections enabled, if available
    if [[ "$LP_ENABLE_SCLS,${X_SCLS-}" = 1,?* ]]; then
        LP_SCLS=" [${LP_COLOR_VIRTUALENV}${X_SCLS%"${X_SCLS##*[![:space:]]}"}${NO_COL}]"
    else
        LP_SCLS=
    fi

    LP_RUNTIME=$(_lp_sl "$(_lp_runtime)")

    # if change of working directory
    if [[ "${LP_OLD_PWD-}" != "LP:$PWD" ]]; then
        # Update directory icon for MacOS X
        $_LP_TERM_UPDATE_DIR

        LP_VCS=""
        LP_VCS_TYPE=""
        # LP_HOST is a global set at load time

        # LP_PERM: shows a ":"
        # - colored in green if user has write permission on the current dir
        # - colored in red if not
        # - can set another symbol with LP_MARK_PERM
        if (( LP_ENABLE_PERM )); then
            if [[ -w "${PWD}" ]]; then
                LP_PERM="${LP_COLOR_WRITE}${LP_MARK_PERM}${NO_COL}"
            else
                LP_PERM="${LP_COLOR_NOWRITE}${LP_MARK_PERM}${NO_COL}"
            fi
        fi

        _lp_shorten_path   # set LP_PWD

        if _lp_are_vcs_enabled; then
            LP_VCS="$(_lp_git_branch_color)"
            LP_VCS_TYPE="git"
            if [[ -n "$LP_VCS" ]]; then
                # If this is a vcsh repository
                if [[ -n "${VCSH_DIRECTORY-}" ]]; then
                    LP_VCS_TYPE="git-vcsh"
                fi
                # If this is a git-svn repository
                if [[ -d "$(\git rev-parse --git-dir 2>/dev/null)/svn" ]]; then
                    LP_VCS_TYPE="git-svn"
                fi # git-svn
            else
                LP_VCS="$(_lp_hg_branch_color)"
                LP_VCS_TYPE="hg"
                if [[ -z "$LP_VCS" ]]; then
                    LP_VCS="$(_lp_svn_branch_color)"
                    LP_VCS_TYPE="svn"
                    if [[ -z "$LP_VCS" ]]; then
                        LP_VCS="$(_lp_fossil_branch_color)"
                        LP_VCS_TYPE="fossil"
                        if [[ -z "$LP_VCS" ]]; then
                            LP_VCS="$(_lp_bzr_branch_color)"
                            LP_VCS_TYPE="bzr"
                            if [[ -z "$LP_VCS" ]]; then
                                LP_VCS=""
                                LP_VCS_TYPE=""
                            fi # nothing
                        fi # bzr
                    fi # fossil
                fi # svn
            fi # hg

        else # if this vcs rep is disabled
            LP_VCS="" # not necessary, but more readable
            LP_VCS_TYPE="disabled"
        fi

        if [[ -z "$LP_VCS_TYPE" ]]; then
            LP_VCS=""
        else
            LP_VCS="$(_lp_sl "${LP_VCS}")"
        fi

        # end of the prompt line: double spaces
        LP_MARK="$(_lp_sr "$(_lp_smart_mark $LP_VCS_TYPE)")"

        LP_OLD_PWD="LP:$PWD"

    # if do not change of working directory but...
    elif [[ -n "$LP_VCS_TYPE" ]]; then # we are still in a VCS dir
        case "$LP_VCS_TYPE" in
            # git, git-svn
            git*)    LP_VCS="$(_lp_sl "$(_lp_git_branch_color)")";;
            hg)      LP_VCS="$(_lp_sl "$(_lp_hg_branch_color)")";;
            svn)     LP_VCS="$(_lp_sl "$(_lp_svn_branch_color)")";;
            fossil)  LP_VCS="$(_lp_sl "$(_lp_fossil_branch_color)")";;
            bzr)     LP_VCS="$(_lp_sl "$(_lp_bzr_branch_color)")";;
            disabled)LP_VCS="";;
        esac
    fi

    if [[ -f "${LP_PS1_FILE-}" ]]; then
        source "$LP_PS1_FILE"
    fi

    if [[ -z "$LP_PS1" ]]; then
        # add title escape time, jobs, load and battery
        PS1="${LP_PS1_PREFIX}${LP_TIME}${LP_BATT}${LP_LOAD}${LP_TEMP}${LP_JOBS}"
        # add user, host and permissions colon
        PS1+="${LP_BRACKET_OPEN}${LP_USER}${LP_HOST}${LP_PERM}"

        PS1+="${LP_PWD}${LP_BRACKET_CLOSE}${LP_SCLS}${LP_VENV}${LP_PROXY}"

        # Add VCS infos
        # If root, the info has not been collected unless LP_ENABLE_VCS_ROOT
        # is set.
        PS1+="${LP_VCS}"

        # add return code and prompt mark
        PS1+="${LP_RUNTIME}${LP_ERR}${LP_MARK_PREFIX}${LP_COLOR_MARK}${LP_MARK}${LP_PS1_POSTFIX}"

        # "invisible" parts
        # Get the current prompt on the fly and make it a title
        LP_TITLE="$(_lp_title "$PS1")"

        # Insert it in the prompt
        PS1="${LP_TITLE}${PS1}"

        # Glue the bash prompt always go to the first column.
        # Avoid glitches after interrupting a command with Ctrl-C
        # Does not seem to be necessary anymore?
        #PS1="\[\033[G\]${PS1}${NO_COL}"
    else
        PS1=$LP_PS1
    fi
}

prompt_tag()
{
    export LP_PS1_PREFIX="$(_lp_sr "$1")"
}

# Activate Liquid Prompt
prompt_on()
{
    # Reset so all PWD dependent variables are computed after loading
    LP_OLD_PWD=""

    # if Liquid Prompt has not been already set
    if [[ -z "${LP_OLD_PS1-}" ]]; then
        LP_OLD_PS1="$PS1"
        if $_LP_SHELL_bash; then
            LP_OLD_PROMPT_COMMAND="$PROMPT_COMMAND"
            _LP_OLD_SHOPT="$(shopt -p promptvars)"
        else # zsh
            LP_OLD_PROMPT_COMMAND=""
            _LP_ZSH_PROMPT_THEME=""
            if [[ -n "$prompt_theme" && "$prompt_theme" != off ]]; then
                _LP_ZSH_PROMPT_THEME="$prompt_theme"
                # Disable the prompt to disable its precmd hook
                prompt off
            fi
            _LP_OLD_SETOPT=()
            # Dump option names: echo ${(ko)options}
            for o in promptpercent promptbang promptsubst
            do
                if [[ "${options[$o]}" = on ]]; then
                    _LP_OLD_SETOPT+=$o
                else
                    _LP_OLD_SETOPT+=no$o
                fi
            done
        fi
    fi
    if $_LP_SHELL_bash; then
        # Prevent some cases where the user shoots in his own foot.
        # PROMPT_COMMAND is not exported by default, but some users
        # incorrectly export it from their profile/bashrc (GitHub #450),
        # so we preventively UNexport it.
        # TODO: warn the user if it was exported
        if (( ${BASH_VERSION%%.*} > 4 )) || [[ ${BASH_VERSION} > 4.2 ]]; then
            # -g is only available since bash 4.2
            declare -g +x PROMPT_COMMAND
        fi

        # Disable parameter/command expansion from PS1
        shopt -u promptvars
        PROMPT_COMMAND=_lp_set_prompt
        (( LP_DEBUG_TIME )) && PROMPT_COMMAND="time $PROMPT_COMMAND" || true
    else # zsh
        [[ -n "$_LP_ZSH_HOOK" ]] && add-zsh-hook -d precmd $_LP_ZSH_HOOK
        # Set options that affect PS1 evaluation
        # Disable parameter/command expansion; enable percent expansion
        setopt promptpercent nopromptbang nopromptsubst
        # 'time' doesn't seem to work on shell functions: no time output
        #if (( LP_DEBUG_TIME )); then
        #    _lp_main_precmd() {
        #        local TIMEFMT='Liquid Prompt build time: %*E'
        #        time _lp_set_prompt
        #    }
        #    _LP_ZSH_HOOK=_lp_main_precmd
        #else
            _LP_ZSH_HOOK=_lp_set_prompt
        #fi
        add-zsh-hook precmd $_LP_ZSH_HOOK
    fi
}

# Come back to the old prompt
prompt_off()
{
    PS1=$LP_OLD_PS1
    if $_LP_SHELL_bash; then
        eval "$_LP_OLD_SHOPT"
        PROMPT_COMMAND="$LP_OLD_PROMPT_COMMAND"
    else # zsh
        add-zsh-hook -d precmd $_LP_ZSH_HOOK
        setopt ${_LP_OLD_SETOPT}
        (( ${#_LP_ZSH_PROMPT_THEME} )) && prompt $_LP_ZSH_PROMPT_THEME
    fi
}

# Use an empty prompt: just the \$ mark
prompt_OFF()
{
    PS1="$_LP_MARK_SYMBOL "
    if $_LP_SHELL_bash; then
        shopt -u promptvars
        PROMPT_COMMAND="$LP_OLD_PROMPT_COMMAND"
    else # zsh
        add-zsh-hook -d precmd $_LP_ZSH_HOOK
        setopt promptpercent nopromptbang nopromptsubst
    fi
}

# By default, sourcing liquidprompt will activate Liquid Prompt
prompt_on

# vim: set et sts=4 sw=4 tw=120 ft=sh: