#router\notif_settings
from fastapi import APIRouter, HTTPException
from fastapi import Depends
from auth.jwt_handler import Identity, require_staff
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from typing import List, Optional
import pyodbc
from core.settings import settings  # cấu hình tập trung (Pha 0)

router = APIRouter(prefix="/api/notifications", tags=["Notification Settings"])

# --- CẤU HÌNH KẾT NỐI SQL SERVER ---
DB_SERVER = settings.db.server
DB_NAME = settings.db.name
DB_USER = settings.db.user
DB_PASSWORD = settings.db.password
CONN_STR = settings.db.local_conn_str

def get_db_conn():
    return pyodbc.connect(CONN_STR)

class NotifSettingUpdate(BaseModel):
    user_id: str
    category: str
    is_enabled: bool
    lead_time: Optional[int] = 30

@router.get("/settings/{user_id}")
def get_user_settings(user_id: str):
    conn = None
    try:
        conn = get_db_conn()
        cursor = conn.cursor()
        
        # 1. Kiểm tra cấu hình hiện có
        cursor.execute("SELECT Category, IsEnabled, LeadTimeMinutes FROM tbl_Notification_User_Settings WHERE UserId = ?", (user_id,))
        rows = cursor.fetchall()

        if not rows:
            print(f"🔍 [DEBUG] User {user_id} chưa có cấu hình. Đang tra cứu vai trò...")
            # 2. TRA CỨU VAI TRÒ TỪ tbl_users
            # Lưu ý: Sơn kiểm tra lại chính xác tên cột trong bảng tbl_users (UserCode hay userid?)
            cursor.execute("SELECT userrole FROM tbl_users WHERE UserCode = ? OR UserCode = ?", (user_id, 'SV' + user_id))
            user_info = cursor.fetchone()
            role = user_info[0] if user_info else "SinhVien"
            print(f"🔍 [DEBUG] Vai trò tìm thấy: {role}")

            # 3. NẠP MẶC ĐỊNH
            defaults = []
            if role in ["CanBo", "CoVan", "Admin"]:
                defaults = [('GENERAL', 1, 0), ('VAN_BAN', 1, 0), ('LICH_TUAN', 1, 30), ('LICH_DAY', 1, 30)]
            else:
                defaults = [('GENERAL', 1, 0), ('LICH_THI', 1, 60), ('DIEM', 1, 0), ('LICH_HOC', 1, 30), ('CAN_BAO', 1, 0)]
            
            for cat, enabled, time in defaults:
                cursor.execute("""
                    INSERT INTO tbl_Notification_User_Settings (UserId, Category, IsEnabled, LeadTimeMinutes)
                    VALUES (?, ?, ?, ?)
                """, (user_id, cat, enabled, time))
            conn.commit()
            
            cursor.execute("SELECT Category, IsEnabled, LeadTimeMinutes FROM tbl_Notification_User_Settings WHERE UserId = ?", (user_id,))
            rows = cursor.fetchall()

        return [{"category": r[0], "is_enabled": bool(r[1]), "lead_time": r[2] or 30} for r in rows]

    except Exception as e:
        print(f"❌ [SQL ERROR] {str(e)}") # Dòng này sẽ hiện lỗi thật ở Terminal
        raise HTTPException(status_code=500, detail=f"Database Error: {str(e)}")
    finally:
        if conn: conn.close()

@router.post("/update")
def update_setting(data: NotifSettingUpdate):
    conn = None
    try:
        conn = get_db_conn()
        cursor = conn.cursor()
        cursor.execute("""
            IF EXISTS (SELECT 1 FROM tbl_Notification_User_Settings WHERE UserId = ? AND Category = ?)
            BEGIN
                UPDATE tbl_Notification_User_Settings SET IsEnabled = ?, LeadTimeMinutes = ? WHERE UserId = ? AND Category = ?
            END
            ELSE
            BEGIN
                INSERT INTO tbl_Notification_User_Settings (UserId, Category, IsEnabled, LeadTimeMinutes) VALUES (?, ?, ?, ?)
            END
        """, (data.user_id, data.category, 1 if data.is_enabled else 0, data.lead_time, data.user_id, data.category,
              data.user_id, data.category, 1 if data.is_enabled else 0, data.lead_time))
        conn.commit()
        return {"status": "success"}
    except Exception as e:
        print(f"❌ [UPDATE ERROR] {str(e)}")
        if conn: conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if conn: conn.close()


# ===========================================================================
# Thông báo tự động theo sự kiện — sinh nhật, ngày lễ
# ===========================================================================
#
# Thêm 19/08/2026. Ứng dụng đã có màn hình "TỰ ĐỘNG & SỰ KIỆN" từ trước nhưng
# phía máy chủ không có gì: bật công tắc rồi chẳng bao giờ gửi. Đây là phần
# còn thiếu.
#
# Phần gửi thật nằm ở sync_and_notify_worker_new.py, hai tác vụ
# job_chuc_mung_sinh_nhat và job_chuc_mung_ngay_le.


@router.get("/tu-dong")
def lay_cau_hinh_tu_dong():
    """Danh sách cấu hình gửi tự động, kèm số liệu để người dùng biết tác dụng."""
    try:
        with pyodbc.connect(CONN_STR, timeout=8) as conn:
            cursor = conn.cursor()

            cau_hinh = []
            for r in cursor.execute("""
                SELECT MaCauHinh, TenHienThi, BatTat, TieuDe, NoiDung, GioGui
                FROM tbl_ThongBao_TuDong ORDER BY MaCauHinh
            """).fetchall():
                cau_hinh.append({
                    "ma": r[0], "ten": r[1], "bat": bool(r[2]),
                    "tieu_de": r[3], "noi_dung": r[4], "gio_gui": int(r[5]),
                })

            # Cho người dùng thấy con số thật, thay vì bật một công tắc mù
            so_sinh_nhat_hom_nay = cursor.execute("""
                SELECT COUNT(DISTINCT u.UserCode) FROM tbl_users u
                WHERE u.Birthday IS NOT NULL
                  AND MONTH(u.Birthday) = MONTH(GETDATE())
                  AND DAY(u.Birthday) = DAY(GETDATE())
                  AND EXISTS (SELECT 1 FROM tbl_FCM_Tokens t
                              WHERE REPLACE(REPLACE(UPPER(RTRIM(t.StudentId)),'SV',''),'CB','')
                                    = REPLACE(REPLACE(UPPER(RTRIM(u.UserCode)),'SV',''),'CB','')
                                AND t.IsActive = 1)
            """).fetchval()

            ngay_le = [
                {"ngay": r[0], "thang": r[1], "ten": r[2],
                 "doi_tuong": r[3], "bat": bool(r[4])}
                for r in cursor.execute("""
                    SELECT Ngay, Thang, TenNgay, DoiTuong, BatTat
                    FROM tbl_NgayLe ORDER BY Thang, Ngay""").fetchall()
            ]

            return {
                "status": "success",
                "cau_hinh": cau_hinh,
                "ngay_le": ngay_le,
                "so_sinh_nhat_hom_nay": so_sinh_nhat_hom_nay,
            }
    except Exception as e:  # noqa: BLE001
        # Chưa chạy kịch bản tạo bảng thì nói rõ, đừng để ứng dụng đoán
        print(f"⚠️ [TựĐộng] Không đọc được cấu hình: {str(e)[:120]}")
        return JSONResponse(
            status_code=503,
            content={"status": "error",
                     "message": "Chức năng gửi tự động chưa được cài đặt trên máy chủ."},
        )


@router.post("/tu-dong")
def cap_nhat_cau_hinh_tu_dong(data: dict, me: Identity = Depends(require_staff)):
    """Bật/tắt hoặc sửa nội dung một cấu hình. Chỉ cán bộ được đổi."""
    ma = str(data.get("ma", "")).strip()
    if not ma:
        return JSONResponse(status_code=400,
                            content={"status": "error", "message": "Thiếu mã cấu hình"})

    try:
        with pyodbc.connect(CONN_STR, timeout=8, autocommit=True) as conn:
            cursor = conn.cursor()

            phan, tham = [], []
            if "bat" in data:
                phan.append("BatTat = ?"); tham.append(1 if data["bat"] else 0)
            if data.get("tieu_de"):
                phan.append("TieuDe = ?"); tham.append(str(data["tieu_de"])[:300])
            if data.get("noi_dung"):
                phan.append("NoiDung = ?"); tham.append(str(data["noi_dung"]))
            if "gio_gui" in data:
                gio = int(data["gio_gui"])
                if not 0 <= gio <= 23:
                    return JSONResponse(status_code=400,
                        content={"status": "error", "message": "Giờ gửi phải từ 0 đến 23"})
                phan.append("GioGui = ?"); tham.append(gio)

            if not phan:
                return JSONResponse(status_code=400,
                    content={"status": "error", "message": "Không có gì để cập nhật"})

            phan += ["NguoiSua = ?", "SuaLuc = GETDATE()"]
            tham.append(me.user_code)
            tham.append(ma)

            cursor.execute(
                f"UPDATE tbl_ThongBao_TuDong SET {', '.join(phan)} WHERE MaCauHinh = ?",
                tham)
            if cursor.rowcount == 0:
                return JSONResponse(status_code=404,
                    content={"status": "error", "message": f"Không có cấu hình '{ma}'"})

            print(f"⚙️  [TựĐộng] {me.user_code} đã cập nhật cấu hình '{ma}'")
            return {"status": "success"}
    except Exception as e:  # noqa: BLE001
        print(f"🔥 [TựĐộng] Lỗi cập nhật cấu hình: {str(e)[:150]}")
        return JSONResponse(status_code=500,
            content={"status": "error", "message": "Không lưu được cấu hình."})
