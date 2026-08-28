# ============================================================
#  DSH 远程链路双守护（常驻监控）
#  由计划任务以最高权限运行，无需用户干预
# ------------------------------------------------------------
#  守护内容：
#  1) portproxy 转发守护：蒲公英/Tailscale 虚拟网卡重连后，
#     netsh portproxy 监听器可能丢失，自动重建转发规则。
#  2) 代理进程守护：检测 127.0.0.1:8443 无监听时，自动拉起
#     HTTPS 反向代理（proxy.js），确保远程链路持续可用。
# ------------------------------------------------------------
#  由计划任务 DSH-PortProxy-Watch 调用，开机登录即启动，
#  常驻循环运行（不会自动退出）。
# ============================================================

# ---------- 配置 ----------
$vip           = '172.16.0.116'          # 蒲公英虚拟 IP
$tsIP          = '100.114.252.11'        # Tailscale IP
$intervalSec   = 30                       # 检测间隔（秒）
$logFile       = 'E:\DSH\remote-access\watch-portproxy.log'
$proxyPort     = 8443                     # 代理监听端口（内部目标）
$listenPort    = 443                      # 对外入口端口（手机访问）
$dshPort       = 3080                     # DSH 本机端口
$proxyJs       = 'E:\DSH\remote-access\proxy.js'
$nodeBin       = 'D:\Program Files\nodejs\node.exe'
$proxyLog      = 'E:\DSH\remote-access\proxy.log'

# ---------- 日志（仅状态变化时写入，避免膨胀） ----------
function Write-WatchLog {
    param([string]$msg)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    try { Add-Content -Path $logFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch {}
}

# ---------- 检测：指定 IP 是否在网卡上 ----------
function Test-IpOnline {
    param([string]$ip)
    return [bool](Get-NetIPAddress -AddressFamily IPv4 -IPAddress $ip -ErrorAction SilentlyContinue)
}

# ---------- 检测：127.0.0.1:$proxyPort 是否处于监听（代理是否存活） ----------
function Test-ProxyAlive {
    $lines = netstat -ano | Select-String ("127\.0\.0\.1:{0}\s+.*LISTENING" -f $proxyPort)
    return [bool]$lines
}

# ---------- 拉起代理进程（独立后台，日志重定向） ----------
function Start-ProxyDaemon {
    # 用 ProcessStartInfo 创建独立进程，彻底脱离本脚本进程树，避免被连带终止
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'cmd.exe'
        $psi.Arguments = '/c start "DSH-Proxy" /min "' + $nodeBin + '" "' + $proxyJs + '" >> "' + $proxyLog + '" 2>&1'
        $psi.WindowStyle = 'Hidden'
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        [System.Diagnostics.Process]::Start($psi) | Out-Null
        Write-WatchLog "[代理] 已拉起 proxy.js（后台）"
    } catch {
        Write-WatchLog "[错误] 拉起代理失败: $($_.Exception.Message)"
    }
}

# ---------- 重建指定 IP 的 portproxy 转发（443 入口 + 8443 直连 + 3080） ----------
function Rebuild-PortProxy {
    param([string]$ip)
    netsh interface portproxy delete v4tov4 listenaddress=$ip listenport=$listenPort 2>$null | Out-Null
    netsh interface portproxy delete v4tov4 listenaddress=$ip listenport=$proxyPort 2>$null | Out-Null
    netsh interface portproxy delete v4tov4 listenaddress=$ip listenport=$dshPort 2>$null | Out-Null
    netsh interface portproxy add v4tov4 listenaddress=$ip listenport=$listenPort connectaddress=127.0.0.1 connectport=$proxyPort 2>$null | Out-Null
    netsh interface portproxy add v4tov4 listenaddress=$ip listenport=$proxyPort connectaddress=127.0.0.1 connectport=$proxyPort 2>$null | Out-Null
    netsh interface portproxy add v4tov4 listenaddress=$ip listenport=$dshPort   connectaddress=127.0.0.1 connectport=$dshPort   2>$null | Out-Null
}

# ---------- 检测：$ip:$listenPort 是否处于监听（对外入口转发是否生效） ----------
function Test-IpListening {
    param([string]$ip)
    $lines = netstat -ano | Select-String ("{0}:{1}\s+.*LISTENING" -f $ip, $listenPort)
    return [bool]$lines
}

# ---------- 主循环 ----------
Write-WatchLog "========== 双守护启动（间隔 ${intervalSec}s，VIP=$vip TS=$tsIP）=========="
$stateProxy = 'init'
$stateVip   = 'init'
$stateTs    = 'init'

while ($true) {
    # ── 守护1：代理进程（127.0.0.1:8443） ──
    if (Test-ProxyAlive) {
        if ($stateProxy -ne 'ok') { Write-WatchLog "[代理] 运行正常"; $stateProxy = 'ok' }
    } else {
        if ($stateProxy -ne 'fixing') {
            Write-WatchLog "[代理] 127.0.0.1:$proxyPort 未监听，准备拉起"
            $stateProxy = 'fixing'
        }
        Start-ProxyDaemon
        Start-Sleep -Seconds 3
        if (Test-ProxyAlive) { $stateProxy = 'ok'; Write-WatchLog "[代理] 拉起成功" }
    }

    # ── 守护2a：蒲公英转发（网卡在线但转发丢失 → 重建） ──
    if (Test-IpOnline $vip) {
        if (Test-IpListening $vip) {
            if ($stateVip -ne 'ok') { Write-WatchLog "[蒲公英] 转发正常"; $stateVip = 'ok' }
        } else {
            if ($stateVip -ne 'fixing') {
                Write-WatchLog "[蒲公英] 网卡在线但 $listenPort 未监听，重建转发"
                $stateVip = 'fixing'
            }
            Rebuild-PortProxy $vip
            Start-Sleep -Seconds 3
            if (Test-IpListening $vip) { $stateVip = 'ok'; Write-WatchLog "[蒲公英] 转发重建成功" }
        }
    } else {
        if ($stateVip -ne 'down') { Write-WatchLog "[蒲公英] 网卡不在线，等待"; $stateVip = 'down' }
    }

    # ── 守护2b：Tailscale 转发 ──
    if (Test-IpOnline $tsIP) {
        if (Test-IpListening $tsIP) {
            if ($stateTs -ne 'ok') { Write-WatchLog "[Tailscale] 转发正常"; $stateTs = 'ok' }
        } else {
            if ($stateTs -ne 'fixing') {
                Write-WatchLog "[Tailscale] 网卡在线但 $listenPort 未监听，重建转发"
                $stateTs = 'fixing'
            }
            Rebuild-PortProxy $tsIP
            Start-Sleep -Seconds 3
            if (Test-IpListening $tsIP) { $stateTs = 'ok'; Write-WatchLog "[Tailscale] 转发重建成功" }
        }
    } else {
        if ($stateTs -ne 'down') { Write-WatchLog "[Tailscale] 网卡不在线，等待"; $stateTs = 'down' }
    }

    Start-Sleep -Seconds $intervalSec
}
