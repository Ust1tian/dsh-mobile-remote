netsh interface portproxy add v4tov4 listenaddress=172.16.0.116 listenport=443 connectaddress=127.0.0.1 connectport=8443 2>&1 | Out-File 'E:\DSH\remote-access\setup-443.log'
netsh advfirewall firewall add rule name='DSH-Pgy-443' dir=in action=allow protocol=TCP localport=443 remoteip=172.16.0.0/16 2>&1 | Out-File 'E:\DSH\remote-access\setup-443.log' -Append
netsh interface portproxy show v4tov4 2>&1 | Out-File 'E:\DSH\remote-access\setup-443.log' -Append
netsh advfirewall firewall show rule name='DSH-Pgy-443' 2>&1 | Out-File 'E:\DSH\remote-access\setup-443.log' -Append
