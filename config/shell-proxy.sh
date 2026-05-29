case ":$PATH:" in
  *:"$HOME/.local/bin":*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

MIHOMO_HOME="${MIHOMO_HOME:-$HOME/.config/mihomo}"
MIHOMO_BIN="${MIHOMO_BIN:-$HOME/.local/bin/mihomo}"
MIHOMO_SUBSCRIPTION_FILE="${MIHOMO_SUBSCRIPTION_FILE:-$HOME/.local/bin/subscription.url}"
MIHOMO_PROXY_PORT="__MIHOMO_PROXY_PORT__"
MIHOMO_CONTROLLER_PORT="__MIHOMO_CONTROLLER_PORT__"
MIHOMO_HTTP_PROXY_URL="http://127.0.0.1:${MIHOMO_PROXY_PORT}"
MIHOMO_SOCKS_PROXY_URL="socks5://127.0.0.1:${MIHOMO_PROXY_PORT}"
MIHOMO_NO_PROXY="${MIHOMO_NO_PROXY:-127.0.0.1,localhost,::1}"
MIHOMO_PID_FILE="${MIHOMO_PID_FILE:-$MIHOMO_HOME/mihomo.pid}"
MIHOMO_LOG_FILE="${MIHOMO_LOG_FILE:-$MIHOMO_HOME/mihomo.log}"

_mihomo_git_ssh_command() {
  printf 'ssh -o ProxyCommand="ncat -v --proxy 127.0.0.1:%s --proxy-type socks5 %%h %%p"' "$MIHOMO_PROXY_PORT"
}

_mihomo_check_binary() {
  if [ ! -e "$MIHOMO_BIN" ]; then
    echo "mihomo binary not found: $MIHOMO_BIN" >&2
    echo "Put the mihomo executable at this exact path, then run: chmod +x $MIHOMO_BIN" >&2
    return 1
  fi
  if [ ! -f "$MIHOMO_BIN" ]; then
    echo "mihomo path is not a regular file: $MIHOMO_BIN" >&2
    if [ -d "$MIHOMO_BIN" ]; then
      echo "It is a directory. Move that directory away and put the actual executable here." >&2
      ls -la "$MIHOMO_BIN" >&2
    fi
    return 1
  fi
  if [ ! -x "$MIHOMO_BIN" ]; then
    echo "mihomo binary is not executable: $MIHOMO_BIN" >&2
    echo "Fix it with: chmod +x $MIHOMO_BIN" >&2
    return 1
  fi
}

_mihomo_running() {
  local pid state
  [ -f "$MIHOMO_PID_FILE" ] || return 1
  pid="$(cat "$MIHOMO_PID_FILE" 2>/dev/null || true)"
  [ -n "$pid" ] || return 1
  kill -0 "$pid" >/dev/null 2>&1
  state="$(ps -p "$pid" -o stat= 2>/dev/null | awk '{print $1}')"
  case "$state" in
    Z*) return 1 ;;
  esac
}

_mihomo_api_ready() {
  python3 - "$MIHOMO_CONTROLLER_PORT" <<'PY'
import sys
from urllib.request import urlopen

port = sys.argv[1]
try:
    with urlopen(f"http://127.0.0.1:{port}/proxies/PROXY", timeout=1) as resp:
        raise SystemExit(0 if resp.status == 200 else 1)
except Exception:
    raise SystemExit(1)
PY
}

proxy_on() {
  export http_proxy="$MIHOMO_HTTP_PROXY_URL"
  export https_proxy="$MIHOMO_HTTP_PROXY_URL"
  export all_proxy="$MIHOMO_SOCKS_PROXY_URL"
  export HTTP_PROXY="$http_proxy"
  export HTTPS_PROXY="$https_proxy"
  export ALL_PROXY="$all_proxy"
  export no_proxy="$MIHOMO_NO_PROXY"
  export NO_PROXY="$no_proxy"
  export GIT_SSH_COMMAND="$(_mihomo_git_ssh_command)"
  command git config --global core.sshCommand "$GIT_SSH_COMMAND" >/dev/null 2>&1 || true
  command git config --global http.proxy "$http_proxy" >/dev/null 2>&1 || true
  command git config --global https.proxy "$https_proxy" >/dev/null 2>&1 || true
}

proxy_off() {
  unset http_proxy https_proxy all_proxy
  unset HTTP_PROXY HTTPS_PROXY ALL_PROXY
  unset no_proxy NO_PROXY
  unset GIT_SSH_COMMAND
  command git config --global --unset core.sshCommand >/dev/null 2>&1 || true
  command git config --global --unset http.proxy >/dev/null 2>&1 || true
  command git config --global --unset https.proxy >/dev/null 2>&1 || true
}

proxy_status() {
  printf 'shell http_proxy=%s\n' "${http_proxy:-<unset>}"
  printf 'shell https_proxy=%s\n' "${https_proxy:-<unset>}"
  printf 'shell all_proxy=%s\n' "${all_proxy:-<unset>}"
  printf 'git GIT_SSH_COMMAND=%s\n' "${GIT_SSH_COMMAND:-<unset>}"
  printf 'git core.sshCommand=%s\n' "$(git config --global --get core.sshCommand || printf '<unset>')"
  printf 'git http.proxy=%s\n' "$(git config --global --get http.proxy || printf '<unset>')"
  printf 'git https.proxy=%s\n' "$(git config --global --get https.proxy || printf '<unset>')"
}

mihomo_start() {
  _mihomo_check_binary || return
  mkdir -p "$MIHOMO_HOME"
  if _mihomo_running; then
    echo "mihomo is already running with pid $(cat "$MIHOMO_PID_FILE")"
    return 0
  fi
  "$MIHOMO_BIN" -d "$MIHOMO_HOME" -f "$MIHOMO_HOME/config.yaml" > "$MIHOMO_LOG_FILE" 2>&1 &
  echo "$!" > "$MIHOMO_PID_FILE"
  echo "Started mihomo in this SSH session, pid $!"
  echo "Log: $MIHOMO_LOG_FILE"
  for _ in 1 2 3 4 5; do
    if _mihomo_running && _mihomo_api_ready; then
      return 0
    fi
    sleep 1
  done
  if ! _mihomo_running; then
    rm -f "$MIHOMO_PID_FILE"
    echo "mihomo exited immediately. Last log lines:" >&2
    tail -n 40 "$MIHOMO_LOG_FILE" >&2
    return 1
  fi
  echo "mihomo process is running, but controller API is not ready yet." >&2
  echo "Last log lines:" >&2
  tail -n 40 "$MIHOMO_LOG_FILE" >&2
  return 1
}

mihomo_stop() {
  local pid
  if ! _mihomo_running; then
    rm -f "$MIHOMO_PID_FILE"
    echo "mihomo is not running"
    return 0
  fi
  pid="$(cat "$MIHOMO_PID_FILE")"
  kill "$pid"
  rm -f "$MIHOMO_PID_FILE"
  echo "Stopped mihomo pid $pid"
}

mihomo_restart() {
  "$HOME/.local/bin/mihomo-gen-config" || return
  mihomo_stop >/dev/null 2>&1 || true
  mihomo_start
}

mihomo_use_existing_provider() {
  "$HOME/.local/bin/mihomo-gen-config" --skip-download || return
  mihomo_stop >/dev/null 2>&1 || true
  mihomo_start
}

mihomo_run() {
  "$HOME/.local/bin/mihomo-gen-config" || return
  _mihomo_check_binary || return
  "$MIHOMO_BIN" -d "$MIHOMO_HOME" -f "$MIHOMO_HOME/config.yaml"
}

mihomo_status() {
  if _mihomo_running; then
    echo "mihomo is running with pid $(cat "$MIHOMO_PID_FILE")"
  else
    echo "mihomo is not running"
  fi
  echo "Config: $MIHOMO_HOME/config.yaml"
  echo "Proxy:  http://127.0.0.1:$MIHOMO_PROXY_PORT"
  echo "Socks:  socks5://127.0.0.1:$MIHOMO_PROXY_PORT"
  echo "API:    http://127.0.0.1:$MIHOMO_CONTROLLER_PORT"
  echo "Log:    $MIHOMO_LOG_FILE"
}

mihomo_logs() {
  if [ -f "$MIHOMO_LOG_FILE" ]; then
    tail -f "$MIHOMO_LOG_FILE"
  else
    echo "No mihomo log found at $MIHOMO_LOG_FILE"
  fi
}

mihomo_pick() {
  "$HOME/.local/bin/mihomo-pick-node" "$@"
}

mihomo_pick_node() {
  mihomo_pick "$@"
}

mihomo_node_pick() {
  mihomo_pick "$@"
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
  mkdir -p "$HOME/.local/bin"
  printf '%s\n' "$normalized_url" > "$MIHOMO_SUBSCRIPTION_FILE"
  chmod 600 "$MIHOMO_SUBSCRIPTION_FILE"
  mihomo_restart
}

mihomo_up() {
  if [ $# -eq 1 ]; then
    mihomo_set_sub "$1" || return
  elif [ $# -eq 0 ]; then
    mihomo_restart || return
  else
    echo "usage: mihomo_up ['<subscription_url>']"
    return 1
  fi
  proxy_on
  mihomo_status
}

mihomo_help() {
  cat <<'EOF'
mihomo quick usage:
  mihomo_up '<url>'       # save subscription, start mihomo, enable proxy
  mihomo_up               # update current subscription, start mihomo, enable proxy
  mihomo_set_sub '<url>'  # save subscription, update config, restart mihomo
  mihomo_restart          # update subscription and restart mihomo in this SSH session
  mihomo_use_existing_provider
                          # generate config/start from existing providers/subscription.yaml
  mihomo_start            # start mihomo in this SSH session
  mihomo_stop             # stop mihomo started by mihomo_start/restart
  mihomo_run              # run mihomo in foreground for debugging
  mihomo_status           # show process and ports
  mihomo_logs             # follow log
  proxy_on                # enable shell/git proxy
  proxy_off               # disable shell/git proxy
  proxy_status            # show shell/git proxy status
  mihomo_test             # test nodes in original order
  mihomo_test --sort      # test nodes and sort by latency
  mihomo_test --best      # test and select fastest node
  mihomo_test --pick 8    # test and select displayed index
  mihomo_pick 8           # select node by original index without testing
  mihomo_pick_node 8      # same as mihomo_pick 8
  mihomo_node_pick 8      # same as mihomo_pick 8
EOF
}
