# routers/voice_control_router.py
from fastapi import APIRouter, UploadFile, File, Depends
from services.whisper_service import WhisperService
from services.ai_corrector_service import AICorrectorService
from auth.security_guard import verify_staff_token
import shutil
import os

router = APIRouter(prefix="/api/voice-control", tags=["Voice Control"])
whisper_service = WhisperService()
ai_corrector = AICorrectorService()

# 🗺️ Cập nhật INTENT_MAP cho bản +19
INTENT_MAP = {
    "LICH_TUAN": "/lichcongtac",         # Khớp với StaffScheduleScreen
    "TRA_CUU_VAN_BAN": "/vanban",        # Khớp với VanBanScreen
    "THU_KY": "/ai_secretary",           # Khớp với MeetingRecorderScreen
    "DIEM_DANH": "/mo_diem_danh",        # Cho Cán bộ
    "STUDENT_FEEDBACK": "/student_feedback", # Phản hồi sinh viên
    "CHUNG_CHI": "/ket_qua_chung_nhan"   # Tra cứu chứng chỉ
}

@router.post("/execute")
async def execute_voice_command(file: UploadFile = File(...), current_user = Depends(verify_staff_token)):
    temp_path = f"cmd_{file.filename}"
    try:
        with open(temp_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
        
        # 1. Whisper: Nghe lệnh
        raw_command = whisper_service.transcribe(temp_path)
        
        # 2. AI: Phân tích ý định
        ai_analysis = ai_corrector.detect_intent(raw_command, list(INTENT_MAP.keys()))
        
        intent = ai_analysis.get("intent", "UNKNOWN")
        target_route = INTENT_MAP.get(intent, "")

        return {
            "status": "success",
            "command": raw_command,
            "intent": intent,
            "target_route": target_route,
            "message": ai_analysis.get("response_message", "Đang thực hiện...")
        }
    finally:
        if os.path.exists(temp_path): os.remove(temp_path)