# dsh-client.ps1 — DeepSeek Harness 桌面启动器 + 通知中心 (v6: 文件通道 + 官方鲸鱼图标)
# 用法: 双击 start-client.cmd 或桌面快捷方式
param(
  [string]$HarnessUrl = 'http://127.0.0.1:3080',
  [int]$HarnessPort = 3080,
  [switch]$NoBrowser
)
$ErrorActionPreference = 'Stop'
$script:LogPath = Join-Path $PSScriptRoot 'client.log'
$script:NotifyFile = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.dsh\dsh-client-notify.json'
$script:IconFile = Join-Path $PSScriptRoot 'dsh.ico'
$script:FaviconSvg = Join-Path $PSScriptRoot 'favicon.svg'

# 单例：防止重复双击起多个实例抢同一份通知；已在运行则直接打开桌面窗口
$script:Mutex = New-Object System.Threading.Mutex($false, 'dsh-client-singleton-v2')
if (-not $script:Mutex.WaitOne(0)) {
  try {
    $e = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") |
      Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if ($e) { Start-Process -FilePath $e -ArgumentList "--app=$HarnessUrl" } else { Start-Process $HarnessUrl }
  } catch { }
  exit 0
}

function Write-Log($m) { try { [System.IO.File]::AppendAllText($script:LogPath, "[$(Get-Date -Format 'HH:mm:ss')] $m`r`n") } catch { } }
Write-Log 'client v6 started'
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

# ---- 0) 图标自愈：官方鲸鱼 favicon.svg → PNG → ICO（仅首次生成；Edge 在用户环境可用）----
if (-not (Test-Path -LiteralPath $script:IconFile)) {
  try {
    $png = Join-Path $PSScriptRoot 'dsh-logo.png'
    $svg256 = Join-Path $PSScriptRoot 'favicon-256.svg'
    # 把 SVG 的 width/height 从 50 改为 256，viewBox 会自动放大鲸鱼填满画布
    $svgText = Get-Content -Raw -Encoding UTF8 -LiteralPath $script:FaviconSvg
    $svgText = $svgText -replace 'width="50\.000000"', 'width="256"' -replace 'height="50\.000000"', 'height="256"'
    [System.IO.File]::WriteAllText($svg256, $svgText, (New-Object System.Text.UTF8Encoding($false)))
    $edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") |
      Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if ($edge -and (Test-Path -LiteralPath $svg256)) {
      Start-Process -FilePath $edge -ArgumentList '--headless','--disable-gpu','--default-background-color=00000000','--window-size=256,256',("--screenshot=$png"),('file:///' + ($svg256 -replace '\\','/')) -Wait -WindowStyle Hidden
    }
    if (Test-Path -LiteralPath $png) {
      $bmp = [System.Drawing.Bitmap]::FromFile($png)
      $icon = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
      $fs = [System.IO.File]::Create($script:IconFile)
      $icon.Save($fs); $fs.Close()
      $icon.Dispose(); $bmp.Dispose()
      Remove-Item -LiteralPath $png, $svg256 -Force -ErrorAction SilentlyContinue
      Write-Log 'dsh.ico generated from official favicon'
    }
  } catch { Write-Log ('icon gen fail: ' + $_.Exception.Message) }
}

# 更新桌面快捷方式图标（指向官方鲸鱼）
try {
  if (Test-Path -LiteralPath $script:IconFile) {
    $ws = New-Object -ComObject WScript.Shell
    $lnkPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'dsh-client.lnk'
    if (Test-Path -LiteralPath $lnkPath) {
      $lnk = $ws.CreateShortcut($lnkPath)
      $lnk.IconLocation = $script:IconFile
      $lnk.Save()
      Write-Log 'desktop shortcut icon updated'
    }
  }
} catch { Write-Log ('shortcut icon update fail: ' + $_.Exception.Message) }

# ---- 1) 确保 dsh web 在运行（强清理 + 日志 + 重试，根治 EADDRINUSE/残留进程）----
function Stop-DshProcesses {
  # 杀掉残留的 dsh 启动器/服务进程（仅匹配命令行含 dsh 特征串的 node/cmd），
  # 避免旧实例占着 3080 导致新实例 bind 失败（EADDRINUSE）
  Get-CimInstance Win32_Process | ForEach-Object {
    $cl = $_.CommandLine
    if ($cl -and (($_.Name -match '^node') -or ($_.Name -match '^cmd')) -and (
        $cl -match 'deepseek-ai[\\/]dsh' -or $cl -match 'dsh[\\/]lib[\\/]bin\.js' -or
        $cl -match 'dsh\.cmd' -or $cl -match '[\\/]start-dsh-web' -or $cl -match 'dsh\s+web')) {
      try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch { }
    }
  }
  Start-Sleep -Milliseconds 800
}

function Wait-PortFree([int]$Port) {
  for ($i = 0; $i -lt 20; $i++) {
    if (-not (Test-Port $Port)) { return $true }
    Start-Sleep -Milliseconds 500
  }
  return -not (Test-Port $Port)
}

function Start-DshWeb {
  param([int]$MaxTries = 3)
  $launcher = Join-Path $PSScriptRoot 'start-dsh-web.cmd'
  $useLauncher = Test-Path -LiteralPath $launcher
  if (-not $useLauncher) { $launcher = Join-Path $env:APPDATA 'npm\dsh.cmd' }
  for ($t = 1; $t -le $MaxTries; $t++) {
    Write-Log "dsh web attempt $t/$MaxTries"
    try {
      if ($useLauncher) {
        Start-Process -FilePath $launcher -WindowStyle Hidden | Out-Null
      } else {
        Start-Process -FilePath $launcher -ArgumentList 'web' -WindowStyle Hidden | Out-Null
      }
    } catch { Write-Log ('dsh web start err: ' + $_.Exception.Message) }
    # 端口连续 2 次探测均通才算真正就绪（防止 TIME_WAIT 假阳性）
    $ready = $false
    for ($i = 0; $i -lt 40; $i++) {
      Start-Sleep -Milliseconds 1000
      if (Test-Port $HarnessPort) {
        Start-Sleep -Milliseconds 1000
        if (Test-Port $HarnessPort) { $ready = $true; break }
      }
    }
    if ($ready) { Write-Log "dsh web ready (attempt $t)"; return $true }
    Write-Log "dsh web attempt $t failed (port not ready)"
    Stop-DshProcesses
    Wait-PortFree $HarnessPort | Out-Null
    Start-Sleep -Seconds 1
  }
  return $false
}

# 端口未被监听时才启动；启动前清理残留，确保无 EADDRINUSE
if (-not (Test-Port $HarnessPort)) {
  Stop-DshProcesses
  Wait-PortFree $HarnessPort | Out-Null
  $null = Start-DshWeb
}
if (Test-Port $HarnessPort) {
  if (-not $NoBrowser) { Open-HarnessApp }
} else {
  Write-Host '[dsh-client] dsh web 启动失败（已重试）。日志：dsh-web.boot.log' -ForegroundColor Yellow
  Write-Log 'dsh web FAILED after retries'
}

# ---- 2) 托盘（官方鲸鱼图标）----
$notify = New-Object System.Windows.Forms.NotifyIcon
if (Test-Path -LiteralPath $script:IconFile) {
  $notify.Icon = New-Object System.Drawing.Icon($script:IconFile)
} else {
  $notify.Icon = [System.Drawing.SystemIcons]::Application
}
$notify.Text = 'dsh-client'
$notify.Visible = $true
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$open = $menu.Items.Add('打开 Harness')
$open.Add_Click({ Open-HarnessApp })
$exitItem = $menu.Items.Add('退出')
$exitItem.Add_Click({ $notify.Visible = $false; [System.Windows.Forms.Application]::Exit() })
$notify.ContextMenuStrip = $menu
$notify.Add_MouseDoubleClick({ Open-HarnessApp })

# ---- 3) 通知：主 STA 线程定时轮询桥接 HTTP 路由（无文件依赖）----
$script:LastId = 0
$script:NotifyUrl = 'http://127.0.0.1:3080/dsh-notify.json'
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$script:TickCount = 0
$timer.Add_Tick({
  $script:TickCount++
  if (($script:TickCount % 100) -eq 0) { Write-Log ("tick alive x" + $script:TickCount) }
  try {
    $wc = New-Object System.Net.WebClient
    $wc.Encoding = [System.Text.Encoding]::UTF8
    $raw = $wc.DownloadString($script:NotifyUrl)
    $wc.Dispose()
    $j = $raw | ConvertFrom-Json
    if ($j -and $j.last -and ([int]$j.last.id) -gt $script:LastId) {
      $script:LastId = [int]$j.last.id
      $t = [System.Windows.Forms.ToolTipIcon]::Info
      if ($j.last.type -eq 'error') { $t = [System.Windows.Forms.ToolTipIcon]::Error }
      elseif ($j.last.type -eq 'approval') { $t = [System.Windows.Forms.ToolTipIcon]::Warning }
      $title = [string]$j.last.title
      $body = [string]$j.last.body
      if ($body.Length -gt 300) { $body = $body.Substring(0, 300) + '…' }
      $notify.ShowBalloonTip(12000, $title, $body, $t)
      Write-Log ("shown: $title (id " + $script:LastId + ")")
    }
  } catch {
    Write-Log ('poll err: ' + $_.Exception.Message)
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
