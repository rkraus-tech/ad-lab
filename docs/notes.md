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
