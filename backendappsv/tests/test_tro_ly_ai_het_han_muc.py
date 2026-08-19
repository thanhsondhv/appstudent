"""
Trợ lý AI hỏng thì phải nói ĐÚNG lý do, không được nói dối.

Ngày 19/08/2026, nhật ký máy chủ ghi:

    openai.RateLimitError: 429 — You have no credits remaining.
                                 code: credit_balance_exhausted

Đó không phải lỗi mã. Nhưng cách hệ thống phản ứng thì có vấn đề: bản cũ bắt
mọi ngoại lệ rồi trả cho người dùng câu "Hệ thống đang đối chiếu dữ liệu, bạn
vui lòng đợi nhé!" — người dùng ngồi đợi một câu trả lời KHÔNG BAO GIỜ tới,
còn quản trị viên thì không biết là hết tiền trong tài khoản.

Bài này khoá chặt cách phân loại lỗi. Không cần mạng, không cần khoá OpenAI.

Chạy:  python tests/test_tro_ly_ai_het_han_muc.py
"""

from __future__ import annotations

import os
import sys
import warnings
from pathlib import Path

warnings.filterwarnings("ignore")

GOC = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(GOC))

for k, v in {
    "APP_ENV": "test", "DB_SERVER": "x", "DB_USER": "x", "DB_PASSWORD": "x",
    "MS_CLIENT_ID": "x", "MS_CLIENT_SECRET": "x", "MS_TENANT_ID": "x",
    "SESSION_SECRET_KEY": "x" * 40, "JWT_SECRET_KEY": "x" * 40,
}.items():
    os.environ.setdefault(k, v)

DAT, HONG = 0, []


def kt(ten: str, thuc_te, mong_doi) -> None:
    global DAT
    if thuc_te == mong_doi:
        DAT += 1
        print(f"  ✅ {ten}")
    else:
        HONG.append(ten)
        print(f"  ❌ {ten}\n       nhận: {thuc_te!r}\n       cần : {mong_doi!r}")


def chay() -> int:
    try:
        from services.embedding_service import EmbeddingService, LoiTroLyAI
    except ImportError as exc:
        print(f"⏭️  Bỏ qua: thiếu thư viện ({exc.name})")
        return 0

    class _LoiGia(Exception):
        pass

    def _dich_vu_nem(mo_ta: str) -> EmbeddingService:
        """Dựng một EmbeddingService mà lời gọi OpenAI luôn ném lỗi cho trước."""
        dv = EmbeddingService.__new__(EmbeddingService)

        class _Embeddings:
            @staticmethod
            def create(**_):
                raise _LoiGia(mo_ta)

        class _Client:
            embeddings = _Embeddings()

        dv.client = _Client()
        return dv

    # ── 1. Hết tín dụng ──────────────────────────────────────────────────
    print("\n\033[1m1. Tài khoản hết tín dụng\033[0m")
    dv = _dich_vu_nem(
        "Error code: 429 - {'error': {'message': 'You have no credits remaining.', "
        "'type': 'insufficient_quota', 'code': 'credit_balance_exhausted'}}")
    try:
        dv.get_embedding("thử")
        kt("phải ném LoiTroLyAI", "không ném", "LoiTroLyAI")
    except LoiTroLyAI as e:
        kt("cần người quản trị xử lý, người dùng thử lại vô ích",
           e.can_nguoi_quan_tri, True)
        kt("thông điệp nhắc tới hạn mức", "hạn mức" in e.thong_diep.lower(), True)
        kt("KHÔNG bảo người dùng chờ đợi",
           any(t in e.thong_diep.lower() for t in ("vui lòng đợi", "đang đối chiếu")), False)

    # ── 2. Gọi quá nhanh ─────────────────────────────────────────────────
    print("\n\033[1m2. Bị chặn nhịp (cùng mã 429 nhưng khác chuyện)\033[0m")
    dv = _dich_vu_nem("Error code: 429 - rate_limit_exceeded")
    try:
        dv.get_embedding("thử")
        kt("phải ném LoiTroLyAI", "không ném", "LoiTroLyAI")
    except LoiTroLyAI as e:
        kt("người dùng thử lại được nên KHÔNG cần quản trị",
           e.can_nguoi_quan_tri, False)
        kt("có bảo thử lại sau", "sau" in e.thong_diep.lower(), True)

    # ── 3. Chưa cấu hình khoá ────────────────────────────────────────────
    print("\n\033[1m3. Chưa có OPENAI_API_KEY\033[0m")
    dv = EmbeddingService.__new__(EmbeddingService)
    dv.client = None
    try:
        dv.get_embedding("thử")
        kt("phải ném LoiTroLyAI", "không ném", "LoiTroLyAI")
    except LoiTroLyAI as e:
        kt("nói rõ là chưa cấu hình", "cấu hình" in e.thong_diep.lower(), True)
        kt("cần người quản trị", e.can_nguoi_quan_tri, True)

    # ── 4. Lỗi khác ──────────────────────────────────────────────────────
    print("\n\033[1m4. Lỗi không đoán được\033[0m")
    dv = _dich_vu_nem("Connection reset by peer")
    try:
        dv.get_embedding("thử")
        kt("phải ném LoiTroLyAI", "không ném", "LoiTroLyAI")
    except LoiTroLyAI as e:
        kt("vẫn là LoiTroLyAI chứ không để lỗi thô lọt ra", isinstance(e, LoiTroLyAI), True)
        kt("không đổ cho người dùng", e.can_nguoi_quan_tri, False)

    # ── 5. Câu trả lời của endpoint chat không được nói dối ──────────────
    print("\n\033[1m5. Câu trả lời trả về cho người dùng\033[0m")
    ma_nguon = (GOC / "routers" / "api_chatbot_v3.py").read_text(encoding="utf-8")
    kt("đã bỏ câu 'đang đối chiếu dữ liệu, vui lòng đợi'",
       "Hệ thống đang đối chiếu dữ liệu, bạn vui lòng đợi nhé!" in ma_nguon, False)
    kt("có nhận ra mã credit_balance_exhausted",
       "credit_balance_exhausted" in ma_nguon, True)
    kt("có nói các chức năng khác vẫn dùng được",
       "chức năng khác" in ma_nguon, True)

    print()
    if HONG:
        print(f"\033[31m❌ {len(HONG)} phép thử KHÔNG ĐẠT\033[0m")
        return 1
    print(f"\033[32m✅ TẤT CẢ ĐẠT\033[0m  ({DAT} phép thử)")
    return 0


if __name__ == "__main__":
    sys.exit(chay())
