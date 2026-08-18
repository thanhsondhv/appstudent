# auth/security_guard.py
from fastapi import Header, HTTPException
import pyodbc
from core.settings import settings  # cấu hình tập trung (Pha 0)

# Chuỗi kết nối SQL Server của Sơn
REMOTE_CONN_STR = settings.db.local_conn_str

async def verify_staff_token(authorization: str = Header(None)):
    """Trạm kiểm soát an ninh Matrix tập trung"""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Vui lòng đăng nhập để tiếp tục")

    token = authorization.split(" ")[1]
    
    try:
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            # Soi Token trong bảng Users của Sơn
            sql = "SELECT RTRIM(UserCode), FullName, RTRIM(UserRole) FROM tbl_Users WHERE SessionToken = ?"
            cursor.execute(sql, (token,))
            user = cursor.fetchone()

            if not user:
                # 🛑 Chỗ này ném ra 401 để Interceptor phía Flutter tự đá ra Login
                raise HTTPException(status_code=401, detail="Phiên làm việc đã hết hạn")

            user_code = str(user[0]).strip().upper()
            user_role = str(user[2]).strip().upper()

            # Kiểm tra quyền: Chỉ Cán bộ, Admin, Cố vấn mới được qua
            if user_role not in ["CANBO", "ADMIN", "COVAN", "AD", "CB"]:
                raise HTTPException(status_code=403, detail="Bạn không có quyền truy cập chức năng này")

            # 🕵️ KÍCH HOẠT WATCHDOG CHO ADMIN 1679
            if "1679" in user_code:
                print(f"🚩 [WATCHDOG] Đối tượng {user[1]} (1679) đang sử dụng quyền Admin.")

            return {"user_code": user_code, "full_name": user[1], "role": user_role}

    except pyodbc.Error as e:
        print(f"🔥 Lỗi Database Guard: {e}")
        raise HTTPException(status_code=500, detail="Lỗi kết nối hệ thống an ninh")