from fastapi import APIRouter, UploadFile, File, Depends
from services.whisper_service import WhisperService
from services.ai_corrector_service import AICorrectorService
import shutil
import os

router = APIRouter()

# Khởi tạo các Service AI
# Lưu ý: WhisperService sẽ nạp model lần đầu nên có thể mất 1-2 phút
whisper_service = WhisperService()
ai_corrector = AICorrectorService()

@router.post("/secretary/transcribe")
async def transcribe_meeting(file: UploadFile = File(...)):
    """
    Endpoint xử lý ghi âm cuộc họp: 
    1. Nhận file -> 2. Whisper (STT) -> 3. OpenAI (Sửa lỗi & Tóm tắt)
    """
    print(f"📥 [SECRETARY] Nhận file ghi âm: {file.filename}")
    
    # Tạo đường dẫn tạm trên server AI2025
    temp_path = f"temp_{file.filename}"
    
    try:
        # 1. Lưu file từ Stream vào ổ đĩa để Whisper đọc
        with open(temp_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
        
        # 2. LỚP 1: Nhận diện giọng nói bằng Faster-Whisper
        print(f"🧠 [LỚP 1] Whisper đang chuyển đổi âm thanh...")
        raw_text = whisper_service.transcribe(temp_path)
        
        if not raw_text.strip():
            return {"status": "error", "message": "Không nhận diện được giọng nói trong file."}
            
        print(f"👉 Bản thô: {raw_text[:60]}...")

        # 3. LỚP 2: OpenAI xử lý đa nhiệm (Sửa lỗi, Tóm tắt, Action Items)
        print(f"🪄 [LỚP 2] OpenAI đang phân tích và tóm tắt...")
        # Kết quả trả về từ hàm này bây giờ là một Dictionary (dict)
        ai_result = ai_corrector.fix_transcript(raw_text)
        
        print(f"✅ [HOÀN TẤT] Đã xử lý xong dữ liệu cuộc họp.")
        
        # 4. Trả về kết quả cấu trúc cho Flutter bóc tách
        return {
            "status": "success",
            "data": {
                "raw_text": raw_text,                   # Văn bản chưa sửa
                "clean_text": ai_result.get("clean_text", ""), # Văn bản đã nắn chỉnh
                "summary": ai_result.get("summary", ""),       # Bản tóm tắt ngắn
                "tasks": ai_result.get("tasks", [])           # Mảng các đầu việc cần làm
            }
        }
        
    except Exception as e:
        print(f"❌ [ERROR] Lỗi hệ thống: {str(e)}")
        return {"status": "error", "message": f"Server Error: {str(e)}"}
        
    finally:
        # 5. Dọn dẹp file tạm để không làm đầy ổ cứng Server
        if os.path.exists(temp_path):
            os.remove(temp_path)
            print(f"🗑️ Đã dọn dẹp file tạm: {temp_path}")

# Hướng dẫn cho Sơn: Sau khi test ổn định, hãy thêm lại bảo mật bằng cách:
# async def transcribe_meeting(file: UploadFile = File(...), current_user = Depends(get_current_user)):