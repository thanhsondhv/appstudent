#router\api_chatgroupv1.py
#from fastapi import APIRouter, Depends, HTTPException, Body
from fastapi import APIRouter, Depends, HTTPException, Body, Form, File, UploadFile
from fastapi.responses import RedirectResponse
from sqlalchemy.orm import Session
from typing import List
from datetime import datetime
from sqlalchemy import text
from config.database import get_db
from config.database import engine
from models.chat_model import ChatMessage, MessageAction, ChatGroup, User, ChatMember
from services.chatgroup.message_service import MessageService
from services.chatgroup.member_service import MemberService
from fastapi import Body
from config.database import SessionLocal # Nhớ import SessionLocal nếu chưa có
import pyodbc
import uuid
from database.database import get_db_conn
from services.onedrive_service import onedrive_gateway

router = APIRouter(prefix="/api/v1/chat", tags=["Chat Group"])


# --- API UPLOAD FILE LÊN ONEDRIVE DÀNH CHO CHAT & CLOUD ---
@router.post("/upload-onedrive")
async def upload_file_to_onedrive(
    user_code: str = Form(...),
    ms_token: str = Form(""), # 🔥 Bổ sung: Nhận Token tươi từ Flutter gửi lên
    file: UploadFile = File(...)
):
    try:
        file_bytes = await file.read()
        
        file_url = await onedrive_gateway.upload_chat_file(
            user_code=user_code, 
            file_bytes=file_bytes, 
            file_name=file.filename,
            ms_token=ms_token # 🔥 Chuyền tiếp Token sang file service
        )
        
        if not file_url:
            raise HTTPException(status_code=400, detail="Lỗi: Tài khoản chưa liên kết Office 365 hoặc Token hết hạn.")
            
        return {"status": "success", "file_name": file.filename, "file_url": file_url}
    except Exception as e:
        print(f"❌ Lỗi API Upload OneDrive: {e}")
        raise HTTPException(status_code=500, detail=str(e))
# --- 1. LẤY LỊCH SỬ TIN NHẮN ---
@router.get("/history/{group_id}")
async def get_chat_history(group_id: str, limit: int = 50, db: Session = Depends(get_db)):
    """Lấy tin nhắn kèm Họ tên từ tbl_Users (Lọc bỏ tin đã xóa)"""
    try:
        results = db.query(
            ChatMessage, 
            User.FullName.label("sender_name")
        ).outerjoin(
            User, ChatMessage.SenderCode == User.UserCode
        ).filter(
            ChatMessage.GroupId == group_id,
            ChatMessage.IsDeleted == False
        ).order_by(ChatMessage.MessageId.desc()).limit(limit).all()

        messages_with_info = []
        for msg, sender_name in results:
            m_dict = {
                "MessageId": msg.MessageId,
                "GroupId": msg.GroupId,
                "SenderCode": msg.SenderCode,
                "SenderName": sender_name or "Người dùng",
                "SenderAvatar": f"https://mobi.vinhuni.edu.vn/api/get-avatar/?student_id={msg.SenderCode}",
                "MessageContent": msg.MessageContent,
                "MessageType": getattr(msg, 'MessageType', 'TEXT'),
                "FileUrl": getattr(msg, 'FileUrl', None), 
                "ReplyToId": msg.ReplyToId,
                "ReplyToName": getattr(msg, 'ReplyToName', None),
                "IsDeleted": msg.IsDeleted,
                "CreatedAt": msg.CreatedAt.isoformat() if msg.CreatedAt else None
            }
            messages_with_info.append(m_dict)
        
        # Đảo ngược lại để tin mới nhất nằm dưới cùng màn hình
        return messages_with_info[::-1]

    except Exception as e:
        print(f"🚨 Lỗi API History: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# ==========================================
# 3. ĐĂNG KÝ VÀO NHÓM & LẤY QUYỀN
# ==========================================
@router.post("/join")
async def join_chat_group(
    group_id: str = Body(...), 
    user_code: str = Body(...), 
    db: Session = Depends(get_db)
):
    # 1. Tự động join nếu chưa có (như cũ)
    MemberService.join_group_if_not_exists(db, group_id, user_code)
    
    group = db.query(ChatGroup).filter(ChatGroup.GroupId == group_id).first()
    
    # 2. 🔥 KIỂM TRA QUYỀN ADMIN (Xử lý tiền tố CB/SV)
    u_code = str(user_code).strip().upper().replace('CB', '').replace('SV', '')
    admin_code = str(group.CreatedBy).strip().upper().replace('CB', '').replace('SV', '') if group else ""
    
    is_admin = (u_code == admin_code)
    
    # Lấy role từ bảng member (1: Admin, 3: Member)
    role = MemberService.get_member_role(db, group_id, user_code)
    
    return {
        "status": "success",
        "group_name": group.GroupName if group else "Nhóm",
        "is_admin": is_admin, # 👈 Flutter sẽ dùng biến này để hiện nút Giải tán
        "user_role": role
    }
@router.delete("/delete_group/{group_id}")
async def api_disband_group(group_id: str, user_code: str, db: Session = Depends(get_db)):
    try:
        group = db.query(ChatGroup).filter(ChatGroup.GroupId == group_id).first()
        if not group:
            raise HTTPException(status_code=404, detail="Không tìm thấy nhóm")

        # Kiểm tra quyền: Chỉ người tạo mới được giải tán
        u_code = str(user_code).strip().upper().replace('CB', '').replace('SV', '')
        admin_code = str(group.CreatedBy).strip().upper().replace('CB', '').replace('SV', '')
        
        if u_code != admin_code:
            raise HTTPException(status_code=403, detail="Bạn không có quyền giải tán nhóm này")

        # Xóa thành viên trước, xóa nhóm sau
        db.query(ChatMember).filter(ChatMember.GroupId == group_id).delete()
        db.delete(group)
        db.commit()
        
        return {"status": "success", "message": "Đã giải tán nhóm thành công"}
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=str(e))
# --- 3. LIVE SQL: GHI NHẬN ĐÃ XEM (READ) ---
@router.post("/track/read")
async def track_message_read(
    message_id: int = Body(...), 
    user_code: str = Body(...), 
    db: Session = Depends(get_db)
):
    """Ghi nhận cán bộ đã xem thông báo quan trọng [cite: 34]"""
    # Tránh ghi đè nếu đã đọc rồi
    exists = db.query(MessageAction).filter(
        MessageAction.MessageId == message_id,
        MessageAction.UserCode == user_code,
        MessageAction.ActionType == 'READ'
    ).first()
    
    if not exists:
        new_action = MessageAction(
            MessageId=message_id,
            UserCode=user_code,
            ActionType='READ'
        )
        db.add(new_action)
        db.commit()
    return {"status": "tracked"}

# --- 4. LIVE SQL: THEO DÕI CLICK LINK (REDIRECT) ---
@router.get("/l/{message_id}")
async def link_tracker(message_id: int, u: str, db: Session = Depends(get_db)):
    """
    Endpoint trung gian để đếm lượt click vào link văn bản[cite: 18, 19, 73].
    u: user_code của người nhấn.
    """
    # 1. Ghi nhận lượt Click [cite: 20]
    new_click = MessageAction(
        MessageId=message_id,
        UserCode=u,
        ActionType='CLICK'
    )
    db.add(new_click)
    db.commit()
    
    # 2. Tìm link gốc từ nội dung tin nhắn hoặc bảng đính kèm
    msg = db.query(ChatMessage).filter(ChatMessage.MessageId == message_id).first()
    
    # Ở đây Sơn có thể Redirect về link văn bản của VinhUni
    target_url = msg.FileUrl if msg and msg.FileUrl else "https://vinhuni.edu.vn"
    return RedirectResponse(url=target_url)




@router.get("/my_groups/{user_code}")
async def get_my_groups(user_code: str, db: Session = Depends(get_db)):
    # Chuẩn hóa user_code: bỏ khoảng trắng, viết hoa
    u_code = str(user_code).strip().upper()
    
    # 1. Tự động kiểm tra và cho vào nhóm Toàn Trường
    try:
        # Chỗ này MemberService cần được viết để xử lý tiền tố (xem bên dưới)
        MemberService.join_group_if_not_exists(
            db, 
            group_id='GROUP_CAN_BO_TOAN_TRUONG', 
            user_code=u_code,
            role=3 
        )
    except Exception as e:
        print(f"⚠️ Lỗi tự động join nhóm: {e}")

    # 2. Truy vấn danh sách nhóm: Hỗ trợ lọc mã có tiền tố CB/SV
    query = text("""
        SELECT DISTINCT
            g.GroupId, 
            g.GroupName,
            (SELECT TOP 1 MessageContent FROM tbl_Chat_Messages 
             WHERE GroupId = g.GroupId ORDER BY CreatedAt DESC) as LastMessage,
            (SELECT TOP 1 FORMAT(CreatedAt, 'HH:mm') FROM tbl_Chat_Messages 
             WHERE GroupId = g.GroupId ORDER BY CreatedAt DESC) as LastTime
        FROM tbl_Chat_Groups g
        JOIN tbl_Chat_Members m ON g.GroupId = m.GroupId
        WHERE m.UserCode IN (:u, 'CB' + :u, 'SV' + :u)
    """)
    
    try:
        result = db.execute(query, {"u": u_code})
        groups = []
        
        # 🔥 TẠO NHÓM ẢO "CLOUD CỦA TÔI" ĐẨY LÊN ĐẦU
        cloud_group_id = f"CLOUD_{u_code}"
        groups.append({
            "GroupId": cloud_group_id,
            "GroupName": "☁️ Cloud của tôi",
            "LastMessage": "Lưu trữ tài liệu trên OneDrive",
            "LastTime": "",
            "UnreadCount": 0 
        })

        # Load các nhóm bình thường vào phía sau
        for row in result:
            groups.append({
                "GroupId": str(row.GroupId),
                "GroupName": row.GroupName,
                "LastMessage": row.LastMessage if row.LastMessage else "Chưa có tin nhắn",
                "LastTime": row.LastTime if row.LastTime else "",
                "UnreadCount": 0 
            })
        return groups
    except Exception as e:
        print(f"❌ Lỗi SQL lấy danh sách nhóm: {e}")
        return []


# ==========================================
# API 1: TẠO NHÓM CHAT MỚI
# ==========================================
@router.post("/groups/create")
def api_create_group(payload: dict = Body(...)):
    """
    Body Test Postman/Swagger:
    {
        "group_id": "TEST_GROUP_001", (Để trống tự sinh UUID ngẫu nhiên)
        "group_name": "Nhóm Test Đêm Nay",
        "created_by": "1679",
        "members": ["1680", "1681"] 
    }
    """
    db = SessionLocal()
    try:
        # Nếu không truyền group_id thì tự sinh mã ngẫu nhiên (cắt ngắn 20 ký tự)
        group_id = payload.get("group_id")
        if not group_id:
            group_id = str(uuid.uuid4())[:20] 
            
        created_by = payload.get("created_by")
        members = payload.get("members", [])
        
        # 1. Tạo bản ghi Nhóm
        new_group = ChatGroup(
            GroupId=group_id,
            GroupName=payload.get("group_name", "Nhóm Mới"),
            GroupType=payload.get("group_type", "TEST"),
            CreatedBy=created_by,
            CreatedAt=datetime.now(),
            LastMessageAt=datetime.now(),
            LastMessageSnippet="Nhóm vừa được tạo thành công!"
        )
        db.add(new_group)
        
        # 2. Thêm người tạo làm Trưởng nhóm (Role = 1)
        db.add(ChatMember(GroupId=group_id, UserCode=created_by, Role=1, JoinedAt=datetime.now()))
        
        # 3. Thêm các thành viên khác làm Thành viên thường (Role = 3)
        for member_code in set(members):
            if member_code != created_by: # Tránh thêm trùng người tạo
                db.add(ChatMember(GroupId=group_id, UserCode=member_code, Role=3, JoinedAt=datetime.now()))
                
        db.commit()
        return {
            "status": "success", 
            "group_id": group_id, 
            "message": f"Tạo nhóm '{new_group.GroupName}' thành công với {len(set(members)) + 1} thành viên!"
        }
    except Exception as e:
        db.rollback()
        return {"status": "error", "message": str(e)}
    finally:
        db.close()

# ==========================================
# API 2: THÊM THÀNH VIÊN VÀO NHÓM ĐÃ CÓ
# ==========================================
@router.post("/groups/add-members")
def api_add_members(payload: dict = Body(...)):
    """
    Body Test Postman/Swagger:
    {
        "group_id": "TEST_GROUP_001",
        "members": ["1682", "1683", "1684"]
    }
    """
    db = SessionLocal()
    try:
        group_id = payload.get("group_id")
        members = payload.get("members", [])
        
        if not group_id or not members:
            return {"status": "error", "message": "Thiếu group_id hoặc danh sách members"}
            
        added_count = 0
        for code in set(members):
            # Kiểm tra xem user này đã nằm trong nhóm chưa, chưa thì mới thêm
            exists = db.query(ChatMember).filter(
                ChatMember.GroupId == group_id, 
                ChatMember.UserCode == code
            ).first()
            
            if not exists:
                db.add(ChatMember(GroupId=group_id, UserCode=code, Role=3, JoinedAt=datetime.now()))
                added_count += 1
                
        if added_count > 0:
            db.commit()
            
        return {"status": "success", "message": f"Đã thêm thành công {added_count} thành viên mới!"}
    except Exception as e:
        db.rollback()
        return {"status": "error", "message": str(e)}
    finally:
        db.close()        
# XEM THÀNH VIÊN

@router.get("/members/{group_id}")
async def get_group_members(group_id: str):
    """Lấy danh sách thành viên kèm thông tin chi tiết và quyền hạn"""
    try:
        # 🔥 ĐÃ SỬA: Gọi hàm get_db_conn() từ file database.py
        with get_db_conn() as conn:
            if not conn:
                return []
                
            cursor = conn.cursor()
            sql = """
                SELECT 
                    RTRIM(m.UserCode) as id, 
                    u.FullName as name, 
                    m.Role as role
                FROM tbl_Chat_Members m
                JOIN tbl_Users u ON m.UserCode = u.UserCode
                WHERE m.GroupId = ?
                ORDER BY m.Role ASC, u.FullName ASC
            """
            cursor.execute(sql, (group_id,))
            rows = cursor.fetchall()
            return [{"id": r[0], "name": r[1], "role": r[2]} for r in rows]
    except Exception as e:
        print(f"❌ Lỗi lấy thành viên: {e}")
        return []      
# ==========================================
# API: RỜI KHỎI NHÓM CHAT (Dành cho Thành viên)
# ==========================================
@router.post("/group/leave")
async def leave_chat_group(payload: dict = Body(...), db: Session = Depends(get_db)):
    """
    Cho phép một thành viên tự động rời khỏi nhóm.
    Body: {"group_id": "...", "user_code": "..."}
    """
    try:
        group_id = payload.get("group_id")
        user_code = payload.get("user_code")
        
        if not group_id or not user_code:
            raise HTTPException(status_code=400, detail="Thiếu group_id hoặc user_code")

        # Chuẩn hóa user_code để khớp với Database
        u_code = str(user_code).strip().upper().replace('CB', '').replace('SV', '')

        # Tìm và xóa bản ghi của User này trong bảng Thành viên
        deleted_count = db.query(ChatMember).filter(
            ChatMember.GroupId == group_id,
            ChatMember.UserCode == u_code
        ).delete()
        
        db.commit()
        
        if deleted_count == 0:
            return {"status": "error", "message": "Bạn không nằm trong nhóm này hoặc nhóm không tồn tại"}

        return {"status": "success", "message": "Đã rời nhóm thành công"}
        
    except Exception as e:
        db.rollback()
        print(f"❌ Lỗi API Rời nhóm: {e}")
        raise HTTPException(status_code=500, detail=str(e))        