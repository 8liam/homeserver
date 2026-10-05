#!/bin/zsh
# fresh-mac.sh - nuke the Dock, then install Homebrew + git, Docker, Apple container, Ghostty, nvm + Node LTS (npm), Claude Code, opencode, Helium (+default browser), T3 Code, and Tailscale in parallel.

APPS_DIR=/Applications
T=$(mktemp -d)
typeset -A STATE_LABEL
ids=(dock brew docker container ghostty node claude opencode helium t3 tailscale)
STATE_LABEL=(dock "Dock" brew "Homebrew" docker "Docker" container "Container" ghostty "Ghostty" node "nvm + Node" claude "Claude Code" opencode "opencode" helium "Helium" t3 "T3 Code" tailscale "Tailscale")

cleanup() { printf '\033[?25h'; [[ -n $SUDO_PID ]] && kill $SUDO_PID 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT
trap 'kill $(jobs -p) 2>/dev/null; exit 130' INT TERM

load_brew() {
  command -v brew >/dev/null && return 0
  local b; for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [[ -x $b ]] && eval "$($b shellenv)" && return 0
  done
  return 1
}

wait_for() { # id -> 0 if that job finished successfully
  local n=0
  until [[ -f $T/$1.s && $(<"$T/$1.s") == (done|fail)* ]] || (( n++ > 3000 )); do sleep 1; done
  [[ $(<"$T/$1.s") == done* ]]
}

wait_brew() { wait_for brew && load_brew; }

set_state() { print -r -- "$2|$3" > "$T/$1.s"; }

gh_asset() { # repo, regex matched against the asset URL
  curl -fsSL "https://api.github.com/repos/$1/releases/latest" \
    | grep -Eo "\"browser_download_url\": *\"[^\"]*$2\"" | head -n1 | cut -d'"' -f4
}

fetch() { # id url dest
  local total
  total=$(curl -sIL "$2" | awk 'tolower($1)=="content-length:"{v=$2} END{gsub(/\r/,"",v); print v+0}')
  print -r -- "$total" > "$T/$1.total"
  print -r -- "$3" > "$T/$1.dest"
  set_state $1 dl "Downloading"
  curl -fsSL "$2" -o "$3"
}

install_dmg() { # dmg
  local mnt=$(mktemp -d) app
  hdiutil attach -nobrowse -quiet -noverify -mountpoint "$mnt" "$1" <<< "Y"
  app=$(find "$mnt" -maxdepth 2 -name '*.app' -print -quit)
  [[ -n $app ]]
  rm -rf "$APPS_DIR/${app:t}"
  ditto "$app" "$APPS_DIR/${app:t}"
  hdiutil detach -quiet "$mnt"
}

job_dock() {
  set_state dock run "Yeeting every icon"
  defaults write com.apple.dock persistent-apps -array
  defaults write com.apple.dock persistent-others -array
  defaults write com.apple.dock show-recents -bool false
  killall Dock || true
  set_state dock run "Waiting for apps to pin"
  wait_brew || true
  local id app pinned=0
  for id in ghostty helium t3 tailscale; do
    wait_for $id || continue
    case $id in
      ghostty) app="$APPS_DIR/Ghostty.app" ;;
      helium) app="$APPS_DIR/Helium.app" ;;
      t3) app=("$APPS_DIR"/T3\ Code*.app(N[1])) ;;
      tailscale) app="$APPS_DIR/Tailscale.app" ;;
    esac
    if command -v dockutil >/dev/null && [[ -d $app ]]; then
      dockutil --add "$app" --no-restart && pinned=$((pinned + 1))
    fi
  done
  killall Dock || true
  set_state dock done "Dock cleared, $pinned apps pinned"
}

job_brew() {
  set_state brew run "Checking for Homebrew"
  if ! load_brew; then
    set_state brew run "Installing Homebrew (+ Xcode CLT)"
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    load_brew
    local rc='eval "$(/opt/homebrew/bin/brew shellenv)"'
    [[ -x /opt/homebrew/bin/brew ]] && ! grep -qs "brew shellenv" ~/.zprofile && print -r -- "$rc" >> ~/.zprofile
  fi
  set_state brew run "brew install git defaultbrowser dockutil"
  HOMEBREW_NO_AUTO_UPDATE=1 brew install git defaultbrowser dockutil
  set_state brew done "Homebrew + git ready"
}

job_docker() {
  set_state docker run "Waiting for Homebrew"
  wait_brew
  set_state docker run "Installing Docker Desktop (big download)"
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install --cask docker-desktop
  open -a Docker
  set_state docker done "Installed & launched (accept its first-run prompts)"
}

job_container() {
  set_state container run "Waiting for Homebrew"
  wait_brew
  set_state container run "Installing Apple container"
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install container
  set_state container run "Starting container services"
  container system start --enable-kernel-install
  set_state container done "Installed & services running"
}

job_ghostty() {
  set_state ghostty run "Waiting for Homebrew"
  wait_brew
  set_state ghostty run "Installing"
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install --cask ghostty
  open -a Ghostty
  set_state ghostty done "Installed & launched"
}

job_node() {
  set_state node run "Waiting for Homebrew"
  wait_brew
  set_state node run "Installing nvm"
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install nvm
  export NVM_DIR="$HOME/.nvm"
  mkdir -p "$NVM_DIR"
  if ! grep -qs "nvm.sh" ~/.zshrc ~/.zprofile; then
    cat >> ~/.zshrc <<'NVMRC'

export NVM_DIR="$HOME/.nvm"
[ -s "$HOMEBREW_PREFIX/opt/nvm/nvm.sh" ] && \. "$HOMEBREW_PREFIX/opt/nvm/nvm.sh"
NVMRC
  fi
  unsetopt ERR_EXIT   # nvm isn't errexit-safe
  source "$(brew --prefix nvm)/nvm.sh" || return 1
  set_state node run "Installing latest LTS Node"
  nvm install --lts || return 1
  nvm alias default 'lts/*' || return 1
  nvm use default || return 1
  set_state node done "nvm + Node $(node -v) (LTS, default), npm $(npm -v)"
}

job_claude() {
  set_state claude run "Waiting for Homebrew"
  wait_brew
  set_state claude run "Installing"
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install --cask claude-code
  set_state claude done "Installed (run: claude)"
}

job_opencode() {
  set_state opencode run "Waiting for Homebrew"
  wait_brew
  set_state opencode run "Installing"
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install opencode
  set_state opencode done "Installed (run: opencode)"
}

job_helium() {
  set_state helium run "Finding latest release"
  local url=$(gh_asset imputnet/helium-macos 'https://[^"]*arm64[^"]*\.dmg')
  [[ -n $url ]]
  fetch helium "$url" "$T/helium.dmg"
  set_state helium run "Installing"
  install_dmg "$T/helium.dmg"
  set_state helium run "Setting default browser"
  local app="$APPS_DIR/Helium.app" bid note=""
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app" || true
  bid=$(defaults read "$app/Contents/Info" CFBundleIdentifier)
  wait_brew || true
  if command -v defaultbrowser >/dev/null && defaultbrowser "${bid##*.}"; then
    note="default browser (confirm the macOS popup)"
  else
    note="installed - set default browser manually"
  fi
  open "$app"
  set_state helium done "Launched, $note"
}

job_t3() {
  set_state t3 run "Finding latest release"
  local url=$(gh_asset pingdotgg/t3code 'https://[^"]*arm64\.dmg')
  [[ -n $url ]]
  fetch t3 "$url" "$T/t3.dmg"
  set_state t3 run "Installing"
  install_dmg "$T/t3.dmg"
  open "$APPS_DIR/T3 Code"*.app
  set_state t3 done "Installed & launched"
}

job_tailscale() {
  fetch tailscale "https://pkgs.tailscale.com/stable/Tailscale-latest-macos.zip" "$T/tailscale.zip"
  set_state tailscale run "Installing"
  ditto -xk "$T/tailscale.zip" "$T/tailscale"
  rm -rf "$APPS_DIR/Tailscale.app"
  ditto "$T/tailscale/Tailscale.app" "$APPS_DIR/Tailscale.app"
  open "$APPS_DIR/Tailscale.app"
  set_state tailscale done "Installed & launched"
}

run_job() {
  ( setopt ERR_EXIT; "job_$1" ) >> "$T/$1.log" 2>&1
  local rc=$?
  (( rc == 0 )) || set_state $1 fail "Failed (exit $rc)"
}

banner=(
'  ▄████  ▄▄▄       ██▀███   ███▄ ▄███▓ ██▓ ███▄    █'
' ██▒ ▀█▒▒████▄    ▓██ ▒ ██▒▓██▒▀█▀ ██▒▓██▒ ██ ▀█   █'
'▒██░▄▄▄░▒██  ▀█▄  ▓██ ░▄█ ▒▓██    ▓██░▒██▒▓██  ▀█ ██▒'
'░▓█  ██▓░██▄▄▄▄██ ▒██▀▀█▄  ▒██    ▒██ ░██░▓██▒  ▐▌██▒'
'░▒▓███▀▒ ▓█   ▓██▒░██▓ ▒██▒▒██▒   ░██▒░██░▒██░   ▓██░'
' ░▒   ▒  ▒▒   ▓▒█░░ ▒▓ ░▒▓░░ ▒░   ░  ░░▓  ░ ▒░   ▒ ▒'
'  ░   ░   ▒   ▒▒ ░  ░▒ ░ ▒░░  ░      ░ ▒ ░░ ░░   ░ ▒░'
'░ ░   ░   ░   ▒     ░░   ░ ░      ░    ▒ ░   ░   ░ ░'
'      ░       ░  ░   ░            ░    ░           ░'
)
spin=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

mb() { printf '%.1f' $(( $1 / 1048576.0 )); }

render() { # frame -> sets $buf and $all_done
  local f=$1 i s phase msg line col size total pct filled bar
  local C=$'\033[' R=$'\033[0m\033[K'
  buf=""
  for i in {1..${#banner}}; do
    buf+="  ${C}38;5;124m${banner[$i]}${R}"$'\n'
  done
  buf+="  ${C}38;5;240mabandon all dock icons, ye who enter${R}"$'\n'$'\n'
  all_done=1
  for i in $ids; do
    s=""; [[ -f $T/$i.s ]] && s=$(<"$T/$i.s")
    [[ -n $s ]] || s="run|Starting"
    phase=${s%%|*}; msg=${s#*|}
    line="${(r:12:)STATE_LABEL[$i]}"
    case $phase in
      done) buf+="  ${C}32m✔${R}  ${C}1m${line}${R}${C}32m${msg}${R}"$'\n' ;;
      fail) buf+="  ${C}31m✘${R}  ${C}1m${line}${R}${C}31m${msg}${R}"$'\n'; ;;
      dl)
        all_done=0
        size=$(stat -f%z "$(<"$T/$i.dest")" 2>/dev/null || echo 0)
        total=$(<"$T/$i.total")
        if (( total > 0 )); then
          pct=$(( size * 100 / total )); filled=$(( pct * 20 / 100 ))
          bar="${(l:$filled::█:)}${(l:$((20 - filled))::░:)}"
          buf+="  ${C}36m${spin[$(( f % 10 + 1 ))]}${R}  ${C}1m${line}${R}${bar} ${(l:3:)pct}%  $(mb $size)/$(mb $total) MB${R}"$'\n'
        else
          buf+="  ${C}36m${spin[$(( f % 10 + 1 ))]}${R}  ${C}1m${line}${R}Downloading  $(mb $size) MB${R}"$'\n'
        fi ;;
      *) all_done=0
         buf+="  ${C}36m${spin[$(( f % 10 + 1 ))]}${R}  ${C}1m${line}${R}${msg}${R}"$'\n' ;;
    esac
  done
}

printf '\033[2J\033[H\n'
for line in $banner; do printf '  \033[38;5;124m%s\033[0m\n' "$line"; done
printf '  \033[38;5;240mabandon all dock icons, ye who enter\033[0m\n\n'
cat <<'EOF2'
  This will:
    - wipe your Dock, then pin Ghostty, Helium, T3 Code, and Tailscale
    - install Homebrew + git, Docker, Apple container, Ghostty,
      nvm + Node LTS (npm), Claude Code, opencode, Helium (default browser),
      T3 Code, and Tailscale
    - launch the apps when they finish
EOF2
printf '\n  \033[1mProceed?\033[0m [y/N] '
read -k 1 -u 0 reply; echo
if [[ $reply != [yY] ]]; then echo "  Aborted. Nothing was changed."; exit 0; fi
echo

if ! command -v brew >/dev/null && [[ ! -x /opt/homebrew/bin/brew ]]; then
  echo "Homebrew's installer needs your password (asked once, up front)."
fi
sudo -v || exit 1
( while true; do sudo -n true; sleep 50; done ) &
SUDO_PID=$!

printf '\033[2J\033[H\033[?25l\n'
pids=(); for id in $ids; do run_job $id & pids+=($!); done

frame=0
while true; do
  (( frame > 0 )) && printf '\033[%dA' $nlines
  render $frame
  printf '%s' "$buf"
  nlines=$(( ${#buf} - ${#${buf//$'\n'/}} ))
  (( all_done )) && break
  sleep 0.1; (( frame++ ))
done
wait $pids

echo
for id in $ids; do
  if [[ $(<"$T/$id.s") == fail* ]]; then
    echo "--- ${STATE_LABEL[$id]} log (tail) ---"; tail -n 15 "$T/$id.log"
  fi
done
echo "All done. Enjoy the clean slate."
