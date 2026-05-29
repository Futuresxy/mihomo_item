case ":$PATH:" in
  *:"$HOME/.local/bin":*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

MIHOMO_HTTP_PROXY_PORT="${MIHOMO_HTTP_PROXY_PORT:-31890}"
MIHOMO_SOCKS_PROXY_PORT="${MIHOMO_SOCKS_PROXY_PORT:-31891}"
MIHOMO_HTTP_PROXY_URL="${MIHOMO_HTTP_PROXY_URL:-http://127.0.0.1:${MIHOMO_HTTP_PROXY_PORT}}"
MIHOMO_SOCKS_PROXY_URL="${MIHOMO_SOCKS_PROXY_URL:-socks5://127.0.0.1:${MIHOMO_SOCKS_PROXY_PORT}}"
MIHOMO_NO_PROXY="${MIHOMO_NO_PROXY:-127.0.0.1,localhost,::1}"

_mihomo_git_ssh_command() {
  printf 'ssh -o ProxyCommand="ncat -v --proxy 127.0.0.1:%s --proxy-type socks5 %%h %%p"' "$MIHOMO_SOCKS_PROXY_PORT"
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

