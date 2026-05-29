#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
confdir="${MIHOMO_HOME:-$HOME/.config/mihomo}"
bindir="${MIHOMO_BIN_DIR:-$HOME/.local/bin}"
unitdir="${MIHOMO_SYSTEMD_USER_DIR:-$HOME/.config/systemd/user}"

mkdir -p "$confdir/providers" "$bindir" "$unitdir"
chmod 700 "$confdir" "$confdir/providers" 2>/dev/null || true

install -m 755 "$repo_dir/bin/mihomo-gen-config" "$bindir/mihomo-gen-config"
install -m 755 "$repo_dir/bin/mihomo-pick-node" "$bindir/mihomo-pick-node"
install -m 755 "$repo_dir/bin/mihomo-test-nodes" "$bindir/mihomo-test-nodes"
install -m 600 "$repo_dir/config/config.yaml.in" "$confdir/config.yaml.in"
install -m 600 "$repo_dir/config/shell-proxy.sh" "$confdir/shell-proxy.sh"
install -m 644 "$repo_dir/systemd/mihomo.service" "$unitdir/mihomo.service"

if [ ! -f "$confdir/subscription.url" ]; then
  install -m 600 "$repo_dir/config/subscription.url.example" "$confdir/subscription.url"
  echo "Created example subscription file: $confdir/subscription.url"
  echo "Edit it before running mihomo_restart."
fi

if ! grep -q 'mihomo user proxy' "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" <<'EOF'

# >>> mihomo user proxy >>>
if [ -f "$HOME/.config/mihomo/shell-proxy.sh" ]; then
  . "$HOME/.config/mihomo/shell-proxy.sh"
fi
# <<< mihomo user proxy <<<

# >>> mihomo helper commands >>>
alias setproxy='proxy_on'
alias unsetproxy='proxy_off'

mihomo_status() {
  systemctl --user status mihomo --no-pager
}

mihomo_logs() {
  journalctl --user -u mihomo -f
}

mihomo_restart() {
  "$HOME/.local/bin/mihomo-gen-config" && systemctl --user restart mihomo
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
  "$HOME/.local/bin/mihomo-gen-config" && systemctl --user restart mihomo
}
# <<< mihomo helper commands <<<
EOF
  echo "Appended mihomo shell helpers to ~/.bashrc"
else
  echo "~/.bashrc already contains mihomo helper block; left it unchanged."
fi

systemctl --user daemon-reload
systemctl --user enable mihomo

echo
echo "Install complete."
echo "Next steps:"
echo "  1. Put your subscription URL in: $confdir/subscription.url"
echo "     or run: mihomo_set_sub '<subscription_url>'"
echo "  2. Ensure mihomo binary exists at: $bindir/mihomo"
echo "  3. Run: source ~/.bashrc"
echo "  4. Run: mihomo_restart"
echo "  5. Run: proxy_on"

