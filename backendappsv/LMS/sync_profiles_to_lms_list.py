import pyodbc
from core.settings import settings  # cấu hình tập trung (Pha 0)

# --- CẤU HÌNH KẾT NỐI SƠN CUNG CẤP ---
LOCAL_CONN_STR = settings.db.local_conn_str

def sync_filtered_profiles():
    try:
        conn = pyodbc.connect(LOCAL_CONN_STR)
        cursor = conn.cursor()
        print("✅ Kết nối SQL Server thành công!")

        # 1. Câu lệnh nạp dữ liệu với bộ lọc Khóa 64, 65, 66
        # IdKhoaHoc là nvarchar nên để trong dấu nháy đơn
        sql_sync = """
        INSERT INTO Students_LMS (MaSV, Password, FullName)
        SELECT MaSinhVien, MaSinhVien, MAX(HoVaTen)
        FROM StudentProfiles
        WHERE IdTrangThai = 1 
          AND IsDeleted = 0 
          AND IdKhoaHoc IN ('K64', 'K65', 'K66')
          AND MaSinhVien IS NOT NULL
        GROUP BY MaSinhVien
        """
        
        print("🔄 Đang lọc và nạp sinh viên khóa 64-66...")
        cursor.execute(sql_sync)
        rows_added = cursor.rowcount
        conn.commit()
        
        print(f"🚀 Đã nạp thành công {rows_added} sinh viên mục tiêu vào danh sách.")
        
        # 2. Kiểm tra tổng số
        cursor.execute("SELECT COUNT(*) FROM Students_LMS")
        total = cursor.fetchone()[0]
        print(f"📊 Tổng số sinh viên cần quét hiện tại: {total}")

        conn.close()
    except Exception as e:
        print(f"🔥 Lỗi: {str(e)}")

if __name__ == "__main__":
    sync_filtered_profiles()