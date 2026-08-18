import pyodbc
import urllib
from core.settings import settings  # cấu hình tập trung (Pha 0)

# ==========================================================
# 1. CẤU HÌNH KẾT NỐI (Gộp trực tiếp vào đây)
# ==========================================================
SERVER = 'AI2025\\SQLEXPRESS02'
DATABASE = 'VinhUni_Local'
USERNAME = settings.db.user
PASSWORD = settings.db.password

# Chuỗi kết nối chuẩn cho máy chủ Remote
REMOTE_CONN_STR = (
    f"DRIVER={{ODBC Driver 17 for SQL Server}};"
    f"SERVER={SERVER};"
    f"DATABASE={DATABASE};"
    f"UID={USERNAME};"
    f"PWD={PASSWORD};"
    f"TrustServerCertificate=yes;"
)

class CertificateService:
    # 1. API lấy danh sách chứng chỉ
    @staticmethod
    def get_list():
        try:
            with pyodbc.connect(REMOTE_CONN_STR) as conn:
                cursor = conn.cursor()
                # Khớp theo file cũ: tbl_DM_ChungChi
                cursor.execute("SELECT ID, TenChungChi FROM tbl_DM_ChungChi WHERE HieuLuc = 1 ORDER BY TenChungChi")
                return [{"id": r[0], "ten": r[1]} for r in cursor.fetchall()]
        except Exception as e:
            print(f"❌ Lỗi SQL chung-chi: {e}")
            return []

    # 2. API lấy đợt thi
    @staticmethod
    def get_dates(id_cc: int):
        try:
            with pyodbc.connect(REMOTE_CONN_STR) as conn:
                cursor = conn.cursor()
                # Khớp theo file cũ: tbl_DotThi
                sql = """
                    SELECT ID, CONVERT(VARCHAR(10), NgayThi, 103) AS NgayThi 
                    FROM tbl_DotThi
                    WHERE HieuLuc = 1 AND IdChungChi = ?
                    ORDER BY NgayThi DESC
                """
                cursor.execute(sql, (id_cc,))
                # Trả về key 'ten_dot' để khớp với Flutter của Sơn
                return [{"id": r[0], "ten_dot": f"Thi ngày: {r[1]}"} for r in cursor.fetchall()]
        except Exception as e:
            print(f"❌ Lỗi SQL dot-thi: {e}")
            return []

    # 3. API Tra cứu tổng hợp (Tích hợp logic tbl_TraCuu_LichThi)
    @staticmethod
    def search_result(ma_sv: str, id_cc: int, id_dot: int = None):
        try:
            with pyodbc.connect(REMOTE_CONN_STR) as conn:
                cursor = conn.cursor()
                # Logic JOIN chính xác từ file tracuu.Py của bạn
                sql = """
                    SELECT 
                        s.MaSinhVien, 
                        (ISNULL(s.Ho, '') + ' ' + ISNULL(s.Ten, '')) AS HoTen, 
                        s.NgaySinh, s.TenLopHanhChinh AS Lop,
                        lt.PhongThi, lt.LanThi,
                        lt.KetQuaDoc, lt.KetQuaViet, lt.KetQuaNghe, lt.KetQuaNoi,
                        lt.KetQuaTong, lt.KetQuaTB, lt.KetQuaBac,
                        CONVERT(VARCHAR(10), d.NgayThi, 103) AS NgayThiFormatted,
                        c.TenChungChi, e.DienGiai, e.ThoiGian
                    FROM [dbo].[tbl_TraCuu_LichThi] lt
                    JOIN [dbo].[StudentProfiles] s ON lt.MaSinhVien = s.MaSinhVien
                    JOIN [dbo].[tbl_DotThi] d ON lt.IdDotThi = d.ID
                    JOIN [dbo].[tbl_DM_ChungChi] c ON lt.IdChungChi = c.ID
                    JOIN [dbo].[tbl_CaThi] e ON lt.CaThi = e.KyHieu
                    WHERE lt.MaSinhVien = ? AND lt.IdChungChi = ? AND lt.HieuLuc = 1
                """
                params = [str(ma_sv).strip(), id_cc]
                if id_dot:
                    sql += " AND lt.IdDotThi = ?"
                    params.append(id_dot)

                cursor.execute(sql, params)
                rows = cursor.fetchall()
                if not rows: return None

                # Định dạng dữ liệu trả về cho App Flutter
                results = []
                for r in rows:
                    results.append({
                        "ten_mon": r[14], # TenChungChi
                        "ten_dot": "--",
                        "ngay_thi": r[13], # NgayThiFormatted
                        "phong_thi": r[4], # PhongThi
                        "lan_thi": r[5],
                        "ca_thi": r[15],   # DienGiai
                        "thoi_gian": r[16], # ThoiGian
                        "diem": {
                            "doc": r[6], "viet": r[7], "nghe": r[8], "noi": r[9],
                            "tong": r[10], "tb": r[11], "bac": r[12]
                        }
                    })
                
                # Trả về cả thông tin sinh viên và danh sách lịch thi/điểm
                return {
                    "ho_ten": rows[0][1],
                    "ma_sv": rows[0][0],
                    "lop": rows[0][3],
                    "lich_thi": results
                }
        except Exception as e:
            print(f"❌ Lỗi thực thi tra cứu: {e}")
            return None