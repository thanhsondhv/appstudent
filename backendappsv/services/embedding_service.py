"""Chuyển văn bản thành vector để tìm kiếm theo ngữ nghĩa.

⚠️ SỬA 19/08/2026 — hết tín dụng OpenAI làm vỡ cả trợ lý AI.

Nhật ký ngày 19/08/2026 ghi nhận:

    openai.RateLimitError: 429 — You have no credits remaining.
                                 code: credit_balance_exhausted

Đó không phải lỗi mã, nhưng cách hệ thống phản ứng thì có vấn đề: ngoại lệ
tràn thẳng lên trên, thành 500 gửi về ứng dụng, và người dùng chỉ thấy "Máy chủ
đang gặp sự cố" — không ai đoán được là hết tiền trong tài khoản OpenAI.

Nay phân biệt ba tình huống, mỗi tình huống một câu nói rõ việc cần làm:
  • hết tín dụng   → người quản trị phải nạp thêm
  • bị chặn nhịp   → hỏi lại sau một lát
  • chưa có khoá   → chưa cấu hình OPENAI_API_KEY

Bên gọi bắt LoiTroLyAI để trả lời người dùng cho tử tế, thay vì để 500 lọt ra.
"""

from core.openai_client import tao_client
from core.settings import settings  # cấu hình tập trung (Pha 0)


class LoiTroLyAI(Exception):
    """Trợ lý AI không dùng được, kèm câu giải thích cho người dùng.

    `can_nguoi_quan_tri` đúng khi chỉ người quản trị mới xử lý được (hết tiền,
    thiếu cấu hình) — người dùng cuối có thử lại bao nhiêu lần cũng vô ích.
    """

    def __init__(self, thong_diep: str, *, can_nguoi_quan_tri: bool = False):
        super().__init__(thong_diep)
        self.thong_diep = thong_diep
        self.can_nguoi_quan_tri = can_nguoi_quan_tri


class EmbeddingService:

    def __init__(self):
        # tao_client() tự chọn OpenAI hay Gemini theo AI_PROVIDER trong .env
        self.client = tao_client(ten_chuc_nang="tạo vector")

    def get_embedding(self, text: str):
        if self.client is None:
            raise LoiTroLyAI(
                "Trợ lý AI chưa được cấu hình (thiếu khoá API).",
                can_nguoi_quan_tri=True,
            )

        try:
            phan_hoi = self.client.embeddings.create(
                model=settings.ai.ten_mo_hinh_vector,
                input=text,
            )
            return phan_hoi.data[0].embedding

        except Exception as loi:  # noqa: BLE001 — phân loại rồi ném lại
            mo_ta = str(loi)

            # OpenAI dùng CHUNG mã 429 cho hai chuyện hoàn toàn khác nhau: hết
            # tiền và gọi quá nhanh. Chỉ nhìn mã số thì bảo người dùng "thử lại
            # sau" trong khi thật ra phải đi nạp tiền.
            if "insufficient_quota" in mo_ta or "credit_balance_exhausted" in mo_ta:
                print("🔴 [TrợLýAI] Tài khoản OpenAI đã hết tín dụng — "
                      "mọi chức năng AI ngừng hoạt động cho tới khi nạp thêm.")
                raise LoiTroLyAI(
                    "Trợ lý AI tạm ngừng do tài khoản dịch vụ đã hết hạn mức. "
                    "Vui lòng báo quản trị hệ thống.",
                    can_nguoi_quan_tri=True,
                ) from loi

            if "rate_limit" in mo_ta or "429" in mo_ta:
                raise LoiTroLyAI(
                    "Trợ lý AI đang bận. Vui lòng hỏi lại sau ít phút."
                ) from loi

            print(f"⚠️ [TrợLýAI] Không tạo được vector: {mo_ta[:160]}")
            raise LoiTroLyAI(
                "Trợ lý AI đang gặp sự cố. Vui lòng thử lại sau."
            ) from loi
