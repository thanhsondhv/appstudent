from sqlalchemy import Column, String, DateTime, BigInteger, UnicodeText
from sqlalchemy.ext.declarative import declarative_base
from datetime import datetime

Base = declarative_base()

class MeetingMinute(Base):
    __tablename__ = 'tbl_Meeting_Minutes'
    MeetingId = Column(BigInteger, primary_key=True, autoincrement=True)
    Title = Column(String(500), nullable=True)
    StaffCode = Column(String(50), nullable=False) # Mã cán bộ ghi âm
    RawTranscript = Column(UnicodeText) # Văn bản thô từ STT
    CreatedAt = Column(DateTime, default=datetime.now)