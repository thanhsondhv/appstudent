"""
Kiểm tra bảng người nhận thông báo — có đúng, có tự cập nhật không.

Bảng tbl_ThongBao_NguoiNhan thay cho việc dò LIKE '%mã%' trên một cột
NVARCHAR(MAX) chứa danh sách mã ngăn bởi dấu phẩy. Nó sửa hai vấn đề đo được
trên dữ liệu thật ngày 19/08/2026:

  • SAI: LIKE '%1679%' khớp cả mã dài hơn có chứa "1679" — tài khoản 1679 đọc
    được 22 thông báo không phải của mình; một sinh viên nhận 381 tin thay vì
    332 tin đúng.
  • CHẬM: cột đó tổng ~240 MB, mỗi lần mở danh sách quét lại toàn bộ — 5,02
    giây cho một người dùng.

Bài này khoá chặt cả hai, và quan trọng nhất là kiểm TRIGGER: nếu trigger
không chạy thì mọi thông báo tạo mới sẽ không tới được ai, mà bảng gốc vẫn
đúng nên rất khó truy ra.

Tự bỏ qua (mã thoát 0) nếu không kết nối được cơ sở dữ liệu.

Chạy:  DB_SERVER=<địa-chỉ> python tests/kiem_tra_bang_nguoi_nhan.py
"""

from __future__ import annotations

import sys
import time
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

    # ── 1. Bảng và chỉ mục có tồn tại ────────────────────────────────────
    print("\n\033[1m1. Bảng và chỉ mục\033[0m")
    kt("bảng tbl_ThongBao_NguoiNhan tồn tại",
       bool(cur.execute("SELECT CASE WHEN OBJECT_ID('dbo.tbl_ThongBao_NguoiNhan','U') "
                        "IS NULL THEN 0 ELSE 1 END").fetchval()), True)
    kt("có chỉ mục theo mã người nhận",
       bool(cur.execute("SELECT COUNT(*) FROM sys.indexes WHERE name='IX_NguoiNhan_Ma'").fetchval()), True)

    # ── 2. Không khớp nhầm chuỗi con ─────────────────────────────────────
    print("\n\033[1m2. Không còn khớp nhầm chuỗi con\033[0m")
    ma_thu = "1679"
    cu = cur.execute(
        "SELECT COUNT(*) FROM tbl_ThongBao WHERE IsDeleted=0 "
        "AND CAST(IdNguoiHocs AS NVARCHAR(MAX)) LIKE ?", (f"%{ma_thu}%",)).fetchval()
    moi = cur.execute(
        "SELECT COUNT(DISTINCT n.ThongBaoId) FROM tbl_ThongBao_NguoiNhan n "
        "JOIN tbl_ThongBao t ON t.Id = n.ThongBaoId "
        "WHERE n.Nguon='THONGBAO' AND n.MaNguoiNhan=? AND t.IsDeleted=0", (ma_thu,)).fetchval()
    dung = cur.execute(
        "SELECT COUNT(*) FROM tbl_ThongBao WHERE IsDeleted=0 "
        "AND (',' + CAST(IdNguoiHocs AS NVARCHAR(MAX)) + ',') LIKE ?", (f"%,{ma_thu},%",)).fetchval()
    print(f"       cách cũ LIKE: {cu} tin | bảng mới: {moi} tin | đúng theo dấu phân cách: {dung} tin")
    kt("bảng mới khớp đúng số tin thật sự gửi cho người này", moi, dung)

    # ── 3. Nhanh hơn hẳn ─────────────────────────────────────────────────
    print("\n\033[1m3. Tốc độ tra cứu\033[0m")
    t = time.time()
    cur.execute("SELECT COUNT(*) FROM tbl_ThongBao WHERE IsDeleted=0 "
                "AND CAST(IdNguoiHocs AS NVARCHAR(MAX)) LIKE ?", (f"%{ma_thu}%",)).fetchval()
    giay_cu = time.time() - t

    t = time.time()
    cur.execute("SELECT COUNT(*) FROM tbl_ThongBao_NguoiNhan "
                "WHERE Nguon='THONGBAO' AND MaNguoiNhan=?", (ma_thu,)).fetchval()
    giay_moi = time.time() - t

    print(f"       quét chuỗi: {giay_cu:.2f}s | theo chỉ mục: {giay_moi:.3f}s")
    kt("tra cứu theo chỉ mục nhanh hơn ít nhất 5 lần", giay_moi * 5 < giay_cu, True)

    # ── 4. Trigger có chạy không ─────────────────────────────────────────
    print("\n\033[1m4. Trigger tự cập nhật\033[0m")
    for ten in ("TR_ThongBao_DongBoNguoiNhan", "TR_ThongBao_XoaNguoiNhan"):
        kt(f"trigger {ten} tồn tại và đang bật",
           bool(cur.execute("SELECT COUNT(*) FROM sys.triggers "
                            "WHERE name=? AND is_disabled=0", (ten,)).fetchval()), True)

    # tbl_Notification_Queue PHẢI KHÔNG có trigger. SQL Server cấm
    # `OUTPUT INSERTED.<cột>` (dạng không có INTO) trên bảng có trigger, mà ba
    # API gửi thông báo đang dùng đúng cú pháp đó — gắn trigger vào là gửi
    # thông báo hỏng ngay. Phép thử này giữ cho điều đó không tái diễn.
    kt("tbl_Notification_Queue KHÔNG có trigger (nếu có sẽ hỏng API gửi thông báo)",
       cur.execute("SELECT COUNT(*) FROM sys.triggers "
                   "WHERE parent_id = OBJECT_ID('dbo.tbl_Notification_Queue')").fetchval(), 0)

    # Thử thật trên tbl_ThongBao: thêm một tin rồi xoá đi
    MA_THU = "KIEMTHU999"
    ma_tin = None
    try:
        # Id của tbl_ThongBao không tự tăng — phải tự cấp một giá trị chưa dùng
        ma_tin = (cur.execute("SELECT ISNULL(MAX(Id), 0) FROM tbl_ThongBao").fetchval()) + 1
        # tbl_ThongBao có nhiều cột NOT NULL không đặt mặc định — phải điền đủ,
        # nếu không INSERT hỏng và bài kiểm thử báo nhầm là trigger có vấn đề.
        cur.execute("""
            INSERT INTO tbl_ThongBao
              (Id, TieuDe, NoiDung, NgayPhatHanh, Created, Modified, IsDeleted,
               InstanceId, IsBuildIn, IsBuildInAll, Version,
               IdLoaiThongBao, IdMucDoThongBao, IdNguoiHocs)
            VALUES (?, N'[Kiểm thử] bỏ qua', N'Tin do bài kiểm thử tạo ra',
                    GETDATE(), GETDATE(), GETDATE(), 0,
                    NEWID(), 0, 0, 1,
                    1, 1, ?)
        """, (ma_tin, f"{MA_THU},205714023110061"))

        co = cur.execute("SELECT COUNT(*) FROM tbl_ThongBao_NguoiNhan "
                         "WHERE Nguon='THONGBAO' AND ThongBaoId=? AND MaNguoiNhan=?",
                         (ma_tin, MA_THU)).fetchval()
        kt("thêm thông báo mới → người nhận được tách ngay", co, 1)

        cur.execute("UPDATE tbl_ThongBao SET IdNguoiHocs = ? WHERE Id = ?",
                    ("205714023110061", ma_tin))
        con = cur.execute("SELECT COUNT(*) FROM tbl_ThongBao_NguoiNhan "
                          "WHERE Nguon='THONGBAO' AND ThongBaoId=? AND MaNguoiNhan=?",
                          (ma_tin, MA_THU)).fetchval()
        kt("sửa danh sách người nhận → bảng cập nhật theo", con, 0)
    finally:
        if ma_tin:
            cur.execute("DELETE FROM tbl_ThongBao WHERE Id = ?", (ma_tin,))
            sot = cur.execute("SELECT COUNT(*) FROM tbl_ThongBao_NguoiNhan "
                              "WHERE Nguon='THONGBAO' AND ThongBaoId=?", (ma_tin,)).fetchval()
            kt("xoá thông báo → không để lại dòng mồ côi", sot, 0)

    conn.close()

    print()
    if HONG:
        print(f"\033[31m❌ {len(HONG)} phép thử KHÔNG ĐẠT\033[0m")
        return 1
    print(f"\033[32m✅ TẤT CẢ ĐẠT\033[0m  ({DAT} phép thử)")
    return 0


if __name__ == "__main__":
    sys.exit(chay())
