import pyodbc
import time
from core.settings import settings  # cấu hình tập trung (Pha 0)

LOCAL_CONN_STR = settings.db.local_conn_str

TABLES_TO_SYNC = {
    "tbl_ThongBao": "DHVINH_Stagging_DBDaoTao_ChinhQuy.dbo.tbl_ThongBao",
    "tbl_Tkb_LopHocPhan": "DHVINH_Stagging_DBDaoTao_ChinhQuy.dbo.tbl_Tkb_LopHocPhan",
    "tbl_Tkb_LopHocPhan_LichHoc": "DHVINH_Stagging_DBDaoTao_ChinhQuy.dbo.tbl_Tkb_LopHocPhan_LichHoc",
    "tbl_HocPhan": "DHVINH_Stagging_DBDaoTao_ChinhQuy.dbo.tbl_HocPhan",
    "tbl_Thi_SinhVien": "DHVINH_Stagging_Thi.dbo.tbl_Thi_SinhVien",
    "tbl_Thi_DanhSachThi": "DHVINH_Stagging_Thi.dbo.tbl_Thi_DanhSachThi",
    "tbl_Thi_CaThi": "DHVINH_Stagging_Thi.dbo.tbl_Thi_CaThi",
    "DiemHocPhan": "DHVINH_PreProd_DBDiem.dbo.DiemHocPhan"
}

def run_sync():
    conn = pyodbc.connect(LOCAL_CONN_STR, autocommit=True)
    cursor = conn.cursor()
    
    for table, remote_path in TABLES_TO_SYNC.items():
        try:
            print(f"🔄 Đang đồng bộ: {table}...")
            if cursor.tables(table=table).fetchone():
                cursor.execute(f"DROP TABLE [{table}]")
            
            # Kéo dữ liệu
            sql = f"SELECT * INTO [{table}] FROM OPENQUERY([172.16.95.200], 'SELECT * FROM {remote_path}')"
            cursor.execute(sql)
            
            # Chỉ tạo Index cho các bảng có chứa dữ liệu sinh viên
            student_tables = ["DiemHocPhan", "tbl_Thi_SinhVien"]
            if table in student_tables:
                cursor.execute(f"CREATE INDEX idx_{table}_sv ON [{table}] (IdNguoiHoc)")
            if table == "tbl_Tkb_LopHocPhan":
                cursor.execute(f"CREATE INDEX idx_lhp_code ON [{table}] (Code)")
                cursor.execute(f"CREATE INDEX idx_lhp_inst ON [{table}] (InstanceId)")
                
        except Exception as e:
            print(f"⚠️ Lỗi tại bảng {table}: {e}")
    
    print("🔄 Đang làm mới bảng viewDSSinhVienDangKyHoc...")
    try:
        if cursor.tables(table="viewDSSinhVienDangKyHoc").fetchone():
            cursor.execute("DROP TABLE viewDSSinhVienDangKyHoc")
        cursor.execute("SELECT * INTO viewDSSinhVienDangKyHoc FROM OPENQUERY([172.16.95.200], 'SELECT * FROM DHVINH_Stagging_DBDaoTao_ChinhQuy.dbo.viewDSSinhVienDangKyHoc')")
        cursor.execute("CREATE INDEX idx_view_sv ON viewDSSinhVienDangKyHoc (IdNguoiHoc)")
    except Exception as e:
        print(f"⚠️ Lỗi bảng view: {e}")

    conn.close()
    print("✅ Đồng bộ hoàn tất!")

if __name__ == "__main__":
    run_sync()