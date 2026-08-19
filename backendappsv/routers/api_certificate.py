from fastapi import APIRouter, status
from fastapi.responses import JSONResponse
import pyodbc
from core.settings import settings  # cấu hình tập trung (Pha 0)

# Cấu hình kết nối lấy từ Main.py
DB_SERVER = settings.db.server
DB_USER = settings.db.user
DB_PASSWORD = settings.db.password
DB_NAME = settings.db.name
REMOTE_CONN_STR = settings.db.local_conn_str

router = APIRouter(prefix="/api/certificate", tags=["Certificate"])


@router.get("/categories")
def get_categories():
    try:
        sql = """
            SELECT * FROM OPENQUERY([172.16.95.200], '
                SELECT Id, Ten FROM U202003_Stagging_vanbangChungChi_V5.dbo.tbl_LoaiVanBang
                WHERE IsDeleted = 0 AND ischungchi = 1
            ')
        """
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            cursor.execute(sql)
            return [{"id": str(r[0]), "name": r[1]} for r in cursor.fetchall()]
    except: return []

def clean_id(raw_id: str) -> str:
    """Làm sạch mã sinh viên, loại bỏ tiền tố SV"""
    if not raw_id: return ""
    clean = str(raw_id).strip().upper()
    return clean.replace("SV", "") if clean.startswith("SV") else clean

@router.get("/student/{student_id}")
def get_student_certs(student_id: str, type_id: str = "ALL"):
    try:
        sid = clean_id(student_id)
        
        # Xử lý filter loại chứng chỉ
        f_cc = f" AND cc.IdLoaiVanBang = CAST(''{type_id}'' AS UNIQUEIDENTIFIER) " if type_id != "ALL" else ""
        f_cn = f" AND cn.IdLoaiVanBang = CAST(''{type_id}'' AS UNIQUEIDENTIFIER) " if type_id != "ALL" else ""

        sql = f"""
            SELECT * FROM OPENQUERY([172.16.95.200], '
                -- Phần 1: Nội bộ
                SELECT lvb.Ten, CAST(cc.Diem AS NVARCHAR(MAX)) as Diem, cc.NgayCap, cc.IsDat, cc.SoQuyetDinh
                FROM U202003_Stagging_vanbangChungChi_V5.dbo.ChungChi_NguoiHoc cc
                JOIN U202003_Stagging_vanbangChungChi_V5.dbo.tbl_LoaiVanBang lvb ON cc.IdLoaiVanBang = lvb.Id
                WHERE (cc.MaNguoiHoc = ''{sid}'' OR cc.MaNguoiHoc = ''SV{sid}'')
                {f_cc} AND cc.IsDeleted = 0 AND lvb.ischungchi = 1

                UNION ALL

                -- Phần 2: Công nhận tương đương (Dựa trên danh sách cột bạn cung cấp)
                SELECT lvb.Ten, CAST(cn.GhiChu AS NVARCHAR(MAX)) as Diem, cn.NgayHieuLuc as NgayCap, 1 as IsDat, cn.SoQuyetDinh
                FROM U202003_Stagging_vanbangChungChi_V5.dbo.ChungChi_QuyetDinh_CongNhan cn
                JOIN U202003_Stagging_vanbangChungChi_V5.dbo.tbl_LoaiVanBang lvb ON cn.IdLoaiVanBang = lvb.Id
                WHERE (cn.MaSV = ''{sid}'' OR cn.MaSV = ''SV{sid}'')
                {f_cn} AND cn.IsDeleted = 0
            ')
        """
        
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            cursor.execute(sql)
            return [{
                "ten": r[0], 
                "diem": r[1] if (r[1] and r[1] != 'None') else "Đạt",
                "ngay_cap": r[2].strftime('%d/%m/%Y') if r[2] else "--",
                "is_dat": bool(r[3]), 
                "so_qd": r[4]
            } for r in cursor.fetchall()]
            
    except Exception as e:
        print(f"🔥 SQL Error: {e}")
        return []