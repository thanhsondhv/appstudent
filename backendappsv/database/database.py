# C:\vinhuni_project\database\database.py
import pyodbc
from core.settings import settings  # cấu hình tập trung (Pha 0)

# Cấu hình SQL Server của VinhUni
DB_CONFIG = {
    "server": 'AI2025\\SQLEXPRESS02',
    "database": 'VinhUni_Local',
    "user": settings.db.user,
    "password": settings.db.password
}

# Chuỗi kết nối chuẩn
CONN_STR = (
    f"DRIVER={{ODBC Driver 17 for SQL Server}};"
    f"SERVER={DB_CONFIG['server']};"
    f"DATABASE={DB_CONFIG['database']};"
    f"UID={DB_CONFIG['user']};"
    f"PWD={DB_CONFIG['password']};"
)

def get_db_conn():
    """Hàm tạo kết nối SQL Server"""
    try:
        # Sử dụng autocommit=True để tránh treo transaction khi chạy đồng bộ
        return pyodbc.connect(CONN_STR, autocommit=True)
    except Exception as e:
        print(f"❌ Lỗi kết nối Database: {e}")
        return None