# ============================================================
#  注册 DSH-PortProxy-Watch 计划任务（管理员运行一次）
# ------------------------------------------------------------
#  功能：登录时以最高权限常驻运行 watch-portproxy.ps1，
#        自动检测并修复蒲公英重连后的端口转发丢失。
#  用法：右键以管理员身份运行 或 提权执行本脚本
# ============================================================

$taskName = 'DSH-PortProxy-Watch'
$script   = 'E:\DSH\remote-access\watch-portproxy.ps1'

Write-Host '=== 检查脚本是否存在 ==='
if (-not (Test-Path $script)) {
    Write-Host "[错误] 监控脚本不存在: $script" -ForegroundColor Red
    Read-Host '按回车退出'
    exit 1
}

Write-Host '=== 检查是否已注册（避免重复） ==='
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host '[提示] 任务已存在，将先删除再重建'
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

Write-Host '=== 创建计划任务 ==='
$trigger    = New-ScheduledTaskTrigger -AtLogOn
$action     = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -File "' + $script + '"')
$settings   = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0
$principal  = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest

try {
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'DSH portproxy auto-repair after PgyVPN reconnection' -Force | Out-Null
    Write-Host '[成功] 计划任务已注册: DSH-PortProxy-Watch' -ForegroundColor Green
} catch {
    Write-Host "[错误] 注册失败: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host '按回车退出'
    exit 1
}

Write-Host '=== 验证任务信息 ==='
Get-ScheduledTask -TaskName $taskName | Select-Object TaskName,State | Format-Table -AutoSize

Write-Host '=== 立即启动一次任务（测试） ==='
try {
    Start-ScheduledTask -TaskName $taskName
    Write-Host '[成功] 任务已启动，监控脚本应在后台运行' -ForegroundColor Green
} catch {
    Write-Host "[提示] 手动启动失败: $($_.Exception.Message)"
}

Read-Host '按回车退出'
