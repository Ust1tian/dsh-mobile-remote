@echo off
rem DSH 远程 HTTPS 代理启动脚本（需在 PATH 中可用 node）
rem 关闭此窗口即停止远程代理
title DSH Remote HTTPS Proxy

rem 如果代理已在运行（8443 被占用），给出明确提示而不是一闪而过
netstat -ano | findstr "127.0.0.1:8443" | findstr "LISTENING" >nul
if %errorlevel%==0 (
    echo [提示] 代理已在运行（端口 8443 已被占用），无需重复启动。
    echo 如确认代理未运行，请先结束占用该端口的进程再重试。
    pause
    exit /b 0
)

node "%~dp0proxy.js"
