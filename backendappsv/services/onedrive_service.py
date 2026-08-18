# C:\vinhuni_project\services\onedrive_service.py
import httpx
import pyodbc
from typing import Optional
from fastapi import HTTPException

# 1. IMPORT BIẾN KẾT NỐI TỪ FILE DATABASE CỦA BẠN
# (Lưu ý sửa lại đường dẫn import nếu cấu trúc thư mục của bạn khác)
from database.database import CONN_STR 

class OneDriveService:
    def __init__(self, db_conn_str: str):
        self.conn_str = db_conn_str
        self.base_url = "https://graph.microsoft.com/v1.0"

    def _get_access_token(self, user_code: str) -> Optional[str]:
        """Truy xuất Access Token của User từ Database VinhUni_Local"""
        try:
            # Sử dụng chuỗi kết nối truyền vào từ hàm khởi tạo
            with pyodbc.connect(self.conn_str) as conn:
                cursor = conn.cursor()
                cursor.execute("""
                    SELECT AccessToken, ExpiresAt 
                    FROM tbl_User_MS_Tokens 
                    WHERE UserCode = ?
                """, (user_code,))
                row = cursor.fetchone()
                
                if not row: return None
                return row[0]
        except Exception as e:
            print(f"❌ Lỗi lấy Token từ DB (VinhUni_Local): {e}")
            return None

    # 🔥 ĐÃ BỔ SUNG: Tham số ms_token: str = "" để nhận Token tươi từ Flutter
    async def upload_chat_file(self, user_code: str, file_bytes: bytes, file_name: str, ms_token: str = "") -> Optional[str]:
        """Upload file lên thư mục VinhUni_Chat trên OneDrive và trả về Link"""
        
        # 🔥 ĐIỂM SÁNG CHẾ: Nếu Flutter gửi token lên thì dùng luôn, không có mới đi tìm trong SQL Server
        token = ms_token if ms_token else self._get_access_token(user_code)
        
        if not token:
            raise HTTPException(status_code=401, detail="Vui lòng đăng nhập Office 365 để gửi file.")

        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/octet-stream"
        }

        # Đường dẫn lưu file trên OneDrive (Tự động tạo thư mục VinhUni_Chat nếu chưa có)
        upload_url = f"{self.base_url}/me/drive/root:/VinhUni_Chat/{file_name}:/content"
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            upload_resp = await client.put(upload_url, headers=headers, content=file_bytes)
            
            if upload_resp.status_code not in (200, 201):
                print(f"❌ Lỗi Upload Graph API: {upload_resp.text}")
                return None
                
            item_id = upload_resp.json().get("id")

            # Tạo link chia sẻ để mọi người trong nhóm chat có thể xem
            share_url = f"{self.base_url}/me/drive/items/{item_id}/createLink"
            share_payload = {
                "type": "view", 
                "scope": "organization" # Chỉ người có tài khoản @vinhuni.edu.vn mới xem được
            }
            share_headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
            
            share_resp = await client.post(share_url, headers=share_headers, json=share_payload)
            
            if share_resp.status_code in (200, 201):
                return share_resp.json()["link"]["webUrl"]
            
            return None

# =======================================================
# 2. KHỞI TẠO INSTANCE DÙNG CHUNG VỚI CONN_STR TỪ DATABASE.PY
# =======================================================
onedrive_gateway = OneDriveService(db_conn_str=CONN_STR)