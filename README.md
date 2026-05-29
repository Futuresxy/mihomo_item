# mihomo_item

一个面向 Linux 服务器的最简 Mihomo 代理模板。适合只有一个订阅 URL、只想在服务器上开一个本地代理端口的场景。

设计目标：

- 固定 Mihomo 可执行文件路径：`~/.local/bin/mihomo`
- 固定订阅 URL 文件：`~/.local/bin/subscription.url`
- 固定配置目录：`~/.config/mihomo`
- 只使用一个 `mixed-port`，HTTP 和 SOCKS5 共用同一个端口
- `.bashrc` 只 source `~/.config/mihomo/shell-proxy.sh`
- 不依赖 `systemd --user`
- 不依赖 `nohup` 常驻；关闭 SSH 后如果进程退出，下次重新启动即可
- 不使用 `GEOIP` 规则，避免新服务器因 MMDB 下载失败而无法启动
- 自动过滤订阅里的“剩余流量/套餐到期”等信息节点

本仓库不包含订阅 token、节点 provider、cache 或个人密钥。

## 适用场景

适合以下需求：

- 服务器上需要通过 `127.0.0.1:4789` 这类本地端口访问代理
- `curl`、`git clone`、`pip`、`npm` 等命令需要临时走代理
- 不想维护复杂的 Clash/Mihomo 规则，只要能稳定连外网
- 服务器没有可用的 `systemd --user`
- 关闭终端后不强求代理进程继续运行

不适合以下需求：

- 给局域网其它机器共享代理
- 需要 TUN、透明代理、复杂分流规则
- 必须让服务开机自启或无人值守常驻

## 前置条件

服务器需要有：

- `bash`
- `curl`
- `python3`
- `git`
- `gzip`
- `ncat`，可选，只有 Git SSH 代理需要它

检查架构：

```bash
uname -m
```

常见结果：

- `x86_64`：下载 `linux-amd64`
- `aarch64` 或 `arm64`：下载 `linux-arm64`

## 一键流程

下面是从零开始的完整流程。把 `YOUR_SUBSCRIPTION_URL` 替换成自己的订阅地址即可。

### 1. 安装 Mihomo 二进制

创建固定目录：

```bash
mkdir -p ~/.local/bin
cd ~/.local/bin
```

`x86_64` 服务器使用：

```bash
curl -L -C - --retry 20 --retry-delay 5 \
  -o mihomo.gz \
  https://github.com/MetaCubeX/mihomo/releases/download/v1.19.25/mihomo-linux-amd64-v1.19.25.gz
gzip -d mihomo.gz
chmod +x mihomo
./mihomo -v
```

`aarch64` / `arm64` 服务器使用：

```bash
curl -L -C - --retry 20 --retry-delay 5 \
  -o mihomo.gz \
  https://github.com/MetaCubeX/mihomo/releases/download/v1.19.25/mihomo-linux-arm64-v1.19.25.gz
gzip -d mihomo.gz
chmod +x mihomo
./mihomo -v
```

如果下载中断，重复执行同一条 `curl -L -C - ...` 命令即可断点续传。

注意：`~/.local/bin/mihomo` 必须是真正的可执行文件，不能是目录。

### 2. 安装本项目

```bash
cd ~
git clone https://github.com/Futuresxy/mihomo_item.git
cd mihomo_item
bash install.sh --proxy-port 4789
source ~/.bashrc
```

如果不确定 `4789` 是否被占用，可以让脚本自动顺延选择端口：

```bash
bash install.sh --proxy-port 4789 --auto-port
source ~/.bashrc
```

也可以完全自动选择端口：

```bash
bash install.sh --proxy-port auto
source ~/.bashrc
```

安装完成后会生成：

```text
~/.local/bin/mihomo-gen-config
~/.local/bin/mihomo-test-nodes
~/.local/bin/mihomo-pick-node
~/.local/bin/subscription.url
~/.config/mihomo/config.yaml.in
~/.config/mihomo/config.yaml
~/.config/mihomo/shell-proxy.sh
~/.config/mihomo/providers/
```

### 3. 写入订阅并启动

第一次启动：

```bash
mihomo_up 'YOUR_SUBSCRIPTION_URL'
```

这个命令会依次完成：

1. 把订阅地址写入 `~/.local/bin/subscription.url`
2. 自动给订阅请求添加 `flag=clash.meta`
3. 下载 provider 到 `~/.config/mihomo/providers/subscription.yaml`
4. 生成 `~/.config/mihomo/config.yaml`
5. 在当前 SSH 会话后台启动 Mihomo
6. 执行 `proxy_on`
7. 打印运行状态

验证代理：

```bash
curl -I https://github.com
curl -I https://api.openai.com
```

## 日常使用

重新登录服务器后：

```bash
source ~/.bashrc
mihomo_up
```

如果已经有可用的 `providers/subscription.yaml`，不想重新下载订阅：

```bash
mihomo_use_existing_provider
proxy_on
```

只开启当前 shell 和 Git 的代理环境变量：

```bash
proxy_on
```

关闭当前 shell 和 Git 的代理环境变量：

```bash
proxy_off
```

查看代理环境变量：

```bash
proxy_status
```

查看 Mihomo 进程和端口：

```bash
mihomo_status
```

查看日志：

```bash
mihomo_logs
```

停止 Mihomo：

```bash
mihomo_stop
```

重启 Mihomo：

```bash
mihomo_restart
```

前台运行调试：

```bash
mihomo_run
```

## 端口说明

安装时通过 `--proxy-port` 指定代理端口：

```bash
bash install.sh --proxy-port 4789
```

这个端口会写入 Mihomo 的 `mixed-port`。因此 HTTP 和 SOCKS5 都走同一个端口：

```text
http://127.0.0.1:4789
socks5://127.0.0.1:4789
```

API 控制端口默认是 `31990`：

```text
http://127.0.0.1:31990
```

`127.0.0.1` 是本机回环地址。每台机器的 `127.0.0.1` 都只代表它自己。在服务器上配置 `127.0.0.1:4789`，意思是只有这台服务器自己的命令能访问这个代理端口。

如果 `4789` 被旧进程占用，先检查：

```bash
ss -ltnp | grep ':4789'
```

如果确认是旧 Mihomo，可以停止旧进程后重新安装或启动。

## 订阅 URL

订阅 URL 的固定位置是：

```text
~/.local/bin/subscription.url
```

推荐使用命令写入：

```bash
mihomo_up 'YOUR_SUBSCRIPTION_URL'
```

之后更新订阅只需要：

```bash
mihomo_up
```

脚本会自动添加 `flag=clash.meta`，订阅 URL 里不需要手动添加。

如果订阅站直连很慢或失败，但你已经有可用的 provider 文件，可以跳过下载：

```bash
mkdir -p ~/.config/mihomo/providers
# 把可用的 subscription.yaml 放到 ~/.config/mihomo/providers/subscription.yaml
mihomo_use_existing_provider
proxy_on
```

## 节点选择和测速

查看节点，默认按订阅原始顺序显示，编号稳定：

```bash
mihomo_test
```

按延迟排序显示：

```bash
mihomo_test --sort
```

自动选择延迟最低的节点：

```bash
mihomo_test --best
```

按当前显示编号选择节点：

```bash
mihomo_test --pick 8
```

按订阅原始顺序选择节点：

```bash
mihomo_pick
mihomo_pick 8
```

配置模板会过滤常见信息节点，例如“剩余流量”“套餐到期”。如果仍然选到了不可用节点，先执行：

```bash
mihomo_test --best
curl -I https://github.com
```

## Git 使用

执行 `proxy_on` 后，脚本会配置：

- `http_proxy`
- `https_proxy`
- `all_proxy`
- `git http.proxy`
- `git https.proxy`
- `git core.sshCommand`
- `GIT_SSH_COMMAND`

HTTPS clone：

```bash
proxy_on
git clone https://github.com/Futuresxy/mihomo_item.git
```

SSH clone 需要服务器有可用 GitHub SSH key，并且安装了 `ncat`：

```bash
proxy_on
git clone git@github.com:Futuresxy/mihomo_item.git
```

如果想清理 Git 代理配置：

```bash
proxy_off
git config --global --unset http.proxy
git config --global --unset https.proxy
git config --global --unset core.sshCommand
unset GIT_SSH_COMMAND
```

## 目录说明

仓库内文件：

```text
bin/
  mihomo-gen-config      # 下载订阅并生成 config.yaml
  mihomo-pick-node       # 按原始顺序选择节点
  mihomo-test-nodes      # 测试节点延迟，也支持选择节点
config/
  config.yaml.in         # Mihomo 配置模板
  shell-proxy.sh         # proxy_on/proxy_off/mihomo_up 等 shell 函数
  subscription.url.example
install.sh
README.md
```

安装后关键文件：

```text
~/.local/bin/mihomo                         # Mihomo 可执行文件，需要用户自己下载
~/.local/bin/subscription.url               # 订阅 URL
~/.local/bin/mihomo-gen-config              # 生成配置工具
~/.local/bin/mihomo-test-nodes              # 测速工具
~/.local/bin/mihomo-pick-node               # 节点选择工具
~/.config/mihomo/config.yaml.in             # 已替换端口的模板
~/.config/mihomo/config.yaml                # 最终运行配置
~/.config/mihomo/providers/subscription.yaml # 下载后的节点 provider
~/.config/mihomo/shell-proxy.sh             # shell helper
~/.config/mihomo/mihomo.log                 # 日志
~/.config/mihomo/mihomo.pid                 # 当前进程 pid
```

## 常见问题

### `mihomo binary not found`

说明还没有把 Mihomo 二进制放到固定路径：

```bash
ls -l ~/.local/bin/mihomo
```

重新下载对应架构的 Mihomo，并确保：

```bash
chmod +x ~/.local/bin/mihomo
~/.local/bin/mihomo -v
```

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

通常是没有执行权限、二进制架构不匹配，或文件系统禁止执行：

```bash
ls -l ~/.local/bin/mihomo
file ~/.local/bin/mihomo
chmod +x ~/.local/bin/mihomo
~/.local/bin/mihomo -v
tail -n 80 ~/.config/mihomo/mihomo.log
```

### `curl: Failed to connect to 127.0.0.1 port 4789`

说明代理环境变量已经打开，但 Mihomo 没有监听这个端口。检查：

```bash
mihomo_status
ss -ltnp | grep ':4789'
tail -n 80 ~/.config/mihomo/mihomo.log
```

常见修复：

```bash
proxy_off
mihomo_stop
mihomo_up
```

### 订阅下载失败

先关闭当前 shell 里的代理，避免 curl 走一个不存在的本地端口：

```bash
proxy_off
mihomo_up
```

如果服务器直连订阅站仍然失败，可以在其它能访问订阅的机器生成或下载 `subscription.yaml`，再上传到：

```text
~/.config/mihomo/providers/subscription.yaml
```

然后执行：

```bash
mihomo_use_existing_provider
proxy_on
```

### Mihomo 启动时报 MMDB 或 GEOIP 错误

本项目当前模板不使用 `GEOIP` 规则。更新项目并重新安装：

```bash
cd ~/mihomo_item
git pull
bash install.sh --proxy-port 4789
source ~/.bashrc
mihomo_use_existing_provider
```

### 关闭 SSH 后代理不可用

这是当前项目的预期行为。本项目不强制使用 `systemd --user` 或 `nohup`。重新登录后执行：

```bash
source ~/.bashrc
mihomo_up
```

如果你需要长期后台运行，可以自行改用 `systemd --user`、`tmux`、`screen` 或服务器级 systemd 服务。

## 安全注意事项

- 不要把真实订阅 URL 提交到 Git。
- 不要公开 `~/.local/bin/subscription.url`。
- 不要公开 `~/.config/mihomo/providers/subscription.yaml`。
- 如果订阅 token 曾经发到公开位置，建议去订阅服务商后台重置 token。

## 更新项目

```bash
cd ~/mihomo_item
git pull
bash install.sh --proxy-port 4789
source ~/.bashrc
mihomo_up
```

如果你原来安装时用了其它端口，更新时继续使用同一个端口即可。
