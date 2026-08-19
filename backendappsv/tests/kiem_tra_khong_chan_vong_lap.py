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

# Những endpoint có await thật sự (gọi HTTP ngoài, đọc tệp tải lên). Chúng buộc
# phải là async; phần truy vấn bên trong nên đẩy sang luồng riêng — việc đó chưa
# làm nên tạm chấp nhận, nhưng ghi tên ra đây để không quên.
CHUA_XU_LY = {
    "verify_student", "search_face_1n", "login_face_gateway", "auth_callback",
    "api_login", "login_face_pro", "update_face_vector",
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


def chay() -> int:
    vi_pham, tam_chap_nhan, dat = [], [], 0

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
            if nut.name in CHUA_XU_LY:
                tam_chap_nhan.append(cho)
            else:
                vi_pham.append(cho)

    print(f"  ✅ {dat} endpoint viết đúng kiểu `def` (FastAPI tự đẩy sang luồng riêng)")

    if tam_chap_nhan:
        print(f"\n  ⚠️  {len(tam_chap_nhan)} endpoint buộc phải async (gọi HTTP ngoài, "
              f"đọc tệp tải lên) — phần truy vấn CHƯA đẩy sang luồng riêng:")
        for c in tam_chap_nhan:
            print(f"       {c}")

    if not vi_pham:
        print("\n✅ Không có endpoint nào chặn vòng lặp sự kiện ngoài danh sách đã biết")
        return 0

    print(f"\n❌ {len(vi_pham)} endpoint `async def` chạy truy vấn ĐỒNG BỘ "
          f"trên vòng lặp sự kiện:\n")
    for c in vi_pham:
        print(f"     {c}")
    print("\n  Một truy vấn chậm ở những chỗ này chặn TOÀN BỘ máy chủ.")
    print("  Sửa: bỏ chữ `async` nếu thân hàm không có `await`; nếu có thì đẩy")
    print("  phần truy vấn sang luồng riêng (starlette.concurrency.run_in_threadpool).")
    return 1


if __name__ == "__main__":
    sys.exit(chay())
