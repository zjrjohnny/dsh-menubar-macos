# DShMenu 安装与使用教程

## 检查与升级 DSH

右键菜单栏图标 → **检查 DSH 更新…**，显示本机版本与 npm 官方 `latest`。
不会检查 `alpha`/`next` 通道，不会自动安装或重启。发现更新时可复制命令。
确认第三方插件兼容后，先停止 Web 服务，再在终端执行
`npm install -g @deepseek-ai/dsh@latest`；验证 `dsh --version` 后启动服务。
若同时升级了 nvm Node 版本，请从源码安装目录重跑 `bash install.sh` 刷新软链。
新版 DSH 会要求认证链接，请通过菜单栏打开网页，而非手工输入裸地址。

本教程适用于 GitHub Release 中的 `macos-source-installer.zip`。安装包携带源码，App 会在你的 Mac 上本地编译并进行 ad-hoc 签名；它不是未经公证的预编译 `.pkg`。

## 1. 安装前准备

需要 macOS 12 或更高版本，以及已经可用的 Node.js、DeepSeek Harness 和 Xcode Command Line Tools：

```bash
xcode-select --install
npm install -g @deepseek-ai/dsh
node --version
dsh --version
```

安装器不会请求管理员权限，也不会自动安装或升级全局 dsh。

## 2. 下载并校验安装包

从 [最新 Release](https://github.com/zjrjohnny/dsh-menubar-macos/releases/latest) 下载同版本的两个文件：

- `DShMenu-vX.Y.Z-macos-source-installer.zip`
- `DShMenu-vX.Y.Z-macos-source-installer.sha256`

在“终端”中进入下载目录并验证：

```bash
cd "$HOME/Downloads"
shasum -a 256 -c DShMenu-v*-macos-source-installer.sha256
```

看到 `OK` 后再解压。校验失败时不要运行其中的脚本，请重新下载并核对 Release 地址。

## 3. 安装

解压 ZIP，进入解压后的目录，然后运行：

```bash
./Install.command
```

安装器会询问 Web 工作目录，默认是 `~/Documents`。这个目录会成为 dsh Web UI 的 workspace 根，请不要选择包含不希望 dsh 浏览的私人文件的上级目录。

也可以直接指定目录并跳过询问：

```bash
DSH_WORKDIR="$HOME/Documents/deepseek" ./Install.command
```

如果 Finder 阻止双击 `.command`，请使用上面的终端命令。不要通过关闭系统安全功能来绕过 Gatekeeper。

安装过程会在本机编译 App、验证 ad-hoc 签名、生成三个用户级 LaunchAgent，并安装到：

- App：`~/Applications/DShMenu.app`
- LaunchAgent：`~/Library/LaunchAgents/com.zjr.dsh-*.plist`
- 配置：`~/.dsh/DShMenu.config.plist`
- 日志：`~/.dsh/logs/`

## 4. 日常使用

- 左键菜单栏图标：打开 dsh Web UI。
- 右键菜单栏图标：启动、停止、重启、查看日志、切换登录自启或退出。
- 绿点：服务正常；黄点：正在启动或异常；橙/红点：外部服务或端口冲突；灰点：已停止。
- “退出菜单栏”不会停止 Web；需要一起停止时选择“停止服务并退出”。

macOS Tahoe 如果在菜单栏最顶边无法右键，请把指针向下移动几像素后再试。

## 5. 修改端口

默认端口是 3080。修改后必须重新运行安装器，使菜单栏和 LaunchAgent 保持一致：

```bash
/usr/libexec/PlistBuddy -c 'Set :Port 3090' ~/.dsh/DShMenu.config.plist
./Install.command
```

## 6. 升级

下载新版本安装包并校验，在新目录中再次运行 `./Install.command`。安装器会保留现有端口、自启偏好和 Web 服务的运行/停止状态。

Node.js 或 dsh 升级后也应重跑安装器，以刷新项目管理的稳定命令链接。

## 7. 排错

先执行不改动已安装服务的预检：

```bash
DSHMENU_NO_PAUSE=1 ./Install.command --check
```

常见检查：

```bash
dsh --version
lsof -nP -iTCP:3080 -sTCP:LISTEN
launchctl list | grep -i dsh
```

日志可从右键菜单的“查看日志”打开。不要把可能包含会话内容的完整日志直接贴到公开 Issue；请先脱敏，安全问题应按照 [SECURITY.md](SECURITY.md) 私下报告。

## 8. 卸载

在安装包目录运行：

```bash
./Uninstall.command
```

卸载会移除 App、三个 LaunchAgent、项目管理的命令链接和服务日志，但保留 dsh 的 sessions、storages、端口配置以及全局 dsh CLI。

## 数据安全提醒

- Web 服务正常情况下应只监听 `127.0.0.1`；不要把它转发到公网。
- 不要同时运行两个写入同一 `DSH_HOME` 的 Web/CLI 实例，避免会话和存储数据竞态。
- 重要会话应定期备份；DShMenu 不会替代数据备份。
