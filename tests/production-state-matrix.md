# 生产 Web Agent 手工状态矩阵

这些步骤会停启真实 `com.zjr.dsh-web`。它们不会被 `tests/check.sh` 自动执行。运行前先关闭正在编辑的 Web 会话，并确认重要数据已有备份。

```bash
DOMAIN="gui/$(id -u)"
PLIST="$HOME/Library/LaunchAgents/com.zjr.dsh-web.plist"
```

每个场景都记录安装前后的两项状态：

```bash
launchctl print "$DOMAIN/com.zjr.dsh-web" | grep -E 'state =|pid =' || true
launchctl print-disabled "$DOMAIN" | grep 'com.zjr.dsh-web' || true
```

## 场景 A：enabled + running

确保 enabled 并启动服务，执行 `./install.sh`。期望安装后 enabled + running。

## 场景 B：enabled + stopped/unloaded

执行 `launchctl enable`，用 `launchctl kill SIGTERM` 停止，必要时等待进程退出；或用 `bootout` 形成 unloaded。执行 `./install.sh`。期望保持 enabled，但不自动把此前 stopped/unloaded 的服务运行起来。

## 场景 C：disabled + loaded + stopped

先 `launchctl disable`，再用 `launchctl kill SIGTERM` 停止但不 bootout。执行 `./install.sh`。期望仍 disabled 且 stopped；随后菜单“启动服务”应能临时启动，但自启仍 disabled。

## 场景 D：disabled + unloaded

先 `launchctl disable`，再 `launchctl bootout`。执行 `./install.sh`。期望安装成功、仍 disabled 且不自动运行；菜单“启动服务”应成功，之后 `print-disabled` 仍显示 disabled。

## 每轮共同检查

- `launchctl print "$DOMAIN/com.zjr.dsh-menubar"` 显示 running 和 PID。
- `pgrep -x DShMenu` 只有一个 PID，且与 launchctl 所示 PID 一致。
- 再执行一次 `open ~/Applications/DShMenu.app` 后仍只有一个实例。
- 修改配置为非 3080 端口并重装后，Web 启动参数、身份探活和左键 URL 一致。
- 用另一个 HTTP 服务占用配置端口时，不得显示绿色。
- 故意让 Web plist 不可加载时，菜单操作应显示明确错误；测试后立即恢复 plist。

完成矩阵后，根据个人偏好重新设置 enabled/disabled，并通过菜单启动或停止服务。
