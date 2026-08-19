"""Nơi duy nhất khởi tạo client OpenAI.

Vì sao cần tệp này — sự cố ngày 18/08/2026:

Năm tệp cùng viết `client = OpenAI(api_key=OPENAI_API_KEY)` ở CẤP MODULE, mỗi
tệp lấy khoá một kiểu (từ appsettings.json, từ config.settings, từ core.settings).
Thư viện openai NÉM LỖI ngay khi khoá rỗng. Nghĩa là thiếu một khoá của chức
năng phụ là **cả backend không khởi động được** — sinh viên không đăng nhập
được, không nhận thông báo, chỉ vì trợ lý AI thiếu cấu hình.

Lỗi này nằm im vì máy chủ đang chạy còn `appsettings.json` cũ. Chỉ lộ ra khi cài
mới từ kho mã — tức đúng lúc triển khai.

Cách làm ở đây: thiếu khoá thì trả `None` kèm một dòng cảnh báo. Backend vẫn
chạy, riêng chức năng AI báo lỗi của nó khi có người dùng tới.
"""

from __future__ import annotations

from typing import Any, Optional

_da_canh_bao: set[str] = set()


def tao_client(khoa: Optional[str] = None, *, ten_chuc_nang: str = "AI") -> Optional[Any]:
    """Tạo client gọi mô hình, trả `None` nếu chưa cấu hình khoá.

    Dùng chung cho CẢ OpenAI lẫn Gemini.

    Gemini có cổng tương thích OpenAI, nên vẫn dùng thư viện `openai` — chỉ đổi
    `base_url` và khoá. Nhờ vậy đổi nhà cung cấp không phải viết lại 21 chỗ gọi
    mô hình rải khắp mã nguồn.

    Chọn nhà cung cấp bằng `AI_PROVIDER` trong .env: `openai` hoặc `gemini`.

    Bên gọi PHẢI kiểm tra `None` trước khi dùng:

        client = tao_client(ten_chuc_nang="trợ lý sinh viên")
        if client is None:
            raise HTTPException(503, "Trợ lý AI chưa được cấu hình")
    """
    dia_chi = None
    ten_nha_cung_cap = "OpenAI"

    if khoa is None:
        try:
            from core.settings import settings
            khoa = settings.ai.khoa_dang_dung
            dia_chi = settings.ai.dia_chi_goc
            ten_nha_cung_cap = "Gemini" if settings.ai.dung_gemini else "OpenAI"
        except Exception:  # noqa: BLE001
            khoa = None

    khoa = (khoa or "").strip()
    if not khoa:
        if ten_chuc_nang not in _da_canh_bao:
            _da_canh_bao.add(ten_chuc_nang)
            bien = "GEMINI_API_KEY" if ten_nha_cung_cap == "Gemini" else "OPENAI_API_KEY"
            print(f"⚠️  [{ten_chuc_nang}] chưa có {bien} — chức năng này tắt. "
                  f"Phần còn lại của hệ thống vẫn chạy bình thường.")
        return None

    try:
        from openai import OpenAI
        if dia_chi:
            return OpenAI(api_key=khoa, base_url=dia_chi)
        return OpenAI(api_key=khoa)
    except Exception as exc:  # noqa: BLE001
        print(f"⚠️  [{ten_chuc_nang}] không khởi tạo được {ten_nha_cung_cap}: "
              f"{str(exc)[:120]}")
        return None
