#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
confdir="${MIHOMO_HOME:-$HOME/.config/mihomo}"
bindir="${MIHOMO_BIN_DIR:-$HOME/.local/bin}"
proxy_port="${MIHOMO_PROXY_PORT:-31890}"
controller_port="${MIHOMO_CONTROLLER_PORT:-31990}"
subscription_file="$bindir/subscription.url"
update_bashrc=1
auto_port=0

usage() {
  cat <<'EOF'
Usage: bash install.sh [options]

Options:
  --proxy-port PORT       Local mixed HTTP/SOCKS proxy port. Default: 31890
  --proxy-port auto       Pick a free proxy port starting at 31890
  --controller-port PORT  Local Mihomo controller API port. Default: 31990
  --controller-port auto  Pick a free controller port starting at 31990
  --auto-port             If a requested/default port is busy, move to the next free port
  --no-bashrc             Do not update ~/.bashrc
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

pick_free_port() {
  python3 - "$1" "$2" <<'PY'
import socket
import sys

start = int(sys.argv[1])
reserved = {int(p) for p in sys.argv[2].split(",") if p}

for port in range(start, 65536):
    if port in reserved:
        continue
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.bind(("127.0.0.1", port))
        except OSError:
            continue
    print(port)
    raise SystemExit(0)

raise SystemExit("no free port found")
PY
}

port_is_free() {
  [ "$(pick_free_port "$1" "")" = "$1" ]
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
    --auto-port)
      auto_port=1
      shift
      ;;
    --no-bashrc)
      update_bashrc=0
      shift
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

if [ "$proxy_port" = "auto" ]; then
  proxy_port="$(pick_free_port 31890 "")"
  echo "Selected free proxy port: $proxy_port"
elif ! is_port "$proxy_port"; then
  echo "Invalid --proxy-port: $proxy_port" >&2
  exit 2
fi

if [ "$controller_port" = "auto" ]; then
  controller_port="$(pick_free_port 31990 "$proxy_port")"
  echo "Selected free controller port: $controller_port"
elif ! is_port "$controller_port"; then
  echo "Invalid --controller-port: $controller_port" >&2
  exit 2
fi

if [ "$auto_port" -eq 1 ]; then
  if ! port_is_free "$proxy_port"; then
    old_proxy_port="$proxy_port"
    proxy_port="$(pick_free_port "$proxy_port" "")"
    echo "Proxy port $old_proxy_port is busy; selected free port: $proxy_port"
  fi
  if ! port_is_free "$controller_port" || [ "$controller_port" = "$proxy_port" ]; then
    old_controller_port="$controller_port"
    controller_port="$(pick_free_port "$controller_port" "$proxy_port")"
    echo "Controller port $old_controller_port is busy; selected free port: $controller_port"
  fi
fi

if [ "$proxy_port" = "$controller_port" ]; then
  echo "--proxy-port and --controller-port must be different." >&2
  exit 2
fi

mkdir -p "$confdir/providers" "$bindir"
chmod 700 "$confdir" "$confdir/providers" 2>/dev/null || true

install -m 755 "$repo_dir/bin/mihomo-gen-config" "$bindir/mihomo-gen-config"
install -m 755 "$repo_dir/bin/mihomo-pick-node" "$bindir/mihomo-pick-node"
install -m 755 "$repo_dir/bin/mihomo-test-nodes" "$bindir/mihomo-test-nodes"

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

python3 - "$repo_dir/config/shell-proxy.sh" "$confdir/shell-proxy.sh" "$proxy_port" "$controller_port" <<'PY'
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

if [ ! -f "$subscription_file" ]; then
  install -m 600 "$repo_dir/config/subscription.url.example" "$subscription_file"
  echo "Created example subscription file: $subscription_file"
else
  chmod 600 "$subscription_file" 2>/dev/null || true
fi

if [ "$update_bashrc" -eq 1 ]; then
  touch "$HOME/.bashrc"
  python3 - "$HOME/.bashrc" <<'PY'
from pathlib import Path
import sys

bashrc = Path(sys.argv[1])
text = bashrc.read_text(encoding="utf-8") if bashrc.exists() else ""

blocks = [
    ("# >>> mihomo user proxy >>>", "# <<< mihomo user proxy <<<"),
    ("# >>> mihomo helper commands >>>", "# <<< mihomo helper commands <<<"),
]

for start_marker, end_marker in blocks:
    while True:
        start = text.find(start_marker)
        if start == -1:
            break
        end = text.find(end_marker, start)
        if end == -1:
            break
        end += len(end_marker)
        text = text[:start].rstrip() + "\n" + text[end:].lstrip()

source_block = """# >>> mihomo user proxy >>>
if [ -f "$HOME/.config/mihomo/shell-proxy.sh" ]; then
  . "$HOME/.config/mihomo/shell-proxy.sh"
fi
# <<< mihomo user proxy <<<
"""

updated = text.rstrip()
if updated:
    updated += "\n\n"
updated += source_block
bashrc.write_text(updated, encoding="utf-8")
print("Updated ~/.bashrc with a minimal mihomo source block.")
PY
else
  echo "Skipped ~/.bashrc update. Manually source: $confdir/shell-proxy.sh"
fi

echo
echo "Install complete."
echo "Configured proxy port: $proxy_port"
echo "Configured controller port: $controller_port"
echo "Subscription file: $subscription_file"
echo "Mihomo binary path: $bindir/mihomo"

if [ -d "$bindir/mihomo" ]; then
  echo
  echo "Problem: $bindir/mihomo is a directory, but it must be the mihomo executable file."
  echo "Move that directory away and put the actual mihomo binary at: $bindir/mihomo"
elif [ ! -e "$bindir/mihomo" ]; then
  echo
  echo "Next required step: put the mihomo executable at: $bindir/mihomo"
elif [ ! -x "$bindir/mihomo" ]; then
  echo
  echo "Next required step: chmod +x $bindir/mihomo"
fi

echo
echo "Next commands:"
echo "  source ~/.bashrc"
echo "  mihomo_set_sub '<subscription_url>'"
echo "  proxy_on"
