"""
Kiểm tra việc đổi nhà cung cấp mô hình AI: OpenAI ⇄ Gemini.

Gemini có cổng TƯƠNG THÍCH OpenAI, nên đổi nhà cung cấp chỉ là đổi địa chỉ,
khoá và tên mô hình — không phải viết lại 21 chỗ gọi mô hình rải khắp mã nguồn.

Điều nguy hiểm nhất khi đổi: VECTOR CŨ KHÔNG DÙNG LẠI ĐƯỢC. Vector của hai mô
hình nằm trong hai không gian khác nhau và khác cả số chiều (OpenAI 1536,
Gemini 768). Đem so với nhau thì kết quả ngẫu nhiên — KHÔNG báo lỗi, chỉ trả về
tài liệu không liên quan. Kiểu hỏng im lặng, trông vẫn như đang chạy.

Vì vậy đổi mô hình xong PHẢI chạy tao_lai_vector.py.

Không cần mạng, không cần khoá API.

Chạy:  python tests/kiem_tra_doi_nha_cung_cap_ai.py
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
        from core.settings import settings
    except ImportError as exc:
        print(f"⏭️  Bỏ qua: thiếu thư viện ({exc.name})")
        return 0

    # Lấy lớp cấu hình AI qua chính đối tượng đang có, để không phụ thuộc tên lớp
    AiSettings = type(settings.ai)  # noqa: N806

    def dung(nha_cung_cap: str, **them):
        """Dựng một bộ cấu hình AI với biến môi trường cho trước."""
        cu = {}
        moi = {"AI_PROVIDER": nha_cung_cap, "OPENAI_API_KEY": "khoa-openai",
               "GEMINI_API_KEY": "khoa-gemini", "AI_CHAT_MODEL": "",
               "AI_EMBEDDING_MODEL": ""}
        moi.update(them)
        for k, v in moi.items():
            cu[k] = os.environ.get(k)
            os.environ[k] = v
        try:
            return AiSettings()
        finally:
            for k, v in cu.items():
                if v is None:
                    os.environ.pop(k, None)
                else:
                    os.environ[k] = v

    # ── 1. Chọn đúng nhà cung cấp ─────────────────────────────────────────
    print("\n\033[1m1. Chọn nhà cung cấp\033[0m")
    o = dung("openai")
    kt("openai: không dùng Gemini", o.dung_gemini, False)
    kt("openai: lấy đúng khoá OpenAI", o.khoa_dang_dung, "khoa-openai")
    kt("openai: dùng địa chỉ mặc định", o.dia_chi_goc, None)

    g = dung("gemini")
    kt("gemini: nhận ra đúng", g.dung_gemini, True)
    kt("gemini: lấy đúng khoá Gemini", g.khoa_dang_dung, "khoa-gemini")
    kt("gemini: có địa chỉ cổng tương thích",
       "generativelanguage.googleapis.com" in (g.dia_chi_goc or ""), True)

    # ── 2. Tên mô hình mặc định theo từng nhà cung cấp ────────────────────
    print("\n\033[1m2. Tên mô hình mặc định\033[0m")
    kt("openai: mô hình chat", o.ten_mo_hinh_chat, "gpt-4o-mini")
    kt("openai: mô hình vector", o.ten_mo_hinh_vector, "text-embedding-3-small")
    kt("gemini: mô hình chat", g.ten_mo_hinh_chat, "gemini-2.0-flash")
    kt("gemini: mô hình vector", g.ten_mo_hinh_vector, "text-embedding-004")

    # ── 3. Ghi đè bằng .env ───────────────────────────────────────────────
    print("\n\033[1m3. Ghi đè tên mô hình\033[0m")
    r = dung("gemini", AI_CHAT_MODEL="gemini-2.5-pro")
    kt("AI_CHAT_MODEL ghi đè được", r.ten_mo_hinh_chat, "gemini-2.5-pro")
    r = dung("openai", AI_EMBEDDING_MODEL="text-embedding-3-large")
    kt("AI_EMBEDDING_MODEL ghi đè được",
       r.ten_mo_hinh_vector, "text-embedding-3-large")

    # ── 4. Viết hoa viết thường, giá trị lạ ───────────────────────────────
    print("\n\033[1m4. Giá trị lạ\033[0m")
    kt("GEMINI viết hoa vẫn nhận ra", dung("GEMINI").dung_gemini, True)
    kt("giá trị lạ thì về OpenAI (mặc định an toàn)",
       dung("khong-biet").dung_gemini, False)

    # ── 5. Mã nguồn không còn viết cứng tên mô hình ───────────────────────
    print("\n\033[1m5. Không viết cứng tên mô hình\033[0m")
    BO_QUA = {"venv", "_luu_tru", "__pycache__", ".git", "tests"}
    CHO_PHEP = {"core/settings.py", "config/settings.py", "tao_lai_vector.py"}
    pham_phai = []
    for tep in GOC.rglob("*.py"):
        r = tep.relative_to(GOC)
        if BO_QUA & set(r.parts) or str(r) in CHO_PHEP:
            continue
        try:
            nguon = tep.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        for dong in nguon.splitlines():
            cat = dong.strip()
            if cat.startswith("#"):
                continue
            if 'model="gpt-' in cat or "model='gpt-" in cat:
                pham_phai.append(f"{r}: {cat[:60]}")
    kt("không tệp nào viết cứng model=\"gpt-...\"", pham_phai, [])

    # ── 6. Có sẵn cách tạo lại vector ─────────────────────────────────────
    print("\n\033[1m6. Tạo lại vector sau khi đổi mô hình\033[0m")
    kt("có kịch bản tao_lai_vector.py", (GOC / "tao_lai_vector.py").exists(), True)
    noi_dung = (GOC / "tao_lai_vector.py").read_text(encoding="utf-8")
    kt("kịch bản có chế độ xem trước, không ghi ngay",
       "--thuc-hien" in noi_dung, True)
    kt("kịch bản KHÔNG đụng vào vector khuôn mặt",
       "Vector_bin" not in noi_dung.split('"""')[2] if noi_dung.count('"""') > 2 else True,
       True)

    print()
    if HONG:
        print(f"\033[31m❌ {len(HONG)} phép thử KHÔNG ĐẠT\033[0m")
        return 1
    print(f"\033[32m✅ TẤT CẢ ĐẠT\033[0m  ({DAT} phép thử)")
    return 0


if __name__ == "__main__":
    sys.exit(chay())
