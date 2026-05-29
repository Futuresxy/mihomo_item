# mihomo_item

一个简化的 Linux 服务器 Mihomo 配置模板。目标是少分叉、可排错：

- Mihomo 二进制固定放在 `~/.local/bin/mihomo`
- 订阅地址固定放在 `~/.local/bin/subscription.url`
- 配置固定放在 `~/.config/mihomo`
- `.bashrc` 只 source 一个文件：`~/.config/mihomo/shell-proxy.sh`
- 不依赖 `systemd --user`
- 不使用 `nohup` 常驻；关闭 SSH 后如果进程退出，下次重新 `mihomo_restart` 即可

本仓库不包含订阅 token、节点 provider、cache 或个人密钥。

## 文件

```text
bin/
  mihomo-gen-config      # 下载订阅并生成 config.yaml
  mihomo-pick-node       # 按原始顺序选择节点
  mihomo-test-nodes      # 测试节点延迟
config/
  config.yaml.in         # mihomo 配置模板
  shell-proxy.sh         # proxy_on/proxy_off/mihomo_restart 等命令
  subscription.url.example
install.sh
```

## 安装

先把 mihomo 可执行文件放到固定位置：

```bash
mkdir -p ~/.local/bin
# 把真正的 mihomo 二进制放到 ~/.local/bin/mihomo
chmod +x ~/.local/bin/mihomo
~/.local/bin/mihomo -v
```

注意：`~/.local/bin/mihomo` 必须是可执行文件，不能是目录。

安装配置：

```bash
git clone git@github.com:Futuresxy/mihomo_item.git
cd mihomo_item
bash install.sh --proxy-port 4789
source ~/.bashrc
```

`--proxy-port 4789` 会把 Mihomo `mixed-port` 配成 `4789`。HTTP、SOCKS、Git SSH 都走同一个端口。

如果不确定端口是否被占用，可以让脚本自动选：

```bash
bash install.sh --proxy-port auto
```

或者给一个起始端口，忙了就顺延到下一个可用端口：

```bash
bash install.sh --proxy-port 4789 --auto-port
```

`127.0.0.1` 是本机回环地址。每台机器的 `127.0.0.1` 都只代表它自己；在服务器上就是服务器自己，在本地电脑上就是本地电脑自己。

## 订阅地址

固定编辑这个文件：

```bash
~/.local/bin/subscription.url
```

或者用命令写入：

```bash
mihomo_set_sub '你的订阅地址'
```

脚本会自动使用 `flag=clash.meta`，不用手动加。

## 启动

更新订阅、生成配置并在当前 SSH 会话后台启动 Mihomo：

```bash
mihomo_restart
```

开启当前 shell 和 git 代理：

```bash
proxy_on
```

查看状态：

```bash
mihomo_status
proxy_status
```

查看日志：

```bash
mihomo_logs
```

停止 Mihomo：

```bash
mihomo_stop
```

前台运行调试：

```bash
mihomo_run
```

如果新服务器直连订阅站失败，可以从一台能访问订阅的机器上传 provider：

```bash
mkdir -p ~/.config/mihomo/providers
# 把可用的 subscription.yaml 上传到 ~/.config/mihomo/providers/subscription.yaml
mihomo_use_existing_provider
proxy_on
```

这种方式会跳过订阅下载，直接使用已有的 `providers/subscription.yaml` 生成配置并启动。

## 节点

按原始顺序选择节点：

```bash
mihomo_pick
mihomo_pick 8
```

测试节点延迟，默认仍按原始顺序显示，编号稳定：

```bash
mihomo_test
```

按延迟排序显示：

```bash
mihomo_test --sort
```

自动选择最快节点：

```bash
mihomo_test --best
```

按屏幕显示编号选择：

```bash
mihomo_test --pick 8
```

## 常见问题

### `mihomo path is not a regular file`

说明 `~/.local/bin/mihomo` 是目录或其它非普通文件。修复：

```bash
ls -ld ~/.local/bin/mihomo
mv ~/.local/bin/mihomo ~/.local/bin/mihomo_dir_backup
# 重新把真正的 mihomo 二进制放到 ~/.local/bin/mihomo
chmod +x ~/.local/bin/mihomo
~/.local/bin/mihomo -v
```

### `Permission denied` 或 `Exit 126`

通常是没有执行权限、文件系统禁止执行，或二进制架构不匹配：

```bash
ls -l ~/.local/bin/mihomo
file ~/.local/bin/mihomo
chmod +x ~/.local/bin/mihomo
~/.local/bin/mihomo -v
tail -n 40 ~/.config/mihomo/mihomo.log
```

### 关闭 SSH 后代理不可用

当前设计不强求常驻。重新登录后执行：

```bash
source ~/.bashrc
mihomo_restart
proxy_on
```
