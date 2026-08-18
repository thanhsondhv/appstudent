from pydantic import BaseModel
from datetime import datetime
from typing import Optional, List

class MessageCreate(BaseModel):
    GroupId: str
    MessageContent: str
    MessageType: str = "TEXT"
    FileUrl: Optional[str] = None

class MessageResponse(BaseModel):
    MessageId: int
    GroupId: str
    SenderCode: str
    MessageContent: str
    MessageType: str
    CreatedAt: datetime
    
    class Config:
        from_attributes = True