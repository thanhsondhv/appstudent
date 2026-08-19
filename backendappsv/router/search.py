from fastapi import APIRouter, Query
from fastapi.responses import JSONResponse
import pyodbc
from typing import Optional
from core.settings import settings  # cấu hình tập trung (Pha 0)

# --- CẤU HÌNH KẾT NỐI DATABASE ---
DB_SERVER = settings.db.server
DB_USER = settings.db.user
DB_PASSWORD = settings.db.password
DB_NAME = settings.db.name
REMOTE_CONN_STR = settings.db.local_conn_str

router = APIRouter(
    prefix="/api",
    tags=["Tìm Kiếm Tổng Hợp"]
)

def clean_student_id(raw_id: str) -> str:
    if not raw_id: return ""
    clean = str(raw_id).strip().upper() 
    if clean.startswith("CB"): return clean
    if clean.startswith("SV") and clean[2:].isdigit(): return clean[2:]
    return clean

# =======================================================
# 1. API TÌM KIẾM MÔN HỌC & ĐIỂM SỐ
# =======================================================
# =======================================================
# 1. API TÌM KIẾM MÔN HỌC & ĐIỂM SỐ (ĐÃ FIX LỖI ÉP KIỂU INT)
# =======================================================
@router.get("/search-subject")
def search_subject(
    student_id: str = Query(..., description="Mã sinh viên"),
    keyword: str = Query("", description="Từ khóa tìm kiếm")
):
    try:
        sid = clean_student_id(student_id)
        search_term = f"%{keyword.strip()}%"
        
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            
            sql = """
                SELECT 
                    lhp.Ten AS subject_name,
                    MAX(d.Diem) AS grade,
                    (SELECT TOP 1 ISNULL(CAST(tkb.MaPhong AS NVARCHAR(100)), '') + ' - Tiết: ' + ISNULL(CAST(tkb.TietHoc AS NVARCHAR(50)), '') 
                     FROM tbl_Tkb_LopHocPhan_LichHoc tkb WHERE tkb.IdLopHocPhan = lhp.Id) AS schedule,
                    (SELECT TOP 1 thi.NgayThi 
                     FROM tbl_Thi_SinhVien tsv 
                     INNER JOIN tbl_Thi_DanhSachThi thi ON tsv.IdDanhSachThi = thi.Id 
                     WHERE tsv.InstanceIdLopHocPhan = lhp.InstanceId AND (RTRIM(tsv.IdNguoiHoc) = ? OR RTRIM(tsv.IdNguoiHoc) = 'SV' + ?)) AS exam_date,
                    (SELECT TOP 1 ISNULL(CAST(tkb.MaPhong AS NVARCHAR(100)), 'P.' + CAST(thi.PhongThiSo AS NVARCHAR(50))) 
                     FROM tbl_Thi_SinhVien tsv 
                     INNER JOIN tbl_Thi_DanhSachThi thi ON tsv.IdDanhSachThi = thi.Id 
                     LEFT JOIN tbl_Tkb_LopHocPhan_LichHoc tkb ON lhp.Id = tkb.IdLopHocPhan 
                     WHERE tsv.InstanceIdLopHocPhan = lhp.InstanceId AND (RTRIM(tsv.IdNguoiHoc) = ? OR RTRIM(tsv.IdNguoiHoc) = 'SV' + ?)) AS exam_room
                FROM DiemHocPhan d
                INNER JOIN tbl_Tkb_LopHocPhan lhp ON d.IdLopHocPhan = lhp.InstanceId 
                WHERE (RTRIM(d.IdNguoiHoc) = ? OR RTRIM(d.IdNguoiHoc) = 'SV' + ?)
                  AND lhp.Ten LIKE ? 
                GROUP BY lhp.Id, lhp.Ten, lhp.InstanceId
            """
            
            params = (sid, sid, sid, sid, sid, sid, search_term)
            cursor.execute(sql, params)
            
            results = []
            for row in cursor.fetchall():
                results.append({
                    "subject_name": row.subject_name,
                    "schedule": row.schedule if row.schedule else "Chưa xếp lịch",
                    "exam_date": row.exam_date.strftime('%H:%M - %d/%m/%Y') if row.exam_date else None,
                    "exam_room": row.exam_room if row.exam_room else "Chưa có",
                    "grade": round(row.grade, 2) if row.grade is not None else None
                })
                
        return {"status": "success", "results": results}
    except Exception as e:
        print(f"🔥 Lỗi Search Subject DB: {e}")
        return JSONResponse(status_code=500, content={"status": "error", "message": str(e), "results": []})


# =======================================================
# 2. API TÌM KIẾM THÔNG BÁO
# =======================================================
# =======================================================
# 2. API TÌM KIẾM THÔNG BÁO (CHUẨN 100%)
# =======================================================
@router.get("/search-notification")
def search_notification(
    student_id: str = Query(..., description="Mã sinh viên"),
    keyword: str = Query("", description="Từ khóa tìm kiếm")
):
    try:
        sid_clean = clean_student_id(student_id)
        search_term = f"%{keyword.strip()}%"
        
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            
            # Sử dụng CTE để gộp thông báo, không dùng tiền tố N trước ?
            sql = """
                WITH CombinedNotifs AS (
                    SELECT 
                        q.Title as TieuDe, 
                        q.Body as NoiDung, 
                        q.CreatedAt as NgayPhatHanh
                    FROM tbl_Notification_Queue q
                    WHERE (REPLACE(UPPER(RTRIM(q.StudentId)), 'SV', '') = ?)
                      AND q.IsSent = 1
                      AND (q.Title LIKE ? OR q.Body LIKE ?)

                    UNION ALL

                    SELECT 
                        t.TieuDe, 
                        CAST(t.NoiDung AS NVARCHAR(MAX)) as NoiDung, 
                        CAST(t.NgayPhatHanh AS DATETIME) as NgayPhatHanh
                    FROM tbl_ThongBao t
                    WHERE (CAST(t.IdNguoiHocs AS NVARCHAR(MAX)) LIKE ? OR t.IdLoaiThongBao = 2)
                      AND t.IsDeleted = 0
                      AND (t.TieuDe LIKE ? OR CAST(t.NoiDung AS NVARCHAR(MAX)) LIKE ?)
                )
                SELECT TOP 30 * FROM CombinedNotifs
                ORDER BY NgayPhatHanh DESC
            """
            
            params = (sid_clean, search_term, search_term, f'%{sid_clean}%', search_term, search_term)
            cursor.execute(sql, params)
            
            results = []
            for row in cursor.fetchall():
                results.append({
                    "title": row.TieuDe or "Không có tiêu đề",
                    "date": row.NgayPhatHanh.strftime('%H:%M - %d/%m/%Y') if row.NgayPhatHanh else "",
                    "content": row.NoiDung or "Không có nội dung"
                })
                
        return {"status": "success", "results": results}
    except Exception as e:
        print(f"🔥 Lỗi Search Notification DB: {e}")
        return JSONResponse(status_code=500, content={"status": "error", "message": str(e), "results": []})