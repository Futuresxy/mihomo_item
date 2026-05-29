# mihomo_item

一个面向 Linux 服务器的 Mihomo 用户级代理模板。它把 mihomo 配置、订阅更新、shell/git/SSH 代理、节点测速和节点选择整理成一套可迁移脚本。

本仓库不包含订阅 token、节点 provider、cache 或任何个人密钥。

## 目录

```text
bin/
  mihomo-gen-config      # 下载订阅并生成 ~/.config/mihomo/config.yaml
  mihomo-pick-node       # 按订阅原始顺序选择节点
  mihomo-test-nodes      # 测试节点延迟，支持自动选择最快节点
config/
  config.yaml.in         # mihomo 主配置模板
  shell-proxy.sh         # proxy_on/proxy_off/proxy_status
  subscription.url.example
systemd/
  mihomo.service         # systemd --user 服务
install.sh               # 安装脚本
```

## 新服务器安装

先准备 Mihomo 二进制：

```bash
mkdir -p ~/.local/bin
# 把 mihomo 二进制放到 ~/.local/bin/mihomo
chmod +x ~/.local/bin/mihomo
```

然后安装本仓库配置：

```bash
git clone git@github.com:Futuresxy/mihomo_item.git
cd mihomo_item
bash install.sh
source ~/.bashrc
```

如果你希望使用自定义本地代理端口，例如 `4789`：

```bash
bash install.sh --proxy-port 4789
source ~/.bashrc
```

`--proxy-port` 配置的是 Mihomo `mixed-port`，同一个端口同时支持 HTTP 和 SOCKS。因此 `proxy_on` 会设置：

```text
http_proxy=http://127.0.0.1:4789
https_proxy=http://127.0.0.1:4789
all_proxy=socks5://127.0.0.1:4789
git SSH ProxyCommand -> 127.0.0.1:4789
```

## 必须修改哪里

必须修改订阅地址：

```bash
mihomo_set_sub '你的订阅地址'
```

或者手动编辑：

```bash
~/.local/bin/subscription.url
```

订阅下载会自动使用 `flag=clash.meta`。使用 `mihomo_set_sub` 时不用手动加；手动编辑时只写原始订阅地址也可以，`mihomo_restart` 下载时会自动补充/替换。

## 可能需要修改哪里

如果端口冲突，推荐重新运行安装脚本指定端口：

```bash
bash install.sh --proxy-port 4789
source ~/.bashrc
```

或者手动修改：

```bash
~/.config/mihomo/config.yaml.in
```

默认端口：

```text
mixed-port: 31890
external-controller: 127.0.0.1:31990
```

如果只手动改配置文件，也要让 shell 代理端口一致：

```bash
export MIHOMO_PROXY_PORT=4789
```

建议把这行放在 `~/.bashrc` 中 source `shell-proxy.sh` 之前。更简单的方式还是重新运行 `bash install.sh --proxy-port 4789`，安装脚本会自动写好 `config.yaml.in` 和 `shell-proxy.sh`。

## 常用命令

更新订阅并重启 Mihomo：

```bash
mihomo_restart
```

启动 Mihomo：

```bash
mihomo_start
```

停止 Mihomo：

```bash
mihomo_stop
```

开启当前 shell、curl、git HTTP、git SSH 代理：

```bash
proxy_on
```

关闭代理：

```bash
proxy_off
```

查看代理状态：

```bash
proxy_status
```

查看服务状态：

```bash
mihomo_status
```

查看日志：

```bash
mihomo_logs
```

## 选择节点

按订阅原始顺序列出并选择节点：

```bash
mihomo_pick
mihomo_pick 8
```

测试节点延迟，默认仍按订阅原始顺序显示，编号稳定：

```bash
mihomo_test
```

按延迟排序显示：

```bash
mihomo_test --sort
```

测速后自动选择最快可用节点：

```bash
mihomo_test --best
```

测速后按屏幕显示编号选择：

```bash
mihomo_test --pick
mihomo_test --pick 8
```

## 启动服务

如果已经设置了订阅：

```bash
mihomo_restart
mihomo_status
```

安装脚本会尝试执行：

```bash
systemctl --user enable mihomo
```

如果安装时看到：

```text
Failed to connect to bus: No medium found
```

或新版安装脚本提示 `systemd --user is unavailable in this SSH session`，说明当前 SSH 会话没有可用的 user systemd bus。配置文件和命令已经安装成功，helper 会使用 `nohup` fallback 启动 Mihomo。

这种情况下仍然可以直接使用：

```bash
source ~/.bashrc
mihomo_restart
```

新版 helper 会自动退回到 `nohup` 后台启动，PID 文件在：

```text
~/.config/mihomo/mihomo.pid
```

日志在：

```text
~/.config/mihomo/mihomo.log
```

如果看到 `Exit 126`，通常表示 `~/.local/bin/mihomo` 不能执行。检查：

```bash
ls -l ~/.local/bin/mihomo
file ~/.local/bin/mihomo
chmod +x ~/.local/bin/mihomo
~/.local/bin/mihomo -v
tail -n 40 ~/.config/mihomo/mihomo.log
```

常见原因是没有执行权限、下载了错误 CPU 架构的 Mihomo 二进制，或者目录所在文件系统禁止执行。

可以在有 user bus 的会话中执行：

```bash
systemctl --user daemon-reload
systemctl --user enable --now mihomo
```

如果服务器退出 SSH 后用户服务会停，可以按需启用 linger：

```bash
sudo loginctl enable-linger "$USER"
```
