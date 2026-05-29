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

## 必须修改哪里

必须修改订阅地址：

```bash
mihomo_set_sub '你的订阅地址'
```

或者手动编辑：

```bash
~/.config/mihomo/subscription.url
```

订阅下载会自动使用 `flag=clash.meta`。使用 `mihomo_set_sub` 时不用手动加；手动编辑时只写原始订阅地址也可以，`mihomo_restart` 下载时会自动补充/替换。

## 可能需要修改哪里

如果端口冲突，修改：

```bash
~/.config/mihomo/config.yaml.in
```

默认端口：

```text
mixed-port: 31890
socks-port: 31891
external-controller: 127.0.0.1:31990
```

如果改了代理端口，也要在 shell 中对应设置：

```bash
export MIHOMO_HTTP_PROXY_PORT=31890
export MIHOMO_SOCKS_PROXY_PORT=31891
```

建议把这两行放在 `~/.bashrc` 中 source `shell-proxy.sh` 之前。

## 常用命令

更新订阅并重启 Mihomo：

```bash
mihomo_restart
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
systemctl --user status mihomo --no-pager
```

开机自启由安装脚本执行：

```bash
systemctl --user enable mihomo
```

如果服务器退出 SSH 后用户服务会停，可以按需启用 linger：

```bash
sudo loginctl enable-linger "$USER"
```

