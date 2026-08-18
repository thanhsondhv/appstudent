"""
Kiểm tra phân quyền của nhóm endpoint thông báo.

Trước 18/08/2026 cả năm endpoint (/get-notifs, /count-unread, /mark-read,
/hide-notif, /mark-all-read) đều lấy mã người dùng từ máy khách và tin luôn.
Mã sinh viên là dãy số có quy luật, mã cán bộ chỉ 4-5 chữ số — nghĩa là đoán mã
là đọc được thông báo của bất kỳ ai trong 62 nghìn tài khoản.

Bài này khoá chặt hành vi đúng, gồm cả bước chuyển tiếp cho ứng dụng bản cũ.

Chạy:  python tests/test_quyen_thong_bao.py
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

GOC = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(GOC))

# Cấu hình giả — chỉ để core.settings không chặn khởi động
for k, v in {
    "APP_ENV": "test", "DB_SERVER": "x", "DB_USER": "x", "DB_PASSWORD": "x",
    "MS_CLIENT_ID": "x", "MS_CLIENT_SECRET": "x", "MS_TENANT_ID": "x",
    "SESSION_SECRET_KEY": "x" * 40, "JWT_SECRET_KEY": "x" * 40,
}.items():
    os.environ.setdefault(k, v)

def _gia_lap_thu_vien_nang() -> None:
    """Thay các thư viện nặng bằng bản giả.

    router.py kéo theo sentence_transformers, pyodbc… — vài trăm MB và cần cả
    cơ sở dữ liệu. Bài này chỉ kiểm tra logic phân quyền, không đụng tới chúng,
    nên giả lập để chạy được trên máy lập trình và trên CI.
    """
    import types

    def _mo_dun(ten: str, **thuoc_tinh):
        if ten in sys.modules:
            return
        m = types.ModuleType(ten)
        for k, v in thuoc_tinh.items():
            setattr(m, k, v)
        sys.modules[ten] = m

    try:
        import sentence_transformers  # noqa: F401
    except ImportError:
        _mo_dun("sentence_transformers",
                SentenceTransformer=lambda *a, **k: types.SimpleNamespace(
                    encode=lambda *a, **k: []))
    try:
        import pyodbc  # noqa: F401
    except ImportError:
        _mo_dun("pyodbc", connect=lambda *a, **k: None, drivers=lambda: [],
                Error=Exception)
    try:
        import numpy  # noqa: F401
    except ImportError:
        _mo_dun("numpy", array=lambda x, **k: x, ndarray=list)


_gia_lap_thu_vien_nang()

DAT, HONG = 0, []


def kt(ten: str, thuc_te, mong_doi) -> None:
    global DAT
    if thuc_te == mong_doi:
        DAT += 1
        print(f"  ✅ {ten}")
    else:
        HONG.append(ten)
        print(f"  ❌ {ten}\n       nhận: {thuc_te!r}\n       cần : {mong_doi!r}")


def chay() -> int:
    try:
        from fastapi import HTTPException
        from auth.jwt_handler import Identity
        from vinhuni_notifications import router as R
    except ImportError as exc:
        print(f"⏭️  Bỏ qua: thiếu thư viện ({exc.name})")
        return 0

    from core.settings import settings

    SV = Identity(user_code="205714023110061", role="SINHVIEN", method="T", token_id="1")
    CB = Identity(user_code="1679", role="CANBO", method="T", token_id="2")

    # ── 1. Sinh viên không mượn được mã người khác ────────────────────────
    print("\n\033[1m1. Sinh viên chỉ đọc được của chính mình\033[0m")
    kt("xin mã người khác → trả về mã của chính mình",
       R._ma_duoc_phep_mem("999999999999999", SV, "t"), "205714023110061")
    kt("xin mã của cán bộ → vẫn là mã của chính mình",
       R._ma_duoc_phep_mem("1679", SV, "t"), "205714023110061")
    kt("xin đúng mã mình → cho qua",
       R._ma_duoc_phep_mem("205714023110061", SV, "t"), "205714023110061")
    kt("tiền tố SV không phá được kiểm tra",
       R._ma_duoc_phep_mem("SV999999999999999", SV, "t"), "205714023110061")

    # ── 2. Cán bộ vẫn tra cứu được ────────────────────────────────────────
    print("\n\033[1m2. Cán bộ tra cứu được của sinh viên\033[0m")
    kt("cán bộ xin mã sinh viên → cho qua",
       R._ma_duoc_phep_mem("205714023110061", CB, "t"), "205714023110061")
    kt("cán bộ không truyền mã → dùng mã của chính mình",
       R._ma_duoc_phep_mem("", CB, "t"), "1679")

    # ── 3. Ứng dụng bản cũ (không token) — bước chuyển tiếp ───────────────
    print("\n\033[1m3. Ứng dụng bản cũ khi CHƯA siết (REQUIRE_AUTH_NOTIFS=false)\033[0m")
    goc = settings.security.require_auth_notifs
    object.__setattr__(settings.security, "require_auth_notifs", False)
    kt("không token → vẫn phục vụ, không làm vỡ máy đang dùng bản cũ",
       R._ma_duoc_phep_mem("205714023110061", None, "t"), "205714023110061")

    truoc = dict(R._dem_khong_token)
    R._ma_duoc_phep_mem("1679", None, "dem_thu")
    kt("có đếm lại lượt gọi không token để biết khi nào siết được",
       R._dem_khong_token.get("dem_thu", 0) > truoc.get("dem_thu", 0), True)

    # ── 4. Sau khi siết ───────────────────────────────────────────────────
    print("\n\033[1m4. Sau khi siết (REQUIRE_AUTH_NOTIFS=true)\033[0m")
    object.__setattr__(settings.security, "require_auth_notifs", True)
    try:
        R._ma_duoc_phep_mem("205714023110061", None, "t")
        kt("không token → phải bị từ chối", "cho qua", "401")
    except HTTPException as e:
        kt("không token → 401", e.status_code, 401)

    kt("có token thì siết hay không cũng chỉ đọc được của mình",
       R._ma_duoc_phep_mem("999999999999999", SV, "t"), "205714023110061")
    object.__setattr__(settings.security, "require_auth_notifs", goc)

    # ── 5. Cả năm endpoint đều đã nhận danh tính ──────────────────────────
    print("\n\033[1m5. Cả năm endpoint đều nhận danh tính\033[0m")
    import inspect
    for ten_ham, ten_api in (
        ("api_get_notifs", "get-notifs"), ("count_unread", "count-unread"),
        ("mark_read", "mark-read"), ("api_hide_notif", "hide-notif"),
        ("mark_all_read", "mark-all-read"),
    ):
        ham = getattr(R, ten_ham, None)
        if ham is None:
            kt(f"/{ten_api} tồn tại", "không có hàm", ten_ham)
            continue
        co_tham_so = "me" in inspect.signature(ham).parameters
        goi_kiem = "_ma_duoc_phep_mem" in inspect.getsource(ham)
        kt(f"/{ten_api} nhận danh tính và có gọi kiểm quyền",
           (co_tham_so, goi_kiem), (True, True))

    print()
    if HONG:
        print(f"\033[31m❌ {len(HONG)} phép thử KHÔNG ĐẠT\033[0m")
        return 1
    print(f"\033[32m✅ TẤT CẢ ĐẠT\033[0m  ({DAT} phép thử)")
    return 0


if __name__ == "__main__":
    sys.exit(chay())
