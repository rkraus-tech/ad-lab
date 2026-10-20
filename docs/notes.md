# ad-lab - Working Notes


## Phase 1 - Repository setup
- Created public GitHub repo `ad-lab` (MIT license, no README/.gitignore template) and cloned it to `C:\Users\Krobe\Projects\homelab\ad-lab`.
- Folder structure: `screenshots/`, `docs/`, `scripts/` (PowerShell), `configs/` (CSV, GPO exports). Empty folders tracked via `.gitkeep`.
- `.gitignore`: excludes `screenshots/raw/` (unredacted originals must never be published), secrets (`secrets/`, `.env`, `*.pfx`, `*.key`, `*.pem`), VM images/ISOs, logs and Windows/editor junk.
- `.gitattributes`: CRLF for `*.ps1/*.psm1/*.psd1/*.csv` (Windows tooling), LF for Markdown, images marked as binary.
- Decision: First line of `.gitignore`/`.gitattributes` is a comment, because Windows PowerShell 5.1 `Set-Content -Encoding utf8` writes a UTF-8 BOM that could otherwise break the first pattern.
