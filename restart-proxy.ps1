# 停掉占用 8443 的旧代理进程（可能是提权进程，需管理员权限）
$conn = Get-NetTCPConnection -LocalPort 8443 -State Listen -ErrorAction SilentlyContinue
if ($conn) { taskkill /PID $conn.OwningProcess /F | Out-Null; Write-Output ('旧代理已停止 PID ' + $conn.OwningProcess) } else { Write-Output '无占用进程' }
Start-Sleep -Seconds 2
# 启动新版代理（带 /share/ 分享功能）
Start-Process 'E:\DSH\remote-access\start-proxy.cmd' -WorkingDirectory 'E:\DSH\remote-access'
Start-Sleep -Seconds 4
netstat -ano | Select-String ':8443.*LISTENING' | Out-String | Write-Output
