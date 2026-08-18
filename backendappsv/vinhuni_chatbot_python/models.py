from pydantic import BaseModel
from typing import List, Optional



class ChatRequest(BaseModel):
    message: str
    sessionId: int
    studentId: str
    fullName: Optional[str] = None  # 🔥 Thêm dòng này để không bị lỗi 422 Unprocessable Entity
class ChatResponse(BaseModel):
    mainReply: str
    suggestions: List[str]
    sessionId: int