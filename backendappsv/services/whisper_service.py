from faster_whisper import WhisperModel
import os

class WhisperService:
    def __init__(self):
        # Sử dụng bản 'large-v3-turbo' tối ưu cho năm 2026
        self.model_size = "large-v3-turbo" 
        self.model = WhisperModel(
            self.model_size, 
            device="cpu", 
            compute_type="int8"
        )

    def transcribe(self, file_path: str):
        vinhuni_context = (
            "Chào mừng bạn đến với Trường Đại học Vinh (VinhUni). "
            "Đây là biên bản cuộc họp về hệ thống định danh, sinh trắc học, "
            "giám sát hành vi, phần mềm quản lý sinh viên và cán bộ."
        )

        segments, info = self.model.transcribe(
            file_path,
            beam_size=5,
            language="vi",
            initial_prompt=vinhuni_context,
            vad_filter=True,
            vad_parameters=dict(min_silence_duration_ms=500)
        )

        text_result = " ".join([segment.text for segment in segments])
        
        # ✅ FIX: Trả về String chuẩn, không trả về Tuple
        return text_result.strip()