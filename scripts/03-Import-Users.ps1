<#
.SYNOPSIS
    Bulk-creates AD users from a CSV file (FirstName, LastName, Department, Title).
.DESCRIPTION
    Derives sAMAccountName (firstname.lastname), UPN, target OU and AGDLP role group
    from the CSV. Existing users are skipped (idempotent). No passwords in the CSV:
    one initial password is prompted securely, users must change it at first logon.
.EXAMPLE
    .\03-Import-Users.ps1 -CsvPath .\users.csv -WhatIf    # dry run
    .\03-Import-Users.ps1 -CsvPath .\users.csv            # real import
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ })]
    [string]$CsvPath,

    [string]$UpnSuffix = "lab.home.arpa",
    [string]$UsersOU   = "OU=Users,OU=_LAB,DC=lab,DC=home,DC=arpa"
)

Import-Module ActiveDirectory -ErrorAction Stop

# Department -> sub-OU and role group (single place to extend)
$departments = @{
    "IT"    = @{ OU = "OU=IT,$UsersOU";    Group = "GG_IT" }
    "Sales" = @{ OU = "OU=Sales,$UsersOU"; Group = "GG_Sales" }
}

$users = Import-Csv -Path $CsvPath
$initialPassword = Read-Host -AsSecureString "Initial password for $($users.Count) users"

$results = foreach ($u in $users) {
    $sam = ("{0}.{1}" -f $u.FirstName, $u.LastName).ToLower()
    $status = $null

    try {
        if (-not $departments.ContainsKey($u.Department)) {
            throw "Unknown department '$($u.Department)'"
        }
        $dept = $departments[$u.Department]

        if (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
            $status = "Skipped (exists)"
        }
        elseif ($PSCmdlet.ShouldProcess($sam, "Create AD user in $($dept.OU)")) {
            New-ADUser -Name "$($u.FirstName) $($u.LastName)" `
                -GivenName $u.FirstName -Surname $u.LastName `
                -DisplayName "$($u.FirstName) $($u.LastName)" `
                -SamAccountName $sam -UserPrincipalName "$sam@$UpnSuffix" `
                -Department $u.Department -Title $u.Title -Path $dept.OU `
                -AccountPassword $initialPassword -ChangePasswordAtLogon $true `
                -Enabled $true -ErrorAction Stop

            Add-ADGroupMember -Identity $dept.Group -Members $sam -ErrorAction Stop
            $status = "Created"
        }
        else {
            $status = "WhatIf"
        }
    }
    catch {
        $status = "Error: $($_.Exception.Message)"
    }

    [pscustomobject]@{ User = $sam; Department = $u.Department; Status = $status }
}

$results | Format-Table -AutoSize
$results | Group-Object { ($_.Status -split ":")[0] } |
    ForEach-Object { "{0,-18} {1}" -f $_.Name, $_.Count }
