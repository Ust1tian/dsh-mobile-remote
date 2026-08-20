netsh interface portproxy delete v4tov4 listenaddress=172.16.0.116 listenport=443
netsh interface portproxy delete v4tov4 listenaddress=172.16.0.116 listenport=3080
netsh interface portproxy add v4tov4 listenaddress=172.16.0.116 listenport=443 connectaddress=127.0.0.1 connectport=8443
netsh interface portproxy add v4tov4 listenaddress=172.16.0.116 listenport=3080 connectaddress=127.0.0.1 connectport=3080
Start-Sleep -Seconds 3
netsh interface portproxy show v4tov4
