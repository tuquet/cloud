# Kế Hoạch Chi Tiết: Xử Lý Mạng Bị Chặn Port (Supabase & Git Push)

Tài liệu này xác định chi tiết kiến trúc, cơ chế định tuyến qua VPS và kế hoạch hành động toàn diện để vượt qua rào cản tường lửa mạng nội bộ (chặn các cổng `5432`, `6543`, SSH `22` và chặn thao tác `git push`).

---

## 1. Phân Tích Hiện Trạng & Rào Cản Mạng

| Dịch Vụ Cần Dùng | Cổng / Giao Thức Mặc Định | Hiện Trạng Mạng Của Máy | Hậu Quả Nếu Không Có Proxy |
| :--- | :--- | :--- | :--- |
| **Supabase CLI (`db push`)** | TCP `5432` (Direct) hoặc `6543` (Pooler) | **Bị chặn hoàn toàn** bởi Firewall | Lỗi `connection refused` hoặc `timeout` |
| **Git Push (SSH)** | TCP `22` (`git@github.com:...`) | **Bị chặn hoàn toàn** | Lỗi `Connection timed out` hoặc `fatal: Could not read from remote` |
| **Git Push (HTTPS)** | TCP `443` (`https://github.com/...`) | **Bị kiểm duyệt / chặn** bởi Firewall / Deep Packet Inspection (DPI) | Lỗi `Failed to connect to github.com` hoặc SSL handshake drop |
| **Cầu nối Cloudflare Tunnel** | HTTPS / WebSocket `443` | **Thông suốt 100%** (Chạy VBS ngầm `127.0.0.1:2222`) | Đã kết nối thành công tới `cdn.flowup.io.vn` |

---

## 2. Mô Hình Kiến Trúc Đường Hầm (Tunnel Topology)

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│ MÁY TÍNH CÁ NHÂN (WINDOWS WORKSTATION)                                          │
│                                                                                 │
│   [VBS Startup]                                                                 │
│         │                                                                       │
│         ▼                                                                       │
│   [cloudflare_ssh_bridge.bat] ────(HTTPS 443 Outbound)─────────────────────┐    │
│   (Lắng nghe: 127.0.0.1:2222)                                              │    │
│         ▲                                                                  │    │
│         │ SSH Tunnel (`ssh -N -D 1080 127.0.0.1`)                          │    │
│         ▼                                                                  │    │
│   [SOCKS5 Proxy Daemon]                                                    │    │
│   (Lắng nghe: 127.0.0.1:1080)                                              │    │
│         ▲                                                                  │    │
│         ├── $env:ALL_PROXY ────────► [Supabase CLI (db push)]              │    │
│         └── http.proxy / sshCommand ► [Git (git push/pull)]                │    │
└────────────────────────────────────────────────────────────────────────────┼────┘
                                                                             │
                      ĐI QUA CLOUDFLARE EDGE NETWORK (PORT 443)              │
                                                                             │
                                                                             ▼
                                                  ┌──────────────────────────────────────┐
                                                  │ VPS (cdn.flowup.io.vn)               │
                                                  │  - Mạng sạch, không giới hạn port    │
                                                  │  - Trạm trung chuyển lưu lượng       │
                                                  └──────────────────┬───────────────────┘
                                                                     │
                                     ┌───────────────────────────────┴─────────────────┐
                                     │                                                 │
                                     ▼ (Port 5432 / 6543)                              ▼ (Port 22 / 443)
                        ┌──────────────────────────────┐              ┌─────────────────────────────────┐
                        │ SUPABASE CLOUD DATABASE      │              │ GITHUB REPOSITORY               │
                        │ (Migration RBAC hoàn tất)    │              │ (Git push mã nguồn thành công)  │
                        └──────────────────────────────┘              └─────────────────────────────────┘
```

---

## 3. Kế Hoạch Chi Tiết Xử Lý `git push`

Để `git push` hoạt động ổn định qua SOCKS5 Proxy (`127.0.0.1:1080`), ta có 2 phương án tùy thuộc vào remote URL bạn sử dụng:

### Phương Án A: Sử dụng Git qua HTTPS (Khuyên Dùng)
Khi remote của bạn có dạng `https://github.com/username/repo.git`:

1. **Cấu hình Git trong repository này sử dụng SOCKS5 proxy**:
   ```powershell
   git config --local http.proxy socks5://127.0.0.1:1080
   git config --local https.proxy socks5://127.0.0.1:1080
   ```
2. **Kiểm tra**:
   ```powershell
   git push origin main
   ```
   *Toàn bộ dữ liệu commit và push sẽ được đóng gói qua SOCKS5 proxy, đi qua VPS ra ngoài GitHub mà không bị tường lửa phát hiện.*

---

### Phương Án B: Sử dụng Git qua SSH (`git@github.com:...`)
Nếu bạn sử dụng SSH key cá nhân để xác thực với GitHub:
Git for Windows có sẵn công cụ trung chuyển proxy tên là `connect.exe` (nằm trong thư mục cài đặt Git).

1. **Cấu hình `core.sshCommand` cho repository**:
   ```powershell
   git config --local core.sshCommand "ssh -o 'ProxyCommand=connect -S 127.0.0.1:1080 %h %p'"
   ```
2. **Hoặc cấu hình trực tiếp vào `~/.ssh/config`**:
   Thêm đoạn cấu hình sau vào file `C:\Users\ndtu6\.ssh\config`:
   ```ssh
   Host github.com
       Hostname ssh.github.com
       Port 443
       User git
       ProxyCommand connect -S 127.0.0.1:1080 %h %p
   ```

---

### Phương Án C: Git Push Gián Tiếp Qua VPS (Phương Án Dự Phòng Khẩn Cấp)
Nếu mạng local chặn ngắt quãng cả SSH proxy:
1. Bạn có thể add thêm 1 remote trỏ thẳng vào thư mục trên VPS qua SSH:
   ```powershell
   git remote add vps-mirror ssh://root@127.0.0.1:2222/var/repo/tuquet-creator.git
   ```
2. Push từ local lên VPS: `git push vps-mirror main`.
3. Trên VPS thiết lập một Git Hook (`post-receive`) tự động `git push origin main` sang GitHub.

---

## 4. Danh Sách Script Hỗ Trợ Tự Động Hóa Trong Dự Án

Chúng tôi đã đóng gói gọn gàng các kịch bản tiện ích tại thư mục [`scripts/network/`](file:///c:/Users/ndtu6/Repository/tuquet-creator/scripts/network/) với cơ chế **Self-Healing (Tự phục hồi, KHÔNG phụ thuộc vào việc VBS có chạy trước hay không)**:

1. **[`scripts/network/ensure_proxy.ps1`](file:///c:/Users/ndtu6/Repository/tuquet-creator/scripts/network/ensure_proxy.ps1)** & **[`scripts/network/ensure_proxy.bat`](file:///c:/Users/ndtu6/Repository/tuquet-creator/scripts/network/ensure_proxy.bat)**:
   - **Tự động hoàn toàn**: Tự kiểm tra cổng 2222 (Cloudflare) và cổng 1080 (SOCKS5). Tự bật ngầm nếu chưa chạy, và tùy chọn thực thi ngay câu lệnh truyền vào.
2. **[`scripts/network/configure_git_proxy.ps1`](file:///c:/Users/ndtu6/Repository/tuquet-creator/scripts/network/configure_git_proxy.ps1)**:
   - Tự động cấu hình Git trong repository này sử dụng proxy cục bộ.
3. **[`scripts/network/stop_proxy.ps1`](file:///c:/Users/ndtu6/Repository/tuquet-creator/scripts/network/stop_proxy.ps1)**:
   - Tắt sạch các tiến trình ngầm `cloudflared` và `ssh` khi bạn không muốn dùng proxy nữa.
4. **[`scripts/network/test_network.ps1`](file:///c:/Users/ndtu6/Repository/tuquet-creator/scripts/network/test_network.ps1)**:
   - Chẩn đoán tình trạng mạng và độ phản hồi của các cổng proxy.

---

## 5. Quy Trình Vận Hành Thường Nhật (Zero-Friction Workflow)

Bạn không cần kiểm tra hay bận tâm xem VBS đã chạy chưa:
* **Cách 1 (Chạy qua VS Code Tasks UI)**:
  - Bấm `Ctrl+Shift+B` hoặc `Ctrl+Shift+P` -> `Tasks: Run Task` -> Chọn `supabase db push` hoặc `git push`.
* **Cách 2 (Chạy lệnh trực tiếp từ Terminal)**:
  ```powershell
  # Chay push git xuyen qua proxy
  .\scripts\network\ensure_proxy.ps1 git push
  
  # Chay push supabase xuyen qua proxy
  .\scripts\network\ensure_proxy.ps1 supabase db push
  ```
