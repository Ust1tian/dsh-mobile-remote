@echo off
rem DSH 远程 HTTPS 代理启动脚本（需在 PATH 中可用 node）
rem 关闭此窗口即停止远程代理
title DSH Remote HTTPS Proxy
node "%~dp0proxy.js"
