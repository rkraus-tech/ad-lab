<#
.SYNOPSIS
    Creates the OU structure, AGDLP security groups and file shares for lab.home.arpa.
.NOTES
    Run on DC01 as LAB\Administrator. Shares on the DC are a lab simplification -
    in production they belong on a dedicated file server.
#>

$domain = "DC=lab,DC=home,DC=arpa"
$root   = "OU=_LAB,$domain"
$groups = "OU=Groups,$root"

# --- OU structure (hybrid: by object type, users by department) ---
New-ADOrganizationalUnit -Name "_LAB"      -Path $domain -Description "Company root OU"
New-ADOrganizationalUnit -Name "Users"     -Path $root -Description "User accounts"
New-ADOrganizationalUnit -Name "Groups"    -Path $root -Description "Security groups (AGDLP)"
New-ADOrganizationalUnit -Name "Computers" -Path $root -Description "Computer accounts"
New-ADOrganizationalUnit -Name "IT"        -Path "OU=Users,$root"     -Description "IT department"
New-ADOrganizationalUnit -Name "Sales"     -Path "OU=Users,$root"     -Description "Sales department"
New-ADOrganizationalUnit -Name "Clients"   -Path "OU=Computers,$root" -Description "Workstations"

# --- AGDLP groups ---
# Global = role/department
New-ADGroup -Name "GG_IT"    -GroupScope Global -GroupCategory Security -Path $groups -Description "Role: IT department"
New-ADGroup -Name "GG_Sales" -GroupScope Global -GroupCategory Security -Path $groups -Description "Role: Sales department"
# Domain local = permission on a resource
New-ADGroup -Name "DL_Share_Sales_RW" -GroupScope DomainLocal -GroupCategory Security -Path $groups -Description "Modify on share Sales"
New-ADGroup -Name "DL_Share_Sales_R"  -GroupScope DomainLocal -GroupCategory Security -Path $groups -Description "Read on share Sales"
New-ADGroup -Name "DL_Share_IT_RW"    -GroupScope DomainLocal -GroupCategory Security -Path $groups -Description "Modify on share IT"
# Nesting G -> DL
Add-ADGroupMember -Identity "DL_Share_Sales_RW" -Members "GG_Sales"
Add-ADGroupMember -Identity "DL_Share_Sales_R"  -Members "GG_IT"
Add-ADGroupMember -Identity "DL_Share_IT_RW"    -Members "GG_IT"

# --- Resources (P): NTFS is the source of truth, share permissions broad ---
New-Item -Path C:\Shares\Sales, C:\Shares\IT -ItemType Directory -Force | Out-Null

icacls C:\Shares\Sales /inheritance:r /grant:r `
    "BUILTIN\Administrators:(OI)(CI)F" "NT AUTHORITY\SYSTEM:(OI)(CI)F" `
    "LAB\DL_Share_Sales_RW:(OI)(CI)M" "LAB\DL_Share_Sales_R:(OI)(CI)RX"
icacls C:\Shares\IT /inheritance:r /grant:r `
    "BUILTIN\Administrators:(OI)(CI)F" "NT AUTHORITY\SYSTEM:(OI)(CI)F" `
    "LAB\DL_Share_IT_RW:(OI)(CI)M"

New-SmbShare -Name "Sales" -Path C:\Shares\Sales -FullAccess "BUILTIN\Administrators" `
    -ChangeAccess "NT AUTHORITY\Authenticated Users" -FolderEnumerationMode AccessBased
New-SmbShare -Name "IT" -Path C:\Shares\IT -FullAccess "BUILTIN\Administrators" `
    -ChangeAccess "NT AUTHORITY\Authenticated Users" -FolderEnumerationMode AccessBased
