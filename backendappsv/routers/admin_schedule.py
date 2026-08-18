from fastapi import APIRouter, HTTPException, Depends, Header
from fastapi.concurrency import run_in_threadpool
import pyodbc
from services.db_service import DBService
from fastapi import APIRouter, Depends # 👈 Nhớ thêm Depends
from auth.security_guard import verify_staff_token # 👈 Gọi đúng file Sơn vừa tạo
from core.settings import settings  # cấu hình tập trung (Pha 0)
router = APIRouter(prefix="/api/admin/schedule", tags=["Admin Schedule"])
db = DBService()

# Giả sử REMOTE_CONN_STR đã được định nghĩa ở file config hoặc main.py
REMOTE_CONN_STR = settings.db.local_conn_str

# async def verify_staff_token(authorization: str = Header(None)):
    # # 🕵️ Soi trực tiếp cái Token gửi từ iPhone/Simulator lên
    # print(f"📡 [RECEIVE] Token nhận được: {authorization}") 

    # if not authorization or not authorization.startswith("Bearer "):
        # print("❌ [DEBUG] Header trống hoặc sai định dạng!")
        # raise HTTPException(status_code=401, detail="Yêu cầu đăng nhập")
    
    # token = authorization.split(" ")[1]

    # try:
        # with pyodbc.connect(REMOTE_CONN_STR) as conn:
            # cursor = conn.cursor()
            # sql = "SELECT RTRIM(UserCode), FullName, RTRIM(UserRole) FROM tbl_Users WHERE SessionToken = ?"
            # cursor.execute(sql, (token,))
            # user = cursor.fetchone()

            # if not user:
                # # 🛑 Chỗ này ném ra 401
                # raise HTTPException(status_code=401, detail="Phiên làm việc hết hạn")

            # return {"user_code": str(user[0]).strip(), "full_name": user[1]}

    # # 🛡️ CHỈ BẮT CÁC LỖI TỪ DATABASE, KHÔNG BẮT HTTPException
    # except pyodbc.Error as e:
        # print(f"🔥 Lỗi Database: {e}")
        # raise HTTPException(status_code=500, detail="Lỗi kết nối hệ thống")
    
    # Nếu là lỗi HTTPException (như 401 ở trên), nó sẽ bỏ qua khối except này 
    # và trả về đúng mã 401 cho Flutter.


@router.get("/view-data")
async def view_data(): 
    """Lấy 50 bản ghi lịch tuần mới nhất (CHẾ ĐỘ TEST - KHÔNG BẢO MẬT)"""
    
    # 🕵️ Tạm ẩn đoạn Watchdog đi vì đang ở chế độ Test không có user đăng nhập
    # if "1679" in current_staff['user_code']:
    #     print(f"🚩 [WATCHDOG] Admin {current_staff['full_name']} (1679) đang xem Lịch Tuần.")

    try:
        sql = "SELECT TOP 50 * FROM tbl_WeeklySchedule ORDER BY EventDate DESC, CreatedAt DESC"
        data = await run_in_threadpool(db.execute_query, sql) 
        return {"status": "success", "data": data}
    except Exception as e:
        print(f"🔥 Lỗi thực thi SQL: {e}")
        raise HTTPException(status_code=500, detail="Lỗi khi đọc dữ liệu lịch tuần")