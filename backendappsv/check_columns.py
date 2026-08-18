import pyodbc
from core.settings import settings  # cấu hình tập trung (Pha 0)

# Cấu hình kết nối
REMOTE_CONN_STR = settings.db.local_conn_str

def super_search():
    try:
        conn = pyodbc.connect(REMOTE_CONN_STR)
        cursor = conn.cursor()
        
        # Danh sách 2 Database cần quét
        databases = ["DHVINH_Stagging_DBDaoTao_ChinhQuy", "DHVINH_PreProd_DBDiem"]
        
        print("🔍 Đang truy quét bảng Khung Lịch thi trên Server .200...")
        
        for db in databases:
            print(f"\n--- Kiểm tra Database: {db} ---")
            # Sử dụng cú pháp 4 thành phần: [LinkedServer].[Database].[Schema].[Table]
            sql = f"""
            SELECT TABLE_NAME, COLUMN_NAME 
            FROM [172.16.95.200].[{db}].INFORMATION_SCHEMA.COLUMNS 
            WHERE (COLUMN_NAME LIKE '%NgayThi%' OR COLUMN_NAME LIKE '%PhongThi%' OR COLUMN_NAME LIKE '%CaThi%' OR COLUMN_NAME LIKE '%TietThi%')
              AND TABLE_NAME NOT LIKE '%Log%' 
              AND TABLE_NAME NOT LIKE '%Temp%'
            """
            cursor.execute(sql)
            results = cursor.fetchall()
            
            # Nhóm kết quả theo tên bảng
            tables = {}
            for row in results:
                if row[0] not in tables: tables[row[0]] = []
                tables[row[0]].append(row[1])
            
            if not tables:
                print("  (Không tìm thấy cột phù hợp trong DB này)")
            else:
                for table, columns in tables.items():
                    print(f"⭐ Bảng tiềm năng: {table} | Các cột: {', '.join(columns)}")

        conn.close()
    except Exception as e:
        print(f"❌ Lỗi: {str(e)}")

if __name__ == "__main__":
    super_search()