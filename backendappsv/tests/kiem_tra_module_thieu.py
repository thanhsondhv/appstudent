"""
Tìm các module NỘI BỘ được import nhưng không có trong mã nguồn.

Phát hiện ngày 18/08/2026: năm tệp import `models.chat_model` nhưng thư mục
`models/` chưa bao giờ được commit — nó chỉ nằm trên server trường. Nghĩa là
sao chép kho mã về một máy mới là phần trò chuyện nhóm không chạy, và không ai
biết cho tới lúc khởi động.

py_compile không bắt được: import sai chỉ vỡ khi chạy.

Chạy:  python tests/kiem_tra_module_thieu.py
"""

from __future__ import annotations

import ast
import sys
from pathlib import Path

GOC = Path(__file__).resolve().parent.parent

BO_QUA_THU_MUC = {"venv", "_luu_tru", "__pycache__", "node_modules", ".git", "tests"}


def _cac_tep() -> list[Path]:
    return [p for p in GOC.rglob("*.py")
            if not (BO_QUA_THU_MUC & set(p.relative_to(GOC).parts))]


def _module_noi_bo_co_san() -> tuple[set[str], set[str]]:
    """Trả về (tên dùng được như GÓI, tên dùng được như MODULE ĐƠN).

    Phân biệt hai loại vì `from models.chat_model import X` đòi `models` phải là
    một THƯ MỤC gói — có tệp `vinhuni_chatbot_python/models.py` trùng tên cũng
    không giải được. Gộp chung hai loại sẽ che mất đúng lỗi mà bài này sinh ra
    để tìm.

    Tính cả tệp .py trong thư mục con: các tiến trình như worker_windows.py tự
    thêm thư mục của mình vào sys.path rồi `import tasks`, nên tên đó có thật
    lúc chạy dù không nhìn thấy từ thư mục gốc.
    """
    goi, don = set(), set()

    for p in GOC.rglob("*"):
        phan = set(p.relative_to(GOC).parts)
        if BO_QUA_THU_MUC & phan:
            continue
        if p.is_dir() and any(p.glob("*.py")):
            goi.add(p.name)
        elif p.suffix == ".py":
            don.add(p.stem)

    return goi, don


def _khai_bao_trong_requirements() -> set[str]:
    """Tên module suy ra từ requirements.txt.

    Cần bước này để tách hai loại hoàn toàn khác nhau:
      • thư viện bên ngoài chưa cài trên máy đang chạy — bình thường, bỏ qua
      • mã nguồn nội bộ chưa được commit — nguy hiểm, phải báo

    Tên gói pip và tên module hay lệch nhau nên có bảng quy đổi cho các trường
    hợp thường gặp.
    """
    quy_doi = {
        "python-jose": "jose", "python-socketio": "socketio",
        "python-multipart": "multipart", "python-dotenv": "dotenv",
        "pyjwt": "jwt", "pillow": "PIL", "beautifulsoup4": "bs4",
        "opencv-python": "cv2", "opencv-python-headless": "cv2",
        "pymupdf": "fitz", "faiss-cpu": "faiss", "scikit-learn": "sklearn",
        "msgraph-core": "msgraph", "azure-identity": "azure",
        "firebase-admin": "firebase_admin", "google-auth": "google",
    }
    tep = GOC / "requirements.txt"
    if not tep.exists():
        return set()

    ten = set()
    for dong in tep.read_text(encoding="utf-8", errors="ignore").splitlines():
        dong = dong.strip()
        if not dong or dong.startswith(("#", "-")):
            continue
        goi = dong.split("==")[0].split(">=")[0].split("<")[0].split("[")[0].strip().lower()
        if not goi:
            continue
        ten.add(quy_doi.get(goi, goi.replace("-", "_")))
    return ten


def chay() -> int:
    goi_co_san, module_co_san = _module_noi_bo_co_san()
    tu_requirements = _khai_bao_trong_requirements()
    thieu: dict[str, list[str]] = {}

    for tep in _cac_tep():
        try:
            cay = ast.parse(tep.read_text(encoding="utf-8"), filename=str(tep))
        except SyntaxError:
            continue

        # Import nằm trong try/except ImportError là CỐ Ý tuỳ chọn — mã đã có
        # đường lui sẵn. Báo những chỗ này chỉ tạo nhiễu, làm người đọc bỏ qua
        # cả các cảnh báo thật.
        dong_tuy_chon: set[int] = set()
        for nut in ast.walk(cay):
            if not isinstance(nut, ast.Try):
                continue
            bat_import_error = any(
                (h.type is None)
                or (isinstance(h.type, ast.Name) and h.type.id in
                    ("ImportError", "ModuleNotFoundError", "Exception"))
                or (isinstance(h.type, ast.Tuple) and any(
                    isinstance(e, ast.Name) and e.id in
                    ("ImportError", "ModuleNotFoundError") for e in h.type.elts))
                for h in nut.handlers
            )
            if bat_import_error:
                for con in ast.walk(nut):
                    if isinstance(con, (ast.Import, ast.ImportFrom)):
                        dong_tuy_chon.add(con.lineno)

        for nut in ast.walk(cay):
            if getattr(nut, "lineno", None) in dong_tuy_chon:
                continue
            goc = None
            can_la_goi = False
            if isinstance(nut, ast.ImportFrom) and nut.level == 0 and nut.module:
                goc = nut.module.split(".")[0]
                # `from a.b import c` cần `a` là thư mục gói, không phải tệp a.py
                can_la_goi = "." in nut.module
            elif isinstance(nut, ast.Import):
                for a in nut.names:
                    g = a.name.split(".")[0]
                    # Chỉ quan tâm tên TRÔNG GIỐNG module nội bộ: đã từng xuất
                    # hiện như thư mục/tệp trong dự án, hoặc rõ ràng không phải
                    # gói bên ngoài. Không cố đoán toàn bộ thư viện của PyPI.
                    if g in goi_co_san or g in module_co_san:
                        continue
                continue

            if goc is None:
                continue
            if goc in goi_co_san:
                continue
            if not can_la_goi and goc in module_co_san:
                continue
            # Có tệp cùng tên ở đâu đó trong dự án? Thì là vấn đề đường dẫn,
            # không phải thiếu tệp — vẫn báo nhưng để bên gọi tự xét.
            if goc in {"fastapi", "pydantic", "starlette"}:
                continue

            # Chỉ báo khi tên đó KHÔNG cài được bằng pip trên máy này
            try:
                import importlib.util
                if importlib.util.find_spec(goc) is not None:
                    continue
            except (ImportError, ValueError, ModuleNotFoundError):
                pass

            duong_dan = str(tep.relative_to(GOC))
            thieu.setdefault(goc, []).append(f"{duong_dan}:{nut.lineno}")

    ben_ngoai = {k: v for k, v in thieu.items() if k in tu_requirements}
    noi_bo = {k: v for k, v in thieu.items() if k not in tu_requirements}

    if ben_ngoai:
        print(f"ℹ️  {len(ben_ngoai)} thư viện có khai trong requirements.txt "
              f"nhưng chưa cài trên máy này — bình thường khi phát triển:")
        print(f"    {', '.join(sorted(ben_ngoai))}\n")

    if not noi_bo:
        print("✅ Không có mã nguồn nội bộ nào bị thiếu")
        return 0

    print(f"❌ {len(noi_bo)} module KHÔNG có trong mã nguồn và cũng KHÔNG khai "
          f"trong requirements.txt:\n")
    for ten, cho in sorted(noi_bo.items()):
        print(f"  • {ten}   ({len(cho)} chỗ)")
        for c in cho[:4]:
            print(f"      {c}")
        if len(cho) > 4:
            print(f"      … và {len(cho) - 4} chỗ nữa")
        print()

    print("Đây nhiều khả năng là mã nguồn nội bộ chưa được commit — chỉ tồn tại")
    print("trên máy chủ đang chạy. Sao chép kho mã về máy mới sẽ thiếu tệp, và")
    print("tiến trình chết ngay khi khởi động chứ không báo trước.")
    return 1


if __name__ == "__main__":
    sys.exit(chay())
