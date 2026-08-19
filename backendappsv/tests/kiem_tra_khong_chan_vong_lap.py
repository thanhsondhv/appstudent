"""
Tìm endpoint chạy truy vấn ĐỒNG BỘ ngay trên vòng lặp sự kiện.

Sự cố ngày 19/08/2026: máy chủ ngừng phục vụ HOÀN TOÀN — mọi yêu cầu hết giờ —
trong khi mạng tới cơ sở dữ liệu vẫn thông và tiến trình vẫn sống.

Nguyên nhân: cả 90 endpoint đều khai `async def` nhưng gọi pyodbc, một thư viện
ĐỒNG BỘ. Trong `async def`, lời gọi đó chạy thẳng trên vòng lặp sự kiện. Một
truy vấn chậm chặn TOÀN BỘ máy chủ, không riêng người gây ra.

Với 15 nghìn sinh viên, đó là điểm gãy chắc chắn xảy ra: chỉ cần một người mở
màn hình có truy vấn nặng, cả trường mất kết nối trong vài giây.

Cách đúng: viết `def` thường. FastAPI tự chạy hàm đồng bộ trong luồng riêng,
nên truy vấn chậm chỉ ảnh hưởng đúng yêu cầu đó. Chỉ giữ `async def` khi thân
hàm thật sự có `await` — và khi ấy phần truy vấn phải được đẩy sang luồng riêng.

Chạy:  python tests/kiem_tra_khong_chan_vong_lap.py
"""

from __future__ import annotations

import ast
import sys
from pathlib import Path

GOC = Path(__file__).resolve().parent.parent
BO_QUA = {"venv", "_luu_tru", "__pycache__", "node_modules", ".git", "tests"}

# Endpoint buộc phải `async` (gọi HTTP ngoài, đọc tệp tải lên) mà phần truy vấn
# CHƯA đẩy sang luồng riêng.
#
# Danh sách này chỉ để biết còn nợ gì — bài kiểm tra KHÔNG tin vào nó. Nó xét
# mã nguồn: endpoint async có gọi run_in_threadpool thì coi là đã xử lý.
#
# Bản đầu của bài này dùng danh sách cứng, nên sau khi sửa xong bốn endpoint mà
# nó vẫn báo y như cũ — một phép thử không phản ánh thực tế thì vô dụng.
CON_NO = {
    "auth_callback": "đăng nhập Office 365 — hai khối truy vấn xen kẽ",
    "login_face_pro": "đăng nhập bằng khuôn mặt — hai khối truy vấn xen kẽ",
}


def _la_endpoint(nut: ast.AST) -> bool:
    return any(
        isinstance(d, ast.Call) and isinstance(d.func, ast.Attribute)
        and d.func.attr in ("get", "post", "put", "delete", "patch")
        and isinstance(d.func.value, ast.Name) and d.func.value.id in ("app", "router")
        for d in getattr(nut, "decorator_list", [])
    )


def _co_truy_van(nut: ast.AST) -> bool:
    return any(
        isinstance(c, ast.Call) and (
            (isinstance(c.func, ast.Attribute) and c.func.attr == "connect")
            or (isinstance(c.func, ast.Name) and c.func.id == "get_db_conn")
        )
        for c in ast.walk(nut)
    )


def _da_day_sang_luong_rieng(nut: ast.AST) -> bool:
    """Hàm async này có gọi run_in_threadpool không."""
    return any(
        isinstance(c, ast.Call) and isinstance(c.func, ast.Name)
        and c.func.id == "run_in_threadpool"
        for c in ast.walk(nut)
    )


def chay() -> int:
    vi_pham, con_no, dat, da_xu_ly = [], [], 0, []

    for tep in GOC.rglob("*.py"):
        if BO_QUA & set(tep.relative_to(GOC).parts):
            continue
        try:
            cay = ast.parse(tep.read_text(encoding="utf-8"), filename=str(tep))
        except (SyntaxError, OSError, UnicodeDecodeError):
            continue

        for nut in ast.walk(cay):
            if not isinstance(nut, (ast.FunctionDef, ast.AsyncFunctionDef)):
                continue
            if not _la_endpoint(nut) or not _co_truy_van(nut):
                continue

            if isinstance(nut, ast.FunctionDef):
                dat += 1
                continue

            cho = f"{tep.relative_to(GOC)}:{nut.lineno}  {nut.name}"

            if _da_day_sang_luong_rieng(nut):
                da_xu_ly.append(cho)
            elif nut.name in CON_NO:
                con_no.append(f"{cho}  — {CON_NO[nut.name]}")
            else:
                vi_pham.append(cho)

    print(f"  ✅ {dat} endpoint viết `def` (FastAPI tự đẩy sang luồng riêng)")
    print(f"  ✅ {len(da_xu_ly)} endpoint async đã đẩy truy vấn sang luồng riêng:")
    for c in da_xu_ly:
        print(f"       {c}")

    if con_no:
        print(f"\n  ⚠️  {len(con_no)} endpoint còn nợ — buộc phải async, chưa xử lý:")
        for c in con_no:
            print(f"       {c}")

    if not vi_pham:
        print("\n✅ Không có endpoint nào chặn vòng lặp sự kiện ngoài danh sách đã biết")
        return 0

    print(f"\n❌ {len(vi_pham)} endpoint `async def` chạy truy vấn ĐỒNG BỘ "
          f"trên vòng lặp sự kiện:\n")
    for c in vi_pham:
        print(f"     {c}")
    print("\n  Một truy vấn chậm ở những chỗ này chặn TOÀN BỘ máy chủ.")
    print("  Sửa: bỏ chữ `async` nếu thân hàm không có `await`; nếu có thì tách")
    print("  phần truy vấn thành hàm lồng rồi gọi qua run_in_threadpool.")
    return 1


if __name__ == "__main__":
    sys.exit(chay())
