"""
Máy chủ THỬ NGHIỆM chạy trên máy lập trình — KHÔNG dùng để triển khai.

Mục đích: kiểm tra luồng thông báo bản mới với ứng dụng thật, mà không phải đưa
mã lên server trường. Ứng dụng trên máy ảo trỏ về đây thay vì mobi.vinhuni.edu.vn.

Khác Main.py ở hai điểm, đều là để chạy được trên máy lập trình:
  • Chỉ nạp router thông báo. Main.py kéo theo cả tầng AI (sentence_transformers,
    openai — vài GB) không liên quan tới việc đang kiểm.
  • Trỏ cơ sở dữ liệu qua địa chỉ IP. Trên server thì SQL nằm cùng máy nên .env
    ghi tên thực thể `AI2025\\SQLEXPRESS02`; từ máy lập trình phải đi qua IP.

Chạy:
    DB_SERVER=172.26.26.253 python3 chay_thu_cuc_bo.py

Rồi trỏ ứng dụng về http://<IP-máy-Mac>:8000 (xem lib/core/api/may_chu.dart).
"""

from __future__ import annotations

import os
import socket
import sys
import types
from pathlib import Path

GOC = Path(__file__).resolve().parent
sys.path.insert(0, str(GOC))

# Mặc định trỏ CSDL qua IP — từ máy lập trình không gọi được tên thực thể SQL
os.environ.setdefault("DB_SERVER", "172.26.26.253")
os.environ.setdefault("APP_ENV", "development")


# Các thư viện nặng mà máy chủ thử KHÔNG cần.
#
# Main.py kéo theo cả tầng AI: nhúng vector, nhận dạng giọng nói, thị giác máy
# tính — cộng lại vài GB và cần GPU để có ý nghĩa. Luồng đang kiểm (đăng nhập,
# thông báo) không đụng tới chúng. Thay bằng bản giả: chỗ nào lỡ gọi thật thì
# báo lỗi rõ ràng, thay vì im lặng trả kết quả sai.
_THU_VIEN_GIA = (
    "sentence_transformers", "faster_whisper", "whisper", "torch",
    "cv2", "face_recognition", "insightface", "onnxruntime",
    "transformers", "easyocr", "paddleocr",
)


def _thay_thu_vien_nang() -> None:
    import importlib.util

    da_thay = []
    for ten in _THU_VIEN_GIA:
        if ten in sys.modules:
            continue
        try:
            if importlib.util.find_spec(ten) is not None:
                continue          # có thật thì dùng bản thật
        except (ImportError, ValueError):
            pass

        mod = types.ModuleType(ten)

        class _KhongCo:
            """Đứng thay một lớp của thư viện nặng chưa cài."""

            _ten = ten

            def __init__(self, *a, **k):
                pass

            def __getattr__(self, item):
                def _bao_loi(*a, **k):
                    raise RuntimeError(
                        f"'{self._ten}.{item}' không dùng được ở máy chủ thử cục bộ "
                        f"— thư viện chưa cài. Chức năng này chỉ chạy trên server."
                    )
                return _bao_loi

        # Trả _KhongCo cho MỌI tên được lấy ra từ module giả, nhờ vậy không phải
        # liệt kê từng lớp (SentenceTransformer, WhisperModel, …) của từng gói.
        mod.__getattr__ = lambda ten_thuoc_tinh, _c=_KhongCo: _c
        sys.modules[ten] = mod
        da_thay.append(ten)

    if da_thay:
        print(f"ℹ️  Dùng bản giả cho: {', '.join(da_thay)}")
        print("   (chỉ ảnh hưởng AI/giọng nói/thị giác — không ảnh hưởng thông báo, đăng nhập)")


_thay_thu_vien_nang()


def _gia_lap_models_chat() -> None:
    """Bản giả cho gói `models` — CHƯA CÓ TRONG KHO MÃ.

    Năm tệp import `models.chat_model` (ChatMessage, ChatGroup, User,
    ChatMember, MessageAction, GroupKnowledge) nhưng thư mục `models/` chưa bao
    giờ được commit — nó chỉ nằm trên máy chủ trường. Thiếu nó thì Main.py không
    nạp được, kéo theo cả /api/login.

    Bản giả này để máy chủ thử chạy được ngay. VIỆC CẦN LÀM THẬT: chép thư mục
    `models/` từ máy chủ về kho mã rồi commit — xem HUONG_DAN_TRIEN_KHAI.md.
    """
    import importlib.util
    try:
        if importlib.util.find_spec("models") is not None:
            return
    except (ImportError, ValueError):
        pass

    goi = types.ModuleType("models")
    goi.__path__ = []                       # khai là gói để import con được
    con = types.ModuleType("models.chat_model")

    class _MoHinh:
        """Đứng thay một lớp dữ liệu chưa có."""
        def __init__(self, **k):
            self.__dict__.update(k)

    con.__getattr__ = lambda _ten, _c=_MoHinh: _c
    goi.chat_model = con
    sys.modules["models"] = goi
    sys.modules["models.chat_model"] = con
    print("⚠️  Gói `models` dùng bản giả — CHƯA CÓ TRONG KHO MÃ, cần chép từ máy chủ về")
    print("    Trò chuyện nhóm sẽ không chạy đúng ở máy chủ thử này.")


_gia_lap_models_chat()

from fastapi import FastAPI                       # noqa: E402
from fastapi.middleware.cors import CORSMiddleware  # noqa: E402

from core.settings import settings                # noqa: E402

# Ưu tiên dùng THẲNG app thật của Main.py.
#
# ⚠️ SỬA 18/08/2026: bản trước tạo một FastAPI riêng rồi sao chép danh sách
# tuyến đường từ Main.app sang. Tuyến đường thì có, nhưng MIDDLEWARE thì không —
# và Main.py cài SessionMiddleware cho luồng đăng nhập Microsoft. Hệ quả:
# /login/microsoft ném "SessionMiddleware must be installed", trông y như một
# lỗi của sản phẩm trong khi đó là lỗi của chính bộ khung thử này.
_LOI_NAP: list[str] = []

try:
    import Main as _Main
    app = _Main.app
    _DUNG_MAIN = True
    print(f"  ✅ Dùng trọn app của Main.py — {len(app.routes)} tuyến đường, "
          f"giữ nguyên middleware")
except Exception as exc:  # noqa: BLE001
    _DUNG_MAIN = False
    _LOI_NAP.append(f"Main.py: {type(exc).__name__}: {str(exc)[:130]}")
    print(f"  ⚠️  Không nạp được Main.py — {type(exc).__name__}: {str(exc)[:130]}")
    print("      Lùi về chế độ tối giản: chỉ luồng thông báo, KHÔNG đăng nhập được.")
    app = FastAPI(title="VinhUni — máy chủ thử cục bộ", docs_url="/docs")

# Máy ảo iOS gọi qua IP máy Mac nên không cùng gốc — mở CORS cho môi trường thử.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], allow_credentials=True,
    allow_methods=["*"], allow_headers=["*"],
)


def _ip_lan() -> str:
    """Địa chỉ máy Mac trong mạng nội bộ — máy ảo/điện thoại phải gọi vào đây."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except Exception:  # noqa: BLE001
        return "127.0.0.1"
    finally:
        s.close()


if not _DUNG_MAIN:
    # Các router TỰ KHAI BÁO tiền tố /api của chúng (APIRouter(prefix="/api")),
    # giống hệt cách Main.py gắn. Gắn thêm prefix ở đây sẽ thành /api/api.
    for ten_mo_dun, ten_hien in (
        ("vinhuni_notifications.router", "Thông báo"),
        ("routers.notif_settings", "Cài đặt thông báo"),
    ):
        try:
            mod = __import__(ten_mo_dun, fromlist=["router"])
            app.include_router(mod.router)
            print(f"  ✅ Đã nạp {ten_hien}")
        except Exception as exc:  # noqa: BLE001
            _LOI_NAP.append(f"{ten_hien}: {type(exc).__name__}: {str(exc)[:100]}")
            print(f"  ⚠️  Bỏ qua {ten_hien} — {type(exc).__name__}: {str(exc)[:100]}")


@app.get("/kiem-tra-cuc-bo")
async def kiem_tra_cuc_bo():
    """Điểm kiểm tra riêng của máy chủ thử — không đụng /health của Main.py."""
    return {"status": "ok", "che_do": "thu-cuc-bo", "csdl": settings.db.safe_repr,
            "dung_main": _DUNG_MAIN}


if __name__ == "__main__":
    import uvicorn

    ip = _ip_lan()
    print("\n" + "═" * 58)
    print("  MÁY CHỦ THỬ CỤC BỘ — không phải bản triển khai")
    print("═" * 58)
    print(f"  Cơ sở dữ liệu : {settings.db.safe_repr}")
    print(f"  Máy ảo gọi vào: http://{ip}:8000")
    print(f"  Tài liệu API  : http://{ip}:8000/docs")
    if _LOI_NAP:
        print("\n  Router không nạp được:")
        for l in _LOI_NAP:
            print(f"    • {l}")
    print("═" * 58 + "\n")

    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="info")
