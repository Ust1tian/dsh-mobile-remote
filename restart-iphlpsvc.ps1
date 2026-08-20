net stop iphlpsvc 2>&1 | Out-String | Write-Output
net start iphlpsvc 2>&1 | Out-String | Write-Output
Start-Sleep -Seconds 5
Write-Output '--- 重启后 172.16.0.116 监听 ---'
netstat -ano | Select-String '172\.16\.0\.116' | Out-String | Write-Output
