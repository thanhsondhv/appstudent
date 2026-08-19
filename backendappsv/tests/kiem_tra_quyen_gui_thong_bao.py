"""
Mọi endpoint GỬI thông báo đều phải yêu cầu quyền cán bộ.

Phát hiện ngày 19/08/2026: NĂM endpoint gửi thông báo không có xác thực nào,
trong đó có `/api/admin/send-notification-all` — gửi cho TOÀN TRƯỜNG.

Kiểm chứng thực tế: gọi không kèm token trả về HTTP 200 và chạy trọn hàm.

Đây là lỗ hổng GHI, nặng hơn nhiều so với lỗ hổng ĐỌC đã vá hôm trước: kẻ xấu
chỉ cần biết địa chỉ là gửi được tin giả danh Nhà trường tới 15 nghìn sinh
viên — lừa đảo, tin sai về lịch thi hay học phí. Người nhận không có cách nào
phân biệt với thông báo thật.

Bài này cũng bắt một cái bẫy đã vấp phải khi vá: mã nguồn có nhiều bản CŨ bị
chú thích của cùng endpoint. Sửa nhầm vào bản chú thích thì sinh ra hai tuyến
đường cùng đường dẫn — FastAPI dùng cái ĐĂNG KÝ TRƯỚC, và nếu cái đó không có
bảo vệ thì bản vá vô tác dụng mà nhìn mã vẫn tưởng đã vá.

Chạy:  python tests/kiem_tra_quyen_gui_thong_bao.py
"""

from __future__ import annotations

import ast
import sys
import warnings
from collections import Counter
from pathlib import Path

warnings.filterwarnings("ignore")

GOC = Path(__file__).resolve().parent.parent
BO_QUA = {"venv", "_luu_tru", "__pycache__", "node_modules", ".git", "tests"}

# Tên phụ thuộc được coi là "đã kiểm quyền cán bộ"
BAO_VE = {"verify_staff_token", "require_staff", "require_admin"}

DAT, HONG = 0, []


def kt(ten: str, thuc_te, mong_doi) -> None:
    global DAT
    if thuc_te == mong_doi:
        DAT += 1
        print(f"  ✅ {ten}")
    else:
        HONG.append(ten)
        print(f"  ❌ {ten}\n       nhận: {thuc_te!r}\n       cần : {mong_doi!r}")


def _ten_phu_thuoc(nut: ast.AST) -> set[str]:
    """Mọi tên hàm xuất hiện trong Depends(...) — ở decorator lẫn tham số."""
    ten = set()
    for con in ast.walk(nut):
        if (isinstance(con, ast.Call) and isinstance(con.func, ast.Name)
                and con.func.id == "Depends" and con.args):
            a = con.args[0]
            if isinstance(a, ast.Name):
                ten.add(a.id)
            elif isinstance(a, ast.Attribute):
                ten.add(a.attr)
    return ten


def chay() -> int:
    khong_bao_ve, duong_dan = [], []

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

            for tt in nut.decorator_list:
                if not (isinstance(tt, ast.Call) and isinstance(tt.func, ast.Attribute)
                        and tt.func.attr == "post"
                        and isinstance(tt.func.value, ast.Name)
                        and tt.func.value.id in ("app", "router")):
                    continue
                if not tt.args or not isinstance(tt.args[0], ast.Constant):
                    continue

                dd = str(tt.args[0].value)
                if "send-notification" not in dd:
                    continue

                duong_dan.append(dd)
                # Bảo vệ có thể nằm ở decorator (dependencies=[...]) hoặc ở
                # tham số hàm (x = Depends(...))
                co = (_ten_phu_thuoc(tt) | _ten_phu_thuoc(ast.arguments(
                    posonlyargs=[], args=nut.args.args, vararg=None,
                    kwonlyargs=nut.args.kwonlyargs, kw_defaults=nut.args.kw_defaults,
                    kwarg=None, defaults=nut.args.defaults))) & BAO_VE

                if not co:
                    khong_bao_ve.append(
                        f"{tep.relative_to(GOC)}:{nut.lineno}  {dd}")

    print("\n\033[1m1. Mọi endpoint gửi thông báo phải kiểm quyền\033[0m")
    print(f"       tìm thấy {len(duong_dan)} endpoint gửi thông báo")
    if khong_bao_ve:
        print("       ❌ những cái sau KHÔNG kiểm quyền:")
        for c in khong_bao_ve:
            print(f"          {c}")
    kt("không endpoint nào để trống bảo vệ", khong_bao_ve, [])

    # ── 2. Không có đường dẫn trùng ───────────────────────────────────────
    print("\n\033[1m2. Không có tuyến đường trùng\033[0m")
    trung = [d for d, n in Counter(duong_dan).items() if n > 1]
    if trung:
        print("       ❌ đường dẫn khai nhiều lần:")
        for d in trung:
            print(f"          {d}")
        print("       FastAPI dùng cái ĐĂNG KÝ TRƯỚC. Nếu cái đó không có bảo")
        print("       vệ thì bản vá vô tác dụng mà nhìn mã vẫn tưởng đã vá.")
    kt("mỗi đường dẫn chỉ khai đúng một lần", trung, [])

    print()
    if HONG:
        print(f"\033[31m❌ {len(HONG)} phép thử KHÔNG ĐẠT\033[0m")
        return 1
    print(f"\033[32m✅ TẤT CẢ ĐẠT\033[0m  ({DAT} phép thử, "
          f"{len(duong_dan)} endpoint được kiểm)")
    return 0


if __name__ == "__main__":
    sys.exit(chay())
