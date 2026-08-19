"""
Tìm chuỗi kết nối cơ sở dữ liệu còn viết cứng trong mã nguồn.

Sự cố ngày 19/08/2026: `database/database.py` đã lấy tài khoản và mật khẩu từ
cấu hình tập trung nhưng vẫn viết cứng tên máy chủ `AI2025\\SQLEXPRESS02`. Tên
đó chỉ phân giải được trên chính máy chủ trường; ở nơi khác pyodbc chờ hết 15
giây mặc định rồi mới báo lỗi.

Vì middleware chặn truy cập gọi hàm đó trên MỌI yêu cầu HTTP, 15 giây cộng vào
từng lượt truy cập của từng người dùng. Đo được: 15,02 giây cho mọi endpoint,
kể cả endpoint không đụng cơ sở dữ liệu.

Loại lỗi này không bao giờ lộ ra trên máy chủ đang chạy — chỉ lộ khi cài ở nơi
khác, tức là muộn nhất có thể.

Chạy:  python tests/kiem_tra_cau_hinh_ket_noi.py
"""

from __future__ import annotations

import ast
import re
import sys
from pathlib import Path

GOC = Path(__file__).resolve().parent.parent
BO_QUA = {"venv", "_luu_tru", "__pycache__", "node_modules", ".git", "tests"}

# Chỉ soi những CHUỖI KÝ TỰ thật sự là chuỗi kết nối ODBC. Dò bằng biểu thức
# chính quy trên cả tệp thì dính đủ thứ không liên quan: `DB_SERVER = settings...`
# (vì có chữ SERVER), tên máy chủ trong câu OPENQUERY (do SQL Server tự phân
# giải, sửa còn hỏng), và ví dụ trong phần chú thích tài liệu.
MAU_CHUOI_KET_NOI = re.compile(r"DRIVER\s*=|SERVER\s*=", re.IGNORECASE)

# Trong một chuỗi kết nối, lấy phần đứng sau SERVER=
MAU_MAY_CHU = re.compile(r"(?<![A-Za-z0-9_])SERVER\s*=\s*(?P<ten>[^;]*)", re.IGNORECASE)

# Giá trị hợp lệ: chỗ giữ chỗ để nội suy, hoặc địa chỉ cục bộ
CHO_PHEP = re.compile(r"^\s*$|^\{|^\$|^<|^127\.0\.0\.1|^localhost|^example",
                      re.IGNORECASE)


def _chuoi_trong_ma(cay: ast.AST) -> list[tuple[int, str]]:
    """Mọi hằng chuỗi trong tệp, kèm số dòng — kể cả các mảnh của f-string.

    Docstring cũng là hằng chuỗi, nhưng nội dung tài liệu KHÔNG phải cấu hình.
    Loại chúng ra để phần giải thích trong tài liệu không bị báo là lỗi.
    """
    dong_tai_lieu: set[int] = set()
    for nut in ast.walk(cay):
        if isinstance(nut, (ast.Module, ast.FunctionDef, ast.AsyncFunctionDef,
                            ast.ClassDef)):
            than = getattr(nut, "body", None)
            if (than and isinstance(than[0], ast.Expr)
                    and isinstance(than[0].value, ast.Constant)
                    and isinstance(than[0].value.value, str)):
                tai_lieu = than[0].value
                dau = tai_lieu.lineno
                cuoi = getattr(tai_lieu, "end_lineno", dau)
                dong_tai_lieu.update(range(dau, cuoi + 1))

    ket_qua: list[tuple[int, str]] = []
    for nut in ast.walk(cay):
        if isinstance(nut, ast.Constant) and isinstance(nut.value, str):
            if nut.lineno in dong_tai_lieu:
                continue
            ket_qua.append((nut.lineno, nut.value))
    return ket_qua


def _cac_tep() -> list[Path]:
    return [p for p in GOC.rglob("*.py")
            if not (BO_QUA & set(p.relative_to(GOC).parts))]


def chay() -> int:
    loi: list[tuple[str, int, str]] = []
    thieu_han_cho: list[str] = []

    for tep in _cac_tep():
        try:
            noi_dung = tep.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        if "pyodbc.connect" not in noi_dung:
            continue

        ten_tep = str(tep.relative_to(GOC))
        try:
            cay = ast.parse(noi_dung, filename=str(tep))
        except SyntaxError:
            continue

        for dong, chuoi in _chuoi_trong_ma(cay):
            if not MAU_CHUOI_KET_NOI.search(chuoi):
                continue
            if "OPENQUERY" in chuoi.upper():
                continue
            m = MAU_MAY_CHU.search(chuoi)
            if not m:
                continue
            ten = m.group("ten").strip()
            if CHO_PHEP.search(ten):
                continue
            loi.append((ten_tep, dong, ten))

        for nut in ast.walk(cay):
            if not (isinstance(nut, ast.Call)
                    and isinstance(nut.func, ast.Attribute)
                    and nut.func.attr == "connect"):
                continue
            if not any(k.arg == "timeout" for k in nut.keywords):
                thieu_han_cho.append(f"{ten_tep}:{nut.lineno}")

    if loi:
        print("❌ Tên máy chủ viết cứng trong chuỗi kết nối:\n")
        for tep, dong, ten in loi:
            print(f"  {tep}:{dong}")
            print(f"      SERVER={ten}   ← phải lấy từ core.settings")
        print("\nTên máy chủ viết cứng chỉ đúng trên đúng một máy. Ở nơi khác,")
        print("pyodbc chờ hết hạn mặc định (15 giây) rồi mới báo lỗi — và nếu hàm")
        print("đó nằm trên đường đi của mọi yêu cầu thì cả hệ thống chậm theo.\n")
        return 1

    print("✅ Không có tên máy chủ nào viết cứng trong chuỗi kết nối")

    if thieu_han_cho:
        print(f"\n⚠️  {len(thieu_han_cho)} lời gọi pyodbc.connect() không đặt hạn chờ")
        print("   (mặc định 15 giây — cân nhắc rút ngắn nếu nằm trên đường đi của yêu cầu):")
        for c in thieu_han_cho[:8]:
            print(f"     {c}")
        if len(thieu_han_cho) > 8:
            print(f"     … và {len(thieu_han_cho) - 8} chỗ nữa")

    return 0


if __name__ == "__main__":
    sys.exit(chay())
