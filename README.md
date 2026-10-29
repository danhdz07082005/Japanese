# 🎮 Japanese Mastery — Realtime Multiplayer Game Server & Mission Control

> **Đồ án môn học**: **GNS301** (Game Networking and Server Development)  
> **Kiến trúc**: ASP.NET Core 8 (.NET 10 Runtime) + WebSocket Full-Duplex (RFC 6455) + Cloudflare Tunnel + PyTunnel Neon HUD  
> **Mục tiêu**: Hệ thống máy chủ game thời gian thực độ trễ siêu thấp (<15ms), kết nối bạn bè toàn cầu qua Tunnel mà không cần mở port modem hay thuê VPS, giám sát tập trung qua Web Dashboard Mission Control thay thế 3 cửa sổ CMD truyền thống.

---

## 🌟 Điểm Nổi Bật Của Hệ Thống (Key Features)

### 1. ⚡ Realtime WebSocket Gateway (Chuẩn GNS301 RFC 6455)
- **Thay thế hoàn toàn cơ chế HTTP Polling cũ**: Không còn tình trạng lặp 500ms hay 800ms gây nghẽn băng thông và trễ tới 1.3s.
- **Độ trễ tức thời (<15ms)**: Mỗi ký tự người chơi gõ trong trận đấu được gửi delta tức thời qua WebSocket frame; đối thủ nhìn thấy thanh tiến trình nhích lên 60fps mượt mà.
- **Đo đạc RTT & Latency liên tục**: Gói tin Ping-Pong được gửi định kỳ 2s/lần để tính toán độ trễ mạng (Round-Trip Time) và hiển thị trực tiếp lên HUD trận đấu (`⚡ 14 ms`).
- **Server-Authoritative Match Engine**: Máy chủ quản lý hàng đợi ghép trận (Matchmaking FIFO), đếm ngược 3 giây đồng bộ, kiểm tra trạng thái gõ phím, tự động phán xét người chiến thắng và cộng thưởng GCoin vào cơ sở dữ liệu.

### 2. 📊 Mission Control Dashboard: Giám Sát Tập Trung Thay Thế 3 Cửa Sổ CMD
- Trước đây khi làm bài tập, sinh viên phải mở đồng thời 3 cửa sổ CMD (1 Server, 2 Client) và xem log đen trắng rất rối mắt.
- Với **PyTunnel Mission Control** (`http://127.0.0.1:8787`):
  - **Single Pane of Glass**: Mọi sự kiện từ Server, kết nối socket, tiến trình gõ của từng người chơi, mã phòng, thắng/thua đều được tổng hợp về 1 màn hình Web Cyber HUD Neon duy nhất.
  - **Bộ lọc thông minh (Console Filters)**: Lọc xem riêng biệt theo từng service: `.NET 8 (8080)`, `PvP Socket`, `PvP Engine`.
  - **Số liệu đo đạc trực quan**: Hiển thị số lượng active connections, packets throughput, trạng thái tunnel.

### 3. 🌐 Giải Pháp Game Online: Đổi URL Tunnel Mà Không Cần Build Lại Game
- Khi sử dụng Cloudflare Quick Tunnel miễn phí, mỗi lần khởi động tunnel sẽ sinh ra một URL ngẫu nhiên (`https://xxxx.trycloudflare.com`).
- **In-Game Dynamic Server Config**:
  - Tại màn hình Login của Game Godot, người chơi có nút **`⚙️ Đổi Server`** và nhãn trạng thái **`Server: 🟢 Online (12 ms)`**.
  - Bạn bè chỉ cần dán link tunnel mới vào ô này 1 lần duy nhất trong game $\rightarrow$ Game tự lưu vào `user://server_config.json`.
  - Client tự động map giao thức: `http://` $\rightarrow$ `ws://` và `https://` $\rightarrow$ `wss://`. **Tuyệt đối không bao giờ phải xuất bản lại file build game!**

---

## 🏛️ Sơ Đồ Kiến Trúc Hệ Thống (Architecture Overview)

```
┌─────────────────────────────────┐       ┌─────────────────────────────────┐
│     Player 1 (Host / LAN)       │       │    Player 2 (Friend qua WAN)    │
│       Godot Game Client         │       │       Godot Game Client         │
└────────────────┬────────────────┘       └────────────────┬────────────────┘
                 │ Local WebSocket                         │ Public WSS Tunnel
                 ▼                                         ▼
┌─────────────────────────────────┐       ┌─────────────────────────────────┐
│   Kestrel WebSocket Gateway     │       │   Cloudflare Edge Network       │
│      Endpoint: /ws/pvp          │       │      (trycloudflare.com)        │
└────────────────┬────────────────┘       └────────────────┬────────────────┘
                 │                                         │ Encrypted Stream
                 │                                         ▼
                 │                        ┌─────────────────────────────────┐
                 │                        │   PyTunnel Studio (Port 8787)   │
                 │                        │      Reverse Proxy Shield       │
                 │                        └────────────────┬────────────────┘
                 │                                         │ Forward 127.0.0.1:8080
                 ▼                                         ▼
┌───────────────────────────────────────────────────────────────────────────┐
│              GameServer — ASP.NET Core 8 (.NET 10 Runtime)                │
│                                                                           │
│  ├── Realtime/                                                            │
│  │   ├── WsPvPMiddleware.cs     : WebSocket Upgrade & Message Routing     │
│  │   ├── WsConnectionManager.cs : Thread-safe Client Connection Registry  │
│  │   ├── PvPMatchEngine.cs      : Matchmaking, Timer, Realtime Sync       │
│  │   └── MetricsTracker.cs      : Packets Counter & RTT Jitter Metric     │
│  ├── Controllers/               : REST APIs (Auth, Shop, SRS, Player)     │
│  ├── Logging/                                                            │
│  │   └── PyTunnelLogSink.cs     : Stream Event Logs to Mission Control    │
│  └── Data/                                                               │
│      └── AppDbContext.cs        : Dual-Mode SQLite & SQL Server Fallback  │
└───────────────────────────────────────────────────────────────────────────┘
```

---

## 📂 Cấu Trúc Thư Mục Tinh Gọn (Project Directory)

```text
E:\8\Sever\
│
├── GameClient/                     # [MÃ NGUỒN GAME GODOT 4.6]
│   ├── data/
│   │   └── jmdict_levels.json      # Cơ sở dữ liệu từ điển từ vựng (Level 25-100)
│   ├── kanji/                      # Dữ liệu Stroke KanjiVG
│   ├── scenes/                     # Giao diện game (Login, Main, PvP, Shop, SoloLearning...)
│   ├── scripts/
│   │   ├── autoloads/
│   │   │   ├── Network.gd          # Quản lý Server Config động & Discovery Health Check
│   │   │   ├── Database.gd         # Local account storage & offline cache
│   │   │   └── Global.gd           # Scene transitions & coin state
│   │   ├── Login.gd                # Màn hình đăng nhập + Modal cấu hình Server URL
│   │   ├── PvP.gd                  # Native WebSocketPeer (<20ms, Ping HUD)
│   │   └── Curriculum.gd           # Quản lý tiến trình học & Resilient fallback
│   ├── kanjivg_paths.json          # Pre-baked kanji stroke paths
│   └── project.godot               # Godot 4.6 Engine Configuration
│
├── GameServer/                     # [MÃ NGUỒN BACKEND C# .NET 8]
│   ├── Controllers/                # REST Web APIs
│   ├── Data/                       # AppDbContext, DatabaseInitializer, Models
│   ├── Logging/                    # PyTunnelLogSink (Event stream to Web HUD)
│   ├── Models/ & DTOs/             # Data Transfer Objects & Schemas
│   ├── Realtime/                   # WebSocket Gateway, Match Engine & Metrics Tracker
│   ├── Services/                   # Business Services (Auth, Shop, Vocabulary...)
│   ├── pvp_paragraphs.txt          # 803 đoạn văn tiếng Nhật cho đấu gõ phím
│   ├── appsettings.json            # Cấu hình Database & PyTunnel Endpoint
│   └── JapaneseMasteryBackendDotNet.csproj
│
├── pytunnelGNS/                    # [TRẠM ĐIỀU KHIỂN CLOUDFLARE TUNNEL & WEB HUD]
│   ├── backend/                    # FastAPI Control Plane (Port 8787)
│   ├── frontend/                   # Cyber HUD Neon Web Interface & Terminal Screen
│   ├── bin/                        # cloudflared executable (Zero-Config)
│   └── start.bat                   # Script khởi chạy riêng của Tunnel
│
├── start_all.bat                   # 🚀 1-CLICK KHỞI ĐỘNG TOÀN BỘ HỆ THỐNG (.NET 8 + PyTunnel Dashboard)
├── run_tunnel_standalone.bat       # ⚡ 1-CLICK MỞ TUNNEL ĐỘC LẬP (Không cần cài Python, tự tải cloudflared)
├── .gitignore                      # Loại trừ file rác, bin/obj, db cache
└── README.md                       # Tài liệu hướng dẫn chi tiết
```

---

## 🚀 Hướng Dẫn Vận Hành Từng Bước (Quick Start)

### 🟢 Cách 1: Khởi động đầy đủ có Web Dashboard (Khuyên dùng khi máy có Python)
Nhấp đúp chuột vào file: **`start_all.bat`** tại thư mục gốc.
1. Khởi chạy **GameServer (.NET 8)** tại `http://127.0.0.1:8080`.
2. Khởi chạy **PyTunnel Web Dashboard** tại `http://127.0.0.1:8787` (có Đài Quan Sát Live Log Neon, theo dõi FPS, ghép trận).
3. Trên web `127.0.0.1:8787`, nhập cổng `8080`, chọn chế độ **Public (Công khai)** và bấm **Bắt đầu đường hầm**.

### 🟢 Cách 2: Khởi động siêu tốc không cần cài Python (Dành cho máy bạn bè chưa có Python)
Nếu máy bạn bè của bạn chỉ có .NET mà **chưa cài đặt Python**:
1. Nhấp đúp vào file: **`run_tunnel_standalone.bat`**.
2. Script sẽ tự động dùng PowerShell/Windows Curl tải động cơ `cloudflared` (chỉ 1 lần duy nhất, ~10s) và mở ngay đường hầm Cloudflare ra Internet cho cổng 8080.
3. Nhìn trên màn hình CMD sẽ xuất hiện dòng:
   `https://xxxx.trycloudflare.com`
4. Copy link đó gửi cho bạn bè hoặc dán vào game là chơi ngay lập tức 100%!

### 🟢 Bước 2: Bật Tunnel chia sẻ cho bạn bè ở xa
1. Trên giao diện Web PyTunnel (`http://127.0.0.1:8787`):
   - **Nhập cổng (Port)**: `8080`
   - **Chế độ (Mode)**: Chọn **CÔNG KHAI (Public)**.
   - Nhấn nút **"Bắt đầu đường hầm" (Start Tunnel)**.
2. Đợi vài giây, PyTunnel sẽ cấp cho bạn đường link HTTPS công khai (ví dụ: `https://sweet-apple-123.trycloudflare.com`).
3. Sao chép link này gửi cho bạn bè qua Zalo / Discord.

### 🟢 Bước 3: Mở Game Godot & Kết Nối
1. Mở **Godot Engine** (`C:\godot\Godot_v4.6.2-stable_win64_console.exe`), chọn mở project `E:\8\Sever\GameClient`.
2. Tại màn hình Login:
   - **Nếu bạn là Host (máy nhà)**: Màn hình tự hiện `Server: 🟢 Online (10 ms)`.
   - **Nếu là bạn bè kết nối qua mạng**: Bấm nút **`⚙️ Đổi Server`**, dán link tunnel `https://sweet-apple-123.trycloudflare.com` vào và bấm **"Lưu & Kết Nối"**.
3. Đăng nhập tài khoản để test ngay:
   - **Người chơi 1 (Host)**: `admin` / mật khẩu `123` (Level 99, GCoin 9999).
   - **Người chơi 2 (Rival)**: `player2` / mật khẩu `123` (Level 25, GCoin 500).
   *(Hoặc bấm nút **Đăng Ký** để tạo tài khoản mới tùy ý).*

### 🟢 Bước 4: Trải nghiệm PvP Realtime & Quan sát Mission Control
1. Cả 2 người chơi vào mục **PvP Arena** $\rightarrow$ Bấm **Quick Match** (hoặc tạo phòng bằng Room Code).
2. Trận đấu ghép cặp ngay tức thì! Bảng đếm ngược 3 giây xuất hiện.
3. Người chơi 1 gõ phím $\rightarrow$ Thanh tiến trình trên màn hình Người chơi 2 nhích theo thời gian thực!
4. Mở lại trình duyệt Web PyTunnel: Xem log nhảy sinh động với tag `[PVP-SOCKET]`, `[PVP-ENGINE]`, độ trễ RTT và thông báo người chiến thắng!

---

## 🛠️ Công Nghệ Sử Dụng (Tech Stack)

| Thành Phần | Công Nghệ | Vai Trò |
| :--- | :--- | :--- |
| **Game Client** | Godot Engine 4.6 (GDScript) | Giao diện đồ họa, xử lý gõ phím, `WebSocketPeer` |
| **Backend Framework** | ASP.NET Core 8 (.NET 10 SDK) | Kestrel Web Server, Dependency Injection, Middleware |
| **Realtime Transport** | WebSocket (RFC 6455) | Full-duplex persistent stream, Binary/Text frames |
| **Database** | SQLite (EF Core 8.0) | Zero-config, tự động tạo bảng & fallback SQL Server |
| **Security** | JWT (JSON Web Tokens), BCrypt | Xác thực bảo mật, chống gian lận |
| **Tunneling** | Cloudflare Tunnel (`cloudflared`) | Vượt NAT/Firewall, cấp phát WSS miễn phí không mở port |
| **Dashboard UI** | FastAPI, HTML5, CSS3 Neon HUD | Trạm điều khiển Mission Control, aggregate live logs |

---

## 👨‍💻 Tác Giả & Bản Quyền
- Dự án phát triển phục vụ học tập & đồ án môn học **GNS301** (Đại học FPT).
- Mã nguồn tuân thủ Clean Architecture, không hardcode, không code smell, tối ưu hiệu năng cao.
