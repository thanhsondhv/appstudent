"""
Bắt các tên biến được dùng ở cấp module nhưng chưa hề được định nghĩa.

VÌ SAO CẦN: `python -m py_compile` chỉ kiểm tra CÚ PHÁP. Một dòng như

    REMOTE_CONN_STR = fsettings.db.local_conn_str

hoàn toàn hợp lệ về cú pháp — Python hiểu `fsettings` là một biến nào đó — nên
py_compile báo OK. Nhưng chạy thật thì `NameError` ngay dòng đầu tiên, và vì
đây là mã ở cấp module nên **cả tiến trình không khởi động được**.

Lỗi này từng xuất hiện ở 10 tệp cùng lúc ngày 18/08/2026 khi gỡ khoá bí mật
bằng biểu thức thay thế tự động: mẫu thay `f"DRIVER=...{...}"` thành
`settings.db.local_conn_str` nhưng để sót chữ `f` bên ngoài dấu nháy.

Chạy:  python tests/kiem_tra_ten_khong_xac_dinh.py
Trả về mã thoát khác 0 nếu phát hiện lỗi — dùng được trong CI.
"""

from __future__ import annotations

import ast
import builtins
import sys
from pathlib import Path

GOC = Path(__file__).resolve().parent.parent

BO_QUA_THU_MUC = {
    "__pycache__", "venv", ".venv", "node_modules", "bk", "tests",
    "vinhuni_chatbot_python",  # dự án con, có vòng đời riêng
}

TEN_CO_SAN = set(dir(builtins)) | {
    "__file__", "__name__", "__doc__", "__package__", "__spec__",
    "__loader__", "__builtins__", "__path__",
}


class ThuThapTen(ast.NodeVisitor):
    """Gom tên được ĐỊNH NGHĨA và tên được DÙNG ở cấp module.

    Chỉ xét cấp module — bên trong hàm và lớp thì bỏ qua, vì tên ở đó có thể
    đến từ tham số, biến cục bộ, hoặc được gán sau. Cấp module là nơi lỗi gây
    hậu quả nặng nhất: tiến trình chết ngay lúc nạp.
    """

    def __init__(self) -> None:
        self.dinh_nghia: set[str] = set()
        self.su_dung: list[tuple[str, int]] = []

    # -- Tên được định nghĩa --------------------------------------------------

    def visit_Import(self, node: ast.Import) -> None:
        for a in node.names:
            self.dinh_nghia.add((a.asname or a.name).split(".")[0])

    def visit_ImportFrom(self, node: ast.ImportFrom) -> None:
        for a in node.names:
            if a.name == "*":
                # `from x import *` — không biết được gì vào, bỏ qua cả tệp
                raise _CoImportSao()
            self.dinh_nghia.add(a.asname or a.name)

    def _tham_so_cap_module(self, node) -> None:
        """Xét phần chữ ký hàm được CHẠY ngay lúc nạp module.

        Thân hàm chỉ chạy khi có người gọi, nên tên chưa định nghĩa ở đó không
        làm chết tiến trình lúc khởi động — cố ý bỏ qua. Nhưng giá trị mặc định
        và chú thích kiểu thì được tính NGAY tại lúc `def` chạy, tức là cấp
        module.

        Bổ sung 18/08/2026: bản đầu bỏ qua cả chữ ký, nên để lọt
        `me: Identity = Depends(get_current_user)` trong routers/api_chatbot_v2.py
        — tệp thiếu import Depends. Cả backend không khởi động nổi, mà py_compile
        vẫn báo hợp lệ. Đúng loại lỗi mà bài kiểm tra này sinh ra để chặn.
        """
        args = node.args
        for gia_tri in list(args.defaults) + [k for k in args.kw_defaults if k]:
            self.generic_visit(gia_tri)

        moi_tham_so = (
            list(args.args) + list(args.posonlyargs) + list(args.kwonlyargs)
            + [a for a in (args.vararg, args.kwarg) if a]
        )
        for ts in moi_tham_so:
            if ts.annotation is not None:
                self.generic_visit(ts.annotation)

        if node.returns is not None:
            self.generic_visit(node.returns)

        for trang_tri in node.decorator_list:
            self.generic_visit(trang_tri)

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:
        self._tham_so_cap_module(node)
        self.dinh_nghia.add(node.name)
        # Không đi vào THÂN hàm — phần đó chỉ chạy khi được gọi

    def visit_AsyncFunctionDef(self, node: ast.AsyncFunctionDef) -> None:
        self._tham_so_cap_module(node)
        self.dinh_nghia.add(node.name)

    def visit_ClassDef(self, node: ast.ClassDef) -> None:
        self.dinh_nghia.add(node.name)

    def visit_Assign(self, node: ast.Assign) -> None:
        for t in node.targets:
            self._ghi_nhan_dich(t)
        self.visit(node.value)

    def visit_AnnAssign(self, node: ast.AnnAssign) -> None:
        self._ghi_nhan_dich(node.target)
        if node.value:
            self.visit(node.value)

    def visit_For(self, node: ast.For) -> None:
        self._ghi_nhan_dich(node.target)
        self.generic_visit(node)

    def visit_With(self, node: ast.With) -> None:
        for item in node.items:
            if item.optional_vars:
                self._ghi_nhan_dich(item.optional_vars)
        self.generic_visit(node)

    def visit_ExceptHandler(self, node: ast.ExceptHandler) -> None:
        if node.name:
            self.dinh_nghia.add(node.name)
        self.generic_visit(node)

    def _ghi_nhan_dich(self, node: ast.AST) -> None:
        if isinstance(node, ast.Name):
            self.dinh_nghia.add(node.id)
        elif isinstance(node, (ast.Tuple, ast.List)):
            for e in node.elts:
                self._ghi_nhan_dich(e)
        elif isinstance(node, ast.Starred):
            self._ghi_nhan_dich(node.value)

    # -- Tên được sử dụng -----------------------------------------------------

    def visit_Name(self, node: ast.Name) -> None:
        if isinstance(node.ctx, ast.Load):
            self.su_dung.append((node.id, node.lineno))


class _CoImportSao(Exception):
    """Tệp dùng `from x import *` — không phân tích tĩnh được."""


def kiem_tra(duong_dan: Path) -> list[tuple[int, str]]:
    try:
        cay = ast.parse(duong_dan.read_text(encoding="utf-8", errors="ignore"))
    except SyntaxError as exc:
        return [(exc.lineno or 0, f"lỗi cú pháp: {exc.msg}")]

    thu = ThuThapTen()
    try:
        for node in cay.body:
            thu.visit(node)
    except _CoImportSao:
        return []

    loi = []
    for ten, dong in thu.su_dung:
        if ten not in thu.dinh_nghia and ten not in TEN_CO_SAN:
            loi.append((dong, ten))
    return loi


def main() -> int:
    tep_loi = 0
    tong_loi = 0

    for p in sorted(GOC.rglob("*.py")):
        if any(part in BO_QUA_THU_MUC for part in p.parts):
            continue
        loi = kiem_tra(p)
        if loi:
            tep_loi += 1
            tong_loi += len(loi)
            print(f"\n❌ {p.relative_to(GOC)}")
            for dong, ten in loi[:6]:
                print(f"     dòng {dong}: tên '{ten}' chưa được định nghĩa")
            if len(loi) > 6:
                print(f"     … và {len(loi) - 6} chỗ nữa")

    if tep_loi == 0:
        print("✅ Không có tên nào chưa định nghĩa ở cấp module")
        return 0

    print(f"\n❌ {tong_loi} chỗ trong {tep_loi} tệp — mỗi chỗ làm tiến trình chết khi khởi động")
    return 1


if __name__ == "__main__":
    sys.exit(main())
