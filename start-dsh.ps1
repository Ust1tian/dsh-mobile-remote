# ============================================================
#  启动 DeepSeek Harness Web（自愈版 v2）
#  桌面快捷方式入口 + 开机自启入口
# ------------------------------------------------------------
#  用法：
#    启动DSH.ps1               默认：检测→启动→开浏览器（桌面双击用）
#    启动DSH.ps1 -Silent       静默模式：检测→启动，不弹窗口不开浏览器（开机自启用）
#    启动DSH.ps1 -OpenOnly     仅打开浏览器：端口就绪就开浏览器（DSH控制台图标用）
# ------------------------------------------------------------
#  自愈能力：
#    1. 启动前自检 dsh.cmd 是否存在、版本是否正常，坏了自动回退 npx
#    2. 若 3080 已被占用（DSH 已在运行）→ 不重复启动，直接开浏览器
#    3. 启动后 60 秒未就绪 → 自动重启一次，仍失败则写日志提示
#    4. 每次启动关键步骤写入 E:\DSH\启动日志.txt，打不开时看日志定位
# ============================================================

param(
    [switch]$Silent,      # 静默模式（开机自启）
    [switch]$OpenOnly     # 仅打开浏览器（控制台图标）
)

$url       = "http://127.0.0.1:3080"
$workspace = "E:\Codex_Project"
$logFile   = "E:\DSH\启动日志.txt"
$dshBin    = 'E:\DSH\dsh-app\node_modules\.bin\dsh.cmd'

# ---------- 日志：静默模式只写文件，普通模式同时打印 ----------
function Write-Log {
    param([string]$msg)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    try {
        Add-Content -Path $logFile -Value $line -Encoding UTF8 -ErrorAction Stop
    } catch {
        # 日志写入失败不阻塞启动
    }
    if (-not $Silent) { Write-Host $msg }
}

# ---------- 检测 3080 端口是否已被 DSH 占用（500ms 超时） ----------
function Test-DshPort {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect("127.0.0.1", 3080, $null, $null)
        $ok = $async.AsyncWaitHandle.WaitOne(500)
        if ($ok -and $client.Connected) { return $true }
        return $false
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

Write-Log "========== 启动请求（Silent=$Silent OpenOnly=$OpenOnly）=========="

# ---------- 模式3：仅打开浏览器（DSH 控制台图标） ----------
if ($OpenOnly) {
    if (Test-DshPort) {
        Write-Log "DSH 正在运行，打开浏览器"
        Start-Process $url
        exit 0
    } else {
        Write-Log "DSH 未运行，无法打开浏览器（请先启动 DSH）"
        if (-not $Silent) {
            [System.Windows.Forms.MessageBox]::Show("DSH 服务未运行，无法打开浏览器。`n请双击桌面上的「DeepSeek Harness」图标启动。", "DSH 控制台", 'OK', 'Warning') | Out-Null
        }
        exit 1
    }
}

# ---------- 若已在运行：直接开浏览器（普通模式）或直接退出（静默模式） ----------
if (Test-DshPort) {
    Write-Log "DSH 已在运行，无需重复启动"
    if (-not $Silent) { Start-Process $url }
    exit 0
}

# ---------- 自检 dsh.cmd，坏了自动回退 npx ----------
$useNpx = $false
if (-not (Test-Path $dshBin)) {
    Write-Log "[自愈] dsh.cmd 不存在，回退到 npx 方式"
    $useNpx = $true
} else {
    try {
        $ver = & cmd /c "`"$dshBin`" --version 2>&1" | Select-Object -First 1
        Write-Log "[自检] dsh 版本: $ver"
        if ($ver -notmatch '\d+\.\d+') {
            Write-Log "[自愈] dsh.cmd 版本异常（$ver），回退到 npx 方式"
            $useNpx = $true
        }
    } catch {
        Write-Log "[自愈] dsh.cmd 自检出错: $($_.Exception.Message)，回退到 npx 方式"
        $useNpx = $true
    }
}

# ---------- 启动 DSH ----------
function Start-Dsh {
    if ($useNpx) {
        Write-Log "正在启动（npx 方式）：npx --yes @deepseek-ai/dsh web"
        $arg = "cd /d `"$workspace`" & npx --yes @deepseek-ai/dsh web"
    } else {
        Write-Log "正在启动（本地方式）：$dshBin web"
        $arg = "cd /d `"$workspace`" & `"$dshBin`" web"
    }

    if ($Silent) {
        # 静默模式：后台无窗口运行，输出重定向到日志文件
        Start-Process cmd.exe -ArgumentList "/c $arg > `"$logFile`" 2>&1" -WindowStyle Hidden
    } else {
        # 普通模式：前台可见窗口运行（能看到日志滚动），关闭窗口即停止服务
        Start-Process cmd.exe -ArgumentList "/k $arg" -WorkingDirectory $workspace
    }
}

# ---------- 启动并轮询就绪（60 秒），失败自动重启一次 ----------
function Wait-ForReady {
    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $deadline) {
        if (Test-DshPort) { return $true }
        Start-Sleep -Seconds 1
    }
    return $false
}

$started = $false
for ($attempt = 1; $attempt -le 2; $attempt++) {
    Write-Log "---- 第 $attempt 次尝试启动 ----"
    Start-Dsh

    if (Wait-ForReady) {
        $started = $true
        break
    }

    Write-Log "[警告] 第 $attempt 次启动后 60 秒内未检测到端口，准备重试"
    if ($attempt -eq 1 -and -not $Silent) {
        Write-Host "首次启动超时，正在自动重试..." -ForegroundColor Yellow
    }
}

# ---------- 结果 ----------
if ($started) {
    Write-Log "DSH 启动成功，端口就绪"
    if (-not $Silent) {
        Start-Process $url
        Write-Host "浏览器已打开：$url"
    }
} else {
    $errMsg = "DSH 启动失败！两次尝试后 3080 端口仍未就绪。`n详细日志见：$logFile"
    Write-Log "[错误] $errMsg"
    if (-not $Silent) {
        [System.Windows.Forms.MessageBox]::Show($errMsg, "DSH 启动失败", 'OK', 'Error') | Out-Null
    }
    exit 1
}
