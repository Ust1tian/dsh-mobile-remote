# ============================================================
#  DSH 端口转发自动修复（常驻监控）
#  由计划任务以最高权限运行，无需用户干预
# ------------------------------------------------------------
#  背景：蒲公英虚拟网卡重连后，netsh portproxy 的监听器可能
#  丢失（规则还在但 443/3080 不监听），导致手机无法访问。
#  本脚本每 30 秒检测一次，发现"网卡在线但 443 未监听"
#  即自动重建两条转发规则。
# ------------------------------------------------------------
#  由计划任务 DSH-PortProxy-Watch 调用，开机登录即启动，
#  常驻循环运行（不会自动退出）。
# ============================================================

# ---------- 配置 ----------
$vip           = '172.16.0.116'          # 蒲公英虚拟 IP（按实际修改）
$intervalSec   = 30                       # 检测间隔（秒）
$logFile       = 'E:\DSH\remote-access\watch-portproxy.log'
$proxyPort     = 8443                     # 代理监听端口
$dshPort       = 3080                     # DSH 本机端口

# ---------- 日志（仅状态变化时写入，避免膨胀） ----------
function Write-WatchLog {
    param([string]$msg)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    try { Add-Content -Path $logFile -Value $line -Encoding UTF8 -ErrorAction Stop } catch {}
}

# ---------- 检测：蒲公英虚拟 IP 是否在网卡上 ----------
function Test-VipOnline {
    return [bool](Get-NetIPAddress -AddressFamily IPv4 -IPAddress $vip -ErrorAction SilentlyContinue)
}

# ---------- 检测：$vip:$proxyPort 是否处于监听 ----------
function Test-ProxyListening {
    $lines = netstat -ano | Select-String ("{0}:{1}\s+.*LISTENING" -f $vip, $proxyPort)
    return [bool]$lines
}

# ---------- 重建两条 portproxy 转发 ----------
function Rebuild-PortProxy {
    # 先删除旧规则（忽略不存在错误）
    netsh interface portproxy delete v4tov4 listenaddress=$vip listenport=$proxyPort 2>$null | Out-Null
    netsh interface portproxy delete v4tov4 listenaddress=$vip listenport=$dshPort 2>$null | Out-Null
    # 重建
    netsh interface portproxy add v4tov4 listenaddress=$vip listenport=$proxyPort connectaddress=127.0.0.1 connectport=$proxyPort 2>$null | Out-Null
    netsh interface portproxy add v4tov4 listenaddress=$vip listenport=$dshPort   connectaddress=127.0.0.1 connectport=$dshPort   2>$null | Out-Null
    # 等待监听器生效
    Start-Sleep -Seconds 3
    if (Test-ProxyListening) {
        Write-WatchLog "[修复] $vip 端口转发已重建，$proxyPort 监听恢复"
        return $true
    } else {
        Write-WatchLog "[警告] 重建后 $proxyPort 仍未监听（可能需要重启 iphlpsvc 服务）"
        return $false
    }
}

# ---------- 主循环 ----------
Write-WatchLog "========== 端口转发监控启动（间隔 ${intervalSec}s，VIP=$vip）=========="
$lastState = 'init'

while ($true) {
    # 1) 蒲公英网卡不在线 → 无需修复，等待
    if (-not (Test-VipOnline)) {
        if ($lastState -ne 'vpn-down') {
            Write-WatchLog "[状态] 蒲公英网卡不在线，等待重连..."
            $lastState = 'vpn-down'
        }
        Start-Sleep -Seconds $intervalSec
        continue
    }

    # 2) 网卡在线且转发正常 → 等待
    if (Test-ProxyListening) {
        if ($lastState -ne 'ok') {
            Write-WatchLog "[状态] 转发正常"
            $lastState = 'ok'
        }
        Start-Sleep -Seconds $intervalSec
        continue
    }

    # 3) 网卡在线但监听丢失 → 自动修复
    if ($lastState -ne 'fixing') {
        Write-WatchLog "[检测] 网卡在线但 $proxyPort 未监听，开始自动修复"
        $lastState = 'fixing'
    }
    Rebuild-PortProxy | Out-Null
    Start-Sleep -Seconds $intervalSec
}
