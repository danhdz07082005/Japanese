# 🚀 PyTunnel Studio (v5.3.1)

**Multi-Tunnel Hub & Session Lifecycle Manager** — Cầu nối 1-click từ máy Windows cá nhân ra Internet công khai (Zero-Cost, Zero-Config, Không mở cổng Router, Không mua VPS, Không đụng vào mã nguồn ứng dụng CMD).

---

## ✨ Điểm Nổi Bật (Features)

1. **Smart URL & Port Parser**:
   - Tự động nhận diện port và query token từ các link CMD động: `http://127.0.0.1:58931?t=1791247438` hoặc cổng thuần `5000`.
   - Giữ nguyên query token khi chia sẻ cho khách.

2. **0ms Hot-Toggle Session Mode**:
   - Chuyển đổi giữa chế độ **Công Khai (Public - Vào thẳng)** và **Bảo Vệ (Protected - Yêu cầu Access Code 8 ký tự)** tức thì mà không làm ngắt kết nối Cloudflare hay thay đổi tên miền.
   - Khi chuyển sang Protected: Cho phép chọn **Giữ nguyên phiên** (khách đang dùng F5 vẫn dùng tiếp được) hoặc **Đăng xuất tất cả** (đá văng về màn hình khóa ngay).

3. **Token Rotation (Xoay Mã Bảo Vệ)**:
   - **Đổi mã & Giữ phiên**: Khách đang online F5 lại vẫn hoạt động bình thường, chỉ người mới cần mã mới.
   - **Đổi mã & Đá văng hết (Kick-All)**: Hủy toàn bộ cookie phiên, mọi kết nối bị văng về màn hình khóa ngay lập tức.

4. **Bảo Mật Cấp Cao (Senior-Grade Security)**:
   - **Chống XSS & Open Redirect**: Mọi tham số điều hướng được lọc và mã hóa HTML.
   - **Chống CSRF**: Token phiên bảo vệ toàn bộ các endpoint thay đổi trạng thái.
   - **Chống Brute-force**: Khóa tạm thời 15 phút nếu nhập sai mã 5 lần.
   - **Chống DNS Rebinding**: Control Plane (`127.0.0.1:8787`) từ chối mọi Host Header không phải `localhost` hoặc `127.0.0.1`.
   - **Port Blacklist**: Chặn mở các cổng nhạy cảm nguy hiểm (RDP 3389, SMB 445, MSSQL 1433, MySQL 3306, MongoDB 27017, Redis 6379, System ports < 1024).
   - **Win32 Job Object**: Gán cờ `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE (0x2000)` qua kernel Windows, bảo đảm các tiến trình con `cloudflared.exe` tự động diệt sạch ngay cả khi tắt bằng Task Manager "End Task" (Zero Zombie Processes).

5. **Giao Diện Cyber-Tunnel Neon HUD**:
   - Thiết kế tinh tế với bảng màu Dark Slate `#030712`, viền phát sáng Emerald Neon `#10b981` và Cyan Neon `#06b6d4`.
   - Đầy đủ 100% **Tiếng Việt 🇻🇳 & Tiếng Anh 🇬🇧**.
   - Hỗ trợ **Dark Mode 🌙 & Light Mode ☀️**.
   - Hoàn toàn độc lập, không phụ thuộc CDN bên ngoài.

---

## 📂 Cấu Trúc Dự Án (BE & FE Modular Architecture)

```
pytunnel/
│
├── backend/                      # [BE] FastAPI Control Plane & Service Core
│   ├── api/
│   │   ├── routes.py             # REST API endpoints (/api/status, /api/tunnels...)
│   │   └── schemas.py            # Pydantic request & response models
│   ├── core/
│   │   ├── config.py             # Cấu hình tĩnh, cổng mặc định, blacklist
│   │   ├── errors.py             # Domain error với mã i18n
│   │   ├── i18n.py               # Từ điển song ngữ tập trung (VI / EN)
│   │   ├── parser.py             # Smart URL parser & port validator
│   │   └── security.py           # HMAC session cookie & brute-force limiter
│   ├── services/
│   │   ├── auth_proxy.py         # Reverse proxy shield, Cyber Gate, WebSocket
│   │   ├── cloudflared.py        # Quản lý subprocess cloudflared, continuous stderr drain
│   │   ├── engine.py             # Tải & kiểm tra hash SHA-256 chính thức cloudflared
│   │   ├── tunnel_manager.py     # Tunnel aggregate root, socket probe & lifecycle
│   │   └── win_job.py            # Win32 Kernel Job Object (chống zombie process)
│   └── main.py                   # FastAPI Application, CSRF & DNS Rebinding guard
│
├── frontend/                     # [FE] Giao Diện Cyber-Tunnel HUD Neon
│   ├── templates/
│   │   └── index.html            # Dashboard + HelloScreen & GoodbyeScreen 3D HUD
│   └── static/
│       ├── css/
│       │   └── style.css         # Cyber HUD Neon Dark/Light theme
│       └── js/
│           ├── app.js            # Frontend controller, live metrics, CSRF, modal UX
│           ├── cyber_tunnel.js   # Bộ dựng đường hầm không gian 3D 60fps (Three.js & 2D fallback)
│           └── vendor/
│               └── three.min.js  # Thư viện Three.js r128 tự lưu trữ offline (Zero CDN)
│
├── tests/                        # Bộ kiểm thử tự động (21 test suites)
│   ├── test_api.py
│   ├── test_auth_proxy.py
│   ├── test_core.py
│   ├── test_services.py
│   └── test_e2e_integration.py
│
├── requirements.txt              # Danh sách thư viện đồng bộ duy nhất
├── start.bat                     # 1-Click khởi chạy ứng dụng (duy nhất)
└── README.md
```

---

## 💻 Hướng Dẫn Sử Dụng (Quick Start)

### 1. Dành cho người dùng (Production Runtime)
- **Khởi chạy ứng dụng:** Nhấp đúp chuột vào file [`start.bat`](file:///E:/8/VPS/pytunnel/start.bat).
  - Tự động kiểm tra Python và bỏ qua cài đặt nếu đã đủ thư viện (0ms chờ đợi).
  - Tự động giải phóng cổng 8787 nếu có tiến trình cũ chiếm giữ.
  - Tự động mở Dashboard tại `http://127.0.0.1:8787` trên trình duyệt.

---

## 🧪 Kiểm Thử Tự Động (Automated Testing)

- **Chạy kiểm thử dòng lệnh:**
  ```bash
  python -m pytest tests/ -v
  ```
