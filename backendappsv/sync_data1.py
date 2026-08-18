import pyodbc
import time
from core.settings import settings  # cấu hình tập trung (Pha 0)

# --- CẤU HÌNH KẾT NỐI (MÁY LOCAL) ---
LOCAL_CONN_STR = settings.db.local_conn_str.replace(
    f"DATABASE={settings.db.name}", "DATABASE=master"
)

def run_sync():
    start_time = time.time()
    try:
        conn = pyodbc.connect(LOCAL_CONN_STR, autocommit=True)
        cursor = conn.cursor()
        cursor.execute("IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'VinhUni_Local') CREATE DATABASE VinhUni_Local")
        cursor.execute("USE VinhUni_Local")

        print("🚀 Đang khởi tạo lại Database Local...")

        # Danh sách các bảng danh mục (Nạp toàn bộ vì dung lượng nhẹ)
        tasks = [
            ("tbl_ThongBao", "SELECT * FROM DHVINH_Stagging_DBDaoTao_ChinhQuy.dbo.tbl_ThongBao WHERE NgayPhatHanh >= DATEADD(month, -6, GETDATE())"),
            ("tbl_Tkb_LopHocPhan_TongHop", "SELECT lhp.Ten, lhp.Code, tkb.MaPhong, tkb.NgayHoc, tkb.TietHoc, tkb.TuanHocFulls, lhp.NamHoc, lhp.IdHocKy FROM DHVINH_Stagging_DBDaoTao_ChinhQuy.dbo.tbl_Tkb_LopHocPhan lhp INNER JOIN DHVINH_Stagging_DBDaoTao_ChinhQuy.dbo.tbl_Tkb_LopHocPhan_LichHoc tkb ON lhp.Id = tkb.IdLopHocPhan"),
            ("tbl_HocPhan", "SELECT Id, Code, Ten, SoTinChi FROM DHVINH_Stagging_DBDaoTao_ChinhQuy.dbo.tbl_HocPhan"),
        ]

        for table_name, remote_sql in tasks:
            print(f"--- Đang nạp: {table_name} ---")
            if cursor.tables(table=table_name).fetchone(): cursor.execute(f"DROP TABLE {table_name}")
            cursor.execute(f"SELECT * INTO {table_name} FROM OPENQUERY([172.16.95.200], '{remote_sql}')")

        # 2. Xử lý Đăng ký học (Ưu tiên nạp mã của bạn trước để tránh treo)
        print("--- Đang nạp: viewDSSinhVienDangKyHoc ---")
        if cursor.tables(table="viewDSSinhVienDangKyHoc").fetchone(): cursor.execute("DROP TABLE viewDSSinhVienDangKyHoc")
        cursor.execute("SELECT * INTO viewDSSinhVienDangKyHoc FROM OPENQUERY([172.16.95.200], 'SELECT * FROM DHVINH_Stagging_DBDaoTao_ChinhQuy.dbo.viewDSSinhVienDangKyHoc WHERE IdNguoiHoc = ''18574802010209''')")
        cursor.execute("INSERT INTO viewDSSinhVienDangKyHoc SELECT * FROM OPENQUERY([172.16.95.200], 'SELECT TOP 5000 * FROM DHVINH_Stagging_DBDaoTao_ChinhQuy.dbo.viewDSSinhVienDangKyHoc ORDER BY MaLopHP DESC') WHERE IdNguoiHoc <> '18574802010209'")

        # 3. Xử lý Điểm
        print("--- Đang nạp: DiemHocPhan ---")
        if cursor.tables(table="DiemHocPhan").fetchone(): cursor.execute("DROP TABLE DiemHocPhan")
        cursor.execute("SELECT * INTO DiemHocPhan FROM OPENQUERY([172.16.95.200], 'SELECT * FROM DHVINH_PreProd_DBDiem.dbo.DiemHocPhan WHERE IdNguoiHoc = ''18574802010209''')")
        cursor.execute("INSERT INTO DiemHocPhan SELECT * FROM OPENQUERY([172.16.95.200], 'SELECT TOP 5000 * FROM DHVINH_PreProd_DBDiem.dbo.DiemHocPhan ORDER BY Id DESC') WHERE IdNguoiHoc <> '18574802010209'")

        # 4. Xử lý Điểm thành phần (Chỉ lấy của riêng bạn)
        print("--- Đang nạp: Diem_ThanhPhan ---")
        if cursor.tables(table="Diem_ThanhPhan").fetchone(): cursor.execute("DROP TABLE Diem_ThanhPhan")
        cursor.execute("SELECT * INTO Diem_ThanhPhan FROM OPENQUERY([172.16.95.200], 'SELECT * FROM DHVINH_PreProd_DBDiem.dbo.Diem_ThanhPhan WHERE IdDiem IN (SELECT Id FROM DHVINH_PreProd_DBDiem.dbo.DiemHocPhan WHERE IdNguoiHoc = ''18574802010209'')')")

        # 5. Tạo Index
        cursor.execute("CREATE INDEX idx_sv_reg ON viewDSSinhVienDangKyHoc (IdNguoiHoc)")
        cursor.execute("CREATE INDEX idx_sv_grade ON DiemHocPhan (IdNguoiHoc)")
        cursor.execute("CREATE INDEX idx_id_diem ON Diem_ThanhPhan (IdDiem)")

        print("\n" + "✨" * 20)
        print(f"ĐỒNG BỘ THÀNH CÔNG TRONG {round(time.time() - start_time, 2)} GIÂY")
        print("✨" * 20)

    except Exception as e:
        print(f"❌ Lỗi đồng bộ: {str(e)}")
    finally:
        if 'conn' in locals(): conn.close()

if __name__ == "__main__":
    run_sync()