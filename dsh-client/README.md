# dsh-client — DeepSeek Harness 桌面客户端（启动器 + 托盘 + 通知）

Windows / PowerShell，无编译依赖。**端到端已验证（2026-08-14）**。

## 功能
- **启动/自愈**：检测 `dsh web`（127.0.0.1:3080），未运行则启动；启动输出进 `dsh-web.boot.log`，失败自动重试 3 次、连续两次探测防假阳性；
- **桌面应用窗口**：Edge `--app` 模式（独立窗口，无地址栏/标签页）；
- **托盘**：单例常驻（v2 互斥锁），双击/右键打开或退出；
- **通知弹窗**：每 1s 轮询 `http://127.0.0.1:3080/dsh-notify.json`（桥接插件的内存路由，UTF-8 解码）：
  - `approval` — 需要你授权（⚠️）
  - `question` — 需要你回答问题（💬）
  - `complete` — 任务完成（✅）
  - `error` — 运行出错（❌）

## 使用
- 双击 `start-client.cmd`（隐藏启动）或桌面快捷方式；`restart-dsh-web.cmd`（→ `restart-dsh-web.ps1`，清理+重试）/ `start-dsh-web.cmd` 管理 dsh web 启停。
- 打不开时：看 `dsh-web.boot.log`（启停日志）与 `client.log`（轮询/弹窗日志）。

## 常驻插件（`~/.dsh/profiles/web/`）
经 `cordis.patch.yml` 挂载，随 dsh web 启动加载、重启不丢：
| 插件 | 作用 |
|---|---|
| `plugins/dsh-ntfy-bridge/index.js` | 事件 → 内存 → `/dsh-notify.json` 路由（本目录 `bridge-notify.js` 为副本） |
| `plugins/dsh-multim/index.js` | 多模型工具包：gemini_vision / escalate_to_sol / github_api / github_push_local |
| `plugins/dsh-client-icons/index.js` | PNG 鲸鱼图标路由 + favicon 注入（任务栏图标，可选） |

> 坑（已修，供后人）：① cmd 脚本必须纯 ASCII（中文在 cmd 里会乱码拆命令）；② `.ps1` 必须 UTF-8 带 BOM；③ 宿主插件无 `harness` 沙箱内置，工具用 `ctx.tools.register` + `@deepseek-ai/dsh-tools` 的 `defineTool`，`parameters` 用属性映射格式；④ 宿主 fs 不可写会话工作区，通知走 webServer 路由而非文件。
