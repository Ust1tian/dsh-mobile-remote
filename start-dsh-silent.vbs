' ============================================================
'  DSH 开机自启（静默版）
'  由启动文件夹调用，隐藏窗口运行 启动DSH.ps1 -Silent
'  效果：登录时自动确保 DSH 服务在跑，无任何弹窗
' ============================================================
Set ws = CreateObject("WScript.Shell")
ws.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""E:\DSH\启动DSH.ps1"" -Silent", 0, False
