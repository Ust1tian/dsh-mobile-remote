' ============================================================
'  DSH 控制台（打开浏览器版）
'  由桌面图标"DSH 控制台"调用：只检测端口 + 打开浏览器
'  不启动服务——服务由开机自启或"DeepSeek Harness"图标负责
' ============================================================
Set ws = CreateObject("WScript.Shell")
ws.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""E:\DSH\启动DSH.ps1"" -OpenOnly", 0, True
