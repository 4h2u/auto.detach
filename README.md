# gui-detach

everything ai made but works fine, i hate when i open stuff from a cli and its not dettached and i hate making some long commands so i used some tokens to make this little script to never be forced to make this detach bs myself.

Interactive zsh returns the prompt when you type the name of an installed GUI app. The app keeps running after the terminal closes. CLI tools stay in the foreground.

```zsh
firefox                 # prompt returns, stdio discarded
command firefox         # foreground, logs stay
firefox --help          # --help/--version/--wait/--block stay attached
echo x | firefox        # no tty: stays attached
gui-detach some-app     # detach a name the scan missed
gui-detach-list
gui-detach-reload
```

Linux only. The manual equivalent is `setsid -f app`. Alias lists, `gtk-launch`, `uwsm app`, and terminal swallow (`devour`) do a different job.

## Requirements

- zsh
- Linux
- util-linux `setsid -f` (BusyBox `setsid` has no `-f`)
- GNU find, GNU coreutils (`stat`, `sha256sum`, `date`)
- binutils `readelf` (without it, ELF apps are wrapped only from desktop metadata)

## Install

Source it at the end of `~/.zshrc`, after `PATH` is final. The scan uses `whence -p` at load time. A directory added later is invisible until `gui-detach-reload`.

```zsh
source /path/to/gui-detach/gui-detach.plugin.zsh
```

Plugin managers that source this before `PATH` is ready: call `gui-detach-reload` at the end of `~/.zshrc`.

Non-interactive shells return immediately. Scripts are unchanged.

## Config

`${XDG_CONFIG_HOME:-$HOME/.config}/gui-detach.zsh` is sourced on shell start and by `gui-detach-reload`. The plugin resets to its defaults first, then sources that file, so `+=` does not stack across reloads.

```zsh
GUI_DETACH_EXTRA+=(my-appimage)
GUI_DETACH_NEVER+=(mpv)
GUI_DETACH_LOG=$HOME/.cache/gui-detach/log
GUI_DETACH_DESKTOP_DIRS+=(/opt/custom/share/applications)
```

`+=` extends the defaults. `=()` replaces them, including the built-in `NEVER` list.

Do not set these in `~/.zshrc` before the `source` line. Reload does not see that. See `config.example.zsh`.

`GUI_DETACH_LOG` empty (the default) sends stdout and stderr to `/dev/null`. Set it to a directory and each program name gets an appended `<name>.log`, with a timestamp header. A relative path is made absolute when the config is read.

## What gets wrapped

Visible `Type=Application` desktop entries (`Terminal` not true, not `NoDisplay`, not `Hidden`) from:

- `/usr/share/applications`
- `/usr/local/share/applications`
- `$XDG_DATA_HOME/applications`
- Flatpak and Snap export directories
- `GUI_DETACH_DESKTOP_DIRS`

The desktop file name (without `.desktop`) and the program token in `Exec` are wrapped only when that name is a real command on `PATH`. Starters are skipped: `env`, `flatpak`, `snap`, `gtk-launch`, `xdg-open`, `sh`, `python`, `wine`, and the rest of the skip list in the plugin. A Flatpak id that is not itself a `PATH` command is not wrapped. `flatpak run …` stays a CLI.

A `#!` script with such a desktop file is treated as a GUI (`firefox`, `discord`, `steam`).

An ELF is a GUI only if one of these is true:

- `StartupWMClass` is set
- `Categories` contains `TerminalEmulator` (`kitty`, `konsole`)
- `StartupNotify=true`
- `readelf -d` shows a GUI library: gtk, Qt Gui/Widgets, gdk, Xaw, SDL2, fltk, wx, adwaita, granite

`libX11` alone does not count. A symlink whose target was already accepted is wrapped too (`code` → `code-oss`).

The index is cached under `${XDG_CACHE_HOME:-$HOME/.cache}/gui-detach`. It rebuilds when the plugin, the config arrays, the desktop-dir list, or a scanned `.desktop` file changes.

## Escape hatches

- `command name` runs the binary. The wrapper is a shell function.
- `--help`, `--version`, `--wait`, `--block` anywhere in the arguments stay attached.
- A pipe, or any launch whose stdin or stdout is not a tty, stays attached.
- An existing alias, builtin, or function is not replaced.

## Known misses and false wraps

Needs `GUI_DETACH_EXTRA` (not detected as GUI):

- `jconsole` links no GUI library
- `lstopo` only links `libX11`
- AppImages and other binaries with no desktop entry

Never wrapped, even with a desktop file (`GUI_DETACH_NEVER` defaults):

- `wine`, `wine64`, `wineserver`, `winetricks` (callers wait)
- `zenity`, `kdialog`, `yad`, `qarma` (dialogs)
- `pinentry`, `pinentry-qt`, `pinentry-gtk`, `pinentry-gnome3`, `pinentry-curses`
- `false`, `true`, `Xwayland`, `Xorg`, `plasmashell`, `kwin_wayland`, `kwin_x11`

Also wrapped on purpose, which can surprise:

- Terminal emulators, because `Categories` contains `TerminalEmulator`. `kitty -e htop` detaches.
- Any `#!` script that has a visible Application desktop file, even if the script is a CLI.

`StartupNotify=true` alone is enough for an ELF. A CLI that sets that key gets wrapped.

## Uninstall

Remove the `source` line, start a new shell, and delete `~/.cache/gui-detach` if you want the index gone. The current shell keeps the wrapper functions until it exits.
