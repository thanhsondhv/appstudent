"""
Kiểm tra máy chủ đã sẵn sàng chưa — CHẠY TRƯỚC KHI KHỞI ĐỘNG DỊCH VỤ.

Mục đích: bắt mọi thứ có thể làm backend chết ngay khi khởi động, tại thời điểm
còn sửa được, thay vì phát hiện qua việc sinh viên không đăng nhập được.

    python kiem_tra_truoc_khi_chay.py

Mã thoát 0 = đủ điều kiện chạy. Khác 0 = còn việc phải làm, in rõ từng việc.

Thêm 18/08/2026 cùng đợt chuyển cấu hình sang .env. Trước đó khoá bí mật nằm
rải trong mã nguồn nên "chạy được" là mặc nhiên; nay thiếu .env là dịch vụ
không lên, nên cần một bước kiểm tra tường minh.
"""

from __future__ import annotations

import os
import socket
import sys
import warnings
from pathlib import Path

warnings.filterwarnings("ignore")

GOC = Path(__file__).resolve().parent
DAT, HONG, CANH = [], [], []


def dat(m): DAT.append(m); print(f"  \033[32m✅\033[0m {m}")
def hong(m, cach=""): HONG.append((m, cach)); print(f"  \033[31m❌\033[0m {m}")
def canh(m): CANH.append(m); print(f"  \033[33m⚠️\033[0m  {m}")
def muc(t): print(f"\n\033[1m{t}\033[0m")


# ── 1. Cấu hình ───────────────────────────────────────────────────────────
muc("1. Tệp cấu hình .env")

if not (GOC / ".env").exists():
    hong("Không có tệp .env",
         f"copy {GOC / '.env.example'} {GOC / '.env'}  rồi điền giá trị thật")
    print("\n\033[31mDỪNG: không có .env thì không kiểm tra tiếp được.\033[0m")
    sys.exit(1)
dat("Có tệp .env")

sys.path.insert(0, str(GOC))
try:
    from core.settings import settings
except SystemExit:
    # settings.py đã in danh sách khoá thiếu ra stderr rồi
    print("\n\033[31mDỪNG: .env thiếu khoá bắt buộc (xem danh sách bên trên).\033[0m")
    sys.exit(1)
except Exception as exc:  # noqa: BLE001
    hong(f"Không nạp được cấu hình: {type(exc).__name__}: {str(exc)[:120]}")
    sys.exit(1)
dat("Đủ 8 khoá bắt buộc")

if settings.security.jwt_secret in ("ci-khong-dung-that", "changeme", "secret"):
    hong("JWT_SECRET_KEY còn là giá trị mẫu",
         "đặt chuỗi ngẫu nhiên dài: python -c \"import secrets;print(secrets.token_urlsafe(48))\"")
elif len(settings.security.jwt_secret) < 32:
    canh(f"JWT_SECRET_KEY hơi ngắn ({len(settings.security.jwt_secret)} ký tự), nên từ 32 trở lên")
else:
    dat("JWT_SECRET_KEY đủ mạnh")


# ── 2. Trình điều khiển ODBC ──────────────────────────────────────────────
muc("2. Trình điều khiển ODBC")
try:
    import pyodbc
    ds = pyodbc.drivers()
    if settings.db.driver in ds:
        dat(f"Có \"{settings.db.driver}\"")
    else:
        hong(f"Thiếu \"{settings.db.driver}\" — máy chỉ có: {', '.join(ds) or '(không có)'}",
             "cài ODBC Driver 17 for SQL Server, hoặc sửa DB_DRIVER trong .env")
except ImportError:
    hong("Chưa cài pyodbc", "pip install pyodbc")


# ── 3. Cơ sở dữ liệu ──────────────────────────────────────────────────────
muc("3. Cơ sở dữ liệu SQL Server")
try:
    import pyodbc
    with pyodbc.connect(settings.db.local_conn_str, timeout=10) as conn:
        cur = conn.cursor()
        dat(f"Kết nối được {settings.db.safe_repr}")

        # Các bảng mà luồng thông báo bắt buộc phải có
        for bang in ("tbl_Notification_Queue", "tbl_ThongBao",
                     "tbl_FCM_Tokens", "tbl_users"):
            co = cur.execute(
                "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = ?",
                bang).fetchval()
            if co:
                dat(f"Có bảng {bang}")
            else:
                hong(f"Thiếu bảng {bang}", "kiểm tra lại DB_NAME trong .env")

        song = cur.execute(
            "SELECT COUNT(*) FROM tbl_FCM_Tokens WHERE IsActive = 1").fetchval()
        if song == 0:
            canh("Không có token thiết bị nào đang hoạt động — sẽ không gửi được thông báo")
        else:
            dat(f"{song} token thiết bị đang hoạt động")
except Exception as exc:  # noqa: BLE001
    hong(f"Không kết nối được cơ sở dữ liệu: {str(exc)[:140]}",
         "kiểm tra DB_SERVER/DB_USER/DB_PASSWORD trong .env và tường lửa cổng 1433")


# ── 4. Redis ──────────────────────────────────────────────────────────────
muc("4. Redis (hàng đợi thông báo)")
try:
    import redis as pyredis
    r = pyredis.Redis(host="localhost", port=6379, socket_connect_timeout=3)
    r.ping()
    dat("Redis phản hồi ở localhost:6379")
    ton = r.llen("notification_queue")
    if ton > 100:
        canh(f"Hàng đợi còn tồn {ton} công việc — kiểm tra worker có chạy không")
    loi = r.llen("notification_queue:that_bai")
    if loi:
        canh(f"{loi} công việc nằm trong hàng đợi lỗi, cần xem lại")
except ImportError:
    hong("Chưa cài thư viện redis", "pip install redis")
except Exception:  # noqa: BLE001
    hong("Redis không chạy ở localhost:6379",
         "Windows: cài Memurai (memurai.com) hoặc chạy Redis trong WSL. "
         "Không có Redis thì thông báo sẽ không gửi được.")


# ── 5. Firebase ───────────────────────────────────────────────────────────
muc("5. Firebase (gửi thông báo đẩy)")
khoa = Path(settings.firebase.credentials_path) if getattr(
    settings, "firebase", None) else GOC / "vinhuni-portal-firebase-adminsdk.json"
if not khoa.is_absolute():
    khoa = GOC / khoa
if khoa.exists():
    dat(f"Có khoá dịch vụ: {khoa.name}")
    try:
        import firebase_admin
        from firebase_admin import credentials
        if not firebase_admin._apps:
            firebase_admin.initialize_app(credentials.Certificate(str(khoa)))
        dat("Khoá Firebase hợp lệ")
    except ImportError:
        hong("Chưa cài firebase-admin", "pip install firebase-admin")
    except Exception as exc:  # noqa: BLE001
        hong(f"Khoá Firebase không dùng được: {str(exc)[:110]}")
else:
    hong(f"Không tìm thấy khoá Firebase tại {khoa}",
         "chép tệp vinhuni-portal-firebase-adminsdk.json vào thư mục backend")


# ── 6. Cổng mạng ──────────────────────────────────────────────────────────
muc("6. Cổng mạng")
for cong, ten in ((8000, "API chính"), (8082, "Điều phối thông báo")):
    s = socket.socket()
    s.settimeout(1)
    dang_dung = s.connect_ex(("127.0.0.1", cong)) == 0
    s.close()
    if dang_dung:
        canh(f"Cổng {cong} ({ten}) đang có tiến trình chiếm — dừng bản cũ trước khi chạy bản mới")
    else:
        dat(f"Cổng {cong} ({ten}) trống")


# ── 7. Tiến trình cũ phải dừng ────────────────────────────────────────────
muc("7. Tiến trình đời cũ phải dừng hẳn")
print("     Ba tiến trình MỚI thay cho các tiến trình cũ. Chạy song song sẽ gửi trùng:")
print("       PHẢI DỪNG:  master_worker.py, sync_and_notify_worker.py, notification_worker.py")
print("       CHẠY THAY:  notification_system/producer_app.py")
print("                   notification_system/worker_windows.py")
print("                   sync_and_notify_worker_new.py")
canh("Tự kiểm tra bằng Task Manager — kịch bản này không tự tắt tiến trình của bạn")


# ── Kết luận ──────────────────────────────────────────────────────────────
print("\n" + "═" * 60)
if HONG:
    print(f"\033[31m❌ CHƯA CHẠY ĐƯỢC — {len(HONG)} việc phải xử lý:\033[0m\n")
    for i, (m, cach) in enumerate(HONG, 1):
        print(f"  {i}. {m}")
        if cach:
            print(f"     → {cach}")
    print()
    sys.exit(1)

print(f"\033[32m✅ SẴN SÀNG CHẠY\033[0m  ({len(DAT)} mục đạt"
      + (f", {len(CANH)} điểm cần để ý" if CANH else "") + ")")
if CANH:
    print()
    for m in CANH:
        print(f"  ⚠️  {m}")
print()
sys.exit(0)
