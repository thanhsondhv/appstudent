import os
import httpx
import uuid
import io
from typing import Optional
from fastapi import APIRouter, Form, Request, HTTPException, UploadFile, File
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from PIL import Image

router = APIRouter()

# 📂 Khởi tạo bộ máy Template (Xác định đường dẫn chính xác)
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
templates = Jinja2Templates(directory=os.path.join(BASE_DIR, "templates"))

# 🔥 CẤU HÌNH LƯU TRỮ NỘI BỘ
UPLOAD_DIR = os.path.join(BASE_DIR, "static/uploads/chat")
os.makedirs(UPLOAD_DIR, exist_ok=True)

async def verify_ms_token(token: str):
    """Xác thực Token Microsoft 365 để đảm bảo phiên làm việc chính chủ"""
    async with httpx.AsyncClient() as client:
        try:
            headers = {"Authorization": f"Bearer {token}"}
            response = await client.get("https://graph.microsoft.com/v1.0/me", headers=headers)
            return response.status_code == 200
        except:
            return False

# --- 1. GIAO DIỆN ĐĂNG NHẬP (Dùng cho cả GET và POST để tránh 404) ---
@router.get("/chat-login", response_class=HTMLResponse)
async def get_login_page(request: Request):
    return templates.TemplateResponse("chat_login.html", {"request": request})

# --- 2. GIAO DIỆN DANH SÁCH NHÓM (Fix lỗi 404 khi gọi trực tiếp) ---

@router.post("/chat-groups", response_class=HTMLResponse)
async def get_group_list(
    request: Request,
    token: Optional[str] = Form(None),
    ms_token: Optional[str] = Form(None),
    user_id: Optional[str] = Form(None),
    user_name: Optional[str] = Form(None)
):
    """Hiển thị danh sách nhóm hội thoại"""
    return templates.TemplateResponse("chat_groups.html", {
        "request": request,
        "token": token,
        "ms_token": ms_token,
        "user_id": user_id,
        "user_name": user_name
    })

# --- 3. CỔNG VÀO BẢO MẬT (Xử lý điều hướng từ Flutter) ---
# routers/api_chat_secure.py

# routers/api_chat_secure.py

# routers/api_chat_secure.py

@router.post("/chat-secure", response_class=HTMLResponse)
async def chat_secure(
    request: Request,
    token: str = Form(...),
    user_id: str = Form(...),
    user_name: str = Form(...),
    
    # 🔥 FIX 1: Bổ sung group_name để truyền tên nhóm xuống HTML
    group_name: Optional[str] = Form("Hội thoại"), 
    group_id: Optional[str] = Form(None), 
    ms_token: Optional[str] = Form(None),
    
    # 🔥 FIX 2: Bắt lấy tín hiệu target_path từ Flutter/Web gửi lên
    target_path: Optional[str] = Form(None)
):
    # Nếu tín hiệu yêu cầu về danh sách HOẶC không có ID nhóm
    if target_path == "/chat-groups" or not group_id or group_id.strip() == "":
        return templates.TemplateResponse("chat_groups.html", {
            "request": request,
            "token": token,
            "user_id": user_id,
            "user_name": user_name,
            "ms_token": ms_token
        })

    # Nếu có ID nhóm hợp lệ, vào phòng chat chi tiết
    return templates.TemplateResponse("chat_secure.html", {
        "request": request,
        "token": token,
        "user_id": user_id,
        "user_name": user_name,
        "group_id": group_id,
        "group_name": group_name, # 🔥 Truyền xuống để Header HTML hiện tên
        "ms_token": ms_token
    })
# --- 4. XỬ LÝ UPLOAD ẢNH LOCAL ---
@router.post("/api/chat/upload-local")
async def upload_local_file(file: UploadFile = File(...)):
    try:
        file_extension = file.filename.split(".")[-1]
        new_filename = f"{uuid.uuid4()}.{file_extension}"
        file_path = os.path.join(UPLOAD_DIR, new_filename)
        
        content = await file.read()
        image = Image.open(io.BytesIO(content))
        
        if image.mode in ("RGBA", "P"):
            image = image.convert("RGB")
            
        max_size = (1200, 1200)
        image.thumbnail(max_size, Image.Resampling.LANCZOS)
        
        image.save(file_path, "JPEG", quality=70, optimize=True)
        
        return JSONResponse(content={"url": f"/static/uploads/chat/{new_filename}"})
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))