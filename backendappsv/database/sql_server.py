import pyodbc
import asyncio
from config.settings import settings

async def get_db_connection():
    return await asyncio.to_thread(pyodbc.connect, settings.REMOTE_CONN_STR)

async def get_user_chat_groups(user_code: str):
    """Lấy danh sách nhóm chat khớp với schema tbl_Chat_Groups của Sơn"""
    conn = await get_db_connection()
    try:
        cursor = conn.cursor()
        # Join 2 bảng để lấy thông tin nhóm và quyền của User trong nhóm đó
        sql = """
            SELECT g.GroupId, g.GroupName, g.GroupType, g.IsLocked, m.Role
            FROM tbl_Chat_Groups g
            JOIN tbl_Chat_Members m ON g.GroupId = m.GroupId
            WHERE m.UserCode = ?
            ORDER BY g.CreatedAt DESC
        """
        cursor.execute(sql, (user_code,))
        rows = cursor.fetchall()
        
        return [
            {
                "group_id": r[0],
                "group_name": r[1],
                "group_type": r[2],
                "is_locked": bool(r[3]),
                "my_role": r[4] # 1: Trưởng, 2: Phó, 3: Thành viên
            } for r in rows
        ]
    except Exception as e:
        print(f"❌ Lỗi SQL Get Groups: {e}")
        return []
    finally:
        conn.close()