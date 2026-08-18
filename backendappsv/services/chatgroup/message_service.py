#services/chatgoup/message_service.py
# services/chatgroup/message_service.py
from sqlalchemy.orm import Session
from sqlalchemy import text
from models.chat_model import ChatMessage, ChatGroup, User  # Đảm bảo các Model đã được định nghĩa
from datetime import datetime

class MessageService:
    @staticmethod
    def save_new_message(db: Session, sender_code: str, group_id: str, content: str, 
                         sender_name: str = None, sender_role: str = None, 
                         msg_type: str = "TEXT", file_url: str = None, reply_id: int = None):
        """
        Lưu tin nhắn mới: Đã cập nhật để nhận sender_name và sender_role từ Socket.
        """
        
        # 1. Xử lý lấy tên người được Reply (nếu có)
        reply_name = None
        if reply_id:
            orig = db.query(ChatMessage).filter(ChatMessage.MessageId == reply_id).first()
            if orig:
                reply_name = orig.SenderName

        # 2. Tạo bản ghi tin nhắn mới
        new_msg = ChatMessage(
            GroupId=group_id,
            SenderCode=sender_code,
            SenderName=sender_name,      # 🔥 Đã có biến để hứng
            SenderRole=sender_role,      # 🔥 Đã có biến để hứng
            MessageContent=content,
            MessageType=msg_type,
            FileUrl=file_url,
            ReplyToId=reply_id,
            ReplyToName=reply_name,
            CreatedAt=datetime.now(),
            IsDeleted=False
        )
        db.add(new_msg)
        
        # 3. Cập nhật Snippet cho danh sách nhóm ngoài màn hình
        group = db.query(ChatGroup).filter(ChatGroup.GroupId == group_id).first()
        if group:
            group.LastMessageAt = datetime.now()
            group.LastMessageSnippet = f"{sender_name}: {content[:50]}"
        
        db.commit()
        db.refresh(new_msg)
        return new_msg

    @staticmethod
    def push_to_notification_queue(db: Session, group_id: str, sender_code: str, sender_name: str, content: str, online_users: list = []):
        """
        Đẩy tin nhắn vào hàng đợi Push Firebase để thông báo cho các thành viên Offline.
        🔥 Tính năng mới: Lọc bỏ những user đang mở App (online_users).
        """
        try:
            # 1. LẤY DANH SÁCH THÀNH VIÊN: Trừ người gửi và những người đã tắt thông báo
            sql_get_members = text("""
                SELECT UserCode 
                FROM tbl_Chat_Members 
                WHERE GroupId = :group_id 
                  AND UserCode <> :sender_code 
                  AND IsMuted = 0
            """)
            
            members = db.execute(sql_get_members, {
                "group_id": group_id, 
                "sender_code": sender_code
            }).fetchall()

            # 2. CÁI PHỄU LỌC: Loại bỏ những người đang Online
            offline_ids = []
            for m in members:
                raw_code = str(m[0])
                # Chuẩn hóa mã (ví dụ CB1679 -> 1679) để đối chiếu
                clean_code = raw_code.strip().upper().replace('SV', '').replace('CB', '')
                
                # Nếu không nằm trong danh sách Online thì mới cho vào danh sách Push
                if clean_code not in online_users:
                    offline_ids.append(clean_code)

            # 🛑 KIỂM TRA CHỐT CHẶN: Nếu tất cả đều online thì KHÔNG làm gì cả
            if not offline_ids:
                print(f"🛑 [CHẶN PUSH] Mọi người đều đang mở nhóm {group_id}. Không bắn thông báo.")
                return

            # Gộp danh sách những người thực sự Offline thành chuỗi "1679,1680"
            ids_string = ",".join(offline_ids)

            # 3. CHÈN VÀO HÀNG ĐỢI: Sử dụng Scope để lưu group_id (Cho Flutter chuyển hướng)
            sql_insert = text("""
                INSERT INTO tbl_Notification_Queue (
                    Title, Body, IdNguoiHocs, Category, IsSent, CreatedAt, 
                    Priority, Sender, Summary, Scope
                ) VALUES (
                    :title, :body, :ids, 'CHAT_GROUP', 0, GETDATE(), 
                    3, :sender, :summary, :group_id
                )
            """)
            
            db.execute(sql_insert, {
                "title": f"💬 {sender_name}",
                "body": content[:150],
                "ids": ids_string, 
                "sender": sender_name,
                "summary": "Tin nhắn mới",
                "group_id": group_id # 🔥 Bắt buộc lưu vào đây để Worker bắn lên Firebase
            })
            
            db.commit()
            print(f"🚀 [PUSH NẠP ĐẠN] Đã nhét {len(offline_ids)} user offline của nhóm {group_id} vào hàng đợi.")
            
        except Exception as e:
            print(f"❌ [PUSH ERROR] Lỗi nạp hàng đợi: {e}")
            db.rollback()

    @staticmethod
    def delete_message(db: Session, message_id: int):
        """
        Thu hồi tin nhắn: Cập nhật cờ IsDeleted thay vì xóa vật lý khỏi DB.
        """
        msg = db.query(ChatMessage).filter(ChatMessage.MessageId == message_id).first()
        if msg:
            msg.IsDeleted = True
            db.commit()
            return True
        return False

    @staticmethod
    def get_history(db: Session, group_id: str, limit: int = 50):
        """
        Lấy lịch sử chat: Trả về dữ liệu sạch bao gồm SenderName để App hiển thị ngay.
        """
        return db.query(ChatMessage)\
                 .filter(ChatMessage.GroupId == group_id, ChatMessage.IsDeleted == False)\
                 .order_by(ChatMessage.MessageId.desc())\
                 .limit(limit).all()
# from sqlalchemy.orm import Session
# from models.chat_model import ChatMessage, ChatGroup
# from datetime import datetime

# class MessageService:
    # @staticmethod
    # def save_new_message(db: Session, sender_code: str, group_id: str, content: str, 
                         # msg_type: str = "TEXT", file_url: str = None, reply_id: int = None):
        # """Lưu tin nhắn mới với đầy đủ tính năng Reply, Ảnh, File"""
        
        # # 1. Tạo bản ghi tin nhắn mới theo đúng cấu trúc SQL của bạn
        # new_msg = ChatMessage(
            # GroupId=group_id,
            # SenderCode=sender_code,
            # MessageContent=content,
            # MessageType=msg_type,
            # FileUrl=file_url,
            # ReplyToId=reply_id,
            # CreatedAt=datetime.now(),
            # IsDeleted=False # Mặc định là 0 (Chưa xóa)
        # )
        # db.add(new_msg)
        
        # # 2. Xử lý "Snippet" thông minh cho danh sách Chat
        # # Nếu gửi ảnh/file thì snippet nên hiện loại tệp thay vì để trống
        # snippet = content[:50] if content else ""
        # if msg_type == "IMAGE":
            # snippet = "[Hình ảnh]"
        # elif msg_type == "FILE":
            # snippet = "[Tệp đính kèm]"
        # elif msg_type == "VIDEO":
            # snippet = "[Video]"

        # # 3. Cập nhật thông tin tin nhắn cuối cùng cho Nhóm
        # group = db.query(ChatGroup).filter(ChatGroup.GroupId == group_id).first()
        # if group:
            # group.LastMessageAt = datetime.now()
            # group.LastMessageSnippet = snippet
        
        # db.commit()
        # db.refresh(new_msg)
        # return new_msg

    # @staticmethod
    # def delete_message(db: Session, message_id: int):
        # """Thu hồi (xóa) tin nhắn"""
        # msg = db.query(ChatMessage).filter(ChatMessage.MessageId == message_id).first()
        # if msg:
            # msg.IsDeleted = True # Update cột IsDeleted lên 1
            # db.commit()
            # return True
        # return False

    # @staticmethod
    # def get_history(db: Session, group_id: str, limit: int = 50):
        # """Lấy lịch sử tin nhắn kèm theo các trường mở rộng"""
        # # Lấy từ mới nhất về cũ nhất, Flutter sẽ đảo ngược lại khi hiển thị
        # return db.query(ChatMessage)\
                 # .filter(ChatMessage.GroupId == group_id, ChatMessage.IsDeleted == False)\
                 # .order_by(ChatMessage.MessageId.desc())\
                 # .limit(limit).all()