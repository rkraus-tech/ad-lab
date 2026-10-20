# ad-lab - Working Notes


## Phase 1 - Repository setup
- Created public GitHub repo `ad-lab` (MIT license, no README/.gitignore template) and cloned it to `C:\Users\Krobe\Projects\homelab\ad-lab`.
- Folder structure: `screenshots/`, `docs/`, `scripts/` (PowerShell), `configs/` (CSV, GPO exports). Empty folders tracked via `.gitkeep`.
- `.gitignore`: excludes `screenshots/raw/` (unredacted originals must never be published), secrets (`secrets/`, `.env`, `*.pfx`, `*.key`, `*.pem`), VM images/ISOs, logs and Windows/editor junk.
- `.gitattributes`: CRLF for `*.ps1/*.psm1/*.psd1/*.csv` (Windows tooling), LF for Markdown, images marked as binary.
- Decision: First line of `.gitignore`/`.gitattributes` is a comment, because Windows PowerShell 5.1 `Set-Content -Encoding utf8` writes a UTF-8 BOM that could otherwise break the first pattern.

## Phase 1 - ISO downloads & DNS issue on pve01
- Downloaded ISOs directly to Proxmox storage `local` via "Download from URL" (no detour through the laptop): `virtio-win.iso` (VirtIO drivers), `WS2025-eval-en-us.iso` (Windows Server 2025 Evaluation, 180 days), `Win11-Ent-eval-en-us.iso` (Windows 11 Enterprise Evaluation, 90 days; Home edition cannot join a domain).
- Decision: en-US ISOs so UI, screenshots and error messages match the English documentation; keyboard/region set to German during setup.
- Issue 1: "Parameter verification failed (400) - filename: wrong file extension" -> typo in the file name; Proxmox only accepts `.iso` files in the ISO store.
- Issue 2: Windows 11 download failed twice with `wget: unable to resolve host address 'software-static.download.prss.microsoft.com'`.
  - Analysis: task log showed the Microsoft fwlink redirect (302) worked, but resolving the CDN host failed. `/etc/resolv.conf` listed only the router (192.168.2.1) as nameserver; `getent hosts` returned inconsistent results (sometimes IPv6 only, sometimes nothing) -> unreliable router DNS, single point of failure.
  - Fix: pve01 -> System -> DNS: kept 192.168.2.1 as DNS server 1 (local names), added 1.1.1.1 and 9.9.9.9 as fallbacks. Verified with `getent ahostsv4 ...` (IPv4 address returned).
  - Retried using the direct CDN URL from the task log instead of the fwlink redirect -> download succeeded (200 OK).
- Lesson: always read the task log before retrying; a host with a single DNS server has no redundancy.

## Phase 1 - Resource check
- Host pve01: 15.5 GiB RAM (~4.2 GiB used), `local` ~57 GB free, `local-lvm` (LVM-Thin) ~147 GB free -> enough for DC (60 GB) and client (64 GB) even if fully allocated.
- Existing VM 125 (ops01, Jenkins from the release-ops-pipeline project) reserves 4 GiB RAM.
- Decision: Shut down ops01 (graceful ACPI shutdown, not Stop, to protect PostgreSQL) during the AD lab to free RAM for the two Windows VMs.

## Phase 2 - Design decisions
- Network: Lab VMs on the home network (bridge vmbr0, 192.168.2.0/24) with static IPs from the homelab range .20-.49. Reason: internet access for evaluation activation/updates, direct RDP from the laptop, simple setup; later projects (Help-Desk-Lab, ticketing) reuse the domain. Network segmentation is planned for the separate OPNsense/VLAN project.
  - Consequence: DC01 runs AD DS + DNS only, no DHCP (would conflict with the Speedport DHCP server); the client gets its DNS server (DC01) configured statically.
- Domain: `lab.home.arpa`, NetBIOS name `LAB`. `home.arpa` is reserved for home networks (RFC 8375) and can never collide with a public domain; `.local` avoided (mDNS conflicts, discouraged by Microsoft). In a company: subdomain of the registered company domain.
- IP plan (convention from release-ops-pipeline: VM ID = last octet):
  | VM ID | Hostname | IP | Role |
  |---|---|---|---|
  | 121 | DC01 | 192.168.2.21/24 | Domain controller (AD DS, DNS) |
  | 122 | CL01 | 192.168.2.22/24 | Windows 11 domain client |
  | 125 | ops01 | 192.168.2.25 | Jenkins (existing, shut down during lab) |
  - Gateway 192.168.2.1. DC01 uses itself as DNS after promotion; DNS forwarders 192.168.2.1 and 1.1.1.1. CL01 uses 192.168.2.21 as DNS.
- Sizing: DC01 2 vCPU / 4 GB RAM / 60 GB disk; CL01 2 vCPU / 4 GB RAM / 64 GB disk; both UEFI (OVMF), CL01 additionally Secure Boot + vTPM 2.0 (Windows 11 requirement). Disks thin-provisioned on local-lvm. vCPUs may be overcommitted, RAM is not. RAM can be increased later if needed.

## Phase 3 - DC01 VM & Windows Server installation
- Created VM 121 `DC01` via Proxmox "Create VM": OS type Windows 11/2022/2025, ISO `WS2025-eval-en-us.iso` + second CD drive with `virtio-win.iso`.
- System: q35, OVMF (UEFI) with EFI disk on local-lvm and pre-enrolled keys (Secure Boot), VirtIO SCSI single controller, QEMU guest agent enabled, no TPM (not required for Server 2025, no BitLocker planned on the DC).
- Disk: scsi0 60 GB on local-lvm with Discard, IO thread and SSD emulation (TRIM returns freed blocks to the thin pool).
- CPU: 1 socket / 2 cores, type `host` (single node, no live migration needed). The type field looked greyed out at first but could be changed.
- Memory: 4096 MiB fixed (minimum = maximum) - no ballooning for a domain controller; balloon device kept for accurate memory reporting.
- Network: VirtIO on vmbr0, firewall flag enabled.
- Installation: English (US) UI, German time/currency format and German keyboard; edition "Windows Server 2025 Standard Evaluation (Desktop Experience)" for the GUI management tools.
- Challenge: Setup showed no disk ("Select location to install" list empty) because Windows has no driver for the VirtIO SCSI controller.
  - Solution: "Load Driver" -> virtio-win CD -> `vioscsi\2k25\amd64` -> "Red Hat VirtIO SCSI pass-through controller" -> 60 GB disk appeared.
- Administrator password: >= 14 characters, avoided y/z and layout-dependent special characters because of possible keyboard mismatches in the noVNC console; stored in a password manager. Ctrl+Alt+Del sent via the noVNC extra-keys menu.
- Post-install: ran `virtio-win-guest-tools.exe` (all VirtIO drivers + QEMU guest agent). Verified in Proxmox Summary: guest agent reports IP addresses -> network driver and agent working.

## Phase 4 - Promotion to domain controller
- `sconfig` (Server Configuration tool) used for the base config:
  - Static IP 192.168.2.21/24, gateway 192.168.2.1, DNS temporarily 192.168.2.1 (DNS role not installed yet; the promotion switches DNS to the DC itself).
  - Hostname changed from the random `WIN-...` name to `DC01` + reboot - must happen BEFORE promotion, renaming a DC later is complex.
  - Remote Desktop enabled (NLA only); further work via RDP from the laptop for copy/paste.
- AD DS role installed via PowerShell (`Install-WindowsFeature AD-Domain-Services -IncludeManagementTools`). Role installation and promotion are two separate steps.
- Promotion with `Install-ADDSForest`: new forest/domain `lab.home.arpa`, NetBIOS `LAB`, integrated DNS. Separate DSRM password stored in the password manager. Expected warning about missing DNS delegation (no parent zone `home.arpa`).
- Result: domain and forest functional level Windows Server 2025, DC01 holds the PDC emulator role.
- DNS hardening after promotion:
  - Forwarders were inherited as 192.168.2.1 and `fe80::1` (link-local, interface-bound and fragile) -> replaced with 192.168.2.1 and 1.1.1.1 (lesson from the unreliable router DNS in phase 1).
  - DNS client was only `127.0.0.1` -> set to own static IP first, loopback second (best practice).
  - Verified internal zone (`dc01.lab.home.arpa` -> 192.168.2.21) and forwarding (`microsoft.com` resolves).
- Evaluation activation verified with `slmgr /xpr`: time-based activation until 18.04.2027.
- Proxmox: DC01 "Start at boot" enabled, start order 1 with 60 s startup delay - the DC must be up before any client.
- Commands documented in `scripts/01-Promote-DC.ps1`.

## Phase 5 - OU structure, AGDLP groups, shares, test users
- OU design decision: hybrid structure. Default `Users`/`Computers` are containers (no GPO links, no clean delegation), so a custom root OU `_LAB` was created (underscore sorts it to the top):
  `_LAB` -> `Users` (`IT`, `Sales`), `Groups`, `Computers` (`Clients`). Allows GPOs for all users/computers or per department.
- All OUs created via PowerShell (`New-ADOrganizationalUnit`), protected from accidental deletion by default.
- AGDLP implemented (Accounts -> Global groups -> Domain Local groups -> Permissions), naming convention `GG_` / `DL_`:
  | Group | Scope | Purpose | Members |
  |---|---|---|---|
  | GG_IT | Global | Role IT | tom.mueller |
  | GG_Sales | Global | Role Sales | sarah.becker |
  | DL_Share_Sales_RW | Domain Local | Modify on Sales | GG_Sales |
  | DL_Share_Sales_R | Domain Local | Read on Sales | GG_IT |
  | DL_Share_IT_RW | Domain Local | Modify on IT | GG_IT |
- Resources: `C:\Shares\Sales` and `C:\Shares\IT` shared as `\\DC01\Sales` and `\\DC01\IT`. NTFS: inheritance removed, only Administrators/SYSTEM + DL groups. Share permissions broad (Authenticated Users: Change) so NTFS is the single source of truth. Access-Based Enumeration enabled.
  - Lab simplification: shares on the DC; in production they belong on a dedicated file server.
- Test users created manually first (to learn the required attributes): `tom.mueller` (IT, System Administrator) and `sarah.becker` (Sales, Sales Representative), UPN `@lab.home.arpa`, "change password at next logon" enabled.
  - Initial password read with `Read-Host -AsSecureString` so it never appears in plain text in history or scripts.
  - Pitfall: pasting a multi-line block that starts with `Read-Host` makes PowerShell consume the next pasted line as input -> run the `Read-Host` line separately.
- Closing the PowerShell window lost only variables, not AD objects; verified current state with `Get-ADUser`/`icacls` before continuing.
- Commands documented in `scripts/02-Create-Structure.ps1`.

## Phase 6 - Bulk user import from CSV
- `configs/users.csv`: only business data (FirstName, LastName, Department, Title) - no passwords, no AD-specific fields, so HR can maintain it. 6 users (3 IT, 3 Sales), no umlauts in names.
- `scripts/03-Import-Users.ps1`:
  - Derives sAMAccountName (`firstname.lastname`), UPN (`@lab.home.arpa`), target OU and role group (GG_IT / GG_Sales) from the department via a single lookup table.
  - One initial password prompted with `Read-Host -AsSecureString`, "change password at next logon" enabled.
  - `[CmdletBinding(SupportsShouldProcess)]` -> supports `-WhatIf` dry runs.
  - Idempotent: existing users are skipped instead of failing.
  - Validation of unknown departments and per-row try/catch, so one bad record does not abort the whole import; summary of Created/Skipped/Error at the end.
- Workflow on DC01: copied script + CSV via the RDP clipboard to `C:\Scripts`, then:
  1. Dry run with `-WhatIf` -> 6 x "WhatIf", correct OUs.
  2. Real run -> 6 x "Created".
  3. Second run -> 6 x "Skipped (exists)" (idempotency proven).
- Verification: GG_IT and GG_Sales each have 4 members (manual test user + 3 imported).
- Pitfall: the last pasted line in the RDP PowerShell was not executed (missing Enter) - always check that the final command actually ran.

## Phase 7 - Windows 11 client CL01 & domain join
- VM 122 `CL01`: same base as DC01 (q35, OVMF + Secure Boot, VirtIO SCSI single, guest agent, VirtIO NIC on vmbr0, CPU host, 2 cores) plus:
  - vTPM 2.0 on local-lvm (Windows 11 refuses to install without TPM 2.0 + Secure Boot).
  - 64 GB disk (Windows 11 minimum).
  - 4096 MiB with ballooning down to 2048 MiB (acceptable for a client, not for a DC).
  - "Start at boot" off (client depends on the DC and should not reserve RAM permanently).
- Installation: Windows 11 Enterprise Evaluation (Home cannot join a domain), VirtIO storage driver `vioscsi\w11\amd64` loaded during setup.
- OOBE: no network driver yet -> "I don't have internet" -> local emergency admin `localadmin` (no Microsoft account on a company device). Then `virtio-win-guest-tools.exe`.
- Static IP 192.168.2.22, DNS 192.168.2.21.
- Challenge: `Resolve-DnsName lab.home.arpa` returned "DNS name does not exist".
  - Analysis: `Get-DnsClientServerAddress` showed IPv4 DNS = DC01, but IPv6 DNS = `fe80::1` (the Speedport advertises itself via Router Advertisement/RDNSS). The client asked the router, which answered NXDOMAIN. `Resolve-DnsName ... -Server 192.168.2.21` worked -> DC fine, client DNS order wrong.
  - Solution (lab): IPv6 DNS also pointed to DC01's link-local address. IPv6 stays enabled (disabling IPv6 is discouraged by Microsoft).
  - In production: configure RA/DHCPv6 on the network so the DCs are advertised as DNS servers.
- Best practice: `redircmp` on DC01 so new computer accounts land in `_LAB\Computers\Clients` instead of the default `Computers` container (no GPO links possible on containers). CL01 appeared there automatically.
- Domain join: `Add-Computer ... -Credential` hung because the credential dialog did not appear in the noVNC console (Ctrl+C was swallowed by the browser) -> closed the window, joined via `sysdm.cpl` instead.
- Observation: a sign-in attempt as `sarah.becker` accidentally on the DC01 console failed with "The sign-in method you're trying to use isn't allowed" -> expected, normal users have no "Allow log on locally" right on domain controllers.
- First domain logon as `LAB\sarah.becker` on CL01: forced password change worked.
- AGDLP verified from the client: `whoami` = `lab\sarah.becker`, file created on `\\DC01\Sales`, `\\DC01\IT` -> Access denied.
- Commands documented in `scripts/04-Join-Client.ps1`.
