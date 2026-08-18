"""Cấu hình dùng chung cho gói trợ lý AI.

Trước 18/08/2026 tệp này đọc thẳng `appsettings.json` từ THƯ MỤC LÀM VIỆC HIỆN
TẠI. Hai vấn đề:

  • Đợt dọn khoá bí mật (Pha 0) chuyển mọi khoá sang `.env` và chặn
    `appsettings.json` khỏi git. Máy chủ đang chạy còn tệp cũ nên không ai thấy
    gì; cài mới từ kho mã thì `open()` ném FileNotFoundError ngay lúc nạp gói,
    kéo theo cả backend không khởi động được.
  • Phụ thuộc thư mục làm việc: chạy `python vinhuni_chatbot_python/x.py` từ chỗ
    khác là không tìm thấy tệp, dù tệp vẫn nằm đúng chỗ.

Nay lấy từ cấu hình tập trung, và vẫn đọc `appsettings.json` làm phương án dự
phòng để máy chủ chưa kịp tạo `.env` không bị gãy khi cập nhật.
"""

import json
import os

_GOC = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _tu_appsettings() -> dict:
    """Đọc appsettings.json nếu còn — dò theo đường dẫn tuyệt đối, không theo cwd."""
    for duong_dan in (
        os.path.join(_GOC, "appsettings.json"),
        os.path.join(os.getcwd(), "appsettings.json"),
    ):
        if os.path.exists(duong_dan):
            try:
                with open(duong_dan, "r", encoding="utf-8") as f:
                    return json.load(f)
            except (OSError, json.JSONDecodeError):
                continue
    return {}


def _dung_config() -> dict:
    cu = _tu_appsettings()

    try:
        import sys
        if _GOC not in sys.path:
            sys.path.insert(0, _GOC)
        from core.settings import settings
    except Exception:  # noqa: BLE001 — thiếu cấu hình tập trung thì dùng tệp cũ
        return cu

    khoa = (settings.ai.openai_api_key or "").strip()
    if not khoa:
        # .env chưa có khoá thì giữ nguyên giá trị từ appsettings.json
        return cu

    openai_cu = cu.get("OpenAI", {}) if isinstance(cu.get("OpenAI"), dict) else {}
    cu["OpenAI"] = {
        **openai_cu,
        "ApiKey": khoa,
        "ChatModel": settings.ai.chat_model or openai_cu.get("ChatModel", "gpt-4o-mini"),
        "EmbeddingModel": (settings.ai.embedding_model
                           or openai_cu.get("EmbeddingModel", "text-embedding-3-small")),
    }
    return cu


CONFIG = _dung_config()
