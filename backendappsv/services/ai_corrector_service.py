import openai
import os
import json
import shutil
import base64
from fastapi import APIRouter, UploadFile, File, Form, HTTPException
from core.settings import settings  # cấu hình tập trung (Pha 0)

router = APIRouter()

# =========================================================
# PHẦN 1: BỘ NÃO AI A3 (SỬ DỤNG GPT-4O VISION)
# =========================================================
class AICorrectorService:
    def __init__(self):
        # API Key dự án VinhUni của Sơn
        self.api_key = settings.ai.openai_api_key
        self.client = openai.OpenAI(api_key=self.api_key)

    # --- 🔵 HÀM CHO CÁN BỘ (CanBo) ---
    def process_for_canbo(self, raw_text: str, user_name: str):
        system_prompt = (
            f"Bạn là Thư ký AI cấp cao hỗ trợ cán bộ {user_name} tại VinhUni. "
            "Nhiệm vụ: Chuyển STT thành BIÊN BẢN HỌP chuyên nghiệp. "
            "Trả về JSON: { 'meeting_title': '', 'clean_text': '', 'summary': '', 'tasks': [] }"
        )
        return self._execute_gpt_call(system_prompt, raw_text)

    # --- 🟠 HÀM CHO SINH VIÊN (sinhvien - SOẠN BÀI GIẢNG) ---
    def process_for_sinhvien(self, raw_text: str, user_name: str):
        system_prompt = (
            f"Bạn là Trợ lý Học tập AI hỗ trợ sinh viên {user_name} tại VinhUni. "
            "Nhiệm vụ: Từ văn bản bài giảng, hãy SOẠN THẢO thành một tài liệu học tập bài bản. "
            "Trả về JSON: { 'meeting_title': 'Tên bài học', 'clean_text': 'Nội dung soạn thảo chi tiết', 'summary': 'Tóm tắt bài', 'tasks': ['Câu hỏi ôn tập 1', 'Câu hỏi ôn tập 2'] }"
        )
        return self._execute_gpt_call(system_prompt, raw_text)

    # --- 🟢 HÀM OCR BẰNG GPT-4O VISION (THAY THẾ TESSERACT) ---
    def process_ocr_with_gpt(self, image_path: str):
        """Dùng GPT-4o đọc ảnh trực tiếp và nắn chỉnh văn bản sạch"""
        try:
            # 1. Chuyển ảnh sang Base64 để gửi lên OpenAI
            with open(image_path, "rb") as image_file:
                base64_image = base64.b64encode(image_file.read()).decode('utf-8')

            # 2. Gọi Model GPT-4o-mini (Vision-capable) để tối ưu chi phí và tốc độ
            response = self.client.chat.completions.create(
                model=settings.ai.ten_mo_hinh_chat,
                messages=[
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "text", 
                                "text": (
                                    "Bạn là chuyên gia OCR tại VinhUni. Hãy đọc ảnh này và thực hiện: "
                                    "1. Trích xuất toàn bộ văn bản chính xác. "
                                    "2. Sửa lỗi chính tả và định dạng lại đoạn văn cho sạch sẽ. "
                                    "3. Trích xuất 3-5 ý chính quan trọng nhất. "
                                    "Trả về định dạng JSON: { 'refined_text': 'văn bản sạch', 'key_points': ['ý 1', 'ý 2'] }"
                                )
                            },
                            {
                                "type": "image_url",
                                "image_url": {"url": f"data:image/jpeg;base64,{base64_image}"},
                            },
                        ],
                    }
                ],
                response_format={"type": "json_object"},
                temperature=0.2
            )
            return json.loads(response.choices[0].message.content)
        except Exception as e:
            print(f"❌ Lỗi Vision OCR: {e}")
            return {"refined_text": f"Lỗi xử lý ảnh: {str(e)}", "key_points": []}

    # --- HÀM GỌI GPT CHUNG ---
    def _execute_gpt_call(self, system_prompt, content):
        try:
            response = self.client.chat.completions.create(
                model=settings.ai.ten_mo_hinh_chat,
                messages=[{"role": "system", "content": system_prompt}, {"role": "user", "content": content}],
                response_format={"type": "json_object"},
                temperature=0.3
            )
            return json.loads(response.choices[0].message.content)
        except:
            return {"meeting_title": "Lỗi", "clean_text": content, "summary": "AI bận", "tasks": []}

# =========================================================
# PHẦN 2: ROUTER (ĐIỀU PHỐI API)
# =========================================================
router = APIRouter()
ai_service = AICorrectorService()

@router.post("/api/secretary/transcribe")
async def transcribe_endpoint(raw_text: str = Form(""), user_name: str = Form("User"), role: str = Form("CanBo")):
    if not raw_text:
        return {"status": "error", "message": "Dữ liệu trống"}
    if role == "sinhvien":
        result = ai_service.process_for_sinhvien(raw_text, user_name)
    else:
        result = ai_service.process_for_canbo(raw_text, user_name)
    return {"status": "success", "data": result}

@router.post("/api/ocr/extract-text")
async def ocr_endpoint(
    file: UploadFile = File(...), 
    user_id: str = Form("unknown")
):
    """Sử dụng GPT-4o Vision để đọc tài liệu học tập của Sinh viên"""
    temp_path = f"temp_{user_id}_{file.filename}"
    try:
        # 1. Lưu file tạm
        with open(temp_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
        
        # 2. 🔥 GỌI HÀM GPT VISION THỰC TẾ (Không dùng Tesseract nữa)
        result = ai_service.process_ocr_with_gpt(temp_path)
        
        print(f"✅ OCR Vision Thành công cho: {user_id}")
        return {"status": "success", "data": result}
        
    except Exception as e:
        print(f"🔥 Lỗi hệ thống OCR: {e}")
        return {"status": "error", "message": str(e)}
    finally:
        # Xóa file tạm sau khi xử lý xong
        if os.path.exists(temp_path):
            os.remove(temp_path)