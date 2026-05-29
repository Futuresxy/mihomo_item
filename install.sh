#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
confdir="${MIHOMO_HOME:-$HOME/.config/mihomo}"
bindir="${MIHOMO_BIN_DIR:-$HOME/.local/bin}"
unitdir="${MIHOMO_SYSTEMD_USER_DIR:-$HOME/.config/systemd/user}"
proxy_port="${MIHOMO_PROXY_PORT:-31890}"
controller_port="${MIHOMO_CONTROLLER_PORT:-31990}"
subscription_file="${MIHOMO_SUBSCRIPTION_FILE:-$bindir/subscription.url}"
subscription_link="$confdir/subscription.url"

usage() {
  cat <<'EOF'
Usage: bash install.sh [options]

Options:
  --proxy-port PORT       Local mixed HTTP/SOCKS proxy port. Default: 31890
  --controller-port PORT  Local Mihomo controller API port. Default: 31990
  -h, --help              Show this help.

Example:
  bash install.sh --proxy-port 4789
EOF
}

is_port() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --proxy-port)
      [ "$#" -ge 2 ] || { echo "Missing value for --proxy-port" >&2; exit 2; }
      proxy_port="$2"
      shift 2
      ;;
    --controller-port)
      [ "$#" -ge 2 ] || { echo "Missing value for --controller-port" >&2; exit 2; }
      controller_port="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! is_port "$proxy_port"; then
  echo "Invalid --proxy-port: $proxy_port" >&2
  exit 2
fi

if ! is_port "$controller_port"; then
  echo "Invalid --controller-port: $controller_port" >&2
  exit 2
fi

if [ "$proxy_port" = "$controller_port" ]; then
  echo "--proxy-port and --controller-port must be different." >&2
  exit 2
fi

mkdir -p "$confdir/providers" "$bindir" "$unitdir"
chmod 700 "$confdir" "$confdir/providers" 2>/dev/null || true

install -m 755 "$repo_dir/bin/mihomo-gen-config" "$bindir/mihomo-gen-config"
install -m 755 "$repo_dir/bin/mihomo-pick-node" "$bindir/mihomo-pick-node"
install -m 755 "$repo_dir/bin/mihomo-test-nodes" "$bindir/mihomo-test-nodes"
install -m 644 "$repo_dir/systemd/mihomo.service" "$unitdir/mihomo.service"

python3 - "$repo_dir/config/config.yaml.in" "$confdir/config.yaml.in" "$proxy_port" "$controller_port" <<'PY'
from pathlib import Path
import sys

src, dst = Path(sys.argv[1]), Path(sys.argv[2])
proxy_port, controller_port = sys.argv[3], sys.argv[4]
text = src.read_text(encoding="utf-8")
text = text.replace("__MIHOMO_PROXY_PORT__", proxy_port)
text = text.replace("__MIHOMO_CONTROLLER_PORT__", controller_port)
dst.write_text(text, encoding="utf-8")
dst.chmod(0o600)
PY

python3 - "$repo_dir/config/shell-proxy.sh" "$confdir/shell-proxy.sh" "$proxy_port" <<'PY'
from pathlib import Path
import sys

src, dst = Path(sys.argv[1]), Path(sys.argv[2])
proxy_port = sys.argv[3]
text = src.read_text(encoding="utf-8").replace("__MIHOMO_PROXY_PORT__", proxy_port)
dst.write_text(text, encoding="utf-8")
dst.chmod(0o600)
PY

if [ ! -f "$subscription_file" ]; then
  if [ -f "$subscription_link" ] && [ ! -L "$subscription_link" ]; then
    install -m 600 "$subscription_link" "$subscription_file"
    echo "Migrated existing subscription file to: $subscription_file"
  else
    install -m 600 "$repo_dir/config/subscription.url.example" "$subscription_file"
    echo "Created example subscription file: $subscription_file"
    echo "Edit it before running mihomo_restart."
  fi
else
  chmod 600 "$subscription_file" 2>/dev/null || true
fi

if [ -e "$subscription_link" ] || [ -L "$subscription_link" ]; then
  if [ ! -L "$subscription_link" ]; then
    backup="$subscription_link.backup.$(date +%Y%m%d%H%M%S)"
    mv "$subscription_link" "$backup"
    echo "Backed up old config subscription file to: $backup"
  else
    rm -f "$subscription_link"
  fi
fi
ln -s "$subscription_file" "$subscription_link"
echo "Linked $subscription_link -> $subscription_file"

helper_block="$(mktemp)"
trap 'rm -f "$helper_block"' EXIT
cat > "$helper_block" <<'EOF'

# >>> mihomo user proxy >>>
if [ -f "$HOME/.config/mihomo/shell-proxy.sh" ]; then
  . "$HOME/.config/mihomo/shell-proxy.sh"
fi
# <<< mihomo user proxy <<<

# >>> mihomo helper commands >>>
alias setproxy='proxy_on'
alias unsetproxy='proxy_off'

_mihomo_user_systemd_available() {
  systemctl --user show-environment >/dev/null 2>&1
}

_mihomo_pid_file() {
  printf '%s\n' "$HOME/.config/mihomo/mihomo.pid"
}

_mihomo_is_running() {
  local pid_file pid
  pid_file="$(_mihomo_pid_file)"
  [ -f "$pid_file" ] || return 1
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  [ -n "$pid" ] || return 1
  kill -0 "$pid" >/dev/null 2>&1
}

_mihomo_check_binary() {
  local bin
  bin="$HOME/.local/bin/mihomo"
  if [ ! -e "$bin" ]; then
    echo "mihomo binary not found: $bin" >&2
    echo "Put the mihomo binary there, then run: chmod +x $bin" >&2
    return 1
  fi
  if [ ! -f "$bin" ]; then
    echo "mihomo path is not a regular file: $bin" >&2
    return 1
  fi
  if [ ! -x "$bin" ]; then
    echo "mihomo binary is not executable: $bin" >&2
    echo "Fix it with: chmod +x $bin" >&2
    return 1
  fi
}

mihomo_start() {
  if _mihomo_user_systemd_available; then
    systemctl --user start mihomo
    return
  fi
  _mihomo_check_binary || return
  if _mihomo_is_running; then
    echo "mihomo is already running with pid $(cat "$(_mihomo_pid_file)")"
    return 0
  fi
  mkdir -p "$HOME/.config/mihomo"
  nohup "$HOME/.local/bin/mihomo" \
    -d "$HOME/.config/mihomo" \
    -f "$HOME/.config/mihomo/config.yaml" \
    > "$HOME/.config/mihomo/mihomo.log" 2>&1 &
  echo "$!" > "$(_mihomo_pid_file)"
  echo "Started mihomo without systemd, pid $!"
  echo "Log: $HOME/.config/mihomo/mihomo.log"
  sleep 1
  if ! _mihomo_is_running; then
    rm -f "$(_mihomo_pid_file)"
    echo "mihomo exited immediately. Last log lines:" >&2
    tail -n 40 "$HOME/.config/mihomo/mihomo.log" >&2
    return 1
  fi
}

mihomo_stop() {
  if _mihomo_user_systemd_available; then
    systemctl --user stop mihomo
    return
  fi
  local pid_file pid
  pid_file="$(_mihomo_pid_file)"
  if ! _mihomo_is_running; then
    echo "mihomo is not running from $pid_file"
    return 0
  fi
  pid="$(cat "$pid_file")"
  kill "$pid"
  rm -f "$pid_file"
  echo "Stopped mihomo pid $pid"
}

mihomo_status() {
  if _mihomo_user_systemd_available; then
    systemctl --user status mihomo --no-pager
  elif _mihomo_is_running; then
    echo "mihomo is running without systemd, pid $(cat "$(_mihomo_pid_file)")"
    echo "Log: $HOME/.config/mihomo/mihomo.log"
  else
    echo "systemd --user is unavailable in this session."
    echo "mihomo is not running from $(_mihomo_pid_file)"
  fi
}

mihomo_logs() {
  if _mihomo_user_systemd_available; then
    journalctl --user -u mihomo -f
  elif [ -f "$HOME/.config/mihomo/mihomo.log" ]; then
    tail -f "$HOME/.config/mihomo/mihomo.log"
  else
    echo "No mihomo log found at $HOME/.config/mihomo/mihomo.log"
  fi
}

mihomo_restart() {
  "$HOME/.local/bin/mihomo-gen-config" || return
  if _mihomo_user_systemd_available; then
    systemctl --user restart mihomo
  else
    mihomo_stop >/dev/null 2>&1 || true
    mihomo_start
  fi
}

mihomo_pick() {
  "$HOME/.local/bin/mihomo-pick-node" "${1:-}"
}

mihomo_test() {
  "$HOME/.local/bin/mihomo-test-nodes" "$@"
}

mihomo_set_sub() {
  if [ $# -ne 1 ]; then
    echo "usage: mihomo_set_sub '<subscription_url>'"
    return 1
  fi
  local normalized_url
  normalized_url="$(python3 - "$1" <<'PY'
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit
import sys

raw = sys.argv[1].strip()
parts = urlsplit(raw)
query = [(k, v) for k, v in parse_qsl(parts.query, keep_blank_values=True) if k != "flag"]
query.append(("flag", "clash.meta"))
print(urlunsplit((parts.scheme, parts.netloc, parts.path, urlencode(query), parts.fragment)))
PY
)"
  mkdir -p "$HOME/.config/mihomo"
  printf '%s\n' "$normalized_url" > "$HOME/.config/mihomo/subscription.url"
  chmod 600 "$HOME/.config/mihomo/subscription.url"
  "$HOME/.local/bin/mihomo-gen-config" || return
  if _mihomo_user_systemd_available; then
    systemctl --user restart mihomo
  else
    mihomo_stop >/dev/null 2>&1 || true
    mihomo_start
  fi
}
# <<< mihomo helper commands <<<
EOF

touch "$HOME/.bashrc"
python3 - "$HOME/.bashrc" "$helper_block" <<'PY'
from pathlib import Path
import sys

bashrc = Path(sys.argv[1])
block = Path(sys.argv[2]).read_text(encoding="utf-8")
text = bashrc.read_text(encoding="utf-8") if bashrc.exists() else ""

starts = ["# >>> mihomo user proxy >>>", "# >>> mihomo helper commands >>>"]
ends = ["# <<< mihomo helper commands <<<", "# <<< mihomo user proxy <<<"]

start_positions = [text.find(marker) for marker in starts if text.find(marker) != -1]
end_positions = [text.find(marker) for marker in ends if text.find(marker) != -1]

if start_positions and end_positions:
    start = min(start_positions)
    end_marker = max(ends, key=lambda marker: text.find(marker))
    end = text.find(end_marker) + len(end_marker)
    updated = text[:start].rstrip() + "\n" + block.rstrip() + "\n" + text[end:].lstrip()
    action = "Updated"
else:
    prefix = text.rstrip()
    updated = (prefix + "\n" if prefix else "") + block.rstrip() + "\n"
    action = "Appended"

bashrc.write_text(updated, encoding="utf-8")
print(f"{action} mihomo shell helpers in ~/.bashrc")
PY

if systemctl --user show-environment >/dev/null 2>&1; then
  systemctl --user daemon-reload
  systemctl --user enable mihomo
  echo "Enabled mihomo user service."
else
  cat <<EOF
systemd --user is unavailable in this SSH session, so install will use the built-in nohup fallback.
This is OK on SSH-only servers, containers, or users without linger.

After setting your subscription, run:
  source ~/.bashrc
  mihomo_restart
  proxy_on

The fallback writes:
  PID: $HOME/.config/mihomo/mihomo.pid
  Log: $HOME/.config/mihomo/mihomo.log

Optional: if you want systemd --user instead, ask an admin or run:
  sudo loginctl enable-linger "$USER"
EOF
fi

echo
echo "Install complete."
echo "Configured proxy port: $proxy_port"
echo "Configured controller port: $controller_port"
echo "Next steps:"
echo "  1. Put your subscription URL in: $subscription_file"
echo "     or run: mihomo_set_sub '<subscription_url>'"
echo "  2. Ensure mihomo binary exists at: $bindir/mihomo"
echo "  3. Run: source ~/.bashrc"
echo "  4. Run: mihomo_restart"
echo "  5. Run: proxy_on"
