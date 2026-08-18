from datetime import datetime, timedelta
from typing import Optional, Tuple
# 🔥 Đã sửa đường dẫn để trỏ đúng vào file database.py của bạn
from database.database import get_db_conn 

class BlacklistManager:
    @staticmethod
    def get_lock_time(target: str) -> Tuple[int, int]:
        """Tính toán thời gian khóa dựa trên lịch sử vi phạm"""
        try:
            # Sử dụng hàm get_db_conn bạn đã viết
            with get_db_conn() as conn:
                cursor = conn.cursor()
                cursor.execute("SELECT total_violations FROM ViolationHistory WHERE target_value = ?", (target,))
                row = cursor.fetchone()
                
                count = (row[0] + 1) if row else 1
                # Lần 1: 5p | Lần 2: 30p | Lần 3: 120p | Lần 4+: 1440p (24h)
                lock_map = {1: 5, 2: 30, 3: 120, 4: 1440}
                return lock_map.get(count, 1440), count
        except Exception as e:
            print(f"⚠️ Lỗi lấy lock_time: {e}")
            return 5, 1

    @staticmethod
    def check_is_blocked(target: str) -> Optional[dict]:
        """Kiểm tra xem đối tượng có đang bị 'nhốt' không"""
        if not target: return None
        try:
            with get_db_conn() as conn:
                cursor = conn.cursor()
                query = """
                    SELECT TOP 1 target_value, reason, expired_at, violation_count 
                    FROM Blacklist 
                    WHERE target_value = ? AND expired_at > GETDATE()
                    ORDER BY created_at DESC
                """
                cursor.execute(query, (target,))
                row = cursor.fetchone()
                if row:
                    return {
                        "target_value": row[0],
                        "reason": row[1],
                        "expired_at": row[2],
                        "violation_count": row[3]
                    }
                return None
        except Exception as e:
            print(f"⚠️ Lỗi check_is_blocked: {e}")
            return None

    @staticmethod
    async def add_to_blacklist(target: str, target_type: str, reason: str):
        """Thực thi lệnh 'nhốt' vào SQL Server VinhUni và in cảnh báo"""
        
        # 1. Lấy thời gian khóa và số lần vi phạm dựa trên lịch sử
        lock_minutes, count = BlacklistManager.get_lock_time(target)
        expiry = datetime.now() + timedelta(minutes=lock_minutes)

        try:
            with get_db_conn() as conn:
                cursor = conn.cursor()

                # --- 🔥 PHẦN 1: IN CẢNH BÁO RA TERMINAL ĐỂ SƠN THEO DÕI ---
                print("\n" + "!" * 60)
                print(f"🚨 [CẢNH BÁO TOOL] PHÁT HIỆN VI PHẠM TẠI VINH UNI")
                print(f"👤 Đối tượng : {target} ({target_type})")
                print(f"🛠️ Hành vi   : {reason}")
                print(f"⏱️ Trạng thái : Khóa lần thứ {count} trong {lock_minutes} phút")
                print(f"📅 Hết hạn   : {expiry.strftime('%H:%M:%S %d/%m/%Y')}")
                print("!" * 60 + "\n")

                # --- 🔥 PHẦN 2: CẬP NHẬT DATABASE (SQL SERVER) ---
                
                # 1. Cập nhật hoặc thêm mới vào lịch sử vi phạm (Sổ bìa đen vĩnh viễn)
                cursor.execute("""
                    IF EXISTS (SELECT 1 FROM ViolationHistory WHERE target_value = ?)
                        UPDATE ViolationHistory 
                        SET total_violations = ?, last_violation_at = GETDATE() 
                        WHERE target_value = ?
                    ELSE
                        INSERT INTO ViolationHistory (target_value, total_violations) 
                        VALUES (?, ?)
                """, (target, count, target, target, count))

                # 2. Đưa vào phòng tạm giam (Blacklist hiện hành)
                cursor.execute("""
                    INSERT INTO Blacklist (target_value, target_type, reason, expired_at, violation_count)
                    VALUES (?, ?, ?, ?, ?)
                """, (target, target_type, reason, expiry, count))
                
                # SQL Server cần commit để xác nhận thay đổi dữ liệu
                conn.commit()

            print(f"✅ [V3 FUSION] Hệ thống đã thực thi lệnh cấm cho: {target}")

        except Exception as e:
            print(f"🔥 [LỖI NGHIÊM TRỌNG] Không thể thực thi add_to_blacklist: {e}")

    @staticmethod
    async def verify_request_access(ip: str, device_id: Optional[str] = None, student_code: Optional[str] = None):
        """Kiểm tra đa tầng: MSV > Device ID > IP để xử lý Shared IP tại trường"""
        for target, t_type in [(student_code, "STUDENT_CODE"), (device_id, "DEVICE_ID"), (ip, "IP")]:
            if target:
                block = BlacklistManager.check_is_blocked(target)
                if block: return block, t_type
        return None, None