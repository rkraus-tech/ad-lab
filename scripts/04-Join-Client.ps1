<#
.SYNOPSIS
    Configures a Windows 11 client (CL01) for lab.home.arpa and joins it to the domain.
.NOTES
    Run on CL01 in an elevated PowerShell after the VirtIO guest tools are installed.
    Prerequisite on DC01 (once): redircmp "OU=Clients,OU=Computers,OU=_LAB,DC=lab,DC=home,DC=arpa"
#>

$if = (Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1).ifIndex

# Static IPv4
New-NetIPAddress -InterfaceIndex $if -IPAddress 192.168.2.22 -PrefixLength 24 -DefaultGateway 192.168.2.1

# DNS: IPv4 AND IPv6 must point to the DC - the home router advertises itself (fe80::1)
# as IPv6 DNS via Router Advertisement (RDNSS), which answers NXDOMAIN for the AD zone.
Set-DnsClientServerAddress -InterfaceIndex $if -ServerAddresses 192.168.2.21, fe80::31b0:1b74:a323:ad48

# Must resolve to 192.168.2.21 before joining
Resolve-DnsName lab.home.arpa

# Rename first, then join (computer account is created with the current name)
Rename-Computer -NewName CL01 -Restart
# --- after reboot ---
Add-Computer -DomainName lab.home.arpa -Credential LAB\Administrator -Restart
