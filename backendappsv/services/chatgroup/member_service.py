#services\chatgroup\member_services.py
from sqlalchemy.orm import Session
from models.chat_model import ChatMember
from datetime import datetime

class MemberService:
    @staticmethod
    def join_group_if_not_exists(db: Session, group_id: str, user_code: str, role: int = 3):
        """Tự động đăng ký thành viên vào nhóm nếu chưa tồn tại (Chống nhân đôi do tiền tố CB/SV)"""
        
        # 1. Lọc ra mã gốc (Xóa bỏ các chữ CB, SV nếu có để lấy đúng phần số)
        raw_code = str(user_code).strip().upper()
        base_code = raw_code.replace('CB', '').replace('SV', '')

        # 2. Tạo danh sách "bủa lưới" mọi trường hợp có thể lưu trong SQL
        possible_codes = [base_code, f"CB{base_code}", f"SV{base_code}"]

        # 3. Quét kiểm tra xem người này (dưới bất kỳ nhân dạng nào) đã ở trong nhóm chưa
        member = db.query(ChatMember).filter(
            ChatMember.GroupId == group_id, 
            ChatMember.UserCode.in_(possible_codes) # 🔥 QUAN TRỌNG: Quét bằng IN
        ).first()

        # 4. Nếu tuyệt đối chưa có, mới cho phép tạo mới
        if not member:
            new_member = ChatMember(
                GroupId=group_id,
                UserCode=user_code, # Vẫn lưu đúng cái mã mà App truyền lên (để đồng nhất với App)
                Role=role, 
                JoinedAt=datetime.now()
            )
            db.add(new_member)
            db.commit()
            return True, "CREATED"
            
        return True, "EXISTS"

    @staticmethod
    def get_member_role(db: Session, group_id: str, user_code: str):
        """Lấy quyền của User trong nhóm"""
        member = db.query(ChatMember).filter(
            ChatMember.GroupId == group_id, 
            ChatMember.UserCode == user_code
        ).first()
        return member.Role if member else 3