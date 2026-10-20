<#
.SYNOPSIS
    Promotes a fresh Windows Server 2025 to the first domain controller of lab.home.arpa.
.NOTES
    Run on DC01 as local Administrator after static IP (192.168.2.21) and hostname (DC01) are set.
    The DSRM password is prompted interactively - never store it in this file.
#>

# 1. Install the AD DS role incl. management tools (ADUC, GPMC, AD PowerShell module)
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

# 2. Create a new forest/domain with integrated DNS (server reboots automatically)
Install-ADDSForest `
    -DomainName "lab.home.arpa" `
    -DomainNetbiosName "LAB" `
    -InstallDns `
    -NoRebootOnCompletion:$false

# --- after reboot, log on as LAB\Administrator ---

# 3. DNS forwarders: router + public resolver (router DNS proved unreliable)
Set-DnsServerForwarder -IPAddress 192.168.2.1, 1.1.1.1

# 4. DNS client: own static IP first, loopback second
Set-DnsClientServerAddress -InterfaceAlias Ethernet -ServerAddresses 192.168.2.21, 127.0.0.1

# 5. Verification
Get-ADDomain | Select-Object DNSRoot, NetBIOSName, DomainMode, PDCEmulator
Get-ADForest | Select-Object Name, ForestMode
Get-DnsServerForwarder | Select-Object IPAddress
Resolve-DnsName dc01.lab.home.arpa
Resolve-DnsName microsoft.com -Type A
