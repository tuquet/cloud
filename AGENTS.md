# Project Agent Behavioral Rules: omni-creator-ecosystem

## 1. Network Constraints & Self-Healing Proxy Guardrails
- **Restricted Network Environment:** This workstation has strict firewall rules that block outbound connections on non-standard ports (e.g., PostgreSQL ports `5432`, `6543`, Git SSH port `22`, and certain direct Git push traffic).
- **Windows Startup Automation (`lotte_services.vbs`):**
  - Both Cloudflare Bridge (`127.0.0.1:2222`) and SSH SOCKS5 Proxy (`127.0.0.1:1080` with auto-reconnect) are started on Windows boot via `lotte_services.vbs`.
- **Self-Healing Fallback Guardrails:**
  - If ports ever get closed or you want to execute a command with proxy, run: `.\scripts\ensure_proxy.ps1 <command>` (e.g. `.\scripts\ensure_proxy.ps1 supabase db push`).

## 2. Supabase CLI Execution Rules
- Before running any Supabase CLI command that requires remote database communication (e.g., `supabase db push`, `supabase db pull`, `supabase link`), ALWAYS ensure the SOCKS5 proxy environment variable is active in the session:
  ```powershell
  $env:ALL_PROXY = "socks5://127.0.0.1:1080"
  ```
- Alternatively, recommend running database migrations via the Supabase Management API (HTTPS Port 443) or the Supabase Web SQL Editor.

## 3. Git Operations & Push Rules
- Direct `git push` will fail without proxy due to network port blocking.
- Always ensure Git is configured to route through the local SOCKS5 proxy for this repository:
  - For HTTPS remotes:
    ```powershell
    git config --local http.proxy socks5://127.0.0.1:1080
    git config --local https.proxy socks5://127.0.0.1:1080
    ```
  - For SSH remotes (`git@github.com:...`):
    ```powershell
    git config --local core.sshCommand "ssh -o 'ProxyCommand=connect -S 127.0.0.1:1080 %h %p'"
    ```
- Run `scripts/configure_git_proxy.ps1` to automatically configure repository-level Git proxy settings.

## 4. Scripting & Execution Standards
- **Strict ASCII Invariance:** All PowerShell and batch scripts in this repository MUST be strictly ASCII-encoded (no Vietnamese diacritics in code, comments, or output strings) to avoid Windows PowerShell 5.1 ANSI parsing issues.
- **Reserved Characters:** Always quote strings containing reserved shell characters (such as `&`, `|`, `<`, `>`).
- **Native Command Stderr Safety:** Always handle native CLI stderr streams safely when checking tool statuses.
