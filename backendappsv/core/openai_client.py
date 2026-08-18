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
    """Tạo client OpenAI, trả `None` nếu không có khoá.

    Bên gọi PHẢI kiểm tra `None` trước khi dùng:

        client = tao_client(ten_chuc_nang="trợ lý sinh viên")
        ...
        if client is None:
            raise HTTPException(503, "Trợ lý AI chưa được cấu hình")
    """
    if khoa is None:
        try:
            from core.settings import settings
            khoa = settings.ai.openai_api_key
        except Exception:  # noqa: BLE001
            khoa = None

    khoa = (khoa or "").strip()
    if not khoa:
        if ten_chuc_nang not in _da_canh_bao:
            _da_canh_bao.add(ten_chuc_nang)
            print(f"⚠️  [{ten_chuc_nang}] chưa có OPENAI_API_KEY — chức năng này tắt. "
                  f"Phần còn lại của hệ thống vẫn chạy bình thường.")
        return None

    try:
        from openai import OpenAI
        return OpenAI(api_key=khoa)
    except Exception as exc:  # noqa: BLE001
        print(f"⚠️  [{ten_chuc_nang}] không khởi tạo được OpenAI: {str(exc)[:120]}")
        return None
