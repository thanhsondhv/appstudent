import pyodbc
from core.settings import settings  # cấu hình tập trung (Pha 0)

class AdminDBService:
    def __init__(self):
        self.DB_SERVER = settings.db.server
        self.DB_NAME = settings.db.name
        self.DB_USER = settings.db.user
        self.DB_PASSWORD = settings.db.password
        self.connection_string = (
            f"DRIVER={{ODBC Driver 17 for SQL Server}};"
            f"SERVER={self.DB_SERVER};"
            f"DATABASE={self.DB_NAME};"
            f"UID={self.DB_USER};"
            f"PWD={self.DB_PASSWORD};"
        )

    def _get_conn(self):
        return pyodbc.connect(self.connection_string)

    def execute_non_query(self, sql, params=None):
        conn = self._get_conn()
        try:
            cursor = conn.cursor()
            cursor.execute(sql, params or ())
            conn.commit()
            return cursor.rowcount
        except Exception as e:
            print(f"🔥 Lỗi SQL: {e}")
            return 0
        finally:
            conn.close()

    def sync_weekly_schedule(self, events):
        """
        Đồng bộ lịch tuần và gọi Store Procedure để AI xử lý phân phối tin
        """
        count_new = 0
        sql_insert_schedule = """
        IF NOT EXISTS (SELECT 1 FROM tbl_WeeklySchedule WHERE EventHash = ?)
        BEGIN
            INSERT INTO tbl_WeeklySchedule 
            (EventDate, Session, TimeValue, Content, Participants, Location, Chairperson, EventHash, IsNotified)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)
        END
        """

        for ev in events:
            params = (
                ev['event_hash'], ev['event_date'], ev['session'], 
                ev['time_value'], ev['content'], ev['participants'], 
                ev['location'], ev['chairperson'], ev['event_hash']
            )
            
            # 1. Lưu vào bảng chính
            if self.execute_non_query(sql_insert_schedule, params) > 0:
                count_new += 1
                
                # 2. 🔥 GỌI STORE PROCEDURE ĐỂ AI XỬ LÝ (BAN, ĐƠN VỊ, XUNG ĐỘT)
                # Việc này giúp Python không cần quan tâm tên cột của bảng TKB nữa.
                self._call_ai_procedure(ev['event_hash'])
                    
        return count_new

    def _call_ai_procedure(self, event_hash):
        """Gọi Procedure xử lý thông báo ngầm trong SQL"""
        conn = self._get_conn()
        try:
            cursor = conn.cursor()
            # Gọi SP đã tạo ở turn trước
            cursor.execute("{CALL sp_AI_Process_Weekly_Notification (?)}", (event_hash,))
            conn.commit()
        except Exception as e:
            print(f"⚠️ Lỗi khi gọi SP AI: {e}")
        finally:
            conn.close()