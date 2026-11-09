# gui-detach 1.0.0
# SPDX-License-Identifier: MIT
#
# Installed GUI apps return the prompt immediately and keep running after
# the terminal closes. CLI tools stay attached.
#
#   firefox
#   discord
#   command firefox          # foreground, with logs
#   firefox --help           # --help/--version/--wait/--block stay attached
#   gui-detach some-app      # detach something the scan missed
#   gui-detach-list
#   gui-detach-reload
#
# Config: ${XDG_CONFIG_HOME:-$HOME/.config}/gui-detach.zsh
# Read on shell start and by gui-detach-reload. Assignments in ~/.zshrc
# before this file is sourced are not re-read on reload.
#
#   GUI_DETACH_EXTRA+=(my-appimage)
#   GUI_DETACH_NEVER+=(mpv)
#   GUI_DETACH_LOG=$HOME/.cache/gui-detach/log
#   GUI_DETACH_DESKTOP_DIRS+=(/opt/custom/share/applications)

[[ -o interactive ]] || return 0

emulate -L zsh

typeset -g _GUI_DETACH_FILE=${${(%):-%x}:a}
typeset -g _GUI_DETACH_CACHE=${XDG_CACHE_HOME:-$HOME/.cache}/gui-detach
typeset -ga _GUI_DETACH_CMDS
typeset -gA _GUI_ACC _GUI_REAL _GUI_NEVER

_gui_detach_launch() {
  emulate -L zsh
  local bin=$1
  shift
  [[ -n $bin && -x $bin ]] || return 127
  local arg
  for arg in "$@"; do
    case $arg in
      --help|--version|--wait|--block)
        "$bin" "$@"
        return
        ;;
    esac
  done
  if [[ ! -t 0 || ! -t 1 ]]; then
    "$bin" "$@"
    return
  fi
  local out=/dev/null
  if [[ -n ${GUI_DETACH_LOG:-} ]]; then
    local logdir=$GUI_DETACH_LOG
    if [[ ! -d $logdir ]] && ! mkdir -p -- "$logdir"; then
      print -u2 -- "gui-detach: cannot create log dir ${logdir}"
    elif [[ ! -d $logdir || ! -w $logdir ]]; then
      print -u2 -- "gui-detach: log dir not writable: ${logdir}"
    else
      out=$logdir/${bin:t}.log
      if ! print -r -- "--- $(command date -Is) ${bin} ${(j: :)${(q)@}} ---" >>"$out"; then
        print -u2 -- "gui-detach: cannot write ${out}"
        out=/dev/null
      fi
    fi
  fi
  if ! command setsid -f "$bin" "$@" </dev/null >>"$out" 2>&1; then
    print -u2 -- "gui-detach: failed to detach ${bin:t}"
    "$bin" "$@"
  fi
}

function _gui_detach_define {
  emulate -L zsh
  setopt localoptions extendedglob
  local cmd=$1 bin=$2 kind
  [[ -n $cmd && -x $bin ]] || return 1
  [[ $cmd == [A-Za-z0-9._+-]## ]] || return 1
  [[ -n ${aliases[$cmd]:-} ]] && return 1
  kind=${$(whence -w -- $cmd)#*: }
  case $kind in
    builtin|reserved) return 1 ;;
    function)
      [[ ${functions[$cmd]} == *gui_detach_launch\ * ]] || return 1
      ;;
  esac
  functions[$cmd]=$'_gui_detach_launch '${(q)bin}' "$@"'
  return 0
}

_gui_detach_apply_config() {
  emulate -L zsh
  typeset -ga GUI_DETACH_EXTRA=()
  typeset -ga GUI_DETACH_NEVER=(
    wine wine64 wineserver winetricks
    zenity kdialog yad qarma
    pinentry pinentry-qt pinentry-gtk pinentry-gnome3 pinentry-curses
  )
  typeset -ga GUI_DETACH_DESKTOP_DIRS=()
  typeset -g GUI_DETACH_LOG=
  local cfg=${XDG_CONFIG_HOME:-$HOME/.config}/gui-detach.zsh
  if [[ -f $cfg ]]; then
    source "$cfg" || {
      print -u2 -- "gui-detach: config failed: ${cfg}"
      return 1
    }
  fi
  [[ -n $GUI_DETACH_LOG ]] && GUI_DETACH_LOG=${GUI_DETACH_LOG:a}
  typeset -ga _GUI_DETACH_DIRS=(
    /usr/share/applications
    /usr/local/share/applications
    ${XDG_DATA_HOME:-$HOME/.local/share}/applications
    /var/lib/flatpak/exports/share/applications
    ${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/exports/share/applications
    /var/lib/snapd/desktop/applications
    ${GUI_DETACH_DESKTOP_DIRS[@]}
  )
}

_gui_detach_stamp() {
  emulate -L zsh
  local d
  local -a existing=()
  for d in $_GUI_DETACH_DIRS; do
    [[ -d $d ]] && existing+=($d)
  done
  {
    print -r -- "file:${_GUI_DETACH_FILE}:$(stat -c %Y -- "$_GUI_DETACH_FILE")"
    print -r -- "never:${(j:,:)GUI_DETACH_NEVER}"
    print -r -- "extra:${(j:,:)GUI_DETACH_EXTRA}"
    print -r -- "dirs:${(j:,:)_GUI_DETACH_DIRS}"
    if (( $#existing )); then
      find $existing -name '*.desktop' -printf '%T@ %p\n' 2>/dev/null | sort
    fi
  } | sha256sum | awk '{print $1}'
}

_gui_detach_exec_token() {
  emulate -L zsh
  local -a words skip
  words=(${(Z:c:)1})
  skip=(env flatpak snap gtk-launch kde-open kde-open5 kioclient kioclient5 gio xdg-open sh bash zsh dash setsid nohup systemd-run bwrap prime-run gamemoderun mangohud python python2 python3 perl ruby lua node deno java mono wine wine64 busybox)
  local w base
  for w in $words; do
    [[ $w == %* ]] && continue
    [[ $w == *=* && $w != /* ]] && continue
    base=${w:t}
    (( ${skip[(Ie)$base]} )) && continue
    print -r -- $base
    return 0
  done
  return 1
}

_gui_detach_is_gui() {
  emulate -L zsh
  local real=$1 cats=$2 wmclass=$3 notify=$4 hex needed
  [[ -f $real && -x $real ]] || return 1
  case ${real:t} in
    false|true) return 1 ;;
  esac
  hex=$(command head -c 4 -- "$real" | command od -An -tx1 | command tr -d ' \n')
  if [[ $hex == 2321* ]]; then
    return 0
  fi
  [[ $hex == 7f454c46 ]] || return 1
  if [[ $cats == *TerminalEmulator* || -n $wmclass || $notify == true ]]; then
    return 0
  fi
  needed=$(command readelf -d -- "$real" 2>/dev/null) || return 1
  [[ $needed == *libgtk* || $needed == *libQtGui* || $needed == *libQt5Gui* || $needed == *libQt6Gui* || $needed == *libQt5Widgets* || $needed == *libQt6Widgets* || $needed == *libgdk-* || $needed == *libXaw* || $needed == *libSDL2* || $needed == *libfltk* || $needed == *libwx_* || $needed == *libadwaita* || $needed == *libgranite* ]]
}

_gui_detach_consider() {
  emulate -L zsh
  local cmd=$1 cats=$2 wmclass=$3 notify=$4 bin real
  [[ -n $cmd ]] || return 0
  [[ -n ${_GUI_NEVER[$cmd]} || -n ${_GUI_ACC[$cmd]} ]] && return 0
  case $cmd in
    false|true|Xwayland|Xorg|plasmashell|kwin_wayland|kwin_x11) return 0 ;;
  esac
  bin=$(whence -p -- $cmd 2>/dev/null) || return 0
  real=$(readlink -f -- "$bin" 2>/dev/null) || return 0
  _gui_detach_is_gui "$real" "$cats" "$wmclass" "$notify" || return 0
  _GUI_ACC[$cmd]=$bin
  _GUI_REAL[$real]=1
}

_gui_detach_index() {
  emulate -L zsh
  setopt localoptions nullglob noaliases
  local -a dirs files
  local d n stem execv cats wmclass notify token cmd bin base target dir link real
  dirs=($_GUI_DETACH_DIRS)
  files=()
  for d in $dirs; do
    [[ -d $d ]] && files+=($d/*.desktop(N))
  done
  _GUI_ACC=()
  _GUI_REAL=()
  _GUI_NEVER=()
  for n in $GUI_DETACH_NEVER false true Xwayland Xorg plasmashell kwin_wayland kwin_x11; do
    _GUI_NEVER[$n]=1
  done

  local parsed=$_GUI_DETACH_CACHE/parsed.$$
  mkdir -p -- $_GUI_DETACH_CACHE
  if (( $#files )); then
    awk '
      function trim(s) { gsub(/^[ \t\r]+|[ \t\r]+$/, "", s); return s }
      function reset() { typ=term=nodisplay=hidden=execv=cats=wmclass=notify=""; in_e=0 }
      function flush() {
        if (!in_e) return
        in_e=0
        if (typ != "Application") return
        if (term == "true") return
        if (nodisplay == "true" || hidden == "true") return
        print stem "\034" execv "\034" cats "\034" wmclass "\034" notify
      }
      FNR == 1 {
        if (NR > 1) flush()
        reset()
        stem = FILENAME
        sub(/^.*\//, "", stem)
        sub(/\.desktop$/, "", stem)
      }
      /^\[/ {
        if ($0 == "[Desktop Entry]") { in_e=1; next }
        if (in_e) flush()
        next
      }
      in_e && /^Type=/ { typ=trim(substr($0, 6)); next }
      in_e && /^Terminal=/ { term=tolower(trim(substr($0, 10))); next }
      in_e && /^NoDisplay=/ { nodisplay=tolower(trim(substr($0, 11))); next }
      in_e && /^Hidden=/ { hidden=tolower(trim(substr($0, 8))); next }
      in_e && /^Exec=/ { execv=trim(substr($0, 6)); next }
      in_e && /^Categories=/ { cats=trim(substr($0, 12)); next }
      in_e && /^StartupWMClass=/ { wmclass=trim(substr($0, 16)); next }
      in_e && /^StartupNotify=/ { notify=tolower(trim(substr($0, 15))); next }
      END { flush() }
    ' $files >$parsed </dev/null
  else
    : >$parsed
  fi

  while IFS=$'\034' read -r stem execv cats wmclass notify; do
    [[ -n $stem ]] && _gui_detach_consider "$stem" "$cats" "$wmclass" "$notify"
    token=$(_gui_detach_exec_token "$execv") || token=
    [[ -n $token ]] && _gui_detach_consider "$token" "$cats" "$wmclass" "$notify"
  done < $parsed
  rm -f -- $parsed

  for n in $GUI_DETACH_EXTRA; do
    [[ -n ${_GUI_NEVER[$n]} ]] && continue
    bin=$(whence -p -- $n 2>/dev/null) || continue
    _GUI_ACC[$n]=$bin
    real=$(readlink -f -- "$bin" 2>/dev/null) || real=$bin
    _GUI_REAL[$real]=1
  done

  for dir in $path; do
    [[ -d $dir ]] || continue
    for link in $dir/*(N@); do
      base=${link:t}
      [[ -n ${_GUI_NEVER[$base]} || -n ${_GUI_ACC[$base]} ]] && continue
      target=$(readlink -f -- "$link" 2>/dev/null) || continue
      [[ -n ${_GUI_REAL[$target]} ]] || continue
      bin=$(whence -p -- $base 2>/dev/null) || continue
      _GUI_ACC[$base]=$bin
    done
  done

  local -a new=()
  for cmd in ${(ko)_GUI_ACC}; do
    if _gui_detach_define "$cmd" "${_GUI_ACC[$cmd]}"; then
      new+=($cmd)
      print -r -- $cmd$'\t'${_GUI_ACC[$cmd]}
    fi
  done
  for n in $_GUI_DETACH_CMDS; do
    (( ${new[(Ie)$n]} )) || unfunction -- $n 2>/dev/null
  done
  _GUI_DETACH_CMDS=($new)
}

_gui_detach_rebuild() {
  emulate -L zsh
  mkdir -p -- $_GUI_DETACH_CACHE || return 1
  local tmp=$_GUI_DETACH_CACHE/commands.$$ stamp
  stamp=$(_gui_detach_stamp) || {
    print -u2 -- "gui-detach: failed to stamp desktop index"
    return 1
  }
  if ! _gui_detach_index >$tmp; then
    rm -f -- $tmp
    print -u2 -- "gui-detach: failed to build desktop index"
    return 1
  fi
  mv -f -- $tmp $_GUI_DETACH_CACHE/commands || return 1
  print -r -- $stamp >| $_GUI_DETACH_CACHE/stamp
}

_gui_detach_load_cache() {
  emulate -L zsh
  local cmd bin
  local -a new=()
  while IFS=$'\t' read -r cmd bin; do
    [[ -n $cmd ]] || continue
    if _gui_detach_define "$cmd" "$bin"; then
      new+=($cmd)
    fi
  done < $_GUI_DETACH_CACHE/commands
  local old
  for old in $_GUI_DETACH_CMDS; do
    (( ${new[(Ie)$old]} )) || unfunction -- $old 2>/dev/null
  done
  _GUI_DETACH_CMDS=($new)
}

_gui_detach_load() {
  emulate -L zsh
  local stamp=
  [[ -f $_GUI_DETACH_CACHE/stamp ]] && stamp=$(<$_GUI_DETACH_CACHE/stamp)
  if [[ -n $stamp && $stamp == $(_gui_detach_stamp) && -f $_GUI_DETACH_CACHE/commands ]]; then
    _gui_detach_load_cache
    return
  fi
  _gui_detach_rebuild
}

gui-detach() {
  emulate -L zsh
  if (( $# < 1 )); then
    print -u2 -- 'usage: gui-detach command [args...]'
    return 2
  fi
  local bin
  bin=$(whence -p -- $1 2>/dev/null) || bin=$1
  shift
  _gui_detach_launch $bin "$@"
}

gui-detach-list() {
  emulate -L zsh
  local n
  for n in ${(ko)functions}; do
    [[ $n == gui-detach || $n == gui-detach-list || $n == gui-detach-reload || $n == _gui_detach* ]] && continue
    [[ ${functions[$n]} == *_gui_detach_launch\ /* ]] && print -r -- $n
  done
}

gui-detach-reload() {
  emulate -L zsh
  _gui_detach_apply_config || return 1
  rm -f -- $_GUI_DETACH_CACHE/stamp
  _gui_detach_rebuild
}

_gui_detach_apply_config || return 1

if ! command setsid -f true </dev/null >/dev/null 2>&1; then
  print -u2 -- "gui-detach: util-linux setsid -f is required; GUI commands will not be wrapped"
  return 0
fi
if ! whence -p readelf >/dev/null; then
  print -u2 -- "gui-detach: readelf not found; ELF apps are wrapped only when the desktop entry says so"
fi
_gui_detach_load || print -u2 -- "gui-detach: index failed"
