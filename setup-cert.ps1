# 生成自签名证书脚本（管理员权限运行）
# 用法: powershell -ExecutionPolicy Bypass -File setup-cert.ps1 -Ip 172.16.0.116
param(
    [string]$Ip = "172.16.0.116"   # 蒲公英组网虚拟 IP（与 netsh 转发/trusted-host 保持一致）
)

$certDir = Join-Path $PSScriptRoot "cert"
New-Item -ItemType Directory -Force -Path $certDir | Out-Null

try {
    # 生成自签名证书：SAN 含指定 IP，有效期 3 年
    $cert = New-SelfSignedCertificate -Subject 'CN=dsh-remote' `
        -CertStoreLocation 'Cert:\LocalMachine\My' `
        -KeyExportPolicy Exportable -KeyAlgorithm RSA -KeyLength 2048 `
        -NotAfter (Get-Date).AddYears(3) `
        -TextExtension @("2.5.29.17={text}ipaddress=$Ip")
    Write-Host ("证书已生成: " + $cert.Thumbprint)

    # 随机口令并导出 PFX
    $pass = [Guid]::NewGuid().ToString('N').Substring(0, 24)
    $pass | Set-Content -Path (Join-Path $certDir 'passphrase.txt') -Encoding ASCII
    Export-PfxCertificate -Cert $cert -FilePath (Join-Path $certDir 'server.pfx') `
        -Password (ConvertTo-SecureString $pass -AsPlainText -Force) | Out-Null
    Write-Host "PFX 已导出到 cert/server.pfx（口令在 cert/passphrase.txt）"
    Write-Host "注意: cert 目录含私钥，切勿提交到 Git！"
} catch {
    Write-Host ("生成失败: " + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
