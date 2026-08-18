"""
Kiểm tra Firebase bằng chế độ dry_run — KHÔNG gửi thông báo tới thiết bị nào.

`dry_run=True` bảo Firebase hãy xác thực mọi thứ rồi dừng lại ngay trước bước
giao tin: kiểm tra khoá dịch vụ, kiểm tra định dạng tin nhắn, và kiểm tra từng
token còn sống hay đã chết. Nhờ vậy kiểm được gần như toàn bộ đường gửi mà
không làm phiền ai.

Bài này đã bắt được một lỗi thật ngày 18/08/2026: danh sách `LOI_TOKEN_CHET`
trong tasks.py thiếu mã `NOT_FOUND` — chính là mã Firebase trả về cho token đã
gỡ ứng dụng. Cơ chế dọn token chết vì thế nhận ra 0/17 token thay vì 17/17.
Không chạy thật với Firebase thì không có cách nào phát hiện.

Cần: khoá vinhuni-portal-firebase-adminsdk.json, kết nối cơ sở dữ liệu, mạng.
Tự bỏ qua (mã thoát 0) nếu thiếu bất kỳ thứ nào — để CI vẫn xanh.

Chạy:  python tests/kiem_tra_firebase.py
"""

from __future__ import annotations

import os
import sys
import warnings
from collections import Counter
from pathlib import Path

warnings.filterwarnings("ignore")

GOC = Path(__file__).resolve().parent.parent
SO_TOKEN_THU = int(os.getenv("FB_TEST_TOKENS", "40"))


def _nap_env() -> None:
    tep = GOC / ".env"
    if not tep.exists():
        return
    for dong in tep.read_text(encoding="utf-8").splitlines():
        dong = dong.strip()
        if dong and not dong.startswith("#") and "=" in dong:
            k, _, v = dong.partition("=")
            os.environ.setdefault(k.strip(), v.strip())


def chay() -> int:
    _nap_env()
    sys.path.insert(0, str(GOC))
    sys.path.insert(0, str(GOC / "notification_system"))

    khoa = GOC / "vinhuni-portal-firebase-adminsdk.json"
    if not khoa.exists():
        print("⏭️  Bỏ qua: không tìm thấy khoá Firebase"); return 0

    try:
        import firebase_admin
        from firebase_admin import credentials, messaging
        import pyodbc
    except ImportError as exc:
        print(f"⏭️  Bỏ qua: thiếu thư viện ({exc.name})"); return 0

    # ── 1. Khoá dịch vụ ──────────────────────────────────────────────────
    try:
        if not firebase_admin._apps:
            firebase_admin.initialize_app(credentials.Certificate(str(khoa)))
        print("  ✅ Khoá Firebase hợp lệ, khởi tạo SDK thành công")
    except Exception as exc:  # noqa: BLE001
        print(f"  ❌ Khoá Firebase không dùng được: {str(exc)[:90]}"); return 1

    # ── 2. Lấy token thật ────────────────────────────────────────────────
    import tasks as T
    from core.settings import settings

    try:
        with pyodbc.connect(settings.db.local_conn_str, timeout=15) as conn:
            tokens = [r[0] for r in conn.cursor().execute(f"""
                SELECT TOP {SO_TOKEN_THU} FCMToken FROM tbl_FCM_Tokens
                WHERE IsActive = 1 AND FCMToken IS NOT NULL AND LEN(FCMToken) > 50
                ORDER BY NEWID()""").fetchall()]
    except Exception as exc:  # noqa: BLE001
        print(f"⏭️  Bỏ qua: không kết nối được cơ sở dữ liệu ({str(exc)[:50]})"); return 0

    if not tokens:
        print("⏭️  Bỏ qua: không có token nào trong cơ sở dữ liệu"); return 0

    # ── 3. Dựng tin nhắn bằng hàm thật ───────────────────────────────────
    loi = 0
    try:
        tin = T._dung_tin_nhan("Kiểm thử hệ thống", "Nội dung thử nghiệm",
                               nid=0, cat="GENERAL", is_chat=False,
                               group_id="", priority=0, tokens=tokens)
        print(f"  ✅ Dựng được tin nhắn với {len(tokens)} token")
    except Exception as exc:  # noqa: BLE001
        print(f"  ❌ Không dựng được tin nhắn: {str(exc)[:90]}"); return 1

    # ── 4. Firebase xác thực, không gửi ──────────────────────────────────
    kq = messaging.send_each_for_multicast(tin, dry_run=True)
    print(f"  ✅ Firebase chấp nhận định dạng tin nhắn "
          f"({kq.success_count} token còn sống / {kq.failure_count} đã chết)")

    # ── 5. Mã lỗi có được nhận ra hết không? ─────────────────────────────
    ma_loi: Counter[str] = Counter()
    khong_nhan_ra: Counter[str] = Counter()
    for r in kq.responses:
        if r.success:
            continue
        ma = str(getattr(getattr(r, "exception", None), "code", "?"))
        ma_loi[ma] += 1
        if ma not in T.LOI_TOKEN_CHET:
            khong_nhan_ra[ma] += 1

    # Các mã tạm thời thì KHÔNG nên nằm trong danh sách token chết
    TAM_THOI = {"UNAVAILABLE", "INTERNAL", "QUOTA_EXCEEDED", "DEADLINE_EXCEEDED"}
    that_su_sot = {m: n for m, n in khong_nhan_ra.items() if m not in TAM_THOI}

    if that_su_sot:
        loi += 1
        print(f"  ❌ Có mã lỗi token chết mà tasks.LOI_TOKEN_CHET chưa biết:")
        for ma, n in that_su_sot.items():
            print(f"       {ma}: {n} token — cần thêm vào LOI_TOKEN_CHET")
    elif ma_loi:
        print(f"  ✅ Nhận ra hết {kq.failure_count}/{kq.failure_count} token chết "
              f"(mã: {', '.join(sorted(ma_loi))})")
    else:
        print("  ✅ Không có token chết trong mẫu này")

    print("\n  ℹ️  Không có thông báo nào được gửi tới thiết bị (dry_run=True)")
    print(f"\n{'✅ TẤT CẢ ĐẠT' if loi == 0 else f'❌ {loi} phép thử KHÔNG ĐẠT'}")
    return 1 if loi else 0


if __name__ == "__main__":
    sys.exit(chay())
