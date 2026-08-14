# dsh-client — DeepSeek Harness 桌面启动器与通知中心

自制轻量客户端（Windows / PowerShell，无编译依赖）。**端到端实测通过（2026-08-14）**。

## 功能
- **启动**：检测 `dsh web` 是否在 127.0.0.1:3080 运行，未运行则自动拉起；
- **桌面应用窗口**：Edge `--app` 模式打开 Harness（无地址栏/标签页的独立窗口，像桌面 App；找不到 Edge 退回默认浏览器）；
- **托盘**：系统托盘常驻（单例锁，重复启动自动退出），双击/右键可打开 Harness 或退出；
- **静默启动**：`start-client.cmd` 以隐藏窗口方式运行 PowerShell，无控制台闪现；
- **通知弹窗**：轮询 `notify.json`（桥接插件写入），出现以下情况弹系统气泡：
  - `approval` — 需要你授权（⚠️ 警告图标）
  - `question` — 需要你回答问题（💬 信息图标）
  - `complete` — 任务完成（✅ 信息图标）
  - `error` — 运行出错（❌ 错误图标）

## 使用
```powershell
# 双击即可（推荐）
start-client.cmd
# 或命令行
powershell -NoProfile -ExecutionPolicy Bypass -STA -File client.ps1
```
加开机自启：把 `start-client.cmd` 的快捷方式放进 `shell:startup`。

## 架构（文件通道）
```
harness 事件（approval/request、ask_user_question、agent/status、agent/error）
  → 桥接插件 ntfy（监听事件）
  → fs.writeText 写 D:\plan\dsh-client\notify.json
  → 客户端主线程定时器（400ms）轮询 → ShowBalloonTip → 删除文件
```
全链路**零网络、零子进程、零 runspace**，避免 PowerShell 多线程陷阱与沙箱进程清理问题。

## 桥接插件
`bridge-notify.js` 为桥接源码（已并入会话插件 `ntfy-2`，当前 pkg-9）。
> 插件是进程级的：若重启后没有插件，按 `multi-model-collab` skill 重建（skill 内含 v3 桥接代码与客户端说明）。

## 文件
| 文件 | 说明 |
|---|---|
| `start-client.cmd` | 双击启动器（绕过执行策略） |
| `client.ps1` | 主程序（UTF-8 BOM，必须保留 BOM） |
| `bridge-notify.js` | 桥接插件源码（Host 半） |
| `client.log` | 运行日志（tick 心跳 / shown 记录） |