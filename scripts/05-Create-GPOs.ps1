<#
.SYNOPSIS
    Configures the domain password policy and the Sales wallpaper GPO for lab.home.arpa.
.NOTES
    Run on DC01 as LAB\Administrator.
#>

# --- 1. Domain password policy (only effective at domain level / Default Domain Policy) ---
# Modern guidance (NIST SP 800-63B, BSI): long passwords, no forced periodic change, lockout against brute force.
Set-ADDefaultDomainPasswordPolicy -Identity lab.home.arpa `
    -MinPasswordLength 14 -ComplexityEnabled $true -PasswordHistoryCount 24 `
    -MaxPasswordAge 0 -MinPasswordAge 1.00:00:00 `
    -LockoutThreshold 5 -LockoutDuration 00:15:00 -LockoutObservationWindow 00:15:00

# --- 2. Wallpaper GPO for Sales only ---
# Image in NETLOGON: replicated to all DCs, readable by all domain users.
$wpDir = "C:\Windows\SYSVOL\sysvol\lab.home.arpa\scripts\Wallpaper"
New-Item -Path $wpDir -ItemType Directory -Force | Out-Null
Copy-Item "C:\Windows\Web\Wallpaper\Windows\img0.jpg" "$wpDir\sales.jpg"
$wpUnc = "\\lab.home.arpa\NETLOGON\Wallpaper\sales.jpg"

$gpo = New-GPO -Name "U_Sales_Desktop_Wallpaper" -Comment "Corporate wallpaper for the Sales department"
$gpo.GpoStatus = "ComputerSettingsDisabled"   # user-only GPO

# User Configuration > Administrative Templates > Desktop > Desktop > Desktop Wallpaper
$key = "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System"
Set-GPRegistryValue -Name $gpo.DisplayName -Key $key -ValueName "Wallpaper"      -Type String -Value $wpUnc
# Policy scale: 0 Center, 1 Tile, 2 Stretch, 3 Fit, 4 Fill, 5 Span (NOT the user-setting value 10)
Set-GPRegistryValue -Name $gpo.DisplayName -Key $key -ValueName "WallpaperStyle" -Type String -Value "4"

New-GPLink -Name $gpo.DisplayName -Target "OU=Sales,OU=Users,OU=_LAB,DC=lab,DC=home,DC=arpa"

# --- 3. Verification (run on the client as the user) ---
# net accounts /domain
# gpupdate /force   (then sign out / in)
# gpresult /r /scope user
