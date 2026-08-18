import pyodbc
import json
import os
from core.settings import settings  # cấu hình tập trung (Pha 0)

# Cấu hình kết nối tại máy nguồn
DB_CONFIG = settings.db.local_conn_str

def export_to_json():
    try:
        conn = pyodbc.connect(DB_CONFIG)
        cursor = conn.cursor()
        print("📥 Đang trích xuất dữ liệu từ VinhUni_Local...")
        
        cursor.execute("""
            SELECT Id, IdNguoiHoc, HoVaTen, MaSinhVien, TenLopHanhChinh, MaDoiTuongDaoTao, UserId, IsDeleted 
            FROM StudentProfiles WHERE IsDeleted = 0
        """)
        
        columns = [column[0] for column in cursor.description]
        results = []
        for row in cursor.fetchall():
            results.append(dict(zip(columns, row)))
            
        # Lưu ra file JSON
        with open('students_data.json', 'w', encoding='utf-8') as f:
            json.dump(results, f, ensure_ascii=False, indent=4, default=str)
            
        print(f"✅ Đã xuất {len(results)} bản ghi ra file students_data.json")
        conn.close()
    except Exception as e:
        print(f"❌ Lỗi: {e}")

if __name__ == "__main__":
    export_to_json()