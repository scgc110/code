# dsh-client.ps1 — DeepSeek Harness 桌面启动器 + 通知中心 (v3: 文件通道)
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -STA -File client.ps1
param(
  [string]$HarnessUrl = 'http://127.0.0.1:3080',
  [int]$HarnessPort = 3080,
  [switch]$NoBrowser
)
$ErrorActionPreference = 'Stop'
$script:LogPath = Join-Path $PSScriptRoot 'client.log'
$script:NotifyFile = Join-Path $PSScriptRoot 'notify.json'

# 单例：防止重复双击起多个实例抢同一份通知
$script:Mutex = New-Object System.Threading.Mutex($false, 'dsh-client-singleton')
if (-not $script:Mutex.WaitOne(0)) {
  Write-Host 'dsh-client 已在运行，本次启动退出。'
  exit 0
}

function Write-Log($m) { try { [System.IO.File]::AppendAllText($script:LogPath, "[$(Get-Date -Format 'HH:mm:ss')] $m`r`n") } catch { } }
Write-Log 'client v3 started'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Test-Port([int]$Port) {
  $c = New-Object System.Net.Sockets.TcpClient
  try { $c.Connect('127.0.0.1', $Port); return $true } catch { return $false } finally { $c.Dispose() }
}

# 桌面应用窗口：Edge --app 模式（无地址栏/标签页的独立窗口），找不到 Edge 时退回默认浏览器
function Open-HarnessApp {
  $edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") |
    Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
  if ($edge) {
    Start-Process -FilePath $edge -ArgumentList "--app=$HarnessUrl" | Out-Null
    Write-Log 'opened Edge app window'
  } else {
    Start-Process $HarnessUrl | Out-Null
    Write-Log 'opened default browser'
  }
}

# ---- 1) 确保 dsh web 在运行 ----
if (-not (Test-Port $HarnessPort)) {
  try { Start-Process -FilePath 'cmd.exe' -ArgumentList '/c','start "" /min dsh web' -WindowStyle Hidden | Out-Null } catch { }
  for ($i = 0; $i -lt 60 -and -not (Test-Port $HarnessPort); $i++) { Start-Sleep -Milliseconds 1000 }
}
if (Test-Port $HarnessPort) {
  if (-not $NoBrowser) { Open-HarnessApp }
} else {
  Write-Host '[dsh-client] dsh web 未检测到，请手动运行 dsh web 后重试。' -ForegroundColor Yellow
}

# ---- 2) 托盘 ----
$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = [System.Drawing.SystemIcons]::Application
$notify.Text = 'dsh-client'
$notify.Visible = $true
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$open = $menu.Items.Add('打开 Harness')
$open.Add_Click({ Open-HarnessApp })
$exitItem = $menu.Items.Add('退出')
$exitItem.Add_Click({ $notify.Visible = $false; [System.Windows.Forms.Application]::Exit() })
$notify.ContextMenuStrip = $menu
$notify.Add_MouseDoubleClick({ Open-HarnessApp })

# ---- 3) 通知：主 STA 线程定时轮询 notify.json（桥接插件写入）----
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 400
$script:TickCount = 0
$timer.Add_Tick({
  $script:TickCount++
  if (($script:TickCount % 50) -eq 0) { Write-Log ("tick alive x" + $script:TickCount) }
  try {
    if (Test-Path -LiteralPath $script:NotifyFile -PathType Leaf) {
      $raw = Get-Content -Raw -Encoding UTF8 -LiteralPath $script:NotifyFile
      $json = $raw | ConvertFrom-Json
      $t = [System.Windows.Forms.ToolTipIcon]::Info
      if ($json.type -eq 'error') { $t = [System.Windows.Forms.ToolTipIcon]::Error }
      elseif ($json.type -eq 'approval') { $t = [System.Windows.Forms.ToolTipIcon]::Warning }
      $title = [string]$json.title
      $body = [string]$json.body
      if ($body.Length -gt 300) { $body = $body.Substring(0, 300) + '…' }
      $notify.ShowBalloonTip(12000, $title, $body, $t)
      Write-Log ("shown: $title")
      Remove-Item -LiteralPath $script:NotifyFile -Force -ErrorAction SilentlyContinue
      Write-Log 'notify.json consumed'
    }
  } catch {
    Write-Log ('tick err: ' + $_.Exception.ToString())
  }
})
$timer.Start()
Write-Log 'timer started'

Write-Host "[dsh-client] 就绪：托盘常驻，通知文件通道 $script:NotifyFile（Harness: $HarnessUrl）"
Write-Log "ready"
try {
  [System.Windows.Forms.Application]::Run()
} catch {
  Write-Log ('Application.Run crash: ' + $_.Exception.ToString())
  throw
} finally {
  try { $notify.Dispose() } catch { }
  try { $script:Mutex.ReleaseMutex() } catch { }
  Write-Log 'client exiting'
}