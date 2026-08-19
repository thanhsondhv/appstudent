#models\chat_models.py
from sqlalchemy import Column, String, DateTime, Integer, BigInteger, Boolean, Text, ForeignKey, UnicodeText, Unicode
from sqlalchemy.ext.declarative import declarative_base
from datetime import datetime

Base = declarative_base()
# Bảng mới: Lưu trữ tri thức đã trích xuất từ tài liệu của nhóm
class GroupKnowledge(Base):
    __tablename__ = 'tbl_Group_Knowledge'
    
    Id = Column(Integer, primary_key=True, autoincrement=True)
    GroupId = Column(String(50), ForeignKey('tbl_Chat_Groups.GroupId'), index=True)
    SenderId = Column(String(100))        # Mã người gửi (UserCode)
    SourceType = Column(String(20))       # 'FILE', 'LINK' hoặc 'ANNOUNCEMENT'
    FileName = Column(Unicode(255))      # Tên file gốc có dấu
    FileUrl = Column(String(500))         # Link lưu trữ vật lý
    RawContent = Column(UnicodeText)      # Văn bản thô bóc tách được (Text Layer)
    SummaryContent = Column(UnicodeText)  # Bản tóm tắt súc tích từ AI
    CreatedAt = Column(DateTime, default=datetime.now)
    IsDeleted = Column(Boolean, default=False)
class ChatGroup(Base):
    __tablename__ = 'tbl_Chat_Groups'
    GroupId = Column(String(50), primary_key=True)
    GroupName = Column(String(255))
    GroupAvatar = Column(String(500))
    GroupType = Column(String(50)) # 'STAFF_COMMUNITY', 'DEPARTMENT', v.v.
    CreatedBy = Column(String(50))
    # Mặc định là False để ai cũng nhắn tin được 
    IsLocked = Column(Boolean, default=False) 
    LastMessageAt = Column(DateTime, default=datetime.now)
    LastMessageSnippet = Column(String(500))
    CreatedAt = Column(DateTime, default=datetime.now)

class ChatMember(Base):
    __tablename__ = 'tbl_Chat_Members'
    GroupId = Column(String(50), primary_key=True)
    UserCode = Column(String(50), primary_key=True)
    # 1: Trưởng nhóm, 2: Phó nhóm, 3: Thành viên [cite: 13, 69]
    Role = Column(Integer, default=3) 
    IsMuted = Column(Boolean, default=False)
    LastReadMessageId = Column(BigInteger, default=0)
    JoinedAt = Column(DateTime, default=datetime.now)

class ChatMessage(Base):
    __tablename__ = 'tbl_Chat_Messages'
    
    # 1. Định danh và Điều hướng
    MessageId = Column(BigInteger, primary_key=True, autoincrement=True)
    GroupId = Column(String(50), index=True)
    
    # 2. Thông tin người gửi (Lưu thẳng để truy vấn cực nhanh)
    SenderCode = Column(String(100)) # Khớp với tbl_Users.UserCode
    SenderName = Column(Unicode(250), nullable=True)  # Họ tên tiếng Việt
    SenderAvatar = Column(String(500), nullable=True) # Link ảnh đại diện
    SenderRole = Column(String(50), nullable=True)   # Giảng viên/Sinh viên
    
    # 3. Nội dung tin nhắn
    MessageContent = Column(UnicodeText) # Nội dung chat tiếng Việt
    MessageType = Column(String(20), default='TEXT') # TEXT, IMAGE, FILE, LINK
    FileUrl = Column(String(500), nullable=True)
    AISummary = Column(UnicodeText, nullable=True) # Tóm tắt thông minh
    
    # 4. Trạng thái và Trả lời (Reply)
    ReplyToId = Column(BigInteger, nullable=True)
    ReplyToName = Column(Unicode(250), nullable=True) # 🔥 Thêm cột này để hiện tên người được reply
    IsDeleted = Column(Boolean, default=False)
    CreatedAt = Column(DateTime, default=datetime.now)

# Bảng mới: Theo dõi tương tác "Live SQL" (Đã xem, Click link, Tải file) [cite: 16, 20, 34, 73]
class MessageAction(Base):
    __tablename__ = 'tbl_Message_Actions'
    ActionId = Column(BigInteger, primary_key=True, autoincrement=True)
    MessageId = Column(BigInteger, ForeignKey('tbl_Chat_Messages.MessageId'))
    UserCode = Column(String(50))
    # 'READ', 'CLICK', 'DOWNLOAD' [cite: 16, 20, 34]
    ActionType = Column(String(20)) 
    CreatedAt = Column(DateTime, default=datetime.now)
# models/user_models.py (hoặc thêm vào chat_models.py)
class User(Base):
    __tablename__ = 'tbl_Users'
    UID = Column(Integer, primary_key=True, autoincrement=True)
    UserCode = Column(String(100), unique=True, nullable=False)
    FullName = Column(Unicode(250)) # Dùng Unicode để hỗ trợ tiếng Việt
    TenFileAnh = Column(String(255))
    UserRole = Column(String(50))    