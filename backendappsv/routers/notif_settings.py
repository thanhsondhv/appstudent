#router\notif_settings
from fastapi import APIRouter, HTTPException
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
async def get_user_settings(user_id: str):
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
async def update_setting(data: NotifSettingUpdate):
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