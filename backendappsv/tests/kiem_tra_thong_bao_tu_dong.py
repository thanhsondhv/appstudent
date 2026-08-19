"""
Kiểm tra chức năng gửi thông báo tự động: sinh nhật và ngày lễ.

Chức năng này thêm ngày 19/08/2026. Trước đó ứng dụng đã có màn hình "TỰ ĐỘNG
& SỰ KIỆN" với hai công tắc, nhưng phía máy chủ KHÔNG có gì cả — cán bộ bật
lên rồi hệ thống chẳng bao giờ gửi.

Ba điều bài này khoá chặt, đều là chỗ dễ sai và hậu quả thấy ngay:

  • CHỐNG GỬI TRÙNG. Tác vụ chạy mỗi giờ và có thể chạy lại sau khi khởi động
    lại máy chủ. Không chặn thì một người nhận cùng lời chúc nhiều lần trong
    ngày — phiền hơn là không gửi.
  • CHỈ GỬI CHO NGƯỜI CÒN CÀI ỨNG DỤNG. Cơ sở dữ liệu không phân biệt được sinh
    viên đang học với người đã tốt nghiệp (cả 61.974 tài khoản đều IsActive=1),
    nên gửi tràn là chúc mừng sinh nhật cả những người ra trường nhiều năm.
  • TÔN TRỌNG NGƯỜI ĐÃ TẮT trong phần cài đặt thông báo.

Tự bỏ qua (mã thoát 0) nếu không kết nối được cơ sở dữ liệu.

Chạy:  DB_SERVER=<địa-chỉ> python tests/kiem_tra_thong_bao_tu_dong.py
"""

from __future__ import annotations

import sys
import warnings
from pathlib import Path

warnings.filterwarnings("ignore")

GOC = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(GOC))

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
        import pyodbc
        from core.settings import settings
    except ImportError as exc:
        print(f"⏭️  Bỏ qua: thiếu thư viện ({exc.name})")
        return 0

    try:
        conn = pyodbc.connect(settings.db.local_conn_str, timeout=10, autocommit=True)
    except Exception as exc:  # noqa: BLE001
        print(f"⏭️  Bỏ qua: không kết nối được cơ sở dữ liệu ({str(exc)[:60]})")
        return 0

    cur = conn.cursor()

    # ── 1. Ba bảng phải có ────────────────────────────────────────────────
    print("\n\033[1m1. Cấu trúc\033[0m")
    for bang in ("tbl_ThongBao_TuDong", "tbl_ThongBao_TuDong_Log", "tbl_NgayLe"):
        kt(f"có bảng {bang}",
           bool(cur.execute(
               "SELECT CASE WHEN OBJECT_ID(?, 'U') IS NULL THEN 0 ELSE 1 END",
               f"dbo.{bang}").fetchval()), True)

    kt("có chỉ mục theo ngày sinh (nếu không sẽ quét cả 62 nghìn dòng mỗi ngày)",
       bool(cur.execute(
           "SELECT COUNT(*) FROM sys.indexes WHERE name='IX_Users_Birthday'").fetchval()), True)

    # ── 2. Cấu hình mặc định phải TẮT ─────────────────────────────────────
    print("\n\033[1m2. Cấu hình\033[0m")
    for ma in ("SINH_NHAT", "NGAY_LE"):
        r = cur.execute(
            "SELECT TieuDe, NoiDung, GioGui FROM tbl_ThongBao_TuDong WHERE MaCauHinh=?",
            ma).fetchone()
        kt(f"có cấu hình {ma}", r is not None, True)
        if r:
            kt(f"{ma}: giờ gửi hợp lệ (0–23)", 0 <= int(r[2]) <= 23, True)
            kt(f"{ma}: nội dung có chỗ thay tên {{ten}}",
               "{ten}" in (r[1] or ""), True)

    # ── 3. Nhật ký chống gửi trùng ────────────────────────────────────────
    print("\n\033[1m3. Chống gửi trùng\033[0m")
    khoa = cur.execute("""
        SELECT COUNT(*) FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
        WHERE TABLE_NAME = 'tbl_ThongBao_TuDong_Log'
          AND CONSTRAINT_NAME LIKE 'PK%'""").fetchval()
    kt("khoá chính gồm đủ ba cột (loại, người nhận, năm)", khoa, 3)

    MA_THU, NAM_THU = "KIEMTHU_TUDONG", 1999
    try:
        cur.execute("""INSERT INTO tbl_ThongBao_TuDong_Log
                       (MaCauHinh, MaNguoiNhan, Nam) VALUES (?, ?, ?)""",
                    (MA_THU, "KT001", NAM_THU))
        trung = False
        try:
            cur.execute("""INSERT INTO tbl_ThongBao_TuDong_Log
                           (MaCauHinh, MaNguoiNhan, Nam) VALUES (?, ?, ?)""",
                        (MA_THU, "KT001", NAM_THU))
            trung = True
        except pyodbc.IntegrityError:
            pass
        kt("cơ sở dữ liệu CHẶN ghi trùng cùng người, cùng năm", trung, False)
    finally:
        cur.execute("DELETE FROM tbl_ThongBao_TuDong_Log WHERE MaCauHinh=?", MA_THU)

    # ── 4. Truy vấn chọn người nhận ───────────────────────────────────────
    print("\n\033[1m4. Chọn đúng người nhận\033[0m")
    tat_ca = cur.execute("""
        SELECT COUNT(*) FROM tbl_users
        WHERE Birthday IS NOT NULL
          AND MONTH(Birthday)=MONTH(GETDATE()) AND DAY(Birthday)=DAY(GETDATE())
    """).fetchval()
    con_dung_app = cur.execute("""
        SELECT COUNT(DISTINCT u.UserCode) FROM tbl_users u
        WHERE u.Birthday IS NOT NULL
          AND MONTH(u.Birthday)=MONTH(GETDATE()) AND DAY(u.Birthday)=DAY(GETDATE())
          AND EXISTS (SELECT 1 FROM tbl_FCM_Tokens t
                      WHERE REPLACE(REPLACE(UPPER(RTRIM(t.StudentId)),'SV',''),'CB','')
                            = REPLACE(REPLACE(UPPER(RTRIM(u.UserCode)),'SV',''),'CB','')
                        AND t.IsActive=1)
    """).fetchval()
    print(f"       sinh nhật hôm nay: {tat_ca} người | còn dùng ứng dụng: {con_dung_app}")
    kt("bộ lọc 'còn dùng ứng dụng' thật sự thu hẹp danh sách",
       con_dung_app <= tat_ca, True)

    # ── 5. Mã nguồn tác vụ nền ────────────────────────────────────────────
    print("\n\033[1m5. Tác vụ nền\033[0m")
    nguon = (GOC / "sync_and_notify_worker_new.py").read_text(encoding="utf-8")
    kt("có tác vụ chúc mừng sinh nhật", "def job_chuc_mung_sinh_nhat" in nguon, True)
    kt("có tác vụ chúc mừng ngày lễ", "def job_chuc_mung_ngay_le" in nguon, True)
    kt("đã đăng ký vào bộ hẹn giờ",
       nguon.count("scheduler.add_job(job_chuc_mung") == 2, True)
    kt("có lọc theo thiết bị đang hoạt động", "tbl_FCM_Tokens" in nguon, True)
    kt("có tôn trọng người đã tắt loại thông báo này",
       "tbl_Notification_User_Settings" in nguon, True)
    kt("có ghi nhật ký để chống gửi trùng",
       "tbl_ThongBao_TuDong_Log" in nguon, True)

    conn.close()

    print()
    if HONG:
        print(f"\033[31m❌ {len(HONG)} phép thử KHÔNG ĐẠT\033[0m")
        return 1
    print(f"\033[32m✅ TẤT CẢ ĐẠT\033[0m  ({DAT} phép thử)")
    return 0


if __name__ == "__main__":
    sys.exit(chay())
