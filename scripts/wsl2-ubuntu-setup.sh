#!/usr/bin/env bash
#
# wsl2-ubuntu-setup.sh
# ---------------------------------------------------------------------------
# Configure a fresh Ubuntu install running on WSL2 (including the WSL "preview"
# / Store build) as a full development box that you can also reach over RDP or
# VNC with a real Linux desktop (XFCE).
#
# What it does:
#   * Enables systemd + a few sensible WSL defaults in /etc/wsl.conf
#   * Updates the system and installs a broad set of developer tooling
#     (build toolchains, languages, CLI utilities, containers helpers, ...)
#   * Installs the XFCE desktop environment
#   * Sets up remote access:
#       - RDP  via xrdp        (default port 3339)
#       - VNC  via TigerVNC    (default display :1  -> port 5901)
#     with the usual WSL fixes (polkit prompts, dbus, xsession, ...)
#
# The script is idempotent: re-running it will not duplicate configuration and
# will happily pick up where it left off.
#
# Usage:
#   chmod +x wsl2-ubuntu-setup.sh
#   ./wsl2-ubuntu-setup.sh                 # everything (dev tools + RDP + VNC)
#   ./wsl2-ubuntu-setup.sh --no-vnc        # skip VNC
#   ./wsl2-ubuntu-setup.sh --no-rdp        # skip RDP
#   ./wsl2-ubuntu-setup.sh --minimal       # dev tools only, no desktop/remote
#   ./wsl2-ubuntu-setup.sh --rdp-port 3389 # override the RDP port
#   ./wsl2-ubuntu-setup.sh --help
#
# After it finishes: run `wsl --shutdown` from Windows PowerShell, then start
# Ubuntu again so systemd and the new /etc/wsl.conf take effect.
# ---------------------------------------------------------------------------

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults / configuration
# ---------------------------------------------------------------------------
RDP_PORT="${RDP_PORT:-3339}"      # xrdp listens here (avoids clashing with Windows' own 3389)
VNC_DISPLAY="${VNC_DISPLAY:-1}"   # VNC display number -> TCP port 5900 + N
VNC_GEOMETRY="${VNC_GEOMETRY:-1920x1080}"
DESKTOP_SESSION_CMD="startxfce4"

DO_DEVTOOLS=1
DO_DESKTOP=1
DO_RDP=1
DO_VNC=1

# ---------------------------------------------------------------------------
# Pretty logging
# ---------------------------------------------------------------------------
c_reset=$'\033[0m'; c_blue=$'\033[1;34m'; c_green=$'\033[1;32m'
c_yellow=$'\033[1;33m'; c_red=$'\033[1;31m'
log()  { printf '%s==>%s %s\n' "$c_blue"   "$c_reset" "$*"; }
ok()   { printf '%s[ok]%s %s\n' "$c_green"  "$c_reset" "$*"; }
warn() { printf '%s[!!]%s %s\n' "$c_yellow" "$c_reset" "$*" >&2; }
die()  { printf '%s[xx]%s %s\n' "$c_red"    "$c_reset" "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
# Print the leading comment banner (from line 2 up to the first non-comment
# line) as help text, stripping the leading "# ". Robust to line-number drift.
print_help() {
  awk 'NR==1 {next} /^#/ {sub(/^#[[:space:]]?/, ""); print; next} {exit}' "$0"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-devtools) DO_DEVTOOLS=0 ;;
    --no-desktop)  DO_DESKTOP=0; DO_RDP=0; DO_VNC=0 ;;
    --no-rdp)      DO_RDP=0 ;;
    --no-vnc)      DO_VNC=0 ;;
    --minimal)     DO_DESKTOP=0; DO_RDP=0; DO_VNC=0 ;;
    --rdp-port)    RDP_PORT="${2:?--rdp-port needs a value}"; shift ;;
    --vnc-display) VNC_DISPLAY="${2:?--vnc-display needs a value}"; shift ;;
    --geometry)    VNC_GEOMETRY="${2:?--geometry needs a value}"; shift ;;
    -h|--help)     print_help ;;
    *) die "Unknown option: $1 (use --help)" ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
SUDO=""
need_root() {
  if [[ $EUID -ne 0 ]]; then
    command -v sudo >/dev/null 2>&1 || die "This script needs root or sudo."
    SUDO="sudo"
  fi
}

is_wsl() { grep -qiE "(microsoft|wsl)" /proc/sys/kernel/osrelease 2>/dev/null; }

apt_install() {
  # Install packages, skipping ones that don't exist in this release.
  local pkgs=() p
  for p in "$@"; do
    if apt-cache show "$p" >/dev/null 2>&1; then
      pkgs+=("$p")
    else
      warn "package '$p' not found for this release, skipping"
    fi
  done
  [[ ${#pkgs[@]} -eq 0 ]] && return 0
  $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${pkgs[@]}"
}

append_once() {
  # append_once <file> <line>  -> add line to file only if not already present
  local file="$1" line="$2"
  $SUDO grep -qxF "$line" "$file" 2>/dev/null || echo "$line" | $SUDO tee -a "$file" >/dev/null
}

# ---------------------------------------------------------------------------
# Step 0: sanity
# ---------------------------------------------------------------------------
need_root
if ! is_wsl; then
  warn "This does not look like WSL. The script still works but the WSL-specific"
  warn "tweaks (wsl.conf, systemd, xrdp polkit fixes) may be unnecessary."
fi
# shellcheck disable=SC1091
. /etc/os-release 2>/dev/null || true
log "Ubuntu ${VERSION_ID:-?} (${VERSION_CODENAME:-?}) on $(uname -r)"

# ---------------------------------------------------------------------------
# Step 1: /etc/wsl.conf  (systemd + defaults)
# ---------------------------------------------------------------------------
configure_wsl_conf() {
  is_wsl || return 0
  log "Configuring /etc/wsl.conf (systemd, boot, interop)"
  local tmp; tmp="$(mktemp)"
  cat > "$tmp" <<'EOF'
# Managed by wsl2-ubuntu-setup.sh
[boot]
systemd=true

[automount]
enabled=true
options="metadata,umask=22,fmask=11"
mountFsTab=true

[interop]
enabled=true
appendWindowsPath=true

[network]
generateResolvConf=true
EOF

  # Preserve any pre-existing wsl.conf: skip if identical, otherwise back it up
  # before overwriting so the user's custom settings are never silently lost.
  if [[ -f /etc/wsl.conf ]]; then
    if $SUDO cmp -s "$tmp" /etc/wsl.conf; then
      rm -f "$tmp"
      ok "wsl.conf already up to date"
      return 0
    fi
    local backup
    backup="/etc/wsl.conf.bak.$(date +%Y%m%d%H%M%S)"
    $SUDO cp -a /etc/wsl.conf "$backup"
    warn "existing /etc/wsl.conf backed up to $backup (review & merge custom settings)"
  fi

  $SUDO install -m 0644 "$tmp" /etc/wsl.conf
  rm -f "$tmp"
  ok "wsl.conf written (requires 'wsl --shutdown' to apply)"
}

# ---------------------------------------------------------------------------
# Step 2: base system update + core dev tooling
# ---------------------------------------------------------------------------
update_system() {
  log "Updating apt package index"
  $SUDO apt-get update -y
  $SUDO DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
}

install_devtools() {
  log "Installing developer tooling (this is the big one)"

  # Build toolchains & headers
  apt_install build-essential gcc g++ make cmake pkg-config autoconf automake \
    libtool gdb clang clang-format lld ninja-build

  # Version control & general CLI utilities
  apt_install git git-lfs curl wget ca-certificates gnupg lsb-release \
    software-properties-common apt-transport-https unzip zip xz-utils \
    tar tree htop btop ncdu jq yq ripgrep fd-find fzf bat neovim vim \
    tmux screen zsh bash-completion man-db less rsync openssh-client \
    net-tools iproute2 dnsutils iputils-ping traceroute nmap socat \
    sqlite3 direnv shellcheck plocate

  # Languages / runtimes available from apt
  apt_install python3 python3-pip python3-venv python3-dev pipx \
    golang-go default-jdk maven

  # Container / cloud helpers (Docker Desktop integration usually provides the daemon)
  apt_install docker.io docker-compose-v2 docker-buildx podman

  # Some distros ship `fd` as `fdfind` and `bat` as `batcat`; add friendly links
  mkdir -p "$HOME/.local/bin"
  command -v fdfind  >/dev/null 2>&1 && ln -sf "$(command -v fdfind)"  "$HOME/.local/bin/fd"
  command -v batcat  >/dev/null 2>&1 && ln -sf "$(command -v batcat)"  "$HOME/.local/bin/bat"

  # pipx-managed Python tooling (user scope, no system pollution)
  if command -v pipx >/dev/null 2>&1; then
    pipx ensurepath >/dev/null 2>&1 || true
    local tool
    for tool in uv poetry ruff httpie; do
      pipx list 2>/dev/null | grep -q "package $tool " || pipx install "$tool" || warn "pipx install $tool failed"
    done
  fi

  install_node
  install_rust

  ok "Developer tooling installed"
}

install_node() {
  if command -v node >/dev/null 2>&1 && [[ -d "$HOME/.nvm" ]]; then
    ok "Node/nvm already present"
    return 0
  fi
  log "Installing nvm + latest LTS Node.js"
  export NVM_DIR="$HOME/.nvm"
  if [[ ! -d "$NVM_DIR" ]]; then
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
  fi
  # shellcheck disable=SC1090,SC1091
  . "$NVM_DIR/nvm.sh"
  nvm install --lts
  nvm alias default 'lts/*'
  corepack enable 2>/dev/null || true
  ok "Node $(node -v 2>/dev/null) installed via nvm"
}

install_rust() {
  if command -v rustc >/dev/null 2>&1; then
    ok "Rust already present"
    return 0
  fi
  log "Installing Rust via rustup"
  curl -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path
  ok "Rust installed (source \$HOME/.cargo/env)"
}

# ---------------------------------------------------------------------------
# Step 3: XFCE desktop
# ---------------------------------------------------------------------------
install_desktop() {
  log "Installing XFCE desktop environment"
  apt_install xfce4 xfce4-goodies xfce4-terminal dbus-x11 x11-xserver-utils \
    fonts-dejavu fonts-liberation policykit-1 xdg-utils \
    firefox || warn "some desktop packages were skipped"
  ok "XFCE installed"
}

# Silence the polkit "Authentication is required to create a color profile"
# and network-manager prompts that spam every RDP/VNC login on WSL.
install_polkit_fixes() {
  log "Applying polkit fixes for headless desktop sessions"

  # Modern polkit (>= 0.106, i.e. Ubuntu 22.04+/24.04) uses JavaScript rules in
  # /etc/polkit-1/rules.d and ignores the legacy .pkla local-authority files.
  local jsrule=/etc/polkit-1/rules.d/45-allow-colord.rules
  $SUDO mkdir -p "$(dirname "$jsrule")"
  cat <<'EOF' | $SUDO tee "$jsrule" >/dev/null
// Allow color-manager actions without a password prompt (headless RDP/VNC).
polkit.addRule(function(action, subject) {
    if (action.id.indexOf("org.freedesktop.color-manager.") === 0) {
        return polkit.Result.YES;
    }
});
EOF

  # Legacy pkla for older polkit (< 0.106) / distros still shipping pklocalauthority.
  local pkla=/etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla
  $SUDO mkdir -p "$(dirname "$pkla")"
  cat <<'EOF' | $SUDO tee "$pkla" >/dev/null
[Allow Colord all Users]
Identity=unix-user:*
Action=org.freedesktop.color-manager.create-device;org.freedesktop.color-manager.create-profile;org.freedesktop.color-manager.delete-device;org.freedesktop.color-manager.delete-profile;org.freedesktop.color-manager.modify-device;org.freedesktop.color-manager.modify-profile
ResultAny=no
ResultInactive=no
ResultActive=yes
EOF
  ok "polkit color-profile prompt suppressed (JS rule + legacy pkla)"
}

# ---------------------------------------------------------------------------
# Step 4: RDP via xrdp
# ---------------------------------------------------------------------------
setup_rdp() {
  log "Setting up xrdp (RDP) on port ${RDP_PORT}"
  apt_install xrdp

  # Point every login at XFCE.
  echo "$DESKTOP_SESSION_CMD" > "$HOME/.xsession"
  chmod 0644 "$HOME/.xsession"

  # xrdp runs as the 'xrdp' user; let it read the ssl cert.
  $SUDO adduser xrdp ssl-cert 2>/dev/null || true

  # Change the listen port (avoids clashing with the Windows host's own 3389).
  $SUDO sed -i "s/^port=.*/port=${RDP_PORT}/" /etc/xrdp/xrdp.ini

  # Make the WM launch XFCE via the user's .xsession.
  if [[ -f /etc/xrdp/startwm.sh ]]; then
    $SUDO sed -i 's/^test -x \/etc\/X11\/Xsession.*/#&/' /etc/xrdp/startwm.sh 2>/dev/null || true
    $SUDO sed -i 's/^exec \/etc\/X11\/Xsession.*/#&/'    /etc/xrdp/startwm.sh 2>/dev/null || true
    append_once /etc/xrdp/startwm.sh "$DESKTOP_SESSION_CMD"
  fi

  # WSL has no real display manager; make sure dbus dir exists.
  $SUDO install -d -m 0755 /var/run/dbus

  enable_service xrdp
  enable_service xrdp-sesman

  ok "xrdp configured. Connect from Windows: mstsc -> localhost:${RDP_PORT}"
}

# ---------------------------------------------------------------------------
# Step 5: VNC via TigerVNC
# ---------------------------------------------------------------------------
setup_vnc() {
  log "Setting up TigerVNC on display :${VNC_DISPLAY} (port $((5900 + VNC_DISPLAY)))"
  apt_install tigervnc-standalone-server tigervnc-common

  mkdir -p "$HOME/.vnc"
  cat > "$HOME/.vnc/xstartup" <<EOF
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XKL_XMODMAP_DISABLE=1
[ -r "\$HOME/.Xresources" ] && xrdb "\$HOME/.Xresources"
dbus-launch --exit-with-session ${DESKTOP_SESSION_CMD}
EOF
  chmod +x "$HOME/.vnc/xstartup"

  warn "Set a VNC password now if you have not: run 'vncpasswd'"

  # Provide a per-user systemd service so it survives logouts (systemd required).
  if have_systemd; then
    local unit="$HOME/.config/systemd/user"
    mkdir -p "$unit"
    cat > "$unit/vncserver@.service" <<EOF
[Unit]
Description=TigerVNC server on display %i
After=syslog.target network.target

[Service]
Type=forking
ExecStartPre=-/usr/bin/vncserver -kill :%i
ExecStart=/usr/bin/vncserver :%i -geometry ${VNC_GEOMETRY} -localhost no
ExecStop=/usr/bin/vncserver -kill :%i
Restart=on-failure

[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable "vncserver@${VNC_DISPLAY}.service" 2>/dev/null || \
      warn "enable user service later with: systemctl --user enable --now vncserver@${VNC_DISPLAY}"
    ok "VNC user service installed. Start: systemctl --user start vncserver@${VNC_DISPLAY}"
  else
    ok "VNC configured. Start manually: vncserver :${VNC_DISPLAY} -geometry ${VNC_GEOMETRY} -localhost no"
  fi
  echo "     Connect a VNC viewer to localhost:$((5900 + VNC_DISPLAY))"
}

# ---------------------------------------------------------------------------
# systemd helpers (WSL only runs systemd if enabled in wsl.conf + restarted)
# ---------------------------------------------------------------------------
have_systemd() { [[ -d /run/systemd/system ]]; }

enable_service() {
  local svc="$1"
  if have_systemd; then
    $SUDO systemctl enable "$svc" >/dev/null 2>&1 || warn "could not enable $svc"
    $SUDO systemctl restart "$svc" >/dev/null 2>&1 || warn "could not start $svc (will start after WSL restart)"
  else
    warn "systemd not active yet -> '$svc' will auto-start after you run 'wsl --shutdown' and reopen Ubuntu"
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  configure_wsl_conf
  update_system
  [[ $DO_DEVTOOLS -eq 1 ]] && install_devtools

  if [[ $DO_DESKTOP -eq 1 ]]; then
    install_desktop
    install_polkit_fixes
    [[ $DO_RDP -eq 1 ]] && setup_rdp
    [[ $DO_VNC -eq 1 ]] && setup_vnc
  fi

  cat <<EOF

${c_green}=====================================================================${c_reset}
 Setup complete.

 Next steps:
   1. From Windows PowerShell:   wsl --shutdown
   2. Reopen Ubuntu (systemd + wsl.conf now active).
EOF
  [[ $DO_RDP -eq 1 && $DO_DESKTOP -eq 1 ]] && cat <<EOF
   3. RDP:  open 'mstsc' -> connect to  localhost:${RDP_PORT}
            (log in with your Linux username + password)
EOF
  [[ $DO_VNC -eq 1 && $DO_DESKTOP -eq 1 ]] && cat <<EOF
   4. VNC:  run 'vncpasswd' once, then
            systemctl --user start vncserver@${VNC_DISPLAY}
            connect a viewer to  localhost:$((5900 + VNC_DISPLAY))
EOF
  cat <<EOF

 Tip: restart your shell (or 'source ~/.bashrc') to pick up nvm / cargo / pipx.
${c_green}=====================================================================${c_reset}
EOF
}

main "$@"
