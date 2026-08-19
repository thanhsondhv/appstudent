from fastapi import FastAPI, Request, HTTPException, status, Body, Query, File, UploadFile, Form
from fastapi.responses import JSONResponse, FileResponse, RedirectResponse, HTMLResponse 
from fastapi.templating import Jinja2Templates
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.sessions import SessionMiddleware
from pydantic import BaseModel
import pyodbc
import base64, hashlib, hmac
from api import secretary_router
from routers import voice_control_router # goi chuc nang am thanh
import os
import uuid
from datetime import datetime
from authlib.integrations.starlette_client import OAuth
import httpx 
import firebase_admin
from firebase_admin import credentials, messaging
import re
import html
import shutil
import numpy as np
from routers import admin_schedule # lich tuan
from typing import Optional
from services.certificate_service import CertificateService # tra cuu chung nhan
# Đảm bảo bạn đã import DBService
from vinhuni_chatbot_python.services.db_service import DBService
from router import search
import importlib
#import vinhuni_chatbot_python.main_chatbot_v2 as v2_module
#import vinhuni_chatbot_python.services.ai_service_v2 as v2_service
from routers.api_chatbot_v2 import router as chatbot_v2_router
from routers.api_chatbot_v3 import router as chatbot_v3_router
    
from fastapi import APIRouter, Request, Body, Depends
from fastapi.responses import JSONResponse
import requests
from datetime import datetime, timedelta


# Đảm bảo đã import hàm tạo token từ file jwt_handler.py bạn vừa tạo
from auth.jwt_handler import create_access_token 

from routers.api_academic import router as academic_router
from routers.api_certificate import router as certificate_router
from routers import attendance_router as attendance # API điểm danh mới
from routers import news
from routers import notif_settings
import json
from fastapi import APIRouter, Request
#chat Group
import socketio
from core.socket_manager import sio
from routers import api_chatgroupv1

#from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.concurrency import run_in_threadpool  # chạy mã đồng bộ ngoài vòng lặp sự kiện
import pyodbc
from fastapi import Depends, HTTPException, Header, status
from firebase_admin import auth, credentials
from fastapi import Request, HTTPException, Header
#import pyodbc
from fastapi import APIRouter, Depends # 👈 Nhớ thêm Depends
from auth.security_guard import verify_staff_token # 👈 Gọi đúng file Sơn vừa tạo
from services.ai_corrector_service import router as ocr_router
from utils.security import BlacklistManager
from routers.api_chat_secure import router as chat_secure_router #webview chat
from routers.signature_router import router as signature_router  # ký số văn bản (Pha 4)
from routers.admin_portal_router import router as admin_portal_router, health_router  # cổng quản trị (Pha 6)
db_service = DBService()

# =======================================================
# 1. CẤU HÌNH HỆ THỐNG & OFFICE 365
# =======================================================
# ĐÃ ĐỔI 18/08/2026 (Pha 0): mọi khoá bí mật chuyển sang tệp .env.
# Các tên biến cũ được giữ nguyên bên dưới để những đoạn mã khác trong
# file này không phải sửa theo — nhưng giá trị nay lấy từ core/settings.py.
from core.settings import settings

SESSION_SECRET_KEY = settings.security.session_secret
CLIENT_ID = settings.microsoft.client_id
CLIENT_SECRET = settings.microsoft.client_secret
TENANT_ID = settings.microsoft.tenant_id
REDIRECT_URI = settings.microsoft.redirect_uri
CONF_URL = settings.microsoft.conf_url

# Cấu hình SQL Server Local
DB_SERVER = settings.db.server
DB_USER = settings.db.user
DB_PASSWORD = settings.db.password
DB_NAME = settings.db.name
REMOTE_CONN_STR = settings.db.local_conn_str

# ĐỊA CHỈ AI SERVER
INTERNAL_STUDENT_AI = settings.internal_student_ai
IMAGE_FOLDER = settings.image_folder

print(f"[Cau hinh] Moi truong={settings.env} | CSDL={settings.db.safe_repr}")

app = FastAPI(
    title="VinhUni AI Core API",
    description="Hệ thống Backend cung cấp API cho Mobile App và Web Client",
    version="2.0.2"
)

# backlist scan
@app.middleware("http")
async def blacklist_protection_middleware(request: Request, call_next):
    # 1. Lấy thông tin định danh từ Request
    ip = request.client.host
    device_id = request.headers.get("X-Device-ID") # App Flutter của Sơn gửi lên Header
    
    # Lấy Student Code (Nếu đã qua bước Verify Token hoặc App gửi kèm)
    student_code = request.headers.get("X-Student-Code") 

    # 2. 🔥 GỌI HÀM KIỂM TRA ĐA TẦNG CỦA SƠN
    # Thứ tự: Ưu tiên chặn MSV > Chặn Device > Cuối cùng mới chặn IP WAN
    block_info, type_blocked = await BlacklistManager.verify_request_access(
        ip=ip, 
        device_id=device_id, 
        student_code=student_code
    )

    # 3. Nếu bị dính Blacklist -> Chặn ngay lập tức
    if block_info:
        # Nếu chặn theo IP (tránh ảnh hưởng IP chung), trả về 429 để báo bận
        status_code = 429 if type_blocked == "IP" else 403
        
        return JSONResponse(
            status_code=status_code,
            content={
                "status": "blocked",
                "message": f"Hệ thống tạm khóa đến {block_info['expired_at'].strftime('%H:%M')}",
                "reason": block_info['reason'],
                "type": type_blocked
            }
        )

    # 4. Nếu an toàn -> Cho phép đi tiếp
    return await call_next(request)
    
# Đường dẫn mới trên ổ E
UPLOAD_DIR = r"E:\app_vinhuni\vanban"

# Đảm bảo thư mục tồn tại
if not os.path.exists(UPLOAD_DIR):
    os.makedirs(UPLOAD_DIR)

# Gắn thư mục E:\app_vinhuni\vanban vào tiền tố /uploads
# Khi đó link /uploads/docs/VinhUni_2699.pdf sẽ trỏ đúng vào E:\app_vinhuni\vanban\docs\VinhUni_2699.pdf
app.mount("/uploads", StaticFiles(directory=UPLOAD_DIR), name="uploads")
app.mount("/static", StaticFiles(directory="static"), name="static")
# Cấu hình Firebase Admin (Nếu có file key)
try:
    if not firebase_admin._apps:
        cred = credentials.Certificate("vinhuni-portal-firebase-adminsdk.json")
        firebase_admin.initialize_app(cred)
    print("✅ Firebase Admin SDK Ready!")
except Exception as e:
    print(f"⚠️ Firebase Warning: {e}")

oauth = OAuth()
oauth.register(
    name="microsoft",
    client_id=CLIENT_ID,
    client_secret=CLIENT_SECRET,
    server_metadata_url=CONF_URL,
    client_kwargs={"scope": "openid email profile User.Read"}
)
# =======================================================
# 2. MIDDLEWARES
# =======================================================
# app.add_middleware(
    # CORSMiddleware,
    # allow_origins=["*"],
    # allow_credentials=True,
    # allow_methods=["*"],
    # allow_headers=["*"],
# )

# app.add_middleware(
    # SessionMiddleware, 
    # secret_key=SESSION_SECRET_KEY,
    # session_cookie="vinhuni_session",
    # same_site="lax",
    # https_only=False 
# )
# 1. Cấu hình CORS: Phải chỉ định rõ Domain, không dùng "*"
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "https://mobi.vinhuni.edu.vn", 
        "http://localhost:1234", # Nếu Sơn test web local
    ],
    allow_credentials=True, # Bắt buộc để gửi Session Cookie
    allow_methods=["*"],
    allow_headers=["*"],
)

# 2. Cấu hình Session
app.add_middleware(
    SessionMiddleware, 
    secret_key=SESSION_SECRET_KEY,
    session_cookie="vinhuni_session",
    same_site="lax",  # Giữ nguyên lax là đúng
    https_only=True,  # 🔥 Đổi thành True nếu mobi.vinhuni.edu.vn đã chạy HTTPS
    max_age=3600      # Session tồn tại 1 tiếng
)
# =======================================================
# 3. CÁC HÀM BỔ TRỢ (HELPER) & MODEL
# =======================================================
class LoginRequest(BaseModel):
    username: str
    password: str

class ChangePassRequest(BaseModel):
    student_id: str
    old_pass: str
    new_pass: str

class NotificationRequest(BaseModel):
    student_id: str
    title: str
    content: str
    sender_id: str  # 👈 Đã đổi tên để khớp 100% với Flutter

def clean_student_id(raw_id: str) -> str:
    if not raw_id: return ""
    clean = str(raw_id).strip().upper() 
    
    # 1. Nếu là Cán bộ (Ví dụ: CB1679 hoặc ntson) -> GIỮ NGUYÊN HOÀN TOÀN
    if clean.startswith("CB"):
        return clean
    
    # 2. Nếu là Sinh viên (Ví dụ: SV2057...) -> CẮT SV LẤY SỐ
    if clean.startswith("SV") and clean[2:].isdigit():
        return clean[2:]
        
    # 3. Các trường hợp khác (ntson, 2057...) trả về nguyên bản
    return clean

def verify_aspnet_v3(hashed_pass, raw_pass):
    try:
        decoded = base64.b64decode(hashed_pass)
        salt, stored_key = decoded[13:29], decoded[29:61]
        generated_key = hashlib.pbkdf2_hmac('sha256', raw_pass.encode(), salt, 10000, 32)
        return hmac.compare_digest(generated_key, stored_key)
    except: return False

def get_thu_tieng_viet(ngay_so):
    mapping = {0: "Chủ Nhật", 1: "Thứ 2", 2: "Thứ 3", 3: "Thứ 4", 4: "Thứ 5", 5: "Thứ 6", 6: "Thứ 7"}
    return mapping.get(ngay_so, "N/A")
#--------------------------------------------------------------




# 1. API lấy danh sách chứng chỉ
@app.get("/api/chung-chi")
async def get_cc():
    # Trả về key 'ds_chung_chi' như Flutter mong đợi
    return {"ds_chung_chi": CertificateService.get_list()}

@app.get("/api/dot-thi")
async def get_dt(loai: int):
    # Trả về key 'ds_dot_thi' như Flutter mong đợi
    return {"ds_dot_thi": CertificateService.get_dates(loai)}

@app.post("/api/tra-cuu")
async def do_tra_cuu(request: dict):
    ma_sv = request.get("ma_sv")
    id_cc = int(request.get("loai_chung_chi"))
    id_dot = request.get("dot_thi") # Có thể None
    
    data = CertificateService.search_result(ma_sv, id_cc, id_dot)
    if not data:
        return {"error": "Không tìm thấy dữ liệu", "lich_thi": []}
    
    # Trả về toàn bộ object, trong đó có key 'lich_thi' cho Flutter
    return data
#====================================================
@app.get("/api/check-version")
def check_version():
    """Số phiên bản mới nhất cho từng nền tảng.

    Đọc tệp mỗi lần gọi, nên sửa version_config.json là ứng dụng nhận ngay,
    không phải khởi động lại máy chủ.

    ⚠️ SỬA 19/08/2026, hai điểm:
      • Đổi `async def` → `def`. Đọc tệp là thao tác ĐỒNG BỘ; đặt trong
        `async def` là nó chạy trên vòng lặp sự kiện. Đây là endpoint MỌI lần
        mở ứng dụng đều gọi, nên cũng là chỗ dễ nghẽn nhất.
      • Tệp hỏng hoặc mất thì trước đây ném ngoại lệ thành 500, và ứng dụng
        hiểu là "không kiểm tra được" rồi im lặng. Nay trả lời rõ ràng.
    """
    duong_dan = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                             "version_config.json")
    try:
        with open(duong_dan, "r", encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        print(f"⚠️ [PhiênBản] Không thấy {duong_dan}")
    except json.JSONDecodeError as exc:
        print(f"⚠️ [PhiênBản] version_config.json sai định dạng: {exc}")

    return JSONResponse(
        status_code=503,
        content={"status": "error",
                 "message": "Chưa đọc được thông tin phiên bản trên máy chủ."},
    )
# =======================================================
# 3. API ĐĂNG NHẬP FULL NAME
# =======================================================    
@app.get("/api/get_fullname/{username}")
def get_fullname(username: str):
    identity_username = clean_student_id(username.strip())
    try:
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            # Lấy thêm UserCode để App biết đường mà load ảnh
            sql = "SELECT FullName, RTRIM(UserCode) FROM tbl_Users WHERE UserName = ? OR UserCode = ?"
            cursor.execute(sql, (identity_username, identity_username))
            row = cursor.fetchone()
            if row:
                # Trả về cả tên và mã số định danh
                return {
                    "status": "success", 
                    "full_name": row[0],
                    "numeric_id": str(row[1]).replace("CB", "").replace("SV", "") 
                }
            return {"status": "error", "message": "Không tìm thấy"}
    except Exception as e:
        return {"status": "error", "message": str(e)}    
        
# =======================================================
# 4. API CHECK QUYEN API CHO CAN BO


    
class SelectiveSecurityMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        path = request.url.path
        
        # Lấy Token để phục vụ Watchdog
        auth_header = request.headers.get("Authorization")
        token = auth_header.split(" ")[1] if auth_header and " " in auth_header else auth_header

        # 1. DANH SÁCH SIẾT CHẶT (Chỉ những cái thực sự nhạy cảm)
        sensitive_prefixes = ["/api/staff", "/api/canbo", "/api/v1/chat"] 
        # Lưu ý: Sơn bỏ "/api/admin" ra để nó không bị Middleware chặn 401 vô lý

        is_sensitive = any(path.startswith(p) for p in sensitive_prefixes)
        
        if is_sensitive and not token:
            print(f"🚫 [SECURITY] Chặn API nhạy cảm {path} do thiếu Token.")
            return JSONResponse(status_code=401, content={"message": "Yêu cầu định danh"})

        # 2. WATCHDOG: Theo dõi 1679 ở cả vùng công cộng
        if token:
            # Sơn có thể dùng lại logic truy vấn SQL ở đây để in Log
            pass

        return await call_next(request)

# 🔥 Đăng ký Middleware
app.add_middleware(SelectiveSecurityMiddleware)



@app.post("/api/auth/refresh-ms-token")
def refresh_ms_token(data: dict):
    # ⚠️ SỬA 19/08/2026: đổi từ `async def` sang `def`, và nhận thân yêu cầu
    # qua tham số thay vì `await request.json()`.
    #
    # Mọi truy vấn ở đây dùng pyodbc — thư viện ĐỒNG BỘ. Đặt chúng trong một
    # hàm `async def` nghĩa là chúng chạy thẳng trên vòng lặp sự kiện: một truy
    # vấn chậm chặn TOÀN BỘ máy chủ, không riêng người gọi. Đã gặp thật ngày
    # 19/08/2026 — máy chủ ngừng phục vụ hoàn toàn dù mạng tới cơ sở dữ liệu
    # vẫn thông.
    #
    # Với hàm `def` thường, FastAPI tự chạy nó trong luồng riêng, nên truy vấn
    # chậm chỉ ảnh hưởng đúng yêu cầu đó.
    user_code = data.get("user_code") 

    if not user_code:
        return {"status": "error", "message": "Missing user_code"}

    try:
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            
            # 1. Lấy Refresh Token từ Database
            cursor.execute("SELECT RefreshToken FROM tbl_User_MS_Tokens WHERE UserCode = ?", (user_code,))
            row = cursor.fetchone()
            
            # 🔥 BẮT LỖI MẠNH TAY: Không có dòng nào, HOẶC có dòng nhưng RefreshToken bị NULL
            if not row or not row[0]: 
                print(f"⚠️ [O365] Không tìm thấy RefreshToken cho User: {user_code}")
                return {"status": "error", "message": "No refresh token found"}
            
            refresh_token = row[0]

            # 2. Gọi Microsoft đổi Refresh Token lấy Access Token mới
            token_url = f"https://login.microsoftonline.com/{TENANT_ID}/oauth2/v2.0/token"
            payload = {
                'client_id': CLIENT_ID,
                'client_secret': CLIENT_SECRET,
                'grant_type': 'refresh_token',
                'refresh_token': refresh_token,
                'scope': 'offline_access Files.ReadWrite.All User.Read'
            }
            
            response = requests.post(token_url, data=payload)
            new_tokens = response.json()

            # 3. KỂM TRA NẾU MICROSOFT CẤP PHÉP THÀNH CÔNG
            if "access_token" in new_tokens:
                new_access_token = new_tokens['access_token']
                # Microsoft có thể trả về Refresh Token mới, phải cập nhật luôn
                new_refresh_token = new_tokens.get('refresh_token', refresh_token)
                
                # Dùng .get() bảo vệ phòng hờ Microsoft không trả về 'expires_in'
                expires_in_seconds = new_tokens.get('expires_in', 3600)
                expires_at = datetime.now() + timedelta(seconds=expires_in_seconds)

                # Cập nhật lại Database
                cursor.execute("""
                    UPDATE tbl_User_MS_Tokens 
                    SET AccessToken = ?, RefreshToken = ?, ExpiresAt = ?, UpdatedAt = GETDATE()
                    WHERE UserCode = ?
                """, (new_access_token, new_refresh_token, expires_at, user_code))
                conn.commit()

                print(f"✅ [O365] Đã làm mới Token thành công cho User: {user_code}")
                return {"status": "success", "access_token": new_access_token}
            
            # 4. 🔥 NẾU THẤT BẠI: IN RA LỖI THẬT SỰ CỦA MICROSOFT
            error_desc = new_tokens.get("error_description", "Unknown Error")
            print(f"❌ [O365] Microsoft từ chối cấp Token cho {user_code}. Lý do: {error_desc}")
            
            return {
                "status": "error", 
                "message": "Microsoft rejected the token refresh", 
                "ms_error": new_tokens # Trả về app để app biết đường bắt login lại
            }
            
    except Exception as e:
        print(f"🔥 [CRITICAL] Lỗi hệ thống tại API refresh_ms_token: {str(e)}")
        return {"status": "error", "message": str(e)}        
@app.post("/api/chat/send-notification")
async def proxy_to_producer(data: dict):
    """
    Cầu nối: Nhận yêu cầu từ Internet (8080) và đẩy vào Producer nội bộ (8081)
    """
    try:
        async with httpx.AsyncClient() as client:
            # Gọi nội bộ từ 8080 sang 8081
            response = await client.post(
                "http://127.0.0.1:8081/api/chat/send-notification", 
                json=data,
                timeout=10.0
            )
            return response.json()
    except Exception as e:
        return {"status": "error", "message": f"Không thể kết nối Producer nội bộ: {str(e)}"}
#kiem tra ket nói 8081
limits = httpx.Limits(max_connections=100, max_keepalive_connections=20)
global_client = httpx.AsyncClient(limits=limits, timeout=10.0)

# Cổng 8080 (Public Gateway)


# 🚀 BƯỚC 3: Đóng client khi tắt server để giải phóng tài nguyên
@app.on_event("shutdown")
async def shutdown_event():
    await global_client.aclose()     
# =======================================================
# 4. API ĐĂNG NHẬP FACE (GATEWAY TO 8011) - ĐÃ FIX ROLE
# =======================================================
@app.post("/api/login_by_face")
async def login_face_gateway(
    student_id: str = Form(...),
    photo_front: UploadFile = File(...), 
    photo_pose: UploadFile = File(...)
):
    try:
        # 1. Đọc dữ liệu ảnh
        content_f = await photo_front.read()
        content_p = await photo_pose.read()

        # 2. Gửi sang Server AI (Cổng 8011) để nhận diện
        async with httpx.AsyncClient(timeout=40.0) as client:
            response = await client.post(
                INTERNAL_STUDENT_AI,
                data={"student_id": student_id},
                files={
                    "photo_front": (photo_front.filename, content_f, photo_front.content_type),
                    "photo_pose": (photo_pose.filename, content_p, photo_pose.content_type)
                }
            )
        
        ai_resp = response.json()
        
        # 3. Xử lý khi AI nhận diện thành công
        if ai_resp.get("status") == "SUCCESS" and "student_id" in ai_resp:
             with pyodbc.connect(REMOTE_CONN_STR) as conn:
                cursor = conn.cursor()
                sid = ai_resp["student_id"]
                
                # Truy vấn thông tin chi tiết từ bảng Users nội bộ
                cursor.execute("""
                    SELECT FullName, UserRole, FacultyName, UserType 
                    FROM tbl_Users 
                    WHERE UserCode = ? OR UserCode = 'SV' + ? OR UserCode = 'CB' + ?
                """, (sid, sid, sid))
                row = cursor.fetchone()
                
                if row:
                    db_role_raw = str(row.UserRole).strip() if row.UserRole else ""
                    db_user_code = str(sid).strip().upper()
                    user_type = row.UserType

                    # --- LOGIC PHÂN QUYỀN THÔNG MINH ---
                    # Ép Role chuẩn dựa trên ID (CB...) hoặc UserType trong DB
                    if db_role_raw == "CanBo" or db_user_code.startswith("CB") or user_type == 1 or (db_user_code.isdigit() and len(db_user_code) < 6):
                        final_role = "CanBo"
                    else:
                        final_role = "SinhVien"

                    # 🔥 BƯỚC QUAN TRỌNG NHẤT: Tạo JWT Token cho hệ thống
                    # Hàm create_access_token lấy từ auth/jwt_handler.py
                    system_token = create_access_token(user_id=db_user_code, role=final_role, method="FaceID")

                    # Đóng gói dữ liệu trả về cho App Flutter
                    ai_resp["user_data"] = {
                        "student_id": clean_student_id(sid),
                        "full_name": row.FullName,
                        "user_role": final_role,
                        "role": final_role,
                        "faculty": row.FacultyName,
                        "access_token": system_token  # 🔑 Chìa khóa để App mở Menu/GPA
                    }
                    
                    print(f"📸 [FACE LOGIN] Thành công: {row.FullName} | Role: {final_role}")
        
        return ai_resp

    except Exception as e:
        print(f"❌ Lỗi tại Gateway 8080: {str(e)}") 
        return JSONResponse(status_code=500, content={"status": "ERROR", "message": "Lỗi kết nối Server AI hoặc Database."})

# =======================================================
# 5. API ĐĂNG NHẬP OFFICE 365 - ĐÃ FIX ROLE
# =======================================================

# =============================================================================
# 🔐 HỆ THỐNG ĐĂNG NHẬP MICROSOFT 365 - BẢO MẬT HANDSHAKE (DATABASE VERSION)
# =============================================================================
import uuid
from datetime import datetime, timedelta

# 1. KHỞI ĐỘNG LUỒNG ĐĂNG NHẬP (BẮT BUỘC GET)
@app.get("/login/microsoft")
async def login_microsoft(request: Request):
    print("🎬 [O365] Khởi động luồng đăng nhập Microsoft...")
    # Thêm các scope cần thiết để sau này dùng được OneDrive và Offline Access
    return await oauth.microsoft.authorize_redirect(
        request, 
        REDIRECT_URI, 
        prompt='select_account'
    )

# 2. CALLBACK NHẬN KẾT QUẢ VÀ LƯU VÀO DATABASE (BẮT BUỘC GET)
@app.get("/office365_login")
async def auth_callback(request: Request):
    print("\n" + "="*50)
    print("🎬 [O365_MONITOR] Bắt đầu xử lý Callback từ Microsoft...")
    try:
        # 1. Lấy toàn bộ Token từ Microsoft
        token = await oauth.microsoft.authorize_access_token(request)
        user_info = token.get('userinfo')
        email_365 = user_info.get('email').lower()
        
        # 🔑 Lấy các khóa của Microsoft
        ms_access_token = token.get('access_token')
        ms_refresh_token = token.get('refresh_token')
        expires_in = token.get('expires_in', 3600)
        expires_at = datetime.now() + timedelta(seconds=expires_in)

        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            
            # 2. Tìm kiếm User trong DB nội bộ
            sql = "SELECT RTRIM(UserCode), FullName, RTRIM(UserRole) FROM tbl_Users WHERE LOWER(Email) = ?"
            cursor.execute(sql, (email_365,))
            user = cursor.fetchone()
            
            if not user:
                return HTMLResponse("<h2>Tài khoản Office 365 này chưa được đồng bộ trên App VinhUni.</h2>")

            raw_user_code = str(user[0]).strip().upper() 
            full_name = user[1]
            db_role = str(user[2]).strip().upper() if user[2] else ""

            # 3. PHÂN QUYỀN (Logic cũ của Sơn)
            if db_role == "ADMIN": final_role = "Admin"
            elif db_role == "COVAN": final_role = "CoVan"
            elif raw_user_code.startswith("CB"): final_role = "CanBo"
            else: final_role = "SinhVien"

            # 🔥 4. LƯU MS TOKEN VÀO BẢNG CHUYÊN BIỆT (Sử dụng UPSERT)
            # Điều này giúp làm sạch token cũ và cập nhật token mới nhất
            cursor.execute("""
                IF EXISTS (SELECT 1 FROM tbl_User_MS_Tokens WHERE UserCode = ?)
                    UPDATE tbl_User_MS_Tokens 
                    SET AccessToken = ?, RefreshToken = ?, ExpiresAt = ?, UpdatedAt = GETDATE()
                    WHERE UserCode = ?
                ELSE
                    INSERT INTO tbl_User_MS_Tokens (UserCode, AccessToken, RefreshToken, ExpiresAt)
                    VALUES (?, ?, ?, ?)
            """, (raw_user_code, ms_access_token, ms_refresh_token, expires_at, raw_user_code,
                  raw_user_code, ms_access_token, ms_refresh_token, expires_at))

            # 5. TẠO HANDSHAKE SESSION (Để Flutter lấy thông tin)
            session_token = str(uuid.uuid4())
            cursor.execute("""
                INSERT INTO tbl_Temp_Login_Sessions (SessionToken, UserCode, FullName, UserRole)
                VALUES (?, ?, ?, ?)
            """, (session_token, raw_user_code, full_name, final_role))
            
            conn.commit() 

            # 6. TRẢ VỀ DEEP LINK
            universal_link = f"vinhuni-app://login_success?session_token={session_token}"
            return HTMLResponse(f"""
                <script>window.onload = function() {{ window.location.replace("{universal_link}"); }};</script>
                <body style="text-align:center;padding-top:100px;font-family:sans-serif;">
                    <h2>Xác thực thành công!</h2><p>Đang quay lại ứng dụng...</p>
                </body>
            """)
    except Exception as e:
        print(f"🔥 Lỗi Callback: {e}")
        return HTMLResponse(f"<h3>Lỗi hệ thống: {str(e)}</h3>")

# 3. API XÁC THỰC TOKEN (SỬ DỤNG POST - APP GỌI VÀO ĐÂY ĐỂ LẤY ROLE THẬT)


@app.post("/api/auth/verify-session")
def verify_session(data: dict = Body(...)):
    # 1. Lấy Session Token từ App
    token = data.get("session_token")
    if not token:
        return JSONResponse(status_code=400, content={"message": "Thiếu mã xác thực session_token"})

    try:
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            
            # 2. TRUY VẤN TỔNG HỢP: 
            # Kết hợp Temp (để verify), MS_Tokens (để lấy OneDrive) và Users (để lấy Faculty/Dept/Profile)
            sql = """
                SELECT 
                    T.UserCode, 
                    T.FullName, 
                    T.UserRole, 
                    M.AccessToken as MSAccessToken,
                    U.FacultyName, 
                    U.DepartmentName,
                    U.UserType,
                    RTRIM(U.UserName) as UserName
                FROM tbl_Temp_Login_Sessions T
                LEFT JOIN tbl_User_MS_Tokens M ON T.UserCode = M.UserCode
                LEFT JOIN tbl_Users U ON T.UserCode = U.UserCode
                WHERE T.SessionToken = ?
            """
            cursor.execute(sql, (token,))
            row = cursor.fetchone()

            if row:
                u_id = str(row[0]).strip()
                u_name = row[1]
                u_role = str(row[2]).strip()
                ms_access_token = row[3]  # Chìa khóa OneDrive
                u_faculty = row[4] or ""
                u_dept = row[5] or ""
                u_type = row[6]
                u_username = row[7] or u_id

                # 3. TẠO JWT CHÍNH THỨC CỦA HỆ THỐNG
                # Đảm bảo Middleware nhận diện được người dùng
                real_jwt = create_access_token(user_id=u_id, role=u_role)
                
                # 4. CẬP NHẬT SESSION VÀO BẢNG USERS (Bắt buộc để pass qua các API khác)
                sql_update_user = "UPDATE tbl_Users SET SessionToken = ? WHERE UserCode = ?"
                cursor.execute(sql_update_user, (real_jwt, u_id))

                # 5. TẠO FIREBASE CHAT TOKEN (Cho chức năng Trợ lý/Chat nhóm)
                try:
                    chat_token = auth.create_custom_token(u_id).decode('utf-8')
                    print(f"🔑 [DEBUG TOKEN] {u_id}: {chat_token}")
                except Exception as e:
                    print(f"⚠️ Lỗi tạo Firebase Token: {e}")
                    chat_token = ""

                # 6. DỌN DẸP: Xóa session tạm thời
                cursor.execute("DELETE FROM tbl_Temp_Login_Sessions WHERE SessionToken = ?", (token,))
                conn.commit()

                print(f"✅ [VERIFY SUCCESS] User: {u_name} | Role: {u_role}")

                # 7. TRẢ VỀ FULL DATA CHO FLUTTER (Đúng cấu trúc HomeScreen đang dùng)
                return {
                    "status": "success",
                    "data": {
                        "user_id": u_id,
                        "user_code": u_id,
                        "student_id": u_id,
                        "full_name": u_name,
                        "user_name": u_username,
                        "user_role": u_role,
                        "role": u_role,
                        "user_faculty": u_faculty,
                        "faculty": u_faculty,
                        "department": u_dept,
                        "access_token": real_jwt,         # Token hệ thống
                        "ms_access_token": ms_access_token, # Token OneDrive
                        "firebase_chat_token": chat_token   # Token Chat
                    }
                }
            
            return JSONResponse(status_code=401, content={"status": "error", "message": "Phiên làm việc hết hạn"})

    except Exception as e:
        print(f"🔥 [CRITICAL] Lỗi Verify Session: {str(e)}")
        return JSONResponse(status_code=500, content={"status": "error", "message": f"Lỗi máy chủ: {str(e)}"})


# =======================================================
# 6. API ĐĂNG NHẬP MẬT KHẨU (KIỂM TRA ROLE)
# =======================================================




def get_md5_pass_n_times(password, n):
    """
    Tái hiện hàm GetMD5Pass(string pass, int n) của C#
    Thực hiện băm MD5 liên tiếp n lần.
    """
    if n <= 0: return password # Nếu n=0 thì không băm
    
    st_pass = password
    for i in range(1, n + 1):
        # Mỗi vòng lặp băm chuỗi hiện tại và chuyển thành IN HOA
        st_pass = hashlib.md5(st_pass.encode('utf-8')).hexdigest().upper()
    
    return st_pass

# ==========================================
# CẤU HÌNH IDENTITY SERVER 4 (ĐẠI HỌC VINH)
# ==========================================

# Cần cài đặt: pip install pyodbc

# Thay bằng tên miền sso chuẩn:
IS4_TOKEN_ENDPOINT = "https://sso.vinhuni.edu.vn/connect/token" 
CLIENT_ID = "app-student-pf"
CLIENT_SECRET = "T4yFg5ipMEUp/eJSdt7OIISZI07XQkvVo3LsUwOq1ss="
            
def get_final_role(db_role_raw: str, user_code: str, user_type: int) -> str:
    """Hàm chuẩn hóa Role dựa trên dữ liệu thực tế từ Database"""
    role_upper = db_role_raw.upper().strip()
    code_upper = user_code.upper().strip()
    clean_id = code_upper.replace("SV", "").replace("CB", "")

    if role_upper == "ADMIN": return "Admin"
    if role_upper == "COVAN": return "CoVan"
    # Logic: Có chữ CB, hoặc Role CanBo, hoặc ID ngắn (<6 số)
    if "CANBO" in role_upper or "CB" in role_upper or code_upper.startswith("CB") or user_type == 1 or (clean_id.isdigit() and len(clean_id) < 6):
        return "CanBo"
    return "SinhVien"


@app.post("/api/login")
async def api_login(data: LoginRequest, request: Request):
    raw_username = data.username.strip()
    identity_username = clean_student_id(raw_username)
    password = data.password

    # 1. PHÂN LUỒNG NGƯỜI DÙNG
    is_student = identity_username.isdigit() or identity_username.lower().startswith("sv")

    try:
        if is_student:
            # =================================================================
            # LUỒNG SINH VIÊN (SSO IDENTITY SERVER 4)
            # =================================================================
            print(f"\n--- 🔐 LOGIN SV: '{identity_username}' ---")
            
            payload = {
                "grant_type": "password",
                "client_id": CLIENT_ID,
                "client_secret": CLIENT_SECRET,
                "username": identity_username,
                "password": password,
                "scope": "openid profile offline_access" 
            }
            headers = {"Content-Type": "application/x-www-form-urlencoded"}

            async with httpx.AsyncClient() as client:
                response = await client.post(IS4_TOKEN_ENDPOINT, data=payload, headers=headers)

            if response.status_code != 200:
                return JSONResponse(status_code=401, content={"status": "error", "message": "Tài khoản hoặc mật khẩu không đúng"})

            # Lấy Profile từ Local DB để xác định Role và thông tin cá nhân
            # ⚠️ SỬA 19/08/2026: phần truy vấn được đẩy sang LUỒNG RIÊNG.
            #
            # pyodbc là thư viện đồng bộ. Gọi nó thẳng trong `async def` nghĩa là
            # nó chạy trên vòng lặp sự kiện, và một truy vấn chậm chặn TOÀN BỘ
            # máy chủ — không riêng người đang đăng nhập. Đã gặp thật hôm nay:
            # máy chủ ngừng phục vụ hoàn toàn dù mạng tới cơ sở dữ liệu vẫn thông.
            #
            # Đây là endpoint MỌI sinh viên đều đi qua, nên cũng là chỗ nguy hiểm
            # nhất nếu để nghẽn.
            #
            # Nội dung bên trong giữ nguyên từng dòng, chỉ lùi vào một cấp.
            def _lay_ho_so_sinh_vien():
                with pyodbc.connect(REMOTE_CONN_STR) as conn:
                    cursor = conn.cursor()
                    sql_profile = """
                        SELECT RTRIM(UserCode), FullName, UserType, RTRIM(UserRole), 
                               FacultyName, DepartmentName, RTRIM(UserName)
                        FROM tbl_Users 
                        WHERE RTRIM(UserName) = ? OR RTRIM(UserCode) = ? OR RTRIM(UserCode) = 'SV' + ?
                    """
                    cursor.execute(sql_profile, (identity_username, identity_username, identity_username))
                    profile = cursor.fetchone()

                    if not profile:
                        return JSONResponse(status_code=403, content={"status": "error", "message": "Hồ sơ chưa đồng bộ."})

                    db_user_code = str(profile[0]).strip()
                    db_role_raw = str(profile[3] or "").strip()
                    user_type = profile[2]

                    # --- LOGIC PHÂN QUYỀN CHUẨN ---
                    if db_role_raw == "CanBo" or db_user_code.startswith("CB") or user_type == 1:
                        final_role = "CanBo"
                    else:
                        final_role = "SinhVien"

                    # 🔥 TẠO JWT ACCESS TOKEN CHO HỆ THỐNG
                    system_access_token = create_access_token(user_id=db_user_code, role=final_role, method="Password")

                    # 🛡️ BƯỚC MỚI: LƯU TOKEN VÀO DATABASE ĐỂ MIDDLEWARE KIỂM TRA
                    cursor.execute("UPDATE tbl_Users SET SessionToken = ? WHERE UserCode = ?", (system_access_token, db_user_code))
                    conn.commit()

                    # Tạo Chat Token (Firebase)
                    try: chat_token = auth.create_custom_token(db_user_code).decode('utf-8')
                    except: chat_token = ""

                    user_data = {
                        "student_id": db_user_code,
                        "user_code": db_user_code,
                        "user_name": str(profile[6] or "").strip() or identity_username,
                        "full_name": profile[1],
                        "user_role": final_role,
                        "role": final_role,
                        "faculty": profile[4],
                        "department": profile[5],
                        "access_token": system_access_token, # Gửi Token này cho App
                        "firebase_chat_token": chat_token
                    }
                
                    print(f"🎉 SINH VIÊN OK: {user_data['full_name']} | SessionToken đã lưu.")
                
                    return {"status": "success", "message": "Đăng nhập thành công", "data": user_data}

            return await run_in_threadpool(_lay_ho_so_sinh_vien)

        else:
            # Nhánh cán bộ chỉ có truy vấn, không có await — đẩy sang
            # luồng riêng vì lý do đã nói ở nhánh sinh viên.
            def _dang_nhap_can_bo():
                # =================================================================
                # LUỒNG CÁN BỘ (XÁC THỰC SQL SERVER .26)
                # =================================================================
                STAFF_DB_CONN = settings.staff_db.conn_str
            
                with pyodbc.connect(STAFF_DB_CONN) as conn:
                    cursor = conn.cursor()
                    sql_info = "SELECT HS_ID, HS_TruyCap_MatKhau_Khoa, (HS_Ho + ' ' + HS_Ten) FROM tbl_CANBO_HoSo WHERE HS_TruyCap_TenDangNhap = ?"
                    cursor.execute(sql_info, (raw_username,))
                    row = cursor.fetchone()

                    if not row:
                        return JSONResponse(status_code=401, content={"status": "error", "message": "Tài khoản không tồn tại"})

                    hs_id, n_iter, full_name = row[0], int(row[1]) if row[1] else 0, row[2]
                    hashed_pw = get_md5_pass_n_times(password, n_iter)

                    cursor.execute("SELECT HS_ID FROM tbl_CANBO_HoSo WHERE HS_ID = ? AND HS_TruyCap_MatKhau = ?", (hs_id, hashed_pw))
                    if not cursor.fetchone():
                        return JSONResponse(status_code=401, content={"status": "error", "message": "Sai mật khẩu"})

                    user_code_mapped = f"CB{str(hs_id).strip()}"

                    # Lấy Profile chi tiết từ DB cục bộ
                    with pyodbc.connect(REMOTE_CONN_STR) as conn_local:
                        cursor_local = conn_local.cursor()
                        cursor_local.execute("""
                            SELECT RTRIM(UserCode), FullName, UserType, RTRIM(UserRole), 
                                   FacultyName, DepartmentName, RTRIM(UserName)
                            FROM tbl_Users WHERE LTRIM(RTRIM(UserCode)) = ?
                        """, (user_code_mapped,))
                        p = cursor_local.fetchone()

                        final_role = str(p[3] or "CanBo").strip() if p else "CanBo"
                    
                        # 🔥 TẠO JWT ACCESS TOKEN CHO CÁN BỘ
                        system_access_token = create_access_token(user_id=user_code_mapped, role=final_role, method="Password")

                        # 🛡️ BƯỚC MỚI: LƯU TOKEN VÀO DATABASE CỤC BỘ ĐỂ MIDDLEWARE KIỂM TRA
                        cursor_local.execute("UPDATE tbl_Users SET SessionToken = ? WHERE UserCode = ?", (system_access_token, user_code_mapped))
                        conn_local.commit()

                        try: chat_token = auth.create_custom_token(user_code_mapped).decode('utf-8')
                        except: chat_token = ""

                        user_data = {
                            "student_id": p[0] if p else user_code_mapped,
                            "user_code": p[0] if p else user_code_mapped,
                            "user_name": str(p[6] or "").strip() if (p and p[6]) else raw_username,
                            "full_name": p[1] if p else full_name,
                            "user_role": final_role,
                            "role": final_role,
                            "faculty": p[4] if (p and p[4]) else "Cán bộ",
                            "department": p[5] if (p and p[5]) else "Trường Đại học Vinh",
                            "access_token": system_access_token, # Token bảo mật thực tế
                            "firebase_chat_token": chat_token
                        }
                        print("\n" + "🚀" * 5 + " MÃ VÀO CHAT (FIREBASE) " + "🚀" * 5)
                        print(chat_token, flush=True)
                        print("🚀" * 25 + "\n")
                        print(f"🎉 CÁN BỘ OK: {user_data['full_name']} | Role: {final_role} | SessionToken đã lưu.")
                        return {"status": "success", "data": user_data}

            return await run_in_threadpool(_dang_nhap_can_bo)

    except Exception as e:
        print(f"🔥 LỖI LOGIN: {str(e)}")
        return JSONResponse(status_code=500, content={"status": "error", "message": "Lỗi hệ thống máy chủ"})
@app.get("/login-success")
async def login_success_page(user_id: str, name: str, role: str):
    # Xác định role cuối cùng (đảm bảo không bị lỗi undefined biến final_role)
    final_role = role 
    
    # Tạo link redirect về App Flutter
    d_link = f"vinhuni-app://login_success?user_id={user_id}&name={name}&role={final_role}&user_role={final_role}"
    
    content = f"""
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
            <meta http-equiv="Pragma" content="no-cache">
            <meta http-equiv="Expires" content="0">
            <title>VinhUni Redirect</title>
        </head>
        <body style="text-align:center; padding-top:100px; font-family:sans-serif; background:#f4f7f9;">
            <div style="max-width:300px; margin:auto; padding:20px; background:white; border-radius:15px; shadow: 0 4px 6px rgba(0,0,0,0.1);">
                <h2 style="color:#0054A6; margin-bottom:10px;">Xác thực xong!</h2>
                <p style="color:#666;">Hệ thống đang mở ứng dụng VinhUni...</p>
                <div style="margin-top:20px; color:#999; font-size:12px;">Đang xử lý tài khoản: {user_id}</div>
            </div>
            
            <script>
                // 1. Xóa sạch dấu vết trên URL trình duyệt ngay lập tức để lần sau không bị nhảy vào account cũ
                if (window.history.replaceState) {{
                    window.history.replaceState(null, null, window.location.pathname);
                }}

                let launched = false;
                function launchApp() {{
                    if (launched) return;
                    launched = true;

                    // 2. Ép trình duyệt mở Custom Scheme
                    window.location.href = "{d_link}";
                    
                    // 3. Tự động đóng tab sau 2.5 giây nếu không chuyển hướng được
                    setTimeout(function() {{
                        document.body.innerHTML = '<h3>Đăng nhập hoàn tất.</h3><p>Vui lòng quay lại ứng dụng VinhUni.</p>';
                        // Cố gắng đóng cửa sổ (chỉ chạy nếu window được mở bằng script)
                        window.close();
                    }}, 2500);
                }}
                window.onload = launchApp;
            </script>
        </body>
        </html>
    """
    
    # Trả về kèm Header chống Cache ở mức độ cao nhất
    return HTMLResponse(content=content, headers={
        "Cache-Control": "no-cache, no-store, must-revalidate",
        "Pragma": "no-cache",
        "Expires": "0"
    })

# =======================================================
# 7. API GỬI THÔNG BÁO (CÁN BỘ)
# =======================================================
@app.post("/api/admin/send-personal-notification")
def send_personal_notification(data: NotificationRequest):
    try:
        # 1. Làm sạch ID sinh viên nhận (Vẫn giữ nguyên để khớp DB sinh viên)
        recipient_id = str(data.student_id).strip().upper().replace("SV", "").replace("CB", "")
        
        # 2. Xử lý ID cán bộ gửi (Lấy mã gốc từ Flutter)
        raw_sender_id = str(data.sender_id).strip().upper()
        # Tạo thêm 1 bản "sạch" (không có CB) để dự phòng
        clean_sender_id = raw_sender_id.replace("CB", "").replace("SV", "")
        
        print(f"🔍 Debug Tìm Kiếm: Gốc='{raw_sender_id}', Sạch='{clean_sender_id}'")

        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            sender_display_name = "Cán bộ hệ thống"

            # 3. TRUY VẤN THÔNG MINH: Thử tìm mã gốc TRƯỚC, mã sạch SAU
            sql_find_user = """
                SELECT FullName FROM tbl_Users 
                WHERE UserCode = ? OR UserCode = ? OR UserCode = ?
            """
            # Thử với: "CB1679", "1679", và trường hợp nếu DB lưu "1679" mà Flutter gửi "1679"
            cursor.execute(sql_find_user, (raw_sender_id, clean_sender_id, f"CB{clean_sender_id}"))
            user_row = cursor.fetchone()
            
            if user_row and user_row[0]:
                sender_display_name = user_row[0]
                print(f"✅ Đã tìm thấy tên cán bộ: {sender_display_name}")
            else:
                print(f"⚠️ Vẫn không tìm thấy tên cán bộ trong DB.")

            # 4. Lưu vào hàng đợi
            summary = (data.content[:495] + '...') if len(data.content) > 500 else data.content
            sql_insert = """
                INSERT INTO tbl_Notification_Queue 
                (StudentId, Title, Body, Category, Summary, IsSent, CreatedAt, IsRead, Sender) 
                VALUES (?, ?, ?, 'PERSONAL', ?, 0, GETDATE(), 0, ?);
            """
            cursor.execute(sql_insert, (recipient_id, data.title, data.content, summary, sender_display_name))
            conn.commit()

            return {"status": "success", "sender": sender_display_name}
                
    except Exception as e:
        print(f"💥 Lỗi: {str(e)}")
        return JSONResponse(status_code=500, content={"status": "error", "message": str(e)})

# =======================================================
@app.post("/api/login_by_face_pro")
async def login_face_pro(photo_front: UploadFile = File(...)):
    print("\n" + "="*50)
    print("📸 [FACE_MONITOR] Bắt đầu nhận diện khuôn mặt Pro...")
    try:
        content_f = await photo_front.read()

        # 1. Gọi sang AI Server để tìm kiếm khuôn mặt
        async with httpx.AsyncClient(timeout=60.0) as client:
            response = await client.post(
                "http://127.0.0.1:8011/internal/search_face_1n",
                files={"photo_front": (photo_front.filename, content_f, photo_front.content_type)}
            )
        
        ai_resp = response.json()
        student_id = ai_resp.get("student_id")
        status = ai_resp.get("status")

        if status == "SUCCESS" and student_id:
            # 2. KIỂM TRA LẠI DỮ LIỆU TỪ SQL SERVER (Không tin hoàn toàn vào AI Server)
            with pyodbc.connect(REMOTE_CONN_STR) as conn:
                cursor = conn.cursor()
                # Truy vấn thông tin chuẩn từ DB
                cursor.execute("""
                    SELECT FullName, UserRole, FacultyName, UserType 
                    FROM tbl_Users 
                    WHERE UserCode = ? OR UserCode = 'SV' + ? OR UserCode = 'CB' + ?
                """, (student_id, student_id, student_id))
                row = cursor.fetchone()

                if row:
                    db_role_raw = str(row.UserRole).strip() if row.UserRole else ""
                    db_user_code = str(student_id).strip().upper()
                    full_name = row.FullName

                    # 🕵️ HỆ THỐNG GIÁM SÁT ĐỐI TƯỢNG (Ví dụ: Lê Văn Tài)
                    is_monitored = "TAI" in full_name.upper() or "1679" in db_user_code
                    if is_monitored:
                        print(f"🚩 [ALERT] PHÁT HIỆN ĐỐI TƯỢNG GIÁM SÁT: {full_name} ({db_user_code})")
                        print(f"🚩 [METHOD] Đang đăng nhập bằng FACE ID PRO")

                    # 3. ÉP ROLE CHUẨN (Cán bộ / Sinh viên)
                    if db_role_raw == "CanBo" or db_user_code.startswith("CB") or row.UserType == 1:
                        final_role = "CanBo"
                    else:
                        final_role = "SinhVien"

                    # 🔥 4. TẠO JWT TOKEN CHÍNH THỨC (Gắn nhãn Method: FaceID)
                    system_token = create_access_token(
                        user_id=db_user_code, 
                        role=final_role, 
                        method="FaceID" 
                    )

                    # 🛡️ BƯỚC MỚI: CẬP NHẬT TOKEN VÀO DATABASE ĐỂ TRẠM GÁC (MIDDLEWARE) KIỂM TRA
                    cursor.execute("UPDATE tbl_Users SET SessionToken = ? WHERE UserCode = ?", (system_token, db_user_code))
                    conn.commit()

                    ai_resp["login_method"] = "FACE_ID_PRO"
                    ai_resp["user_data"] = {
                        "student_id": db_user_code,
                        "user_code": db_user_code,
                        "full_name": full_name,
                        "user_role": final_role,
                        "role": final_role,
                        "faculty": row.FacultyName,
                        "access_token": system_token # 🔑 Chìa khóa để App mở Menu
                    }
                    
                    print(f"✅ [FACE OK] User: {db_user_code} | Role: {final_role} | SessionToken đã lưu thành công.")
                else:
                    print(f"⚠️ [FACE ERROR] AI nhận diện ra {student_id} nhưng không tìm thấy trong SQL!")
                    return {"status": "ERROR", "message": "Dữ liệu AI không khớp với hệ thống."}
        
        print("="*50)
        return ai_resp

    except Exception as e:
        print(f"🔥 [CRITICAL] Lỗi Gateway Pro: {e}")
        return JSONResponse(status_code=500, content={"status": "ERROR", "message": "Lỗi hệ thống Server AI nội bộ."})
# =======================================================
# 5. API DỮ LIỆU (LỊCH, ĐIỂM...) - GIỮ NGUYÊN
# =======================================================

@app.get("/api/get-filters/{student_id}")
def api_get_filters(student_id: str):
    try:
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            sql = """
                SELECT DISTINCT 
                    CAST(hk.NamHoc AS VARCHAR) + '-' + CAST(hk.NamHoc + 1 AS VARCHAR) AS TenNam, 
                    hk.Ten AS TenKy,
                    CAST(s.value AS INT) AS TuanThu
                FROM tbl_HeThong_HocKy hk
                INNER JOIN tbl_Tkb_LopHocPhan lhp ON hk.Id = lhp.IdHocKy
                INNER JOIN tbl_Tkb_LopHocPhan_LichHoc tkb ON lhp.Id = tkb.IdLopHocPhan
                CROSS APPLY STRING_SPLIT(REPLACE(tkb.TuanHocFulls, ' ', ''), ',') s
                WHERE hk.NamHoc >= 2020
                ORDER BY TenNam DESC, TenKy DESC, TuanThu ASC
            """
            cursor.execute(sql)
            return [{"nam": r[0], "ky": r[1], "tuan": r[2]} for r in cursor.fetchall()]
    except: return []

@app.get("/api/get-schedule/{student_id}")
def api_get_schedule(
    student_id: str, 
    nam_hoc: str = Query(None), 
    hoc_ky: str = Query(None), 
    tuan: str = Query(None),
    program_id: str = Query("ALL")
):
    try:
        sid = clean_student_id(student_id)
        params = [sid, sid]
        f_sql = ""
        
        # Logic lọc dữ liệu (Giữ nguyên của Sơn)
        if nam_hoc and nam_hoc != "ALL": 
            f_sql += " AND hk.NamHoc = ?"
            params.append(nam_hoc.split('-')[0])
        if hoc_ky and hoc_ky != "ALL":
            f_sql += " AND hk.HocKy = ?"
            params.append(hoc_ky.replace("Học kỳ ", "").split(".")[0])
        if tuan and tuan != "": 
            f_sql += " AND CAST(s.value AS INT) = ?"
            params.append(int(tuan))
        if program_id and program_id != "ALL":
            f_sql += " AND ct.IdChuongTrinhDaoTao = ?"
            params.append(int(program_id))

        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            
            # 🔥 Giải pháp: Đưa toàn bộ biểu thức tính ngày vào SELECT và ORDER BY theo vị trí (Column Index)
            sql = f"""
                SELECT DISTINCT 
                    lhp.Ten,                    -- r[0]
                    tkb.NgayHoc,                -- r[1]
                    tkb.MaPhong,                -- r[2]
                    tkb.TietHoc,                -- r[3]
                    tkb.SoTiet,                 -- r[4]
                    ISNULL(u.FullName, tkb.MaCanBo), -- r[5]
                    DATEADD(DAY, (CAST(s.value AS INT) - 1) * 7 + (CASE WHEN tkb.NgayHoc = 0 THEN 6 ELSE tkb.NgayHoc - 1 END), hk.TuNgay) AS NgayHocXac, -- r[6]
                    lhp.Code                    -- r[7] (MaLopHP quan trọng cho Flutter)
                FROM viewDSSinhVienDangKyHoc dk
                INNER JOIN tbl_Tkb_LopHocPhan lhp ON RTRIM(dk.MaLopHP) = RTRIM(lhp.Code)
                INNER JOIN tbl_HeThong_HocKy hk ON lhp.IdHocKy = hk.Id
                INNER JOIN tbl_Tkb_LopHocPhan_LichHoc tkb ON lhp.Id = tkb.IdLopHocPhan
                CROSS APPLY STRING_SPLIT(REPLACE(tkb.TuanHocFulls, ' ', ''), ',') s
                LEFT JOIN tbl_HocPhan hp ON lhp.IdHocPhan = hp.Id
                LEFT JOIN tbl_ChuongTrinhDaoTao_HocPhan ct ON hp.Id = ct.IdHocPhan 
                LEFT JOIN tbl_Users u ON (
                    REPLACE(REPLACE(RTRIM(tkb.MaCanBo), 'CB', ''), 'SV', '') = 
                    REPLACE(REPLACE(RTRIM(u.UserCode), 'CB', ''), 'SV', '')
                )
                WHERE (RTRIM(dk.IdNguoiHoc) = ? OR RTRIM(dk.IdNguoiHoc) = 'SV' + ?)
                  AND lhp.IsDeleted = 0 
                  AND tkb.IsDeleted = 0
                {f_sql}
                ORDER BY NgayHocXac ASC  -- Sắp xếp theo Alias đã có trong SELECT DISTINCT
            """
            cursor.execute(sql, tuple(params))
            rows = cursor.fetchall()

            return [{
                "TenHocPhan": r[0],
                "MaLopHP": r[7], # 🚩 Trả về MaLopHP cho Flutter
                "NgayThi": f"{get_thu_tieng_viet(r[1])} - {r[6].strftime('%d/%m/%Y')}" if r[6] else "N/A",
                "NoiDung": (
                    f"GV: {r[5]} | "
                    f"Phòng: {r[2]} | "
                    f"Tiết: {r[3] + 1}-{r[3] + r[4]} ({r[4]} tiết)"
                )
            } for r in rows]
            
    except Exception as e:
        print(f"🔥 Lỗi Schedule: {e}")
        return []

@app.get("/api/get-exams/{student_id}")
def api_get_exams(
    student_id: str, 
    nam_hoc: str = Query(None), 
    hoc_ky: str = Query(None),
    program_id: str = Query("ALL")
):
    try:
        # Làm sạch ID sinh viên (Xóa khoảng trắng, chuyển hoa)
        sid = student_id.strip().upper()
        if sid.startswith("SV"):
            sid_no_prefix = sid[2:]
            sid_with_prefix = sid
        else:
            sid_no_prefix = sid
            sid_with_prefix = "SV" + sid

        params = [sid_no_prefix, sid_with_prefix]
        f_sql = ""
        
        # Xử lý bộ lọc Năm học (Ví dụ: 2025-2026 -> lấy 2025)
        if nam_hoc and nam_hoc != "ALL": 
            year_val = nam_hoc.split('-')[0]
            f_sql += " AND hk.NamHoc = ?"
            params.append(year_val)
            
        # Xử lý bộ lọc Học kỳ
        if hoc_ky and hoc_ky != "ALL": 
            f_sql += " AND hk.Ten = ?"
            params.append(hoc_ky)

        # Sử dụng kết nối đến VinhUni_Local
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            
            # SQL JOIN đa tầng - Chuyển sang LEFT JOIN ở các bảng Local để tránh mất dữ liệu
            sql = f"""
                SELECT DISTINCT 
                    ISNULL(lhp.Ten, N'Học phần mới (Chưa đồng bộ)') as TenHocPhan, 
                    thi.NgayThi, 
                    ca.ThoiGianBatDau, 
                    tsv.SoBaoDanh,
                    ISNULL(ph.Code, N'P.' + CAST(thi.PhongThiSo AS NVARCHAR(10))) AS TenPhong,
                    ISNULL(htt.Ten, N'Tự luận') as TenHinhThuc,
                    ISNULL(ph.IdDm_CoSoDaoTao, 1) as IdCoSo
                FROM tbl_Thi_SinhVien tsv 
                INNER JOIN tbl_Thi_DanhSachThi thi ON tsv.IdDanhSachThi = thi.Id 
                LEFT JOIN tbl_Thi_CaThi ca ON thi.IdCaThi = ca.Id 
                -- 🔥 Đổi sang LEFT JOIN để nếu chưa đồng bộ môn học vẫn hiện lịch thi
                LEFT JOIN tbl_Tkb_LopHocPhan lhp ON tsv.InstanceIdLopHocPhan = lhp.InstanceId
                LEFT JOIN tbl_HeThong_HocKy hk ON lhp.IdHocKy = hk.Id
                -- Lấy dữ liệu từ server từ xa .200
                LEFT JOIN [172.16.95.200].[DHVINH_Stagging_Thi].[dbo].[tbl_thi_HinhThucThi] htt 
                    ON ca.IdHinhThucThi = htt.Id
                LEFT JOIN (
                    SELECT CAST(InstanceId AS NVARCHAR(100)) as RemoteIID, Code, IdDm_CoSoDaoTao 
                    FROM [172.16.95.200].[DHVINH_Stagging_DBTaiNguyen].[dbo].[tbl_Dm_PhongHoc]
                ) AS ph ON CAST(thi.InstanceIdPhong AS NVARCHAR(100)) = ph.RemoteIID
                WHERE (RTRIM(tsv.IdNguoiHoc) = ? OR RTRIM(tsv.IdNguoiHoc) = ?)
                  AND tsv.IsDeleted = 0 AND thi.IsDeleted = 0
                {f_sql}
                ORDER BY thi.NgayThi ASC
            """
            
            # Log để kiểm tra (Sơn có thể xem ở terminal chạy Python)
            print(f"🚀 [EXAM CHECK] Student: {sid} | Params: {params}")
            
            cursor.execute(sql, tuple(params))
            rows = cursor.fetchall()
            
            results = []
            for r in rows:
                results.append({
                    "TenHocPhan": r[0],
                    "NgayThi": r[1].strftime('%d/%m/%Y') if r[1] else "--",
                    "Phong": r[4],
                    "Gio": str(r[2])[:5] if r[2] else "--",
                    "SBD": r[3] or "--",
                    "HinhThucThi": r[5],
                    "IDDM_Cosodaotao": r[6],
                    "NoiDung": f"Hình thức: {r[5]} | Cơ sở: {r[6]}"
                })
            
            return results

    except Exception as e:
        print(f"🔥 Lỗi Exam chi tiết: {e}")
        return []

@app.get("/api/get-grades/{student_id}")
def api_get_grades(
    student_id: str, 
    nam_hoc: str = Query(None), 
    hoc_ky: str = Query(None),
    program_id: str = Query("ALL")
):
    try:
        sid = clean_student_id(student_id)
        
        # CHỈ KHỞI TẠO 2 THAM SỐ GỐC: sid và program_id
        params = [sid, program_id]
        
        f_sql = ""
        if nam_hoc and nam_hoc != "ALL": 
            f_sql += " AND hk.NamHoc = ?"
            params.append(nam_hoc.split('-')[0])
        if hoc_ky and hoc_ky != "ALL": 
            f_sql += " AND hk.Ten = ?"
            params.append(hoc_ky)

        # SQL rút gọn số lượng dấu ?: Chỉ dùng 2 dấu ? ở đầu
        sql = f"""
            DECLARE @sid NVARCHAR(50) = ?;        -- Dấu ? thứ 1
            DECLARE @input_prog NVARCHAR(50) = ?; -- Dấu ? thứ 2
            
            DECLARE @target_prog INT = NULL;
            IF @input_prog <> 'ALL' 
                SET @target_prog = TRY_CAST(@input_prog AS INT);
            ELSE 
                SELECT TOP 1 @target_prog = ct.IdChuongTrinhDaoTao 
                FROM DiemHocPhan d
                INNER JOIN tbl_HocPhan hp ON d.IdHocPhan = hp.InstanceId
                INNER JOIN tbl_ChuongTrinhDaoTao_HocPhan ct ON hp.Id = ct.IdHocPhan
                WHERE (d.IdNguoiHoc = @sid OR d.IdNguoiHoc = 'SV' + @sid) AND ct.IsDeleted = 0;

            SELECT 
                lhp.Ten, 
                MAX(ISNULL(ct.SoTinChi, hp.SoTinChi)) as SoTinChi, 
                d.Diem, d.DiemHe4, d.DiemChu,
                (SELECT STUFF((
                    SELECT ' | ' + CASE 
                        WHEN UPPER(CAST(dtp.IdLoaiDiem AS NVARCHAR(50))) = '3854768B-8EED-4577-80FF-C1AA69591CD7' THEN N'CC'
                        WHEN UPPER(CAST(dtp.IdLoaiDiem AS NVARCHAR(50))) = '8120D054-D282-49AE-B014-4D8DC7807686' THEN N'GK'
                        WHEN UPPER(CAST(dtp.IdLoaiDiem AS NVARCHAR(50))) = '1C114810-2EEB-4B9B-A6B0-9E608E44218D' THEN N'Thi'
                        ELSE N'TP'
                    END + ': ' + CAST(dtp.Diem AS NVARCHAR(10))
                    FROM Diem_ThanhPhan dtp
                    WHERE dtp.IdDiem = d.Id AND dtp.IsDeleted = 0
                    FOR XML PATH('')), 1, 3, '')
                ) as DiemChiTiet
            FROM DiemHocPhan d
            INNER JOIN tbl_Tkb_LopHocPhan lhp ON d.IdLopHocPhan = lhp.InstanceId 
            LEFT JOIN tbl_HocPhan hp ON d.IdHocPhan = hp.InstanceId
            LEFT JOIN tbl_HeThong_HocKy hk ON lhp.IdHocKy = hk.Id
            LEFT JOIN tbl_ChuongTrinhDaoTao_HocPhan ct ON hp.Id = ct.IdHocPhan AND ct.IsDeleted = 0
            WHERE (RTRIM(d.IdNguoiHoc) = @sid OR RTRIM(d.IdNguoiHoc) = 'SV' + @sid)
            AND (ct.IdChuongTrinhDaoTao = @target_prog OR @target_prog IS NULL)
            {f_sql}
            GROUP BY d.Id, lhp.Ten, d.Diem, d.DiemHe4, d.DiemChu, d.Created
            ORDER BY d.Created DESC
        """

        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            cursor.execute(sql, tuple(params)) #
            rows = cursor.fetchall()
            
            return [{
                "TenHocPhan": r[0], # lhp.Ten
                "NgayThi": f"Tổng kết: {r[2]} ({r[4]})", # Hệ 10 và Điểm chữ
                # Bổ sung "Hệ 4: {r[3]}" vào đây để Flutter có thể bóc tách
                "NoiDung": f"TC: {r[1]} | Hệ 4: {r[3] or '0.0'} | {r[5] or 'Đang cập nhật'}"
            } for r in rows]
            
    except Exception as e:
        print(f"🔥 Lỗi API Grades: {e}")
        return []

@app.post("/api/change-password")
def api_change_password(data: ChangePassRequest):
    try:
        sid = clean_student_id(data.student_id)
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            sql_check = f"SELECT PasswordHash FROM OPENQUERY([172.16.95.200], 'SELECT PasswordHash FROM DHVINH_Stagging_Core.Identityserver.Users WHERE UserName = ''{sid}''')"
            cursor.execute(sql_check)
            row = cursor.fetchone()
            if not row or not verify_aspnet_v3(row.PasswordHash, data.old_pass):
                return JSONResponse(status_code=400, content={"status": "error", "message": "Mật khẩu cũ không đúng"})
            return {"status": "success", "message": "Đổi mật khẩu thành công!"}
    except Exception as e:
        return JSONResponse(status_code=500, content={"status": "error", "message": "Lỗi hệ thống"})



# Đường dẫn ảnh mặc định (Sơn kiểm tra file này có tồn tại trong thư mục web/ chưa nhé)
DEFAULT_AVATAR = "image/logo.png"

# 🔥 THỐNG NHẤT: Dùng gạch ngang (-) cho tất cả các route avatar
@app.get("/api/get-avatar/{student_id}") # Kiểu 1: /api/get-avatar/1679
@app.get("/api/get-avatar/")            # Kiểu 2: /api/get-avatar/?student_id=1679
def get_student_avatar(student_id: str = None, v: str = None):
    """
    Hàm lấy avatar thống nhất dùng dấu gạch ngang.
    Nhận student_id từ đường dẫn hoặc query parameter.
    """
    # 1. Kiểm tra ID hợp lệ
    if not student_id or str(student_id).lower() in ["", "null", "undefined", "none"]:
        if os.path.exists(DEFAULT_AVATAR):
            return FileResponse(DEFAULT_AVATAR)
        return JSONResponse(status_code=404, content={"message": "ID không hợp lệ"})

    # 2. Làm sạch ID (Ví dụ: SV1679 -> 1679)
    sid = str(student_id).strip().upper().replace("SV", "").replace("CB", "")
    target_file = None

    # 3. Tìm tên file trong Database
    try:
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            sql = """
                SELECT TenFileAnh FROM tbl_Users 
                WHERE RTRIM(UserCode) = ? 
                OR RTRIM(UserCode) = 'CB' + ? 
                OR RTRIM(UserCode) = 'SV' + ?
            """
            cursor.execute(sql, (sid, sid, sid))
            row = cursor.fetchone()
            if row and row[0]:
                target_file = row[0]
    except Exception as e:
        print(f"🔥 Lỗi DB lấy avatar cho {sid}: {e}")

    # 4. Kiểm tra file vật lý trên ổ cứng
    paths_to_check = []
    if target_file:
        paths_to_check.append(os.path.join(IMAGE_FOLDER, target_file))
    
    # Thử các định dạng phổ biến nếu DB không có tên file chuẩn
    for ext in [".jpg", ".png", ".jpeg", ".JPG", ".PNG"]:
        paths_to_check.append(os.path.join(IMAGE_FOLDER, f"{sid}{ext}"))

    # Trả về file đầu tiên tìm thấy
    for img_path in paths_to_check:
        if os.path.exists(img_path):
            return FileResponse(img_path)

    # 5. Nếu không thấy gì, trả về ảnh mặc định
    if os.path.exists(DEFAULT_AVATAR):
        return FileResponse(DEFAULT_AVATAR)
    
    return JSONResponse(status_code=404, content={"message": "Không tìm thấy ảnh"})
#======Hàm hiện thông báo chi tiêt

# =========================================================
# API LẤY THỐNG KÊ HỌC TẬP CHO TRANG CHỦ (GPA 2.73, Tín chỉ 142)
# =========================================================
@app.get("/api/academic-stats/{student_id}")
async def get_academic_stats(student_id: str):
    try:
        # Bây giờ db_service đã được định nghĩa, sẽ không còn lỗi NameError
        stats = db_service.get_student_academic_stats(student_id)
        
        if not stats:
            return JSONResponse(
                status_code=404, 
                content={"status": "error", "message": "Không tìm thấy dữ liệu"}
            )
            
        return stats
        
    except Exception as e:
        print(f"🔥 Lỗi API Academic Stats: {e}")
        return JSONResponse(status_code=500, content={"message": str(e)})
# --- HÀM CẬP NHẬT ẢNH ĐẠI DIỆN
@app.post("/api/update-face-vector")
async def update_face_vector(
    student_id: str = Form(...),
    photo: UploadFile = File(...)
):
    try:
        print(f"🔄 Đang cập nhật khuôn mặt cho: {student_id}")
        
        # Bước 1: Gửi ảnh sang Server AI (8011) để trích xuất Vector
        photo_content = await photo.read()
        async with httpx.AsyncClient(timeout=30.0) as client:
            ai_response = await client.post(
                "http://127.0.0.1:8011/internal/extract_vector",
                files={"photo": (photo.filename, photo_content, photo.content_type)}
            )
        
        ai_result = ai_response.json()
        if ai_result.get("status") != "SUCCESS":
            return JSONResponse(status_code=400, content=ai_result)

        # Bước 2: Nhận Vector (dạng list) và chuyển thành bytes để lưu vào SQL
        face_vector = np.array(ai_result["vector"], dtype=np.float32).tobytes()

        # Bước 3: Lưu vào bảng tbl_Users (Cột Vector_bin)
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            sql_update = """
                UPDATE tbl_Users 
                SET Vector_bin = ?, LastSync = GETDATE() 
                WHERE UserCode = ? OR UserCode = 'SV' + ? OR UserCode = 'CB' + ?
            """
            cursor.execute(sql_update, (pyodbc.Binary(face_vector), student_id, student_id, student_id))
            conn.commit()

        return {"status": "SUCCESS", "message": "Cập nhật khuôn mặt thành công!"}

    except Exception as e:
        print(f"🔥 Lỗi cập nhật Face Vector: {str(e)}")
        return JSONResponse(status_code=500, content={"status": "ERROR", "message": f"Lỗi hệ thống: {str(e)}"})
# --- API LẤY CHI TIẾT THÔNG BÁO THEO ID ---


# --- 2. HÀM LÀM SẠCH THẺ HTML (Dùng cho nội dung thông báo) ---
def clean_html_content(raw_html):
    if not raw_html:
        return ""
    
    # Loại bỏ style và script
    clean_text = re.sub(r'<(style|script)[^>]*>.*?</\1>', '', raw_html, flags=re.DOTALL | re.IGNORECASE)
    
    # Thay thế các thẻ block bằng dấu xuống dòng để giữ cấu trúc văn bản
    clean_text = re.sub(r'<(br|p|div|li)[^>]*>', '\n', clean_text, flags=re.IGNORECASE)
    
    # Loại bỏ tất cả các thẻ HTML còn lại
    clean_text = re.sub(r'<[^>]*>', '', clean_text)
    
    # Giải mã các thực thể (&nbsp;, &quot;,...)
    clean_text = html.unescape(clean_text)
    
    # Dọn dẹp khoảng trắng thừa
    clean_text = re.sub(r'\n\s*\n', '\n', clean_text)
    
    return clean_text.strip()

# --- 3. API LẤY CHI TIẾT THÔNG BÁO ---

# =======================================================
# 6. STATIC FILES & MODULES
# =======================================================
from vinhuni_chatbot_python.main_chatbot import router as chatbot_router
#from vinhuni_chatbot_python.main_chatbot_v2 import router as chatbot_v2_router
from vinhuni_ai_docs.router import router as ai_docs_router
from vinhuni_notifications.router import router as notifications_router
app.include_router(ocr_router)
app.include_router(signature_router)  # /api/chu-ky-so/*
app.include_router(admin_portal_router)  # /api/admin/*
app.include_router(health_router)  # /health cho công cụ giám sát

# Phục vụ giao diện cổng quản trị tại /admin
from fastapi.staticfiles import StaticFiles as _StaticFiles
import os as _os
_thu_muc_admin = _os.path.join(_os.path.dirname(_os.path.abspath(__file__)), 'admin_portal')
if _os.path.isdir(_thu_muc_admin):
    app.mount('/admin', _StaticFiles(directory=_thu_muc_admin, html=True), name='cong_quan_tri')
app.include_router(voice_control_router.router)
app.include_router(chatbot_router)
app.include_router(ai_docs_router)
app.include_router(chatbot_v2_router)
app.include_router(chatbot_v3_router)
app.include_router(notifications_router)
app.include_router(search.router)
app.include_router(academic_router)
app.include_router(certificate_router)
app.include_router(admin_schedule.router)
app.include_router(attendance.router) # Sử dụng biến router bên trong file mới
app.include_router(news.router) # Đưa router của news vào hệ thống
app.include_router(notif_settings.router)
#chat group
app.include_router(api_chatgroupv1.router)
app.include_router(secretary_router.router, prefix="/api")
socket_app = socketio.ASGIApp(sio, socketio_path='/socket.io')
app.mount('/socket.io', socket_app) # "Gắn" đường ống socket vào path này
app.include_router(chat_secure_router)

# Gộp Socket.io với FastAPI
#app_combined = socketio.ASGIApp(sio, app)


# 📂 Khai báo thư mục chứa file html bằng đường dẫn tuyệt đối
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
templates = Jinja2Templates(directory=os.path.join(BASE_DIR, "templates"))

@app.get("/chat-secure", response_class=HTMLResponse)
async def get_secure_chat(request: Request, token: str, user: str):
    """
    API phục vụ giao diện Web Chat cho sinh viên.
    Luồng: App Flutter bốc Firebase Token -> Mở WebView gọi URL này -> Web tự Login.
    """
    # Trả về giao diện chat_secure.html và truyền "chìa khóa" Token vào
    return templates.TemplateResponse("chat_secure.html", {
        "request": request,
        "token": token,
        "user": user
    })
templates = Jinja2Templates(directory="templates")
@app.get("/privacy-policy", response_class=HTMLResponse)



async def get_privacy_policy(request: Request):
    # Trả về file privacy_policy.html nằm trong thư mục templates
    return templates.TemplateResponse("privacy_policy.html", {"request": request})
    
# @app.get("/api/count-unread/{student_id}")
# async def count_unread(student_id: str):
    # try:
        # sid = clean_student_id(student_id)
        # with pyodbc.connect(REMOTE_CONN_STR) as conn:
            # cursor = conn.cursor()
            # # Tìm khớp chính xác sid (CB1679 hoặc 2057...) hoặc thêm SV để dự phòng
            # sql = """
                # SELECT COUNT(*) FROM tbl_Notification_Queue 
                # WHERE (RTRIM(StudentId) = ? OR RTRIM(StudentId) = 'SV' + ?)
                  # AND IsRead = 0 AND IsSent = 1
            # """
            # cursor.execute(sql, (sid, sid))
            # count = cursor.fetchone()[0]
            # return {"status": "success", "unread_count": count}
    # except Exception as e:
        # return {"status": "error", "unread_count": 0}

@app.get("/api/get-name-by-id/{user_id}") # Dùng @app nếu trong main.py
def get_name_by_id(user_id: str):
    """
    API lấy tên người dùng: 
    1. Tự động cắt tiền tố SV, CB
    2. Tìm trong bảng tbl_Users
    """
    try:
        # 1. Xử lý làm sạch và cắt tiền tố
        raw_id = user_id.strip().upper()
        
        # 🔥 THUẬT TOÁN CẮT TIỀN TỐ:
        # Nếu bắt đầu bằng SV hoặc CB (2 ký tự đầu), ta lấy từ ký tự thứ 3 trở đi
        if raw_id.startswith('SV') or raw_id.startswith('CB'):
            clean_id = raw_id[2:]
        else:
            clean_id = raw_id
            
        print(f"📡 Đang check tên cho ID gốc: {raw_id} -> ID đã cắt: {clean_id}")

        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            
            # 2. Truy vấn vào bảng tbl_Users (Sơn vừa gửi cấu trúc)
            # Dùng clean_id để khớp với UserCode trong DB của bạn
            sql = "SELECT FullName, UserRole FROM tbl_Users WHERE UserCode = ? AND IsActive = 1"
            cursor.execute(sql, (clean_id,))
            row = cursor.fetchone()
            
            if row:
                full_name = str(row[0])
                role = str(row[1])
                return {
                    "full_name": full_name,
                    "role": role,
                    "status": "success"
                }
            else:
                return {"full_name": None, "status": "not_found"}

    except Exception as e:
        print(f"🔥 Lỗi API get-name: {str(e)}")
        return {"full_name": None, "status": "error", "message": str(e)}
        


@app.get("/api/admin/refresh-v2-brain")
async def refresh_v2():
    try:
        # 1. Import các module chứa "não bộ" AI hiện tại của bạn
        from services import chatbot_service
        from services import ai_prompt_service
        from routers import api_chatbot_v2
        
        # 2. Ép Python đọc lại code mới từ ổ cứng vào RAM
        importlib.reload(ai_prompt_service)
        importlib.reload(chatbot_service)
        importlib.reload(api_chatbot_v2)
        
        return {
            "status": "success", 
            "message": "Đã cập nhật bộ não AI mới thành công (Hot Reload) mà không cần Restart Server!"
        }
    except Exception as e:
        return {
            "status": "error", 
            "message": f"Lỗi khi cập nhật não: {str(e)}"
        }    
# Bổ sung vào các route hiện có trong main.py
# =======================================================
# API HỖ TRỢ UNIVERSAL LINKS CHO APPLE (iOS)
# =======================================================
@app.get("/.well-known/apple-app-site-association")
@app.get("/apple-app-site-association")
async def apple_app_site_association():
    """Cung cấp file xác thực cho iOS để bấm link web tự mở App"""
    # LƯU Ý: Phải thay TEAM_ID và BUNDLE_ID bằng thông tin thật trên Apple Developer của trường
    aasa_data = {
        "applinks": {
            "apps": [],
            "details": [
                {
                    "appID": "V9L7W52Z68.vn.edu.vinhuni.studentapp", # Ví dụ: 8XABCD1234.com.vinhuni.app
                    "paths": ["*"] # Cho phép mở App từ mọi đường dẫn web
                }
            ]
        }
    }
    return JSONResponse(content=aasa_data)
@app.get("/delete-account", response_class=HTMLResponse)
async def get_delete_account(request: Request):
    # Trả về giao diện hướng dẫn xóa tài khoản
    return templates.TemplateResponse("delete_account.html", {"request": request})
@app.get("/admin-ai", response_class=HTMLResponse)
async def get_admin_ai_page(request: Request):
    # Đảm bảo file admin_ai_upload.html nằm trong thư mục templates
    return templates.TemplateResponse("admin_ai_upload.html", {"request": request})    
# if os.path.exists("web"): 
    # app.mount("/mobile", StaticFiles(directory="web", html=True), name="mobi_app")

@app.get("/")
async def root():
    # Trả về chuỗi JSON kèm theo mã trạng thái HTTP 403
    return JSONResponse(
        status_code=403,
        content={
            "status": "forbidden", 
            "message": "Không có quyền truy cập vào hệ thống."
        }
    )
# @app.get("/")
# async def root():
    # if os.path.exists("web/index.html"): return RedirectResponse("/mobile/")
    # return {"status": "running", "message": "VinhUni API Backend is ready!"}
from fastapi import APIRouter, HTTPException, Query
import pyodbc

#@app.post("/api/get-token")
@app.get("/api/get-token")
def get_token_by_hsid(hsid: Optional[str] = Query(None)): 
    # 1. Kiểm tra tham số đầu vào
    if hsid is None:
        return {"status": "error", "message": "Thiếu tham số hsid"}

    conn = None
    try:
        # 2. Kết nối tới SQL Server cục bộ
        conn = pyodbc.connect(REMOTE_CONN_STR)
        cursor = conn.cursor()

        # 3. Sử dụng cú pháp truy vấn 4 thành phần trực tiếp qua Linked Server
        # Định dạng: [Server].[Database].[Schema].[Table/View]
        # Chú ý: Dùng dấu nháy đơn chuẩn cho hsid
        query = f"""
            SELECT TOP 1 Token 
            FROM [172.16.0.26\\vinhuni].[DBCongThongTin].[dbo].[view_CANBO_Token] 
            WHERE HS_ID = ? 
            ORDER BY NgayTao DESC
        """
        
        # Thực thi với tham số (?) để chống SQL Injection và lỗi định dạng chuỗi
        cursor.execute(query, (hsid,))
        row = cursor.fetchone()

        # 4. Trả về kết quả
        if row:
            return {
                "status": "success",
                "token": row[0] if row[0] else ""
            }
        return {"status": "error", "message": f"Không tìm thấy token cho HSID: {hsid}"}

    except Exception as e:
        # In lỗi ra Terminal để bạn dễ debug
        print(f"🔥 Lỗi truy vấn Token: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        # Đảm bảo đóng kết nối
        if conn: conn.close()

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080, proxy_headers=True, forwarded_allow_ips="*")
    # ==========================================================
# CẤU HÌNH CHẠY SERVER VỚI CHẾ ĐỘ AUTO-RELOAD
# # ==========================================================
# if __name__ == "__main__":
    # import uvicorn
    # Lưu ý: Nếu file tên là Main.py thì đổi "main:app" thành "Main:app"
    # uvicorn.run(
        # "main:app", 
        # host="0.0.0.0", 
        # port=8080, 
        # proxy_headers=True, 
        # forwarded_allow_ips="*",
        # reload=True
    # )