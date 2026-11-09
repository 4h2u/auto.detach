#!/usr/bin/env zsh
# Contract check. Needs a tty: zsh -fi tests/smoke.zsh
if [[ -z ${_GUI_DETACH_SMOKE:-} ]]; then
  export _GUI_DETACH_SMOKE=1
  exec zsh -fi -- "$0" "$@"
fi

emulate -L zsh
setopt no_aliases

fail() {
  print -u2 -- "smoke: $*"
  exit 1
}

[[ $options[interactive] == on ]] || fail "shell is not interactive"
[[ $options[rcs] == off ]] || fail "user rc is enabled"
whence -w gui-detach >/dev/null && fail "gui-detach already defined; user rc leaked"
[[ -t 0 && -t 1 ]] || fail "stdin and stdout must be a tty"

here=${${(%):-%x}:A:h}
plugin=$here/../gui-detach.plugin.zsh
[[ -f $plugin ]] || fail "missing $plugin"

root=$(mktemp -d)
trap 'rm -rf -- "$root"' EXIT
bindir=$root/bin
apps=$root/applications
cfgdir=$root/config
cachedir=$root/cache
mkdir -p -- "$bindir" "$apps" "$cfgdir" "$cachedir"

cat >"$bindir/gd-smoke-bin" <<'EOF'
#!/bin/sh
marker=${GUI_DETACH_SMOKE_MARKER:?}
if [ "${1:-}" = "--help" ]; then
  echo help-ok
  exit 0
fi
echo "stdout:$*"
echo "started:$*" >> "$marker"
sleep 1
EOF
chmod 755 -- "$bindir/gd-smoke-bin"
cp -- "$bindir/gd-smoke-bin" "$bindir/gd-smoke-extra"
ln -s gd-smoke-bin "$bindir/gd-smoke-never"
ln -s gd-smoke-bin "$bindir/gd-smoke-link"
cp -- "$bindir/gd-smoke-bin" "$bindir/gui-detach-smoke"

cat >"$apps/gd-smoke-bin.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Smoke Bin
Exec=gd-smoke-bin
Terminal=false
EOF
cat >"$apps/gd-smoke-never.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Smoke Never
Exec=gd-smoke-never
Terminal=false
StartupWMClass=smoke-never
EOF
cat >"$apps/gd-smoke-link.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Smoke Link
Exec=gd-smoke-bin
Terminal=false
EOF

marker=$root/marker
export GUI_DETACH_SMOKE_MARKER=$marker
: >"$marker"

cat >"$cfgdir/gui-detach.zsh" <<EOF
GUI_DETACH_EXTRA=(gd-smoke-extra gui-detach-smoke)
GUI_DETACH_NEVER+=(gd-smoke-never)
GUI_DETACH_DESKTOP_DIRS=($apps)
GUI_DETACH_LOG=rel-log
EOF

export XDG_CONFIG_HOME=$cfgdir
export XDG_CACHE_HOME=$cachedir
cd -- "$root" || fail "cd $root"
path=($bindir $path)
hash -r

source "$plugin" || fail "source failed"
[[ $GUI_DETACH_LOG == /*/rel-log ]] || fail "log path not absolute: $GUI_DETACH_LOG"

listed() {
  gui-detach-list | grep -qx -- "$1"
}
listed gd-smoke-bin || fail "desktop script was not wrapped"
listed gd-smoke-extra || fail "EXTRA was not wrapped"
listed gd-smoke-link || fail "symlink to a GUI binary was not wrapped"
listed gui-detach-smoke || fail "wrapper whose name starts with gui-detach was hidden"
if listed gd-smoke-never; then
  fail "NEVER was wrapped"
fi

out=$(gd-smoke-bin --help) || fail "--help status $?"
[[ $out == help-ok ]] || fail "--help output: ${out}"

typeset -F SECONDS
start=$SECONDS
gd-smoke-bin det
elapsed=$(( SECONDS - start ))
(( elapsed < 0.7 )) || fail "detach took ${elapsed}s"
found=0
for _ in {1..40}; do
  if grep -q 'started:det' "$marker"; then
    found=1
    break
  fi
  sleep 0.05
done
(( found )) || fail "detached process did not start"

start=$SECONDS
command gd-smoke-bin via-command
elapsed=$(( SECONDS - start ))
(( elapsed >= 0.8 )) || fail "command bypass detached (${elapsed}s)"

start=$SECONDS
gd-smoke-bin via-pipe | cat
elapsed=$(( SECONDS - start ))
(( elapsed >= 0.8 )) || fail "pipe detached (${elapsed}s)"

start=$SECONDS
gd-smoke-bin via-stdin </dev/null
elapsed=$(( SECONDS - start ))
(( elapsed >= 0.8 )) || fail "stdin redirect detached (${elapsed}s)"

start=$SECONDS
gui-detach gd-smoke-never manual
elapsed=$(( SECONDS - start ))
(( elapsed < 0.7 )) || fail "gui-detach manual took ${elapsed}s"
found=0
for _ in {1..40}; do
  if grep -q 'started:manual' "$marker"; then
    found=1
    break
  fi
  sleep 0.05
done
(( found )) || fail "manual detach did not start"

start=$SECONDS
gd-smoke-bin logtok
elapsed=$(( SECONDS - start ))
(( elapsed < 0.7 )) || fail "logged detach took ${elapsed}s"
log=$GUI_DETACH_LOG/gd-smoke-bin.log
found=0
for _ in {1..40}; do
  if [[ -f $log ]] && grep -q 'stdout:logtok' "$log" && grep -q '^--- ' "$log"; then
    found=1
    break
  fi
  sleep 0.05
done
(( found )) || fail "log missing header or stdout:logtok ($([[ -f $log ]] && cat "$log"))"

cat >"$cfgdir/gui-detach.zsh" <<EOF
GUI_DETACH_NEVER+=(gd-smoke-never)
GUI_DETACH_DESKTOP_DIRS=($apps)
GUI_DETACH_LOG=rel-log
EOF
gui-detach-reload || fail "reload failed"
if listed gd-smoke-extra; then
  fail "EXTRA survived reload"
fi
if listed gui-detach-smoke; then
  fail "prefixed EXTRA survived reload"
fi
listed gd-smoke-bin || fail "desktop wrap lost on reload"
[[ $GUI_DETACH_LOG == /*/rel-log ]] || fail "reload log path: $GUI_DETACH_LOG"

if zsh -f -c "source ${(q)plugin}; whence -w gui-detach >/dev/null"; then
  fail "non-interactive source defined gui-detach"
fi

print -r -- "smoke: ok"
