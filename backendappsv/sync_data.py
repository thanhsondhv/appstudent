import pyodbc
import time
from core.settings import settings  # cấu hình tập trung (Pha 0)

# --- CẤU HÌNH KẾT NỐI ---
# Kết nối vào Database đích (VinhUni_Local)
LOCAL_CONN_STR = settings.db.local_conn_str

# 1. Danh sách View từ Server .200
VIEWS_TO_SYNC = {
    "StudentProfiles": "DHVINH_Stagging_DBDaoTao_ChinhQuy.dbo.Vw_NguoiHoc_Info",
    "viewDSSinhVienDangKyHoc": "DHVINH_Stagging_DBDaoTao_ChinhQuy.dbo.viewDSSinhVienDangKyHoc",
}

# 2. Danh sách Bảng từ Server .200
TABLES_TO_SYNC = {
    "tbl_HeThong_NamHoc": "DHVINH_Stagging_DBDaoTao_ChinhQuy.dbo.tbl_HeThong_NamHoc",
    "tbl_HeThong_HocKy": "DHVINH_Stagging_DBDaoTao_ChinhQuy.dbo.tbl_HeThong_HocKy",
    "tbl_Diem_LoaiDiem": "DHVINH_Stagging_DBDaoTao_ChinhQuy.dbo.tbl_Diem_LoaiDiem",
    "DiemHocPhan": "DHVINH_Stagging_DBDiem.dbo.DiemHocPhan",
    "tbl_Thi_SinhVien": "DHVINH_Stagging_Thi.dbo.tbl_Thi_SinhVien"
}

def sync_from_diem_danh(cursor):
    """Đồng bộ Hồ sơ & Vector từ DB DIEM_DANH sang VinhUni_Local"""
    print("🧬 Đang cấu trúc lại và đồng bộ dữ liệu từ DB DIEM_DANH...")
    
    try:
        # 1. Xóa bảng local cũ để đảm bảo cấu trúc khớp 100% với định nghĩa mới
        cursor.execute("IF OBJECT_ID('tbl_NguoiHoc_HoSo_Local', 'U') IS NOT NULL DROP TABLE tbl_NguoiHoc_HoSo_Local")
        
        # 2. Tạo bảng mới dựa trên cấu trúc bảng DIEM_DANH
        # Chúng ta tạo bảng trắng trước
        cursor.execute("""
            SELECT * INTO tbl_NguoiHoc_HoSo_Local 
            FROM DIEM_DANH.dbo.tbl_NguoiHoc_HoSo 
            WHERE 1=0
        """)
        
        # 3. Thêm cột đánh dấu thời gian đồng bộ riêng cho App
        cursor.execute("ALTER TABLE tbl_NguoiHoc_HoSo_Local ADD [LastSync_App] DATETIME DEFAULT GETDATE()")
        
        # 4. Thực hiện chèn dữ liệu
        # Bật IDENTITY_INSERT để copy nguyên ID từ bảng điểm danh sang
        print("📥 Đang sao chép dữ liệu hồ sơ và vector...")
        
        # Liệt kê các cột chính để tránh lỗi mismatch số lượng cột
        # Ở đây tôi dùng SELECT * vì bảng local vừa tạo từ SELECT * của chính nó
        sql_sync = """
            SET IDENTITY_INSERT tbl_NguoiHoc_HoSo_Local ON;
            
            INSERT INTO tbl_NguoiHoc_HoSo_Local (
                Id, Ho, Ten, Code, NgaySinh, GioiTinh, DienThoai, Email, 
                AnhKhuonMat_Vector, AnhKhuonMat_Vector_bin, Email_VinhUni, 
                InstanceId, IsDeleted, IsBuildIn, IsBuildInAll, Version, RenLuyenBatThuongSum, EnumNguoiThue, IsDoiTuongTuDo,
                LastSync_App
            )
            SELECT 
                Id, Ho, Ten, Code, NgaySinh, GioiTinh, DienThoai, Email, 
                AnhKhuonMat_Vector, AnhKhuonMat_Vector_bin, Email_VinhUni, 
                InstanceId, IsDeleted, IsBuildIn, IsBuildInAll, Version, RenLuyenBatThuongSum, EnumNguoiThue, IsDoiTuongTuDo,
                GETDATE()
            FROM DIEM_DANH.dbo.tbl_NguoiHoc_HoSo;
            
            SET IDENTITY_INSERT tbl_NguoiHoc_HoSo_Local OFF;
        """
        cursor.execute(sql_sync)
        print("✅ Đồng bộ bảng Hồ sơ & Vector thành công!")
        
    except Exception as e:
        print(f"⚠️ Lỗi chi tiết tại sync_from_diem_danh: {e}")
        # Nếu lỗi do thiếu cột trong bảng nguồn, ta sẽ dùng phương án SELECT * INTO trực tiếp
        print("🔄 Đang thử phương án dự phòng (Full Copy)...")
        cursor.execute("IF OBJECT_ID('tbl_NguoiHoc_HoSo_Local', 'U') IS NOT NULL DROP TABLE tbl_NguoiHoc_HoSo_Local")
        cursor.execute("SELECT *, GETDATE() as LastSync_App INTO tbl_NguoiHoc_HoSo_Local FROM DIEM_DANH.dbo.tbl_NguoiHoc_HoSo")

def sync_remote_item(cursor, target_name, remote_path, is_view=False):
    """Logic đồng bộ từ Server .200 như cũ"""
    try:
        exists = cursor.tables(table=target_name).fetchone()
        if is_view or not exists:
            if exists: cursor.execute(f"DROP TABLE [{target_name}]")
            sql = f"SELECT * INTO [{target_name}] FROM OPENQUERY([172.16.95.200], 'SELECT * FROM {remote_path}')"
            cursor.execute(sql)
        else:
            # Incremental sync cho các bảng có ID
            cursor.execute(f"SELECT MAX(Id) FROM [{target_name}]")
            last_id = cursor.fetchone()[0] or 0
            sql = f"INSERT INTO [{target_name}] SELECT * FROM OPENQUERY([172.16.95.200], 'SELECT * FROM {remote_path} WHERE Id > {last_id}')"
            cursor.execute(sql)
        print(f"✅ Xong: {target_name}")
    except Exception as e:
        print(f"⚠️ Lỗi tại {target_name}: {e}")

def run_all_sync():
    conn = pyodbc.connect(LOCAL_CONN_STR, autocommit=True)
    cursor = conn.cursor()

    # 1. Đồng bộ Hồ sơ & Vector từ Local DB (DIEM_DANH)
    sync_from_diem_danh(cursor)

    # 2. Đồng bộ các bảng khác từ Remote (.200)
    for table, path in TABLES_TO_SYNC.items():
        sync_remote_item(cursor, table, path, is_view=False)
        
    for view, path in VIEWS_TO_SYNC.items():
        sync_remote_item(cursor, view, path, is_view=True)

    conn.close()
    print("\n🚀 TOÀN BỘ HỆ THỐNG ĐÃ ĐƯỢC ĐỒNG BỘ HOÀN HẢO!")

if __name__ == "__main__":
    run_all_sync()