# dsh-mobile-remote — 手机/平板远程操控 DSH Web

通过 **贝锐蒲公英组网 + HTTPS 反向代理**，让手机/平板在任何网络下安全地远程操控本机 [DeepSeek Harness](https://github.com/deepseek-ai/dsh)（DSH）Web 界面：继续 PC 端工作区、查看历史对话、远程让 AI 干活，并支持把 AI 生成的文件直接下载到手机。

> 本方案解决的核心问题：DSH Web 只监听 `127.0.0.1`，且前端依赖 `crypto.randomUUID`（仅 HTTPS/localhost 安全上下文可用），因此远程访问**必须走 HTTPS**。原生目录选择器在远程浏览器不可用，需切换为网页浏览模式。

---

## 原理

```
手机浏览器 ──HTTPS──> 蒲公英组网（虚拟局域网，WireGuard 加密）
                          │
              netsh portproxy: <蒲公英IP>:443 ──> 127.0.0.1:8443
                          │
              proxy.js（Node HTTPS 反代，保留 Host 头，支持 WebSocket/SSE）
                          │
              127.0.0.1:3080（DSH Web，绑定不变，不暴露局域网）
```

- **访问控制**：蒲公英组网的设备身份（只有你的账号下的设备能进组）+ 防火墙仅放行组网网段
- **/share/ 下载目录**：把要发给手机的文件放进 `share/` 目录，手机访问 `https://<IP>/share/` 直接下载

---

## 快速开始（Windows）

### 0. 前置条件

- Windows 10/11，Node.js ≥ 18
- 已安装 [贝锐蒲公英客户端](https://pgy.oray.com/download/) 并登录，电脑与手机加入同一智能组网
- DSH Web 已在本机 127.0.0.1:3080 运行

### 1. 生成自签名证书（管理员 PowerShell）

```powershell
powershell -ExecutionPolicy Bypass -File setup-cert.ps1 -Ip <你的蒲公英IP>
```

### 2. 启动 HTTPS 代理

```bat
start-proxy.cmd
```

或直接 `node proxy.js`。代理监听 `127.0.0.1:8443`，转发到 `127.0.0.1:3080`。

### 3. 端口转发 + 防火墙（管理员）

```powershell
# 把蒲公英 IP 的 443 转发到本机 8443
netsh interface portproxy add v4tov4 listenaddress=<蒲公英IP> listenport=443 connectaddress=127.0.0.1 connectport=8443

# 防火墙放行 443（仅蒲公英组网网段，示例为 172.16.0.0/16，按实际网段调整）
netsh advfirewall firewall add rule name="DSH-Remote-443" dir=in action=allow protocol=TCP localport=443 remoteip=172.16.0.0/16
```

### 4. DSH 信任围栏：允许该 IP 的 /api 请求

在 DSH 用户层补丁 `$DSH_HOME\.dsh\profiles\web\cordis.patch.yml` 追加（把 `<蒲公英IP>` 换成你的 IP）：

```yaml
- id: web-runtime
  config:
    printUrl: true
    surfaceContext: true
    trustedHosts: !!js ctx.webStartup.trustedHosts.concat(['<蒲公英IP>'])

# 目录选择器固定为网页浏览模式（手机端可选文件夹/新建工作区）
- id: directory-picker
  disabled: true

- insert:
    - id: directory-picker-browse
      name: '@deepseek-ai/dsh-host-directory-picker-browse'
    - id: ui-directory-picker-browse
      name: '@deepseek-ai/dsh-client-ui-directory-picker-browse'
```

> 补丁会被 DSH 热加载（watchUserPatches），通常无需重启。

### 5. 手机访问

手机安装蒲公英 App（同一账号登录，加入同一组网），浏览器打开：

```
https://<蒲公英IP>
```

首次会提示自签名证书不受信任，选择"继续访问"即可。

### 6. 文件分享（把 AI 生成的文件发到手机）

- 把文件放入 `share/` 目录（相对 proxy.js 所在目录）
- 手机浏览器访问 `https://<蒲公英IP>/share/`，点文件名下载
- 网页目录树选择的"新建工作区"同样走这个 HTTPS 通道

---

## 开机自启（可选）

把 `start-proxy.cmd` 放入启动文件夹：

```powershell
# 打开启动文件夹
shell:startup
```

下次登录自动启动代理。

## DSH 自愈启动 + 开机自启（推荐）

> 背景：DSH 更新后可能出现"双击图标打不开"（如 `dsh.cmd` 哈希路径失效、端口被旧实例占用、启动即退出等）。以下脚本让 DSH 启动具备自愈能力，并支持登录自动运行。

### 文件说明

| 文件 | 作用 |
|---|---|
| `start-dsh.ps1` | 自愈版启动脚本（部署到本机时改名为 `启动DSH.ps1` 并放 `E:\DSH\`） |
| `start-dsh-silent.vbs` | 静默自启包装（隐藏窗口，供启动文件夹调用，改名 `启动DSH-静默.vbs`） |
| `dsh-console.vbs` | 桌面"DSH 控制台"图标（只检测端口 + 开浏览器，不启动服务，改名 `DSH控制台.vbs`） |

### 部署步骤

1. **自愈启动脚本**：把 `start-dsh.ps1` 复制为 `E:\DSH\启动DSH.ps1`，桌面快捷方式指向：
   ```
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "E:\DSH\启动DSH.ps1"
   ```
   （脚本含 UTF-8 BOM，Windows PowerShell 5.1 可正常解析中文注释）

2. **开机自启**：把 `start-dsh-silent.vbs` 复制为 `E:\DSH\启动DSH-静默.vbs`，再复制一份到启动文件夹：
   ```powershell
   # 打开启动文件夹
   shell:startup
   ```
   登录后自动静默启动 DSH（无窗口、不弹浏览器）。

3. **DSH 控制台图标**：把 `dsh-console.vbs` 复制为 `E:\DSH\DSH控制台.vbs`，桌面新建快捷方式：
   ```
   Target: wscript.exe
   Args:   "E:\DSH\DSH控制台.vbs"
   ```
   双击只打开浏览器，服务未运行时弹窗提示。

### 自愈能力

- 启动前自检 `dsh.cmd` 是否存在、版本是否正常，异常自动回退 `npx @deepseek-ai/dsh web`
- 检测到 3080 已被占用 → 不重复启动，直接开浏览器
- 启动后 60 秒未就绪 → 自动重试一次，仍失败弹窗提示
- 每次启动写入 `E:\DSH\启动日志.txt`，打不开时看日志定位原因

> 脚本中的 `E:\DSH`、`E:\Codex_Project`、`127.0.0.1:3080` 为部署示例路径，请按本机实际调整。

---

## 安全提醒

- **cert/ 目录含私钥，绝不提交到 Git**（`.gitignore` 已排除）；手机端遇到证书警告属正常
- 蒲公英虚拟 IP 变动后，需同步更新：证书（重新生成）、netsh 转发、防火墙、DSH trusted-host
- 组网网段限定防火墙规则，避免把 443/8443 暴露到整个局域网
- DSH 本身始终只绑定 127.0.0.1，不直接暴露到任何网络接口

## 已知限制

- 自签名证书：手机首次需手动信任，且非企业级 CA 签名
- 蒲公英免费版对组网成员数/带宽有限制（以官方为准）
