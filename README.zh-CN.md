# DSh 菜单栏控制器（DShMenu）

[English](README.md) | 简体中文

把 DeepSeek Harness（dsh）的 Web UI 作为 macOS 登录会话内的常驻服务运行，并用原生 AppKit 菜单栏程序控制它。服务不依赖打开的终端窗口。

> [!IMPORTANT]
> DShMenu 是独立的非官方社区项目，与 DeepSeek 没有隶属、背书或维护关系。DeepSeek Harness 目前仍处于 Developer Preview，后续版本可能包含破坏性变更。

## 架构

安装后由三个相互独立的 LaunchAgent 负责运行：

```text
DShMenu.app（LSUIElement 菜单栏程序，launchd 管理，flock 单实例）
   │ 左键打开 Web UI；右键显示控制菜单
   │ 读取 ~/.dsh/DShMenu.config.plist
   ▼
com.zjr.dsh-web
   │ ~/.dsh/dshmenu/bin/node ~/.dsh/dshmenu/bin/dsh web --port <Port>
   │ 日志写入 ~/.dsh/logs/
   ▼
DeepSeek Harness Web UI（默认 http://127.0.0.1:3080）

com.zjr.dsh-logrotate
   └─ 每日 03:15 检查日志并按需 copytruncate
```

- Web 服务：`~/Library/LaunchAgents/com.zjr.dsh-web.plist`
- 菜单栏：`~/Library/LaunchAgents/com.zjr.dsh-menubar.plist`
- 日志轮转：`~/Library/LaunchAgents/com.zjr.dsh-logrotate.plist`
- 项目管理的稳定命令路径：`~/.dsh/dshmenu/bin/{node,dsh,npm,npx,pnpm,corepack}`
- 配置：`~/.dsh/DShMenu.config.plist`
- 数据与日志根目录：`~/.dsh`（可在安装时通过 `DSH_HOME` 覆盖）

## 交互

| 操作 | 行为 |
|---|---|
| 左键点击 | 用默认浏览器打开配置端口上的 Web UI |
| 右键点击 | 显示启动、停止、重启、查看日志、自启开关和退出菜单 |
| 查看日志 | 在 App 内打开只读日志窗口，不调用 Terminal 或 osascript |
| 状态点 | 绿=服务正常；黄=启动中或异常；橙=外部实例/端口身份不符；灰=已停止 |

状态判断同时参考 launchd 和 DSh 身份探活。仅端口有任意 HTTP 响应不再视为 DSh 已就绪。

> macOS Tahoe 存在菜单栏最顶边右键事件未送达应用的系统回归。在屏幕顶边点不到右键菜单时，把指针向下移动少许后再点。应用不使用全局事件监听或辅助功能权限绕过这一限制。

## 安装

要求：macOS 12 或更高版本、兼容的 Node.js、已经安装且可执行的 `dsh`，以及包含 `swiftc`/`codesign` 的 Xcode Command Line Tools。首个版本已在 macOS 26.6.1（Apple Silicon）、Node.js 24.18.0、dsh 0.1.0-rc.6 上验证。

先安装依赖：

```bash
xcode-select --install
npm install -g @deepseek-ai/dsh
dsh --version
```

安装器不会静默安装或升级全局 dsh。

```bash
git clone https://github.com/zjrjohnny/dsh-menubar-macos.git
cd dsh-menubar-macos
./install.sh
```

默认使用仓库的上级目录作为 Web workspace 根。可显式指定其他已存在目录：

```bash
DSH_WORKDIR="$HOME/Documents" ./install.sh
```

安装器会：

1. 确认全局 `dsh` CLI 可用，并刷新 `~/.dsh/dshmenu/bin` 中的项目管理软链。
2. 编译 App，完成 bundle 后进行显式 ad-hoc 签名并验证签名。
3. 创建默认配置（若尚不存在），生成并校验三个 LaunchAgent plist。
4. 仅通过 launchd 拉起菜单栏 App，避免 `open` 与 launchd 抢单实例锁。
5. 首次安装默认启用并运行 Web 服务。

如果切换失败，安装器会尽力恢复安装前的 App、plist 和 launchd 状态。也可以只构建并检查、不修改任何已安装文件或 job：

```bash
./install.sh --check
```

如果终端中已有手动启动的 `dsh web`，请先退出该进程，以免两个实例争用同一端口或 `DSH_HOME`。

## 配置端口

配置文件是标准 property list，顶层 `Port` 必须是 `1...65535` 的整数。首次安装默认写入 3080：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Port</key>
  <integer>3080</integer>
</dict>
</plist>
```

修改端口后重跑安装器，使 Web Agent 的启动参数与菜单栏读取的配置保持一致：

```bash
/usr/libexec/PlistBuddy -c 'Set :Port 3090' ~/.dsh/DShMenu.config.plist
./install.sh
```

## 重新安装与升级

Node.js（包括 nvm 当前版本）或 dsh 升级后，重跑 `./install.sh` 即可。服务 plist 始终引用项目管理的稳定软链，不直接记录某个 nvm 版本目录。

已安装环境重跑安装器时，Web 服务的两个状态维度分别保留：

- 原来 disabled，安装后仍 disabled；原来 enabled，安装后仍 enabled。
- 原来 running，安装后恢复 running；原来 stopped 或 unloaded，安装后保持 stopped（可以处于 loaded 状态）。
- 只有首次安装采用 enabled + running 默认值。

安装器会等待旧菜单栏实例完全退出，再 bootstrap 新实例；安装完成后 DShMenu 的 PID 应归属于 `com.zjr.dsh-menubar`，不会再额外执行 `open`。

## 日志与轮转

- 标准输出：`~/.dsh/logs/dsh-web.out.log`
- 标准错误：`~/.dsh/logs/dsh-web.err.log`
- 菜单栏 App 的“查看日志”会打开内部只读窗口。

日志轮转 Agent 在加载时以及每天 03:15 执行一次检查。只有单个 `*.log` **大于 10 MiB** 时才轮转；采用 copytruncate 保持 launchd 已打开的 inode，保留 `.1` 到 `.5` 共 5 份历史副本。复制与截断之间存在很短的竞态窗口，极少量恰在该时刻写入的内容可能重复或遗漏；这不是事务型归档。

## 手动命令速查

```bash
DOMAIN="gui/$(id -u)"
launchctl kickstart -k "$DOMAIN/com.zjr.dsh-web"       # 启动或重启
launchctl kill SIGTERM "$DOMAIN/com.zjr.dsh-web"      # 优雅停止，job 仍 loaded
launchctl print "$DOMAIN/com.zjr.dsh-web"              # 查看 launchd 状态
launchctl print-disabled "$DOMAIN"                     # 查看自启偏好
```

`launchctl kill` 只发送信号，并不等价于 `bootout`。另外，`launchctl print` 和 `print-disabled` 的文本输出不是稳定 API，应用解析失败时会显示 unknown，而不会猜测 enabled。

## 验收

先运行完全隔离的自动检查；它使用临时 `DSH_HOME`，默认不修改生产 LaunchAgent：

```bash
./tests/check.sh
```

可选的 throwaway LaunchAgent 状态矩阵使用专用固定测试 label，并通过 trap 强制清理 job 和临时文件。`launchctl` 没有删除单项 override 的接口，因此使用固定 label 可避免重复测试不断留下新记录：

```bash
RUN_LAUNCHCTL_MATRIX=1 ./tests/check.sh
```

生产环境的只读检查：

```bash
DOMAIN="gui/$(id -u)"
launchctl print "$DOMAIN/com.zjr.dsh-web" | grep -E 'state =|program =|arguments ='
launchctl print "$DOMAIN/com.zjr.dsh-menubar" | grep -E 'state =|pid =|program ='
launchctl print "$DOMAIN/com.zjr.dsh-logrotate" | grep -E 'state =|last exit code'
launchctl print-disabled "$DOMAIN" | grep 'com.zjr.dsh-web'
/usr/bin/codesign --verify --deep --strict --verbose=2 ~/Applications/DShMenu.app
```

需要人为操作的生产状态矩阵（会停启服务）记录在 [`tests/production-state-matrix.md`](tests/production-state-matrix.md)。请先读完再执行；`tests/check.sh` 不会自动运行这些命令。

## 共享 DSH_HOME 的并发限制

Web 与 CLI 默认共用 `~/.dsh`。目前没有证据证明 dsh 对 sessions/storages 的 JSON、zstd 文件提供跨进程锁或原子更新，因此不要同时运行两个会写入同一 `DSH_HOME` 的实例。端口不同并不能消除数据竞态。

安全压力测试必须使用全新的临时 `DSH_HOME`、可重复的真实 dsh 写操作，并在每轮后验证 JSON 可解析、zstd 可解压以及业务记录无丢失。当前项目不知道上游 CLI 哪些命令能稳定地产生这些写入，因而不提供会虚假宣称覆盖业务并发的自动测试。详细测试设计见 [`tests/concurrency-plan.md`](tests/concurrency-plan.md)。

## 卸载

```bash
./uninstall.sh
```

卸载脚本移除 App、LaunchAgent、项目管理的运行链接和服务日志；保留 `~/.dsh` 中的会话、存储与 `DShMenu.config.plist` 端口配置，也不会卸载全局 dsh。执行前请阅读脚本输出确认实际范围。

## 发布与许可

项目采用源码优先发布：在用户自己的 Mac 上编译并进行 ad-hoc 签名。未使用 Apple Developer ID 签名和公证前，不发布预编译 App 下载包，避免 Gatekeeper 带来的安全提示。

DShMenu 采用 [MIT License](LICENSE)。上游署名和非官方项目声明见 [NOTICE.md](NOTICE.md)。

## 文件结构

```text
dsh-menubar/
├── DShMenu/main.swift
├── DShMenu/Info.plist
├── DShMenu.config.plist.template
├── build_app.sh
├── install.sh
├── uninstall.sh
├── rotate_logs.sh
├── com.zjr.dsh-*.plist.template
└── tests/
    ├── check.sh
    ├── test_launchctl_disabled_matrix.sh
    ├── production-state-matrix.md
    └── concurrency-plan.md
```
