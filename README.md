# homeserver

Setup scripts for my Mac mini home server.

## fresh-mac.sh

One-shot setup for a brand-new Apple Silicon Mac. Shows a GARMIN banner, asks `y/N`, then does everything in parallel with live progress bars.

### Run it

```sh
zsh -c "$(curl -fsSL https://raw.githubusercontent.com/8liam/homeserver/main/fresh-mac.sh)"
```

Use that form rather than `curl ... | zsh`, so the script can still read your `y/N` answer and password from the terminal.

### What it does

- Wipes every icon from the Dock (and turns off "recent apps"), then pins Ghostty, Helium, T3 Code and Tailscale once they're installed
- Installs [Homebrew](https://brew.sh) (plus Xcode Command Line Tools) and `git`
- Installs Docker Desktop, Apple [`container`](https://github.com/apple/container) (and starts its services), and Ghostty, Node (with npm), Claude Code, and opencode via Homebrew
- Downloads the latest [Helium](https://github.com/imputnet/helium-macos) and [T3 Code](https://github.com/pingdotgg/t3code) arm64 `.dmg`s, installs them, and sets Helium as the default browser
- Installs [Tailscale](https://tailscale.com) (standalone build)
- Launches each app once it's installed

### Notes

- Apple Silicon only. Apple `container` needs macOS 26 or later.
- Asks for your password once up front (Homebrew's installer needs `sudo`).
- macOS will still show a popup to confirm the default browser change, and Docker and Tailscale have first-run prompts. None of those can be scripted.
- Safe to re-run: anything already installed is skipped or replaced.
- Read the script before piping anything from the internet into your shell: [`fresh-mac.sh`](fresh-mac.sh).
