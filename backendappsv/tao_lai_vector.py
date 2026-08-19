"""
Tạo lại toàn bộ vector văn bản sau khi đổi mô hình nhúng.

VÌ SAO BẮT BUỘC

Vector của hai mô hình khác nhau nằm trong hai KHÔNG GIAN khác nhau. Đem vector
do Gemini tạo đi so với vector cũ do OpenAI tạo thì kết quả là ngẫu nhiên —
không báo lỗi, chỉ trả về tài liệu không liên quan. Đó là kiểu hỏng tệ nhất:
im lặng và trông vẫn như đang chạy.

Ngoài ra số chiều cũng khác (OpenAI text-embedding-3-small: 1536, Gemini
text-embedding-004: 768), nên phép tính tương đồng sẽ vỡ hoặc cho số vô nghĩa.

Vì vậy: ĐỔI MÔ HÌNH XONG PHẢI CHẠY TỆP NÀY.

Vector khuôn mặt (tbl_users.Vector_bin, tbl_NguoiHoc_HoSo.*) do thư viện nhận
diện tạo, KHÔNG liên quan tới đây và không bị đụng tới.

Chạy:
    python tao_lai_vector.py            # xem sẽ làm gì, không ghi
    python tao_lai_vector.py --thuc-hien
"""

from __future__ import annotations

import json
import sys
import time
import warnings
from pathlib import Path

warnings.filterwarnings("ignore")

GOC = Path(__file__).resolve().parent
sys.path.insert(0, str(GOC))

# (bảng, cột khoá chính, cột văn bản nguồn, cột vector)
BANG_CAN_TAO_LAI = [
    ("tbl_AI_SQL_Knowledge", "Id", "QuestionText", "QuestionVector"),
    ("DocumentChunks", "Id", "ChunkText", "VectorJson"),
]


def chay() -> int:
    thuc_hien = "--thuc-hien" in sys.argv

    import pyodbc
    from core.settings import settings
    from services.embedding_service import EmbeddingService, LoiTroLyAI

    print(f"🧠 Nhà cung cấp : {settings.ai.nha_cung_cap}")
    print(f"   Mô hình vector: {settings.ai.ten_mo_hinh_vector}")
    print(f"   Chế độ        : {'GHI THẬT' if thuc_hien else 'chỉ xem trước'}\n")

    dich_vu = EmbeddingService()
    if dich_vu.client is None:
        print("❌ Chưa cấu hình khoá API — không tạo được vector.")
        return 1

    # Thử một lần trước khi động vào dữ liệu, để hỏng thì hỏng sớm
    try:
        mau = dich_vu.get_embedding("kiểm tra")
        print(f"   Số chiều      : {len(mau)}\n")
    except LoiTroLyAI as e:
        print(f"❌ {e.thong_diep}")
        return 1

    tong = 0
    with pyodbc.connect(settings.db.local_conn_str, timeout=20, autocommit=True) as conn:
        for bang, cot_khoa, cot_van_ban, cot_vector in BANG_CAN_TAO_LAI:
            cur = conn.cursor()
            try:
                dong = cur.execute(
                    f"SELECT [{cot_khoa}], [{cot_van_ban}] FROM [{bang}] "
                    f"WHERE [{cot_van_ban}] IS NOT NULL AND LEN([{cot_van_ban}]) > 0"
                ).fetchall()
            except Exception as exc:  # noqa: BLE001
                print(f"⏭️  {bang}: bỏ qua ({str(exc)[:60]})")
                continue

            print(f"📄 {bang}: {len(dong):,} bản ghi")
            if not thuc_hien:
                tong += len(dong)
                continue

            xong, hong = 0, 0
            t0 = time.time()
            for khoa, van_ban in dong:
                try:
                    vec = dich_vu.get_embedding(str(van_ban)[:8000])
                    cur.execute(
                        f"UPDATE [{bang}] SET [{cot_vector}] = ? WHERE [{cot_khoa}] = ?",
                        (json.dumps(vec), khoa))
                    xong += 1
                except LoiTroLyAI as e:
                    # Hết hạn mức thì dừng hẳn, đừng cố chạy tiếp cho hỏng nửa vời
                    if e.can_nguoi_quan_tri:
                        print(f"   ❌ Dừng: {e.thong_diep}")
                        return 1
                    hong += 1
                except Exception as exc:  # noqa: BLE001
                    hong += 1
                    if hong <= 3:
                        print(f"   ⚠️  bản ghi {khoa}: {str(exc)[:70]}")

                if xong and xong % 50 == 0:
                    print(f"   … {xong}/{len(dong)}")

            print(f"   ✅ {xong} xong, {hong} hỏng, {time.time()-t0:.0f} giây\n")
            tong += xong

    if not thuc_hien:
        print(f"\n→ Sẽ tạo lại {tong:,} vector. Chạy lại với --thuc-hien để làm thật.")
    else:
        print(f"✅ Đã tạo lại {tong:,} vector bằng {settings.ai.ten_mo_hinh_vector}")
    return 0


if __name__ == "__main__":
    sys.exit(chay())
