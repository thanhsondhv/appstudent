import random
import string
from datetime import datetime, timedelta
import math
import urllib.parse
import io
from fastapi import APIRouter, Query, HTTPException
from fastapi.responses import StreamingResponse
import pyodbc
import pandas as pd # Cần: pip install pandas openpyxl
from core.settings import settings  # cấu hình tập trung (Pha 0)

router = APIRouter(prefix="/api/attendance", tags=["Attendance"])

# --- CẤU HÌNH KẾT NỐI ---
REMOTE_CONN_STR = settings.db.local_conn_str

def calculate_distance(lat1, lon1, lat2, lon2):
    R = 6371000 
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2)**2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c

# =================================================================
# 1. API LẤY DANH SÁCH HỌC KỲ (Để đổ vào Dropdown 1)
# =================================================================
@router.get("/semesters")
async def get_semesters():
    try:
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            # Lấy 5 học kỳ gần nhất
            sql = "SELECT TOP 5 Ten, NamHoc FROM tbl_HeThong_HocKy ORDER BY NamHoc DESC, Ten DESC"
            cursor.execute(sql)
            return [{"value": f"{r[0]}_{r[1]}", "label": f"{r[0]} ({r[1]})"} for r in cursor.fetchall()]
    except: return []

# =================================================================
# 2. API LẤY DANH SÁCH BUỔI HỌC CỦA LỚP (Để Dropdown 3)
# =================================================================
@router.get("/sessions-by-class/{lhp_code}")
async def get_sessions_by_class(lhp_code: str):
    try:
        clean_lhp = urllib.parse.unquote(lhp_code).strip()
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            sql = "SELECT BuoiHocID, BuoiThu, FORMAT(NgayHoc, 'dd/MM/yyyy') FROM tbl_DiemDanh_BuoiHoc WHERE LhpCode = ? ORDER BY BuoiThu DESC"
            cursor.execute(sql, (clean_lhp,))
            return [{"id": r[0], "buoi": r[1], "ngay": r[2]} for r in cursor.fetchall()]
    except: return []

# =================================================================
# 3. GIẢNG VIÊN: MỞ PHIÊN (Fix LHP_ID NULL & Cho phép chọn ngày)
# =================================================================
@router.post("/create-session")
async def create_attendance_session(data: dict):
    try:
        lhp_code = data.get("lhp_code")
        lecturer_id = str(data.get("lecturer_id")).upper().replace("CB", "").strip()
        ngay_hoc_str = data.get("ngay_hoc") # Định dạng YYYY-MM-DD từ Flutter
        
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            
            # 🔥 FIX LHP_ID: Tìm ID từ mã lớp
            cursor.execute("SELECT TOP 1 Id FROM tbl_Tkb_LopHocPhan WHERE Code = ?", (lhp_code,))
            lhp_row = cursor.fetchone()
            if not lhp_row: return {"status": "error", "message": "Mã lớp không tồn tại!"}
            lhp_id = lhp_row[0]

            # Tự tăng buổi học dựa trên mã lớp
            cursor.execute("SELECT ISNULL(MAX(BuoiThu), 0) + 1 FROM tbl_DiemDanh_BuoiHoc WHERE LhpCode = ?", (lhp_code,))
            next_buoi = cursor.fetchone()[0]

            # Chèn buổi học với Ngày do GV chọn
            sql_buoi = """
                INSERT INTO tbl_DiemDanh_BuoiHoc (LHP_ID, LhpCode, NgayHoc, BuoiThu, LecturerId) 
                OUTPUT INSERTED.BuoiHocID VALUES (?, ?, ?, ?, ?)
            """
            cursor.execute(sql_buoi, (lhp_id, lhp_code, ngay_hoc_str, next_buoi, lecturer_id))
            buoi_hoc_id = cursor.fetchone()[0]

            # Mã PIN 4 số
            code = ''.join(random.choices(string.digits, k=4))
            expiry = datetime.now() + timedelta(minutes=int(data.get("duration", 15)))
            
            cursor.execute("INSERT INTO tbl_Attendance_Sessions (BuoiHocID, AttendanceCode, ExpiryTime, Latitude, Longitude) VALUES (?, ?, ?, ?, ?)",
                           (buoi_hoc_id, code, expiry, data.get("lat", 0), data.get("lon", 0)))
            conn.commit()

        return {"status": "success", "code": code, "buoi_hoc_id": buoi_hoc_id, "buoi_thu": next_buoi}
    except Exception as e:
        return {"status": "error", "message": str(e)}

# =================================================================
# 2. GIẢNG VIÊN: ĐIỂM DANH TAY (Muộn, Vắng, Phép)
# =================================================================
@router.post("/manual-submit")
async def manual_submit(data: dict):
    try:
        buoi_hoc_id = data.get("buoi_hoc_id")
        sid = str(data.get("student_id")).upper().replace("SV", "").strip()
        loai = int(data.get("loai_vang", 0)) 
        
        # 🔥 ĐỊNH NGHĨA 4 TRẠNG THÁI RIÊNG BIỆT
        # 0: Có mặt -> 'CoMat'
        # 1: Đi muộn -> 'Muon'
        # 2: Có phép -> 'CoPhep'
        # 3: Vắng    -> 'Vang'
        mapping = {
            0: 'CoMat',
            1: 'Muon',
            2: 'CoPhep',
            3: 'Vang'
        }
        status = mapping.get(loai, 'Vang')

        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            sql = """
                MERGE tbl_DiemDanh_ChiTiet AS target
                USING (SELECT ? AS b_id, ? AS s_id) AS source
                ON (target.BuoiHocID = source.b_id AND target.MaSV = source.s_id)
                WHEN MATCHED THEN
                    UPDATE SET TrangThai = ?, LoaiVang = ?, ThoiGianDiemDanh = GETDATE(), Method = 'MANUAL'
                WHEN NOT MATCHED THEN
                    INSERT (BuoiHocID, MaSV, TrangThai, LoaiVang, ThoiGianDiemDanh, Method)
                    VALUES (?, ?, ?, ?, GETDATE(), 'MANUAL');
            """
            # Tham số cho MERGE (Sơn để ý thứ tự nhé)
            cursor.execute(sql, (buoi_hoc_id, sid, status, loai, buoi_hoc_id, sid, status, loai))
            conn.commit()
        return {"status": "success"}
    except Exception as e:
        print(f"🔥 Lỗi manual_submit: {e}")
        return {"status": "error", "message": str(e)}

# =================================================================
# 2. API KẾT THÚC ĐIỂM DANH (Đóng phiên ngay lập tức)
# =================================================================
@router.post("/end-session/{buoi_id}")
async def end_attendance_session(buoi_id: int):
    try:
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            # Set thời gian hết hạn về thời điểm hiện tại
            cursor.execute("UPDATE tbl_Attendance_Sessions SET ExpiryTime = GETDATE() WHERE BuoiHocID = ?", (buoi_id,))
            conn.commit()
        return {"status": "success", "message": "Đã kết thúc phiên điểm danh"}
    except Exception as e:
        return {"status": "error", "message": str(e)}

# =================================================================
# 3. FIX LỖI FILE EXCEL TRẮNG
# =================================================================
@router.get("/export-excel/{lhp_code}")
async def export_attendance_excel(lhp_code: str):
    try:
        clean_lhp = urllib.parse.unquote(lhp_code).strip()
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            query = """
                SELECT 
                    v.IdNguoiHoc AS [Mã SV], 
                    u.FullName AS [Họ Tên],
                    COUNT(CASE WHEN ct.TrangThai = 'CoMat' THEN 1 END) AS [Có mặt],
                    COUNT(CASE WHEN ct.TrangThai = 'Muon' THEN 1 END) AS [Đi muộn],
                    COUNT(CASE WHEN ct.TrangThai = 'CoPhep' THEN 1 END) AS [Có phép],
                    COUNT(CASE WHEN ct.TrangThai = 'Vang' THEN 1 END) AS [Vắng]
                FROM viewDSSinhVienDangKyHoc v
                INNER JOIN tbl_Users u ON v.IdNguoiHoc = u.UserCode
                LEFT JOIN tbl_DiemDanh_BuoiHoc b ON v.MaLopHP = b.LhpCode
                LEFT JOIN tbl_DiemDanh_ChiTiet ct ON b.BuoiHocID = ct.BuoiHocID AND v.IdNguoiHoc = ct.MaSV
                WHERE v.MaLopHP = ?
                GROUP BY v.IdNguoiHoc, u.FullName
                ORDER BY u.FullName ASC
            """
            df = pd.read_sql(query, conn, params=[clean_lhp])

        output = io.BytesIO()
        with pd.ExcelWriter(output, engine='openpyxl') as writer:
            df.to_excel(writer, index=False, sheet_name='DiemDanh')
        output.seek(0)
        return StreamingResponse(output, media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                                 headers={"Content-Disposition": f"attachment; filename=DiemDanh_{clean_lhp}.xlsx"})
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# =================================================================
# 4. THỐNG KÊ CHI TIẾT SINH VIÊN (Dùng cho cửa sổ báo cáo trên App)
# =================================================================
@router.get("/student-summary/{lhp_code}/{student_id}")
async def get_student_summary(lhp_code: str, student_id: str):
    try:
        sid = student_id.upper().replace("SV", "").strip()
        clean_lhp = urllib.parse.unquote(lhp_code).strip()
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            sql = """
                SELECT 
                    COUNT(CASE WHEN ct.TrangThai = 'CoMat' THEN 1 END) as CoMat,
                    COUNT(CASE WHEN ct.LoaiVang = 2 THEN 1 END) as Phep,
                    COUNT(CASE WHEN ct.TrangThai = 'Vang' AND (ct.LoaiVang = 3 OR ct.LoaiVang = 0) THEN 1 END) as Vang
                FROM tbl_DiemDanh_ChiTiet ct
                INNER JOIN tbl_DiemDanh_BuoiHoc b ON ct.BuoiHocID = b.BuoiHocID
                WHERE b.LhpCode = ? AND ct.MaSV = ?
            """
            cursor.execute(sql, (clean_lhp, sid))
            r = cursor.fetchone()
            return {"status": "success", "co_mat": r[0], "phep": r[1], "vang": r[2]}
    except Exception as e:
        return {"status": "error", "message": str(e)}

# =================================================================
# 2. SINH VIÊN: GỬI ĐIỂM DANH (Cập nhật tbl_DiemDanh_ChiTiet)
# =================================================================
@router.post("/submit")
async def submit_attendance(data: dict):
    try:
        student_id = str(data.get("student_id", "")).upper().replace("SV", "").strip()
        code_input = "".join(filter(str.isdigit, str(data.get("code", ""))))
        lat_sv = float(data.get("lat", 0))
        lon_sv = float(data.get("lon", 0))
        is_biometric_valid = data.get("is_biometric_valid", False)

        if not is_biometric_valid:
            return {"status": "error", "message": "Yêu cầu xác thực FaceID/Vân tay!"}

        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            
            # A. Kiểm tra mã PIN 4 số trong phiên còn hiệu lực
            sql_check = """
                SELECT TOP 1 BuoiHocID, Latitude, Longitude 
                FROM tbl_Attendance_Sessions 
                WHERE AttendanceCode = ? AND ExpiryTime > GETDATE()
                ORDER BY CreatedAt DESC
            """
            cursor.execute(sql_check, (code_input,))
            sess = cursor.fetchone()

            if not sess:
                return {"status": "error", "message": "Mã PIN sai hoặc đã hết hạn!"}

            buoi_hoc_id, lat_gv, lon_gv = sess[0], sess[1], sess[2]
            distance = calculate_distance(lat_sv, lon_sv, lat_gv, lon_gv)
            
            if distance > 2000: # Giới hạn 2km
                return {"status": "error", "message": f"Bạn ở quá xa ({int(distance)}m)!"}

            # B. Ghi nhận chi tiết điểm danh (CoMat)
            # Dùng MERGE để xử lý cả trường hợp điểm danh lại
            sql_upsert = """
                MERGE tbl_DiemDanh_ChiTiet AS target
                USING (SELECT ? AS b_id, ? AS s_id) AS source
                ON (target.BuoiHocID = source.b_id AND target.MaSV = source.s_id)
                WHEN MATCHED THEN
                    UPDATE SET TrangThai = 'CoMat', LoaiVang = 0, ThoiGianDiemDanh = GETDATE(), Distance = ?, Method = 'APP'
                WHEN NOT MATCHED THEN
                    INSERT (BuoiHocID, MaSV, TrangThai, LoaiVang, ThoiGianDiemDanh, Method, Distance)
                    VALUES (?, ?, 'CoMat', 0, GETDATE(), 'APP', ?);
            """
            cursor.execute(sql_upsert, (buoi_hoc_id, student_id, distance, buoi_hoc_id, student_id, distance))
            conn.commit()

        return {"status": "success", "message": "✅ Điểm danh thành công!"}
    except Exception as e:
        return {"status": "error", "message": str(e)}

# =================================================================

# 1. API LẤY MÃ PIN LIVE (Đảm bảo trả về đúng KEY cho Flutter)
# =================================================================
# --- TRONG attendance_router.py ---

@router.get("/current-session-info/{buoi_id}")
async def get_current_session_info(buoi_id: int):
    try:
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            # Ưu tiên lấy mã PIN mới nhất mà vẫn còn hạn (ExpiryTime > hiện tại)
            sql = "SELECT TOP 1 AttendanceCode FROM tbl_Attendance_Sessions WHERE BuoiHocID = ? AND ExpiryTime > GETDATE() ORDER BY CreatedAt DESC"
            cursor.execute(sql, (buoi_id,))
            row = cursor.fetchone()
            
            if row:
                return {"status": "success", "code": str(row[0])}
            else:
                return {"status": "success", "code": "EXPIRED"} # Trả về trạng thái hết hạn để App biết
    except:
        return {"status": "error", "code": "----"}

@router.get("/session-report/{buoi_id}")
async def get_session_report(buoi_id: int):
    try:
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            
            # 1. Lấy mã lớp gốc từ buổi học
            cursor.execute("SELECT LhpCode FROM tbl_DiemDanh_BuoiHoc WHERE BuoiHocID = ?", (buoi_id,))
            res_lhp = cursor.fetchone()
            if not res_lhp: return {"status": "error", "message": "Không thấy buổi"}
            target_lhp = res_lhp[0].strip()

            # 2. TRUY VẤN SINH VIÊN: Dùng LIKE để né lỗi dấu ngoặc/khoảng trắng
            # Dùng LEFT JOIN tbl_Users để chắc chắn hiện danh sách dù User rỗng
            sql = """
                SELECT 
                    v.IdNguoiHoc as sid, 
                    ISNULL(u.FullName, N'Sinh viên ' + v.IdNguoiHoc) as name, 
                    ISNULL(ct.TrangThai, 'Vang') as status,
                    FORMAT(ct.ThoiGianDiemDanh, 'HH:mm') as time
                FROM (
                    -- Lấy danh sách SV giống hệt cách hàm Gửi tin làm
                    SELECT DISTINCT IdNguoiHoc 
                    FROM viewDSSinhVienDangKyHoc 
                    WHERE MaLopHP LIKE ? -- Dùng LIKE thay vì bằng tuyệt đối
                ) v
                LEFT JOIN tbl_Users u ON v.IdNguoiHoc = u.UserCode
                LEFT JOIN tbl_DiemDanh_ChiTiet ct ON v.IdNguoiHoc = ct.MaSV AND ct.BuoiHocID = ?
                ORDER BY u.FullName ASC
            """
            
            # Truyền mã lớp bọc trong dấu % để khớp 100%
            cursor.execute(sql, (f"{target_lhp}", buoi_id))
            rows = cursor.fetchall()
            
            data = []
            for r in rows:
                data.append({
                    "sid": str(r[0]).strip().upper(),
                    "name": str(r[1]).strip(),
                    "status": str(r[2]),
                    "time": str(r[3]) if r[3] else ""
                })
            
            print(f"✅ Đã tìm thấy {len(data)} SV cho lớp {target_lhp}")
            return {
                "status": "success", 
                "present_count": sum(1 for x in data if x['status'] == 'CoMat'), 
                "data": data
            }
    except Exception as e:
        print(f"🔥 Lỗi nghiêm trọng: {str(e)}")
        return {"status": "error", "message": str(e), "data": []}
# API Gia hạn hoặc đổi mã PIN mới cho Buổi học hiện tại
@router.post("/refresh-pin")
async def refresh_pin(data: dict):
    try:
        buoi_id = data.get("buoi_id")
        duration = data.get("duration", 15)
        
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            # Sinh mã PIN 4 số mới
            import random, string
            new_code = ''.join(random.choices(string.digits, k=4))
            expiry = datetime.now() + timedelta(minutes=int(duration))
            
            # Lấy tọa độ cũ từ phiên gần nhất (nếu có)
            cursor.execute("SELECT TOP 1 Latitude, Longitude FROM tbl_Attendance_Sessions WHERE BuoiHocID = ? ORDER BY CreatedAt DESC", (buoi_id,))
            row = cursor.fetchone()
            lat, lon = (row[0], row[1]) if row else (18.659, 105.695)

            # Chèn phiên mới vào bảng Sessions
            sql = """
                INSERT INTO tbl_Attendance_Sessions (BuoiHocID, AttendanceCode, ExpiryTime, Latitude, Longitude)
                VALUES (?, ?, ?, ?, ?)
            """
            cursor.execute(sql, (buoi_id, new_code, expiry, lat, lon))
            conn.commit()
            
            return {"status": "success", "code": new_code}
    except Exception as e:
        return {"status": "error", "message": str(e)}        