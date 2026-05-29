#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
confdir="${MIHOMO_HOME:-$HOME/.config/mihomo}"
bindir="${MIHOMO_BIN_DIR:-$HOME/.local/bin}"
unitdir="${MIHOMO_SYSTEMD_USER_DIR:-$HOME/.config/systemd/user}"
proxy_port="${MIHOMO_PROXY_PORT:-31890}"
controller_port="${MIHOMO_CONTROLLER_PORT:-31990}"

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

if [ ! -f "$confdir/subscription.url" ]; then
  install -m 600 "$repo_dir/config/subscription.url.example" "$confdir/subscription.url"
  echo "Created example subscription file: $confdir/subscription.url"
  echo "Edit it before running mihomo_restart."
fi

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

mihomo_status() {
  if _mihomo_user_systemd_available; then
    systemctl --user status mihomo --no-pager
  else
    echo "systemd --user is unavailable in this session."
    echo "Manual check: pgrep -af mihomo"
  fi
}

mihomo_logs() {
  if _mihomo_user_systemd_available; then
    journalctl --user -u mihomo -f
  else
    echo "systemd --user is unavailable in this session."
    echo "Start Mihomo manually or enable user linger before using journalctl --user."
  fi
}

mihomo_restart() {
  "$HOME/.local/bin/mihomo-gen-config" || return
  if _mihomo_user_systemd_available; then
    systemctl --user restart mihomo
  else
    echo "systemd --user is unavailable; config was generated but service was not restarted." >&2
    echo "Manual start command:" >&2
    echo "  nohup \"$HOME/.local/bin/mihomo\" -d \"$HOME/.config/mihomo\" -f \"$HOME/.config/mihomo/config.yaml\" > \"$HOME/.config/mihomo/mihomo.log\" 2>&1 &" >&2
    return 1
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
    echo "systemd --user is unavailable; subscription was saved and config was generated, but service was not restarted." >&2
    echo "Manual start command:" >&2
    echo "  nohup \"$HOME/.local/bin/mihomo\" -d \"$HOME/.config/mihomo\" -f \"$HOME/.config/mihomo/config.yaml\" > \"$HOME/.config/mihomo/mihomo.log\" 2>&1 &" >&2
    return 1
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
Skipped systemd --user setup: user systemd bus is unavailable.
This is common on SSH-only servers, containers, or users without linger.

After logging in with a normal user session, run:
  systemctl --user daemon-reload
  systemctl --user enable --now mihomo

If the service stops after SSH logout, ask an admin or run:
  sudo loginctl enable-linger "$USER"
EOF
fi

echo
echo "Install complete."
echo "Configured proxy port: $proxy_port"
echo "Configured controller port: $controller_port"
echo "Next steps:"
echo "  1. Put your subscription URL in: $confdir/subscription.url"
echo "     or run: mihomo_set_sub '<subscription_url>'"
echo "  2. Ensure mihomo binary exists at: $bindir/mihomo"
echo "  3. Run: source ~/.bashrc"
echo "  4. Run: mihomo_restart"
echo "  5. Run: proxy_on"
