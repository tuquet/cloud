# Project Agent Behavioral Rules: tuquet-cloud

## 1. Global Network Proxy Guardrails (Host OS Managed)
- **Restricted Network Environment:** This workstation has strict firewall rules that block outbound connections on non-standard ports (e.g., PostgreSQL ports `5432`, `6543`, Git SSH port `22`, and direct Git push traffic).
- **Windows Startup Automation (`lotte_services.vbs`):**
  - Both Cloudflare Bridge (`127.0.0.1:2222`) and SSH SOCKS5 Proxy (`127.0.0.1:1080` with auto-reconnect) are started on Windows boot via `lotte_services.vbs`.
  - Proxy management is handled at the **global OS level**, not within the workspace repository.

## 2. Git Operations & Push Rules
- Direct `git push` routes through the local SOCKS5 proxy configured in Git:
  - For HTTPS remotes:
    ```powershell
    git config --local http.proxy socks5://127.0.0.1:1080
    git config --local https.proxy socks5://127.0.0.1:1080
    ```
- Run standard `git push`, `git pull` directly in the shell.

## 3. Supabase CLI Execution Rules
- Before running any Supabase CLI command that requires remote database communication (e.g., `supabase db push`, `supabase db pull`, `supabase link`), ensure the SOCKS5 proxy environment variable is active in the session:
  ```powershell
  $env:ALL_PROXY = "socks5://127.0.0.1:1080"
  ```
- For local development (`supabase start`, `supabase db reset`), execute native commands directly without proxy.

## 4. Scripting & Execution Standards
- **Strict ASCII Invariance:** All PowerShell and batch scripts in this repository MUST be strictly ASCII-encoded (no Vietnamese diacritics in code, comments, or output strings) to avoid Windows PowerShell 5.1 ANSI parsing issues.
- **Reserved Characters:** Always quote strings containing reserved shell characters (such as `&`, `|`, `<`, `>`).
- **Native Command Stderr Safety:** Always handle native CLI stderr streams safely when checking tool statuses.
