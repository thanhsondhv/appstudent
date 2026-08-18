"""
Kiểm thử tích hợp: chạy MÃ THẬT của worker với REDIS THẬT.

Khác với test_hang_doi_thong_bao.py — tệp đó dùng Redis giả và bản sao thuật
toán, nên nếu mã thật đổi mà quên cập nhật thì vẫn đạt. Tệp này import thẳng
`worker_windows` và `tasks`, đẩy việc qua Redis thật, nên bắt được cả sai lệch
giữa mã và phép thử.

Chỉ Firebase và cơ sở dữ liệu là giả — không gửi thông báo thật, không ghi
dữ liệu thật.

Điều kiện: Redis đang chạy ở localhost:6379.
    brew install redis && redis-server --daemonize yes

Chạy:  python tests/test_tich_hop_redis.py
Tự bỏ qua (mã thoát 0) nếu không có Redis, để CI trên máy chưa cài vẫn xanh.
"""

from __future__ import annotations

import json
import sys
import time
import types
from pathlib import Path

GOC = Path(__file__).resolve().parent.parent


# ===========================================================================
# Giả lập Firebase và cơ sở dữ liệu — phải cài TRƯỚC khi import mã thật
# ===========================================================================

LO_DA_GUI: list[int] = []
LAN_GHI_CSDL: list[tuple] = []


def _cai_module_gia() -> None:
    class _KetQua:
        def __init__(self, ok: bool):
            self.success = ok
            self.exception = None

    class _PhanHoi:
        def __init__(self, n: int):
            self.success_count = n
            self.failure_count = 0
            self.responses = [_KetQua(True)] * n

    msg = types.ModuleType("firebase_admin.messaging")
    for ten in ("AndroidConfig", "AndroidNotification", "APNSConfig",
                "APNSPayload", "Aps", "ApsAlert", "Notification"):
        setattr(msg, ten, lambda *a, **k: types.SimpleNamespace(**k))
    msg.MulticastMessage = lambda **k: types.SimpleNamespace(tokens=k.get("tokens", []))

    def _gui(m):
        LO_DA_GUI.append(len(m.tokens))
        return _PhanHoi(len(m.tokens))

    msg.send_each_for_multicast = _gui

    fb = types.ModuleType("firebase_admin")
    fb._apps = {"da_khoi_tao": True}
    fb.credentials = types.SimpleNamespace(Certificate=lambda p: None)
    fb.initialize_app = lambda *a, **k: None
    fb.messaging = msg

    sys.modules["firebase_admin"] = fb
    sys.modules["firebase_admin.messaging"] = msg

    class _Con:
        def execute(self, sql, *a):
            if "tbl_Notification_Queue" in sql:
                LAN_GHI_CSDL.append((sql.strip()[:50], a))
            return self

        def fetchall(self):
            return []

    class _KetNoi:
        def cursor(self):
            return _Con()

        def commit(self):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

    db = types.ModuleType("database")
    db.get_db_conn = lambda: _KetNoi()
    sys.modules["database"] = db


# ===========================================================================


def chay() -> int:
    try:
        import redis as pyredis
    except ImportError:
        print("⏭️  Bỏ qua: chưa cài thư viện redis (pip install redis)")
        return 0

    r = pyredis.Redis(host="localhost", port=6379, decode_responses=True,
                      socket_connect_timeout=3)
    try:
        r.ping()
    except Exception:  # noqa: BLE001
        print("⏭️  Bỏ qua: Redis không chạy ở localhost:6379")
        return 0

    # Kiểm tra import THẬT trước khi giả lập.
    #
    # Bổ sung 18/08/2026: bản đầu tiên của tệp này giả lập module `database`
    # ngay từ đầu, nên che mất một lỗi thật — thư mục gốc có gói `database/`
    # còn notification_system có tệp `database.py`, và thứ tự sys.path sai làm
    # worker ném ImportError ngay khi khởi động. Phép thử vẫn xanh vì bản giả
    # đã chiếm chỗ. Nay import thật trước, giả lập sau.
    import subprocess
    kq = subprocess.run(
        [sys.executable, "-c",
         "import sys; sys.path.insert(0, '.'); import worker_windows"],
        cwd=str(GOC / "notification_system"),
        capture_output=True, text=True, timeout=60,
    )
    if kq.returncode != 0:
        dong_cuoi = [l for l in kq.stderr.strip().splitlines() if l.strip()][-1:]
        print(f"  ❌ worker_windows KHÔNG import được khi chạy thật")
        print(f"     {dong_cuoi[0] if dong_cuoi else kq.stderr[:120]}")
        return 1
    print("  ✅ worker_windows import được khi chạy thật (không giả lập)")

    _cai_module_gia()
    sys.path.insert(0, str(GOC / "notification_system"))
    import worker_windows as W          # noqa: E402
    from tasks import send_fcm_task     # noqa: E402

    loi = 0
    Q, DL = "q_kiemthu", "q_kiemthu:dang_xu_ly"

    # ── 1. Trọn vòng đời với công việc chia nhỏ ──────────────────────────
    LO_DA_GUI.clear(); LAN_GHI_CSDL.clear()
    r.delete(Q, DL, f"{Q}:that_bai", "notif:999:con_lai", "notif:999:thanh_cong")

    tokens = [f"token_{i}" for i in range(1000)]
    LO = 450
    cac_lo = [tokens[i:i + LO] for i in range(0, len(tokens), LO)]
    r.set("notif:999:con_lai", len(cac_lo))
    r.set("notif:999:thanh_cong", 0)
    for i, lo in enumerate(cac_lo, 1):
        r.rpush(Q, json.dumps({
            "nid": 999, "title": "Thử", "body": "Nội dung", "cat": "GENERAL",
            "tokens": lo, "priority": 0, "phan": i, "tong_phan": len(cac_lo),
            "tong_thiet_bi": len(tokens),
        }))

    ghi_giua_chung = []
    while r.llen(Q) > 0:
        chuoi = r.brpoplpush(Q, DL, timeout=1)
        d = json.loads(chuoi)
        kq = send_fcm_task(d["nid"], d["title"], d["body"], d["cat"],
                           d["tokens"], d["priority"], "")
        r.lrem(DL, 1, chuoi)
        if r.llen(Q) > 0:
            ghi_giua_chung.append(len(LAN_GHI_CSDL))
        W._ghi_ket_qua_neu_xong(r, d["nid"], kq["thanh_cong"], d["tong_thiet_bi"])

    if sum(LO_DA_GUI) != 1000:
        print(f"  ❌ Gửi {sum(LO_DA_GUI)}/1000 thiết bị — thiếu hoặc trùng"); loi += 1
    elif any(n > 450 for n in LO_DA_GUI):
        print(f"  ❌ Có lô vượt giới hạn 500 của Firebase: {LO_DA_GUI}"); loi += 1
    elif len(LAN_GHI_CSDL) != 1:
        print(f"  ❌ Ghi CSDL {len(LAN_GHI_CSDL)} lần, phải đúng 1 lần"); loi += 1
    elif any(n > 0 for n in ghi_giua_chung):
        print("  ❌ Đã ghi CSDL khi chưa xong hết các phần"); loi += 1
    elif r.llen(Q) or r.llen(DL):
        print(f"  ❌ Hàng đợi chưa sạch: q={r.llen(Q)} đang_xử_lý={r.llen(DL)}"); loi += 1
    else:
        print(f"  ✅ Trọn vòng đời: 1000 thiết bị → {len(cac_lo)} công việc → "
              f"lô {LO_DA_GUI} → ghi CSDL đúng 1 lần")

    # ── 2. Worker chết giữa chừng ────────────────────────────────────────
    r.delete(Q, DL, f"{Q}:that_bai")
    goc = W.GIAY_COI_NHU_CHET
    W.GIAY_COI_NHU_CHET = 1
    try:
        r.rpush(DL, json.dumps({"nid": 555, "_bat_dau_luc": time.time() - 10}))
        W._nhat_lai_viec_bo_do(r, Q, DL)
        if r.llen(Q) == 1 and r.llen(DL) == 0:
            print("  ✅ Worker chết giữa chừng: việc được nhặt lại, không mất")
        else:
            print(f"  ❌ Mất việc: q={r.llen(Q)} đang_xử_lý={r.llen(DL)}"); loi += 1

        # ── 3. Thất bại quá số lần → hàng đợi lỗi ────────────────────────
        r.delete(Q, DL, f"{Q}:that_bai")
        r.rpush(DL, json.dumps({"nid": 556, "_lan_thu": W.SO_LAN_THU_LAI,
                                "_bat_dau_luc": time.time() - 10}))
        W._nhat_lai_viec_bo_do(r, Q, DL)
        if r.llen(Q) == 0 and r.llen(f"{Q}:that_bai") == 1:
            print("  ✅ Thất bại quá số lần: chuyển sang hàng đợi lỗi, không quay vòng")
        else:
            print(f"  ❌ Quay vòng vô tận: q={r.llen(Q)}"); loi += 1
    finally:
        W.GIAY_COI_NHU_CHET = goc
        r.delete(Q, DL, f"{Q}:that_bai", "notif:999:con_lai", "notif:999:thanh_cong")

    print(f"\n{'✅ TẤT CẢ ĐẠT' if loi == 0 else f'❌ {loi} phép thử KHÔNG ĐẠT'}  (3 phép thử tích hợp)")
    return 1 if loi else 0


if __name__ == "__main__":
    sys.exit(chay())
