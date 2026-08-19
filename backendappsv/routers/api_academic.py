# routers/api_academic.py
from fastapi import APIRouter, Query, HTTPException
import pyodbc
from database.db_config import DBConfig
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, status 
# Đảm bảo bạn đã import hàm verify_token của mình nữa nhé
from auth.jwt_handler import verify_token
from core.settings import settings  # cấu hình tập trung (Pha 0)

# Khởi tạo Router (Các API trong này sẽ tự động có tiền tố /api)
router = APIRouter(prefix="/api", tags=["Academic API"])

# Hàm xử lý mã sinh viên (Copy từ main.py sang để dùng nội bộ)
def clean_student_id(raw_id: str) -> str:
    if not raw_id: return ""
    clean = str(raw_id).strip().upper() 
    if clean.startswith("CB"): return clean
    if clean.startswith("SV") and clean[2:].isdigit(): return clean[2:]
    return clean

# =========================================================
# 1. LẤY DANH SÁCH NGÀNH HỌC (CHO COMBOBOX)
# =========================================================
@router.get("/student-programs/{student_id}")
def get_student_programs(student_id: str):
    """API lấy danh sách các ngành học của sinh viên để đổ vào Combobox"""
    try:
        sid = clean_student_id(student_id)
        conn_str = DBConfig.get_connection_string()
        
        with pyodbc.connect(conn_str) as conn:
            cursor = conn.cursor()
            sql = """
                SELECT 
                    ctdt.Id AS ProgramId, 
                    ctdt.Ten AS TenNganh,
                    sp.IdChuongTrinhDaoTao AS ProgramCode
                FROM StudentProfiles sp
                INNER JOIN tbl_ChuongTrinhDaoTao ctdt ON RTRIM(sp.IdChuongTrinhDaoTao) = RTRIM(ctdt.Code)
                WHERE (RTRIM(sp.MaSinhVien) = ? OR RTRIM(sp.MaSinhVien) = 'SV' + ?)
                  AND ctdt.IsDeleted = 0
            """
            cursor.execute(sql, (sid, sid))
            programs = []
            for row in cursor.fetchall():
                programs.append({
                    "program_id": row.ProgramId,
                    "program_name": row.TenNganh,
                    "program_code": row.ProgramCode
                })
            
            if not programs:
                return [{"program_id": 2300, "program_name": "Chưa có chuyên ngành", "program_code": "N/A"}]
                
            return programs
    except Exception as e:
        print(f"🔥 Lỗi API student-programs: {e}")
        return []

# =========================================================
# 2. LẤY KHUNG CHƯƠNG TRÌNH (KHI CHỌN NGÀNH)
# =========================================================


# =========================================================
# 3. LẤY KHUNG CHƯƠNG TRÌNH KÈM TIẾN ĐỘ (ĐÃ HỌC / CHƯA HỌC)
# =========================================================
@router.get("/curriculum-progress/{program_id}")
def get_curriculum_progress(program_id: int, student_id: str = Query(...)):
    """API mới: Lấy Khung chương trình và trạng thái Đã học / Chưa học của 1 sinh viên cụ thể"""
    try:
        sid = clean_student_id(student_id)
        conn_str = DBConfig.get_connection_string()
        with pyodbc.connect(conn_str) as conn:
            cursor = conn.cursor()
            
            sql = """
                SELECT 
                    hp.[Ten] AS TenHocPhan, 
                    ct.SoTinChi, 
                    ct.PhanKy AS HocKyDuKien,
                    CASE WHEN dh.IdHocPhan IS NOT NULL THEN N'Đã học' ELSE N'Chưa học' END AS TrangThai,
                    -- 🔥 ĐÃ SỬA: 1 là Bắt buộc, 2-3-4 là Tự chọn
                    CASE WHEN ct.IdDM_KhoiKienThuc = 1 THEN N'Bắt buộc' ELSE N'Tự chọn' END AS LoaiMon
                FROM tbl_ChuongTrinhDaoTao_HocPhan ct
                INNER JOIN tbl_HocPhan hp ON ct.IdHocPhan = hp.Id
                LEFT JOIN (
                    -- Subquery lấy danh sách các môn sinh viên ĐÃ CÓ ĐIỂM
                    SELECT DISTINCT IdHocPhan 
                    FROM DiemHocPhan 
                    WHERE (RTRIM(IdNguoiHoc) = ? OR RTRIM(IdNguoiHoc) = 'SV' + ?)
                ) AS dh ON dh.IdHocPhan = hp.InstanceId
                WHERE ct.IdChuongTrinhDaoTao = ? 
                  AND ct.IsDeleted = 0 
                  AND hp.IsDeleted = 0
                ORDER BY ct.PhanKy ASC, hp.[Ten] ASC
            """
            cursor.execute(sql, (sid, sid, program_id))
            curriculum = []
            stt = 1
            for row in cursor.fetchall():
                curriculum.append({
                    "stt": stt,
                    "ten_mon": row.TenHocPhan,
                    "tin_chi": row.SoTinChi,
                    "hoc_ky": f"Học kỳ {row.HocKyDuKien}" if row.HocKyDuKien else "Tự chọn",
                    "trang_thai": row.TrangThai,
                    "loai_mon": row.LoaiMon # 🔥 Trả về chuẩn Bắt buộc/Tự chọn
                })
                stt += 1
            return curriculum
    except Exception as e:
        print(f"🔥 Lỗi API curriculum-progress: {e}")
        return []

# =========================================================
# 4. BẢNG ĐIỂM TỔNG HỢP THEO HỌC KỲ (Dùng OPENQUERY qua con 200)
# =========================================================
@router.get("/transcript-summary/{student_id}")
def get_transcript_summary(student_id: str, program_id: str = Query("ALL")):
    """API lấy Bảng điểm tổng hợp của sinh viên từ Server 200"""
    try:
        sid = clean_student_id(student_id)
        conn_str = DBConfig.get_connection_string()
        with pyodbc.connect(conn_str) as conn:
            cursor = conn.cursor()
            
            # 🔥 Sử dụng OPENQUERY để lấy dữ liệu từ con 200 về
            # Thêm IsDeleted = 0 ngay trong câu query gửi sang con 200
            sql = f"""
                SELECT 
                    dt.MaHocKy,
                    dt.Diem_CPA_He4,
                    dt.Diem_CPA_He10,
                    dt.DiemGPA_He4,
                    dt.DiemGPA_He10,
                    dt.Tong_TC_TichLuy,
                    dt.Tong_TC_NoDky,
                    dt.Tong_TC_DangKy,
                    dt.MaCTDT
                FROM OPENQUERY([172.16.95.200], '
                    SELECT MaHocKy, Diem_CPA_He4, Diem_CPA_He10, DiemGPA_He4, DiemGPA_He10, 
                           Tong_TC_TichLuy, Tong_TC_NoDky, Tong_TC_DangKy, MaCTDT 
                    FROM DHVINH_Stagging_DBDiem.dbo.Diem_TichLuy
                    WHERE (RTRIM(MaNguoiHoc) = ''{sid}'' OR RTRIM(MaNguoiHoc) = ''SV{sid}'')
                      AND IsDeleted = 0
                ') AS dt
                WHERE 1 = 1
            """
            params = []
            
            # 🔥 Lọc ngành học bằng cách JOIN với bảng tbl_ChuongTrinhDaoTao (Local)
            if program_id and program_id != "ALL":
                sql += """ 
                    AND RTRIM(dt.MaCTDT) IN (
                        SELECT RTRIM(Code) FROM tbl_ChuongTrinhDaoTao WHERE Id = ? AND IsDeleted = 0
                    )
                """
                params.append(int(program_id))
                
            # Sắp xếp theo Học kỳ 
            sql += " ORDER BY dt.MaHocKy ASC"
            
            cursor.execute(sql, tuple(params))
            
            summary = []
            stt = 1
            for row in cursor.fetchall():
                summary.append({
                    "stt": stt,
                    "hoc_ky": row.MaHocKy or "---",
                    "tbc_he4": round(row.Diem_CPA_He4 or 0, 2),
                    "tbc_he10": round(row.Diem_CPA_He10 or 0, 2),
                    "tbc_hk_he4": round(row.DiemGPA_He4 or 0, 2),
                    "tbc_hk_he10": round(row.DiemGPA_He10 or 0, 2),
                    "tc_tich_luy": row.Tong_TC_TichLuy or 0,
                    "tc_no": row.Tong_TC_NoDky or 0,
                    "tc_dang_ky": row.Tong_TC_DangKy or 0,
                    "ctdt": row.MaCTDT or "---"
                })
                stt += 1
            return summary
    except Exception as e:
        print(f"🔥 Lỗi API transcript-summary: {e}")
        return []

# =========================================================
# 5. LẤY THÔNG TIN TÀI CHÍNH & HỌC PHÍ (TỪ SERVER 200)
# =========================================================
# 5. LẤY THÔNG TIN TÀI CHÍNH & HỌC PHÍ (TỪ SERVER 200)
# =========================================================
@router.get("/finance/{student_id}")
def get_finance_info(student_id: str):
    """API lấy Tổng công nợ, Số dư ví, Chi tiết học phí và Lịch sử giao dịch"""
    try:
        sid = clean_student_id(student_id)
        conn_str = DBConfig.get_connection_string()
        
        with pyodbc.connect(conn_str) as conn:
            cursor = conn.cursor()

            # ==========================================
            # 0. TẠO TỪ ĐIỂN MÔN HỌC (TỪ DB ĐÀO TẠO CHÍNH QUY)
            # Dùng đúng cột 'Code' và 'Ten' như trong database
            # ==========================================
            dict_mon_hoc = {}
            try:
                sql_dict = """
                    SELECT Code, Ten 
                    FROM OPENQUERY([172.16.95.200], '
                        SELECT Code, Ten 
                        FROM DHVINH_Stagging_DBDaoTao_ChinhQuy.dbo.tbl_HocPhan 
                        WHERE IsDeleted = 0 AND Code IS NOT NULL
                    ')
                """
                cursor.execute(sql_dict)
                for r in cursor.fetchall():
                    if r[0]: 
                        dict_mon_hoc[str(r[0]).strip()] = r[1]
            except Exception as e:
                print(f"⚠️ Cảnh báo: Không thể tải từ điển môn học: {e}")

            # ==========================================
            # 1. LẤY SỐ DƯ VÍ TÀI KHOẢN
            # ==========================================
            sql_vi = f"""
                SELECT TongTien
                FROM OPENQUERY([172.16.95.200], '
                    SELECT TongTien
                    FROM DHVINH_Stagging_DBTaiChinh.dbo.tbl_NguoiHoc_ViTien
                    WHERE (RTRIM(Code) = ''{sid}'' OR RTRIM(Code) = ''SV{sid}''
                           OR RTRIM(EntityKey) = ''{sid}'' OR RTRIM(EntityKey) = ''SV{sid}'')
                      AND IsDeleted = 0
                ')
            """
            cursor.execute(sql_vi)
            row_vi = cursor.fetchone()
            so_du_vi = float(row_vi[0]) if row_vi and row_vi[0] else 0.0

            # ==========================================
            # 2. LẤY CHI TIẾT CÔNG NỢ & TỔNG ĐÃ NỘP
            # ==========================================
            sql_khoanthu = f"""
                SELECT 
                    NamHoc, 
                    TenKhoanThu,
                    MaHocPhan, 
                    SoTinChi, 
                    SoTienSauMienGiam, 
                    SoTienDaNop, 
                    SoTienConNo
                FROM OPENQUERY([172.16.95.200], '
                    SELECT 
                        nk.NamHoc, 
                        dm.Ten AS TenKhoanThu,
                        nk.MaHocPhan, 
                        nk.SoTinChi, 
                        nk.SoTienSauMienGiam, 
                        nk.SoTienDaNop, 
                        nk.SoTienConNo
                    FROM DHVINH_Stagging_DBTaiChinh.dbo.tbl_NguoiHoc_KhoanThu nk
                    LEFT JOIN DHVINH_Stagging_DBTaiChinh.dbo.tbl_DM_KhoanThu dm 
                        ON nk.IdDM_KhoanThu = dm.Id
                    WHERE (RTRIM(nk.MaNguoiHoc) = ''{sid}'' OR RTRIM(nk.MaNguoiHoc) = ''SV{sid}'')
                      AND nk.IsDeleted = 0
                ')
                ORDER BY NamHoc DESC
            """
            cursor.execute(sql_khoanthu)
            chi_tiet_hoc_phi = []
            tong_con_no = 0.0
            tong_da_nop = 0.0

            for row in cursor.fetchall():
                tong_da_nop += float(row.SoTienDaNop) if row.SoTienDaNop else 0.0
                tong_con_no += float(row.SoTienConNo) if row.SoTienConNo else 0.0
                
                ma_hp = row.MaHocPhan.strip() if row.MaHocPhan else ""
                
                # 🔥 Lấy tên môn từ Từ điển Server 200 (Nếu không có thì giữ nguyên mã)
                ten_mon_hoc = dict_mon_hoc.get(ma_hp, ma_hp) 
                
                ten_hien_thi = row.TenKhoanThu or "Khoản thu khác"
                if ma_hp:
                    ten_hien_thi += f" - {ten_mon_hoc}" # Hiển thị: "Học phí theo STC - Toán cao cấp"

                chi_tiet_hoc_phi.append({
                    "nam_hoc": row.NamHoc or "---",
                    "ma_hoc_phan": ten_hien_thi,
                    "hoc_phi": float(row.SoTienSauMienGiam) if row.SoTienSauMienGiam else 0.0,
                    "da_nop": float(row.SoTienDaNop) if row.SoTienDaNop else 0.0,
                    "con_no": float(row.SoTienConNo) if row.SoTienConNo else 0.0
                })

            # ==========================================
            # 3. LẤY LỊCH SỬ GIAO DỊCH (NẠP RÚT TIỀN VÍ)
            # ==========================================
            sql_giaodich = f"""
                SELECT SoTien, NoiDung, NgayGiaoDich, TrangThai
                FROM OPENQUERY([172.16.95.200], '
                    SELECT SoTien, NoiDung, NgayGiaoDich, TrangThai
                    FROM DHVINH_Stagging_DBTaiChinh.dbo.tbl_NguoiHoc_LichSuGiaoDich
                    WHERE (RTRIM(MaNguoiHoc) = ''{sid}'' OR RTRIM(MaNguoiHoc) = ''SV{sid}'')
                      AND IsDeleted = 0
                ')
                ORDER BY NgayGiaoDich DESC
            """
            cursor.execute(sql_giaodich)
            lich_su_giao_dich = []
            
            for row in cursor.fetchall():
                trang_thai_text = "Thành công" if row.TrangThai == 1 else ("Thất bại/Hủy" if row.TrangThai == 2 else "Đang xử lý")
                lich_su_giao_dich.append({
                    "so_tien": float(row.SoTien) if row.SoTien else 0.0,
                    "noi_dung": row.NoiDung or "Nạp tiền vào tài khoản",
                    "ngay_giao_dich": row.NgayGiaoDich.strftime('%d/%m/%Y %H:%M') if row.NgayGiaoDich else "---",
                    "trang_thai": trang_thai_text
                })

            return {
                "status": "success",
                "so_du_vi": so_du_vi,
                "tong_da_nop": tong_da_nop,
                "tong_con_no": tong_con_no,
                "chi_tiet_hoc_phi": chi_tiet_hoc_phi,
                "lich_su_giao_dich": lich_su_giao_dich
            }
            
    except Exception as e:
        print(f"🔥 Lỗi API finance: {e}")
        return {
            "status": "error", "message": "Không thể tải dữ liệu tài chính", 
            "so_du_vi": 0.0, "tong_da_nop": 0.0, "tong_con_no": 0.0, 
            "chi_tiet_hoc_phi": [], "lich_su_giao_dich": []
        }


# =========================================================
# 6. TRA CỨU BẢO HIỂM Y TẾ (BHYT)
# =========================================================
@router.get("/bhyt/{student_id}")
def get_bhyt_info(student_id: str):
    try:
        sid = clean_student_id(student_id)
        conn_str = DBConfig.get_connection_string()
        
        with pyodbc.connect(conn_str) as conn:
            cursor = conn.cursor()

            # 1. Lấy thông tin thẻ BHYT hiện tại (Bỏ alias ở SELECT ngoài)
            sql_the = f"""
                SELECT TOP 1 SoThe, TuNgay, DenNgay, MaDinhDanh
                FROM OPENQUERY([172.16.95.200], '
                    SELECT SoThe, TuNgay, DenNgay, MaDinhDanh
                    FROM DHVINH_Stagging_DBTaiChinh.dbo.tbl_BHYT_NguoiHoc
                    WHERE (RTRIM(MaNguoiHoc) = ''{sid}'' OR RTRIM(MaNguoiHoc) = ''SV{sid}'')
                      AND IsDeleted = 0
                    ORDER BY DenNgay DESC
                ')
            """
            cursor.execute(sql_the)
            row_the = cursor.fetchone()
            
            # Xử lý hiển thị số thẻ
            so_the_hien_thi = "Chưa có dữ liệu"
            tu_ngay = "---"
            den_ngay = "---"

            if row_the:
                so_the_hien_thi = row_the[0] or row_the[3] or "Đang cập nhật"
                tu_ngay = row_the[1].strftime('%d/%m/%Y') if row_the[1] else "---"
                den_ngay = row_the[2].strftime('%d/%m/%Y') if row_the[2] else "---"

            thong_tin_the = {
                "so_the": so_the_hien_thi,
                "tu_ngay": tu_ngay,
                "den_ngay": den_ngay
            }

            # 2. Lấy lịch sử đăng ký (Đã sửa lỗi multi-part identifier)
            sql_lich_su = f"""
                SELECT 
                    TenDot, NamHoc, SoTien, ThoiGianDangKy, 
                    TrangThai, HieuLucThe_DenNgay
                FROM OPENQUERY([172.16.95.200], '
                    SELECT 
                        d.TenDot, d.NamHoc, ls.SoTien, ls.ThoiGianDangKy, 
                        ls.TrangThai, ls.HieuLucThe_DenNgay
                    FROM DHVINH_Stagging_DBTaiChinh.dbo.tbl_BHYT_LichSu ls
                    LEFT JOIN DHVINH_Stagging_DBTaiChinh.dbo.tbl_BHYT_Dot d ON ls.IdDotBHYT = d.Id
                    WHERE (RTRIM(ls.MaNguoiHoc) = ''{sid}'' OR RTRIM(ls.MaNguoiHoc) = ''SV{sid}'')
                      AND ls.IsDeleted = 0
                ')
                ORDER BY ThoiGianDangKy DESC
            """
            cursor.execute(sql_lich_su)
            lich_su = []
            
            for r in cursor.fetchall():
                # Map trạng thái dựa trên mã trong DB: 1-Đã duyệt, 4-Đã cấp thẻ, 2-Đã hủy
                status_map = {1: "Đã duyệt", 4: "Đã cấp thẻ", 2: "Đã hủy"}
                status_text = status_map.get(r[4], "Đang xử lý")
                
                lich_su.append({
                    "ten_dot": r[0] or f"Đợt {r[1]}",
                    "so_tien": float(r[2]) if r[2] else 0.0,
                    "ngay_dk": r[3].strftime('%d/%m/%Y') if r[3] else "---",
                    "han_dung": r[5].strftime('%d/%m/%Y') if r[5] else "---",
                    "trang_thai": status_text
                })

            return {
                "status": "success",
                "the_bhyt": thong_tin_the,
                "lich_su": lich_su
            }

    except Exception as e:
        print(f"🔥 Lỗi API BHYT: {e}")
        return {"status": "error", "message": str(e)}
# =========================================================
# 7. LẤY MENU ĐỘNG THEO VAI TRÒ (SERVER-DRIVEN UI)
# =========================================================
# @router.get("/app-menu/{role}")
# async def get_app_menu(role: str):
    # """API lấy danh sách chức năng động tùy theo người dùng là SV hay CB"""
    # try:
        # # Chuyển đổi role thành mã tương ứng trong Database
        # role_code = 'SV' if role.lower() == 'sinhvien' else 'CB' if role.lower() == 'canbo' else 'ALL'
        
        # conn_str = DBConfig.get_connection_string()
        # with pyodbc.connect(conn_str) as conn:
            # cursor = conn.cursor()
            # sql = """
                # SELECT TenChucNang, IconCode, ColorCode, RouteName 
                # FROM tbl_AppMenu 
                # WHERE IsActive = 1 AND (VaiTro = 'ALL' OR VaiTro = ?)
                # ORDER BY ThuTu ASC
            # """
            # cursor.execute(sql, (role_code,))
            # menu = []
            # for row in cursor.fetchall():
                # menu.append({
                    # "title": row.TenChucNang,
                    # "icon": row.IconCode,
                    # "color": row.ColorCode,
                    # "route": row.RouteName
                # })
            # return menu
    # except Exception as e:
        # print(f"🔥 Lỗi API app-menu: {e}")
        # return []        
# from fastapi import APIRouter, Depends
# import pyodbc
# from auth.jwt_handler import verify_token # Đảm bảo file này đã có log phương thức
# Giả sử DBConfig đã được Sơn định nghĩa sẵn

@router.get("/app-menu")
def get_app_menu(current_user: dict = Depends(verify_token)):
    """
    API lấy danh sách Menu dựa trên Role thực tế trong Database.
    Tích hợp hệ thống Audit Log để giám sát truy cập của đối tượng đặc biệt.
    """
    # 1. TRÍCH XUẤT DỮ LIỆU GIÁM SÁT TỪ TOKEN
    user_id = current_user.get("user_id")
    # 'method' sẽ là 'FaceID', 'Password', hoặc 'Office365' nếu đã cấu hình ở bước login
    login_method = current_user.get("method", "N/A") 

    # 📡 HỆ THỐNG GIÁM SÁT TRUY CẬP (LOG TERMINAL)
    print(f"\n" + "="*40)
    print(f"📡 [TRAFFIC] User: {user_id} | Method: {login_method} | Requesting Menu")

    # 🚩 CHẾ ĐỘ GIÁM SÁT ĐẶC BIỆT (AUDIT ALERT)
    # Tự động bắt các ID 1679 hoặc tên có chứa 'TAI'
    is_monitored = "1679" in str(user_id) or "TAI" in str(user_id).upper()
    if is_monitored:
        print(f"🚨 [ALERT-AUDIT] PHÁT HIỆN ĐỐI TƯỢNG GIÁM SÁT TRUY CẬP: {user_id}")
        print(f"🚨 [INFO] Phương thức đăng nhập: {login_method}")
        print(f"🚨 [TIME] Truy cập lúc: {datetime.now().strftime('%H:%M:%S %d/%m/%Y')}")

    try:
        conn_str = DBConfig.get_connection_string()
        with pyodbc.connect(conn_str) as conn:
            cursor = conn.cursor()
            
            # --- BƯỚC 1: XÁC THỰC QUYỀN HẠN THỰC TẾ ---
            # Truy vấn UserRole trực tiếp từ SQL Server để tránh việc User giả mạo Role trong máy
            cursor.execute("SELECT RTRIM(UserRole) FROM tbl_Users WHERE UserCode = ?", (user_id,))
            row = cursor.fetchone()
            
            # Nếu không tìm thấy trong DB, mặc định trả về Menu Sinh viên (SV) để bảo mật
            db_role_raw = str(row[0]).upper().strip() if row and row[0] else "SV"

            # --- BƯỚC 2: CHUẨN HÓA MÃ VAI TRÒ (VaiTro) ---
            # Logic: Nếu Role thuộc nhóm Cán bộ/Admin thì dùng code 'CB', ngược lại dùng 'SV'
            staff_roles = ['CB', 'CANBO', 'ADMIN', 'COVAN']
            role_code = 'CB' if db_role_raw in staff_roles else 'SV'
            
            # --- BƯỚC 3: LẤY DANH SÁCH MENU ---
            # Chỉ lấy các chức năng đang hoạt động (IsActive = 1)
            # VaiTro = 'ALL' sẽ hiện cho tất cả, còn lại hiện theo role_code
            sql = """
                SELECT TenChucNang, IconCode, ColorCode, RouteName 
                FROM tbl_AppMenu 
                WHERE IsActive = 1 AND (VaiTro = 'ALL' OR VaiTro = ?)
                ORDER BY ThuTu ASC
            """
            cursor.execute(sql, (role_code,))
            
            menu_list = []
            for r in cursor.fetchall():
                menu_list.append({
                    "title": r.TenChucNang,
                    "icon": r.IconCode,
                    "color": r.ColorCode,
                    "route": r.RouteName
                })
            
            # Log kết quả cuối cùng để Sơn kiểm tra trên Terminal
            status_icon = "👔" if role_code == 'CB' else "🎓"
            print(f"✅ [SUCCESS] User: {user_id} {status_icon} | Method: {login_method}")
            print(f"📦 Trả về: {len(menu_list)} chức năng.")
            print("="*40 + "\n")
            
            return menu_list

    except Exception as e:
        print(f"🔥 [CRITICAL_ERR] Lỗi lấy menu cho {user_id}: {str(e)}")
        # Trả về mảng rỗng để App không bị crash, chỉ hiện màn hình trống
        return []
# =========================================================
# 6. LẤY THÔNG TIN TỔNG HỢP: HỒ SƠ + ĐIỂM TÍCH LŨY TỪNG NGÀNH
@router.get("/student-info/{student_id}")
def get_student_info(student_id: str):
    try:
        sid = clean_student_id(student_id)
        conn_str = DBConfig.get_connection_string()
        with pyodbc.connect(conn_str) as conn:
            cursor = conn.cursor()
            # 🔥 Đã cập nhật SQL: JOIN với tbl_ChuongTrinhDaoTao để lấy TenNganh
            sql_profile = """
                SELECT 
                    sp.TenTrangThai, 
                    sp.TenLopHanhChinh, 
                    RTRIM(sp.IdChuongTrinhDaoTao) as MaCTDT,
                    ctdt.Ten AS TenNganh
                FROM dbo.StudentProfiles sp
                LEFT JOIN tbl_ChuongTrinhDaoTao ctdt ON RTRIM(sp.IdChuongTrinhDaoTao) = RTRIM(ctdt.Code)
                WHERE (RTRIM(sp.MaSinhVien) = ? OR RTRIM(sp.MaSinhVien) = 'SV' + ?) 
                  AND sp.IsDeleted = 0
            """
            cursor.execute(sql_profile, (sid, sid))
            rows = cursor.fetchall()
            if not rows: return {"status": "error", "message": "Không tìm thấy hồ sơ"}

            profiles = []
            for row in rows:
                ten_trang_thai = row.TenTrangThai or "Đang học"
                ten_lop = row.TenLopHanhChinh or "Chưa xếp lớp"
                ten_nganh = row.TenNganh or ten_lop # Nếu ko có tên ngành thì lấy tên lớp
                ma_ctdt = row.MaCTDT
                
                gpa, tin_chi, rank = 0.0, 0, "---"
                try:
                    sql_diem = f"""
                        SELECT TOP 1 Diem_CPA_He4, Tong_TC_TichLuy
                        FROM OPENQUERY([172.16.95.200], '
                            SELECT Diem_CPA_He4, Tong_TC_TichLuy, MaHocKy
                            FROM DHVINH_Stagging_DBDiem.dbo.Diem_TichLuy
                            WHERE (RTRIM(MaNguoiHoc) = ''{sid}'' OR RTRIM(MaNguoiHoc) = ''SV{sid}'')
                              AND RTRIM(MaCTDT) = ''{ma_ctdt}'' AND IsDeleted = 0
                            ORDER BY MaHocKy DESC
                        ')
                    """
                    cursor.execute(sql_diem)
                    d_row = cursor.fetchone()
                    if d_row:
                        gpa = round(float(d_row[0]), 2) if d_row[0] else 0.0
                        tin_chi = int(d_row[1]) if d_row[1] else 0
                        if gpa >= 3.6: rank = "Xuất sắc"
                        elif gpa >= 3.2: rank = "Giỏi"
                        elif gpa >= 2.5: rank = "Khá"
                        elif gpa >= 2.0: rank = "Trung bình"
                        else: rank = "Yếu"
                except: pass

                profiles.append({
                    "ten_nganh": ten_nganh, # 🔥 Thêm trường này
                    "lop_hanh_chinh": ten_lop,
                    "trang_thai": ten_trang_thai,
                    "gpa": gpa,
                    "tin_chi": tin_chi,
                    "rank": rank
                })
            return {"status": "success", "profiles": profiles}
    except Exception as e:
        print(f"🔥 Lỗi: {e}")
        return {"status": "error", "message": "Lỗi hệ thống"}




# =========================================================
# 7. LẤY LỚP GIẢNG VIÊN THEO BỘ LỌC (NĂM, KỲ, TUẦN)
# =========================================================
# Hàm hỗ trợ làm sạch mã để so khớp mọi trường hợp (CB1088, 1088, SV1088)
def clean_any_id(raw_id: str) -> str:
    s = str(raw_id).strip().upper()
    if s.startswith("CB"): return s[2:]
    if s.startswith("SV"): return s[2:]
    return s



@router.get("/lecturer/classes-filtered")
def get_lecturer_classes_filtered(
    lecturer_id: str = Query(...),
    nam: str = Query(...), 
    ky: str = Query(...),  
    tuan: Optional[int] = Query(None) # 🔥 Đã sửa: Cho phép tuần là None
):
    try:
        raw_id = clean_any_id(lecturer_id)
        nam_hoc_start = int(nam.split('-')[0])
        
        conn_str = DBConfig.get_connection_string()
        with pyodbc.connect(conn_str) as conn:
            cursor = conn.cursor()
            
            # 🔥 SQL thông minh: Nếu tuan IS NULL thì lấy tất cả lớp của kỳ đó
            sql = """
                SELECT DISTINCT 
                    lhp.Code AS MaLopHP, 
                    lhp.Ten AS TenLopHP
                FROM tbl_Tkb_LopHocPhan lhp
                INNER JOIN tbl_Tkb_LopHocPhan_LichHoc lh ON lhp.Id = lh.IdLopHocPhan
                INNER JOIN tbl_HeThong_HocKy hk ON lhp.IdHocKy = hk.Id
                OUTER APPLY STRING_SPLIT(REPLACE(lh.TuanHocFulls, ' ', ''), ',') s
                WHERE (RTRIM(lh.MaCanBo) = ? OR RTRIM(lh.MaCanBo) = 'CB' + ? OR RTRIM(lh.MaCanBo) = 'SV' + ?)
                  AND hk.NamHoc = ?
                  AND hk.Ten = ?
                  AND (? IS NULL OR TRY_CAST(s.value AS INT) = ?) -- 🔥 Xử lý lọc tuần linh hoạt
                  AND lhp.IsDeleted = 0
            """
            
            print(f"🔎 Tìm lớp: ID={raw_id}, Năm={nam_hoc_start}, Kỳ='{ky}', Tuần={tuan}")
            cursor.execute(sql, (raw_id, raw_id, raw_id, nam_hoc_start, ky, tuan, tuan))
            rows = cursor.fetchall()
            
            classes = [{"ma_lop": r[0], "ten_lop": r[1]} for r in rows]
            return {"status": "success", "data": classes}
            
    except Exception as e:
        print(f"🔥 Lỗi API classes-filtered: {e}")
        return {"status": "error", "message": str(e)}

# =========================================================
# 8. GỬI THÔNG BÁO THEO LỚP (LỚP HỌC PHẦN HOẶC HÀNH CHÍNH)
# =========================================================
DB_SERVER = settings.db.server
DB_USER = settings.db.user
DB_PASSWORD = settings.db.password
DB_NAME = settings.db.name
REMOTE_CONN_STR = settings.db.local_conn_str


@router.post("/lecturer/send-notification")
def send_notification(data: dict):
    # data: title, content, type, target_id, sender_id (Cần Flutter gửi thêm cái này)
    try:
        title = data.get("title")
        content = data.get("content")
        target_id = data.get("target_id") 
        type_notif = data.get("type")    
        raw_sender_id = str(data.get("sender_id", "")).strip().upper() # 👈 Lấy ID người gửi
        
        if not title or not content or not target_id:
            return {"status": "error", "message": "Thiếu thông tin tiêu đề, nội dung hoặc mã lớp."}

        # --- BƯỚC 1: TRUY TÌM TÊN CÁN BỘ GỬI ---
        sender_display_name = "Cán bộ hệ thống"
        if raw_sender_id:
            clean_sender_id = raw_sender_id.replace("CB", "").replace("SV", "")
            with pyodbc.connect(REMOTE_CONN_STR) as conn:
                cursor = conn.cursor()
                # Tìm theo mã gốc, mã số thuần, hoặc mã kèm CB
                sql_find = "SELECT FullName FROM tbl_Users WHERE UserCode = ? OR UserCode = ? OR UserCode = ?"
                cursor.execute(sql_find, (raw_sender_id, clean_sender_id, f"CB{clean_sender_id}"))
                user_row = cursor.fetchone()
                if user_row:
                    sender_display_name = user_row[0]

        # --- BƯỚC 2: LẤY DANH SÁCH SINH VIÊN ---
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            if type_notif == 'LHP':
                sql_sv = "SELECT DISTINCT IdNguoiHoc FROM viewDSSinhVienDangKyHoc WHERE MaLopHP = ?"
            else:
                sql_sv = "SELECT DISTINCT MaSinhVien FROM StudentProfiles WHERE TenLopHanhChinh = ? AND IsDeleted = 0"
            
            cursor.execute(sql_sv, (target_id,))
            student_ids = [row[0] for row in cursor.fetchall()]

            if not student_ids:
                return {"status": "error", "message": f"Lớp {target_id} không có sinh viên."}

            # --- BƯỚC 3: ĐẨY VÀO HÀNG ĐỢI (BULK INSERT) ---
            summary = (content[:495] + '...') if len(content) > 500 else content
            
            # Thêm cột Sender vào câu lệnh SQL
            sql_insert = """
                INSERT INTO tbl_Notification_Queue 
                (StudentId, Title, Body, Category, Summary, IsSent, CreatedAt, IsRead, Sender) 
                VALUES (?, ?, ?, 'CLASS', ?, 0, GETDATE(), 0, ?);
            """

            count = 0
            for sid in student_ids:
                if sid:
                    # Làm sạch ID sinh viên
                    clean_sid = str(sid).strip().upper().replace("SV", "").replace("CB", "")
                    cursor.execute(sql_insert, (clean_sid, title, content, summary, sender_display_name))
                    count += 1
            
            conn.commit()

            print(f"✅ [{sender_display_name}] đã gửi {count} tin tới lớp {target_id}")
            return {
                "status": "success", 
                "message": f"Đã gửi thông báo tới {count} sinh viên lớp {target_id}",
                "sender": sender_display_name
            }
                
    except Exception as e:
        print(f"❌ Lỗi: {str(e)}")
        return {"status": "error", "message": str(e)}     




@router.get("/lecturer/schedule-v4/{lecturer_id}")
def get_lecturer_schedule_v4(
    lecturer_id: str, 
    nam: str = Query(..., description="VD: 2025-2026"), 
    ky: str = Query(...), 
    tuan: int = Query(...)
):
    try:
        # 1. Làm sạch ID và tách năm học (VD: "2025-2026" -> 2025)
        raw_id = str(lecturer_id).strip().upper().replace("CB", "").replace("SV", "")
        nam_hoc_start = int(nam.split('-')[0])
        
        conn_str = DBConfig.get_connection_string()
        with pyodbc.connect(conn_str) as conn:
            cursor = conn.cursor()
            
            # 🔥 SQL BỔ SUNG: LHP.Code (Mã lớp học phần) để liên kết với đơn xin phép
            sql = """
                SELECT 
                    LHP.Ten AS TenLop, 
                    LH.NgayHoc + 2 AS Thu,
                    LH.TietHoc + 1 AS TietBatDau,
                    LH.SoTiet,
                    LH.MaPhong,
                    FORMAT(LH.NgayBatDau, 'dd/MM/yyyy') AS TuNgay,
                    FORMAT(LH.NgayKetThuc, 'dd/MM/yyyy') AS DenNgay,
                    LHP.Code AS MaLopHP  -- 🚩 Cột quan trọng để khớp đơn xin phép
                FROM [172.16.95.200].DHVINH_Stagging_DBDaoTao_ChinhQuy.dbo.tbl_Tkb_LopHocPhan AS LHP 
                INNER JOIN [172.16.95.200].DHVINH_Stagging_DBDaoTao_ChinhQuy.dbo.tbl_HeThong_HocKy AS HK 
                    ON HK.ID = LHP.IdHocKy 
                INNER JOIN [172.16.95.200].DHVINH_Stagging_DBDaoTao_ChinhQuy.dbo.tbl_Tkb_LopHocPhan_LichHoc AS LH 
                    ON LHP.Id = LH.IdLopHocPhan
                CROSS APPLY STRING_SPLIT(REPLACE(LH.TuanHocFulls, ' ', ''), ',') AS s
                WHERE LH.MaCanBo = ? 
                  AND HK.NamHoc = ? 
                  AND HK.Ten = ?
                  AND TRY_CAST(s.value AS INT) = ?
                  AND LHP.IsDeleted = 0
                ORDER BY Thu, TietBatDau
            """
            
            print(f"🔎 Lọc lịch dạy GV: ID={raw_id}, Năm={nam_hoc_start}, Kỳ={ky}, Tuần={tuan}")
            cursor.execute(sql, (raw_id, nam_hoc_start, ky, tuan))
            rows = cursor.fetchall()
            
            return {
                "status": "success", 
                "data": [{
                    "ten_lop": r[0], 
                    "thu": r[1], 
                    "tiet_bd": r[2], 
                    "so_tiet": r[3], 
                    "phong": r[4] or "---",
                    "tu_ngay": r[5],
                    "den_ngay": r[6],
                    "ma_lop_hp": r[7]  # 👈 Trả về mã lớp cho Flutter
                } for r in rows]
            }
            
    except Exception as e:
        print(f"🔥 Lỗi API TKB Lecturer: {e}")
        return {"status": "error", "message": str(e)}
        
@router.post("/lecturer/attendance-scan")
def attendance_scan(data: dict):
    class_id = data.get("class_id")
    student_cccd = data.get("student_cccd") # Mã lấy được từ QR
    
    conn_str = DBConfig.get_connection_string()
    try:
        with pyodbc.connect(conn_str) as conn:
            cursor = conn.cursor()
            
            # Kiểm tra sinh viên có thuộc lớp này không
            cursor.execute("SELECT 1 FROM Users WHERE CCCD = ? AND ClassID = ?", (student_cccd, class_id))
            if not cursor.fetchone():
                return {"status": "error", "message": "SV không thuộc lớp này"}

            # Lưu điểm danh (Ví dụ tính buổi học hiện tại)
            cursor.execute("""
                INSERT INTO Attendance (CCCD, SessionNo, StudyDate, IsPresent)
                VALUES (?, (SELECT MAX(SessionNo)+1 FROM Attendance WHERE CCCD=?), GETDATE(), 1)
            """, (student_cccd, student_cccd))
            
            conn.commit()
            return {"status": "success", "message": "Điểm danh thành công"}
    except Exception as e:
        return {"status": "error", "message": str(e)}    
        
# # --- API 1: LẤY DANH SÁCH CÁC LỚP SĨ SỐ ÍT (TOÀN TRƯỜNG) ---
# @router.get("/admin/low-enrollment-classes")
# async def get_low_enrollment_classes(
    # nam: str = Query(..., description="Ví dụ: 2025-2026 hoặc 2025"),
    # ky: str = Query(..., description="Ví dụ: Học kỳ 2.1"),
    # threshold: int = Query(20, description="Ngưỡng sĩ số nhỏ hơn")
# ):
    # try:
        # # Xử lý lấy năm số (2025-2026 -> 2025)
        # nam_val = int(nam.split('-')[0]) if '-' in nam else int(nam)
        
        # with pyodbc.connect(REMOTE_CONN_STR) as conn:
            # cursor = conn.cursor()
            # sql = """
                # SELECT 
                    # lhp.Code AS MaLopHP, 
                    # lhp.Ten AS TenLopHP,
                    # COUNT(DISTINCT sv.IdNguoiHoc) AS SiSo,
                    # MAX(lh.MaCanBo) AS MaGiangVien
                # FROM tbl_Tkb_LopHocPhan lhp
                # INNER JOIN tbl_Tkb_LopHocPhan_LichHoc lh ON lhp.Id = lh.IdLopHocPhan
                # INNER JOIN tbl_HeThong_HocKy hk ON lhp.IdHocKy = hk.Id
                # LEFT JOIN viewDSSinhVienDangKyHoc sv ON lhp.Code = sv.MaLopHP
                # WHERE hk.NamHoc = ? 
                  # AND hk.Ten = ?
                  # AND lhp.IsDeleted = 0
                # GROUP BY lhp.Code, lhp.Ten
                # HAVING COUNT(DISTINCT sv.IdNguoiHoc) < ?
                # ORDER BY SiSo ASC, MaLopHP ASC
            # """
            # cursor.execute(sql, (nam_val, ky, threshold))
            # rows = cursor.fetchall()
            
            # data = [
                # {
                    # "ma_lop": r[0],
                    # "ten_lop": r[1],
                    # "si_so": int(r[2]),
                    # "ma_gv": r[3]
                # } for r in rows
            # ]
            # return {"status": "success", "data": data}
            
    # except Exception as e:
        # return {"status": "error", "message": str(e)}

# # --- API 2: LẤY CHI TIẾT SINH VIÊN THUỘC CÁC LỚP SĨ SỐ ÍT ---
@router.get("/admin/low-enrollment-students")
def get_low_enrollment_students(
    nam: str = Query(...),
    ky: str = Query(...),
    threshold: int = Query(20)
):
    try:
        nam_val = int(nam.split('-')[0]) if '-' in nam else int(nam)
        
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            sql = """
                WITH LowEnrollmentClasses AS (
                    SELECT 
                        lhp.Code AS MaLopHP,
                        COUNT(DISTINCT sv.IdNguoiHoc) AS SiSo
                    FROM tbl_Tkb_LopHocPhan lhp
                    INNER JOIN tbl_HeThong_HocKy hk ON lhp.IdHocKy = hk.Id 
                    LEFT JOIN viewDSSinhVienDangKyHoc sv ON lhp.Code = sv.MaLopHP
                    WHERE hk.NamHoc = ? 
                      AND hk.Ten = ?
                      AND lhp.IsDeleted = 0
                    GROUP BY lhp.Code
                    HAVING COUNT(DISTINCT sv.IdNguoiHoc) < ?
                )
                SELECT 
                    lec.MaLopHP,
                    lec.SiSo,
                    sv.IdNguoiHoc,
                    sv.HoTen,
                    sv.TenLopHP
                FROM viewDSSinhVienDangKyHoc sv
                INNER JOIN LowEnrollmentClasses lec ON sv.MaLopHP = lec.MaLopHP
                ORDER BY lec.SiSo ASC, lec.MaLopHP, sv.IdNguoiHoc
            """
            cursor.execute(sql, (nam_val, ky, threshold))
            rows = cursor.fetchall()
            
            data = [
                {
                    "ma_lop": r[0],
                    "si_so_lop": int(r[1]),
                    "sv_id": r[2],
                    "sv_name": r[3],
                    "ten_lop_hp": r[4]
                } for r in rows
            ]
            return {"status": "success", "data": data}
            
    except Exception as e:
        return {"status": "error", "message": str(e)}     
# @router.post("/admin/send-notification-multi-lhp")
# async def send_notification_multi_lhp(data: dict):
    # try:
        # title = data.get("title")
        # content = data.get("content")
        # # target_ids sẽ là chuỗi: "ENG30004(225.2)_LT_08,MATH1001..."
        # raw_target_ids = str(data.get("target_id", "")).strip() 
        # category = data.get("category", "LHP_MULTI")
        # raw_sender_id = str(data.get("sender_id", "")).strip().upper()

        # if not raw_target_ids:
            # return {"status": "error", "message": "Chưa chọn lớp nào!"}

        # # Chuyển chuỗi mã lớp thành danh sách để đưa vào SQL
        # list_target_ids = [x.strip() for x in raw_target_ids.split(",") if x.strip()]

        # with pyodbc.connect(REMOTE_CONN_STR) as conn:
            # cursor = conn.cursor()

            # # 1. Lấy TẤT CẢ sinh viên từ DANH SÁCH mã lớp học phần
            # # Sử dụng toán tử IN trong SQL
            # placeholders = ",".join(['?' for _ in list_target_ids])
            # sql_get_students = f"""
                # SELECT DISTINCT IdNguoiHoc 
                # FROM viewDSSinhVienDangKyHoc 
                # WHERE MaLopHP IN ({placeholders})
            # """
            
            # cursor.execute(sql_get_students, list_target_ids)
            # # Gom toàn bộ sinh viên, lọc trùng và làm sạch mã
            # recipient_ids = list(set([
                # str(r[0]).strip().upper().replace("SV", "").replace("CB", "") 
                # for r in cursor.fetchall() if r[0]
            # ]))

            # if not recipient_ids:
                # return {"status": "error", "message": "Không tìm thấy sinh viên nào trong các lớp đã chọn."}

            # # 2. Chuẩn bị dữ liệu lưu Queue (Gom tất cả vào 1 bản ghi Queue)
            # id_list_str = ",".join(recipient_ids)
            # summary = (content[:200] + '...') if len(content) > 200 else content
            
            # sql_queue = """
                # INSERT INTO tbl_Notification_Queue 
                # (StudentId, Title, Body, Category, Summary, IsSent, CreatedAt, IsRead, SenderId, Scope, IdNguoiHocs, ExternalId) 
                # OUTPUT INSERTED.ID
                # VALUES (NULL, ?, ?, ?, ?, 0, GETDATE(), 0, ?, 'LHP', ?, ?)
            # """
            
            # # ExternalId lưu danh sách mã lớp để sau này biết tin này gửi cho những lớp nào
            # params = (title, content, category, summary, raw_sender_id, id_list_str, raw_target_ids[:255])
            # cursor.execute(sql_queue, params)
            # new_id = cursor.fetchone()[0]

            # # 3. Nạp nhật ký chi tiết cho từng sinh viên
            # sql_log = "INSERT INTO tbl_Notification_Log_Detail (QueueId, StudentId, IsRead) VALUES (?, ?, 0)"
            # log_entries = [(new_id, sid) for sid in recipient_ids]
            # cursor.executemany(sql_log, log_entries)
            
            # conn.commit()
            
            # print(f"✅ Gửi thành công {len(list_target_ids)} lớp LHP. Tổng: {len(recipient_ids)} SV")
            # return {
                # "status": "success", 
                # "queue_id": new_id, 
                # "student_count": len(recipient_ids),
                # "class_count": len(list_target_ids)
            # }

    # except Exception as e:
        # print(f"❌ Lỗi Multi-LHP: {str(e)}")
        # return {"status": "error", "message": f"Lỗi Server: {str(e)}"}
# API Lấy danh sách lớp lý thuyết sĩ số thấp
@router.get("/admin/low-enrollment-theory-classes")
def get_low_enrollment_theory(
    nam: str = Query(..., description="Ví dụ: 2025-2026"),
    ky: str = Query(..., description="Ví dụ: Học kỳ 2.1"),
    threshold: int = Query(20)
):
    try:
        # 1. Xử lý lấy năm bắt đầu (ví dụ: 2025-2026 -> 2025) để tránh lỗi ép kiểu trong SQL
        nam_val = int(nam.split('-')[0]) if '-' in nam else int(nam)
        
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            
            # Câu lệnh SQL đã tích hợp: HS_ID, Họ tên giảng viên, IsDeleted và HinhThucHoc
            sql = """
                SELECT 
                    lhp.Code AS MaLopHP, 
                    lhp.Ten AS TenLopHP,
                    COUNT(DISTINCT sv.IdNguoiHoc) AS SiSo,
                    MAX(lh.MaCanBo) AS MaGiangVien,
                    -- Lấy Họ + Tên từ bảng hồ sơ cán bộ
                    MAX(ISNULL(hs.HS_Ho, '') + ' ' + ISNULL(hs.HS_Ten, '')) AS TenGiangVien
                FROM tbl_Tkb_LopHocPhan lhp
                INNER JOIN tbl_Tkb_LopHocPhan_LichHoc lh ON lhp.Id = lh.IdLopHocPhan
                INNER JOIN tbl_HeThong_HocKy hk ON lhp.IdHocKy = hk.Id
                LEFT JOIN viewDSSinhVienDangKyHoc sv ON lhp.Code = sv.MaLopHP
                -- JOIN qua HS_ID (ép kiểu HS_ID sang NVARCHAR để so khớp với MaCanBo)
                LEFT JOIN tbl_CANBO_HoSo hs ON (
                    lh.MaCanBo = CAST(hs.HS_ID AS NVARCHAR(20)) 
                    OR lh.MaCanBo = 'CB' + CAST(hs.HS_ID AS NVARCHAR(20))
                )
                WHERE hk.NamHoc = ? 
                  AND hk.Ten = ?
                  AND lhp.IsDeleted = 0 
                  AND lhp.HinhThucHoc = 1 -- Chỉ lấy lớp Lý thuyết
                GROUP BY lhp.Code, lhp.Ten
                HAVING COUNT(DISTINCT sv.IdNguoiHoc) < ? 
                   AND COUNT(DISTINCT sv.IdNguoiHoc) > 0 -- Lọc bỏ lớp 0 sinh viên
                ORDER BY SiSo ASC
            """
            
            print(f"📡 API Quét lớp lý thuyết: Năm={nam_val}, Kỳ='{ky}', Ngưỡng={threshold}")
            cursor.execute(sql, (nam_val, ky, threshold))
            rows = cursor.fetchall()
            
            # Chuyển đổi dữ liệu sang JSON cho Flutter
            data = [
                {
                    "ma_lop": r[0], 
                    "ten_lop": r[1], 
                    "si_so": int(r[2]), 
                    "ma_gv": r[3] if r[3] else "Chưa phân công",
                    "ten_gv": r[4].strip() if (r[4] and r[4].strip()) else "Chưa xác định"
                } for r in rows
            ]
            
            return {
                "status": "success", 
                "count": len(data),
                "data": data
            }
            
    except Exception as e:
        print(f"🔥 Lỗi API low-enrollment-theory: {e}")
        return {"status": "error", "message": str(e)}
#gui cho sinh vien lớp học phần ít sv
@router.post("/admin/send-notification-multi-lhp-theory")
def send_notification_multi_lhp_theory(data: dict):
    try:
        title = data.get("title", "").strip()
        content = data.get("content", "").strip()
        raw_target_ids = str(data.get("target_id", "")).strip() 
        category = data.get("category", "HUY_LOP_LT")
        raw_sender_id = str(data.get("sender_id", "")).strip().upper()

        if not raw_target_ids:
            return {"status": "error", "message": "Danh sách lớp trống!"}

        list_target_ids = [x.strip() for x in raw_target_ids.split(",") if x.strip()]

        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            placeholders = ",".join(['?' for _ in list_target_ids])

            # --- BƯỚC 1: LẤY ID SINH VIÊN (Dùng View nên có sẵn MaLopHP) ---
            sql_get_students = f"""
                SELECT DISTINCT IdNguoiHoc 
                FROM viewDSSinhVienDangKyHoc 
                WHERE MaLopHP IN ({placeholders})
            """
            cursor.execute(sql_get_students, list_target_ids)
            student_ids = [str(r[0]).strip().upper().replace("SV", "").replace("CB", "") for r in cursor.fetchall() if r[0]]

            # --- BƯỚC 2: LẤY ID GIẢNG VIÊN (Phải JOIN để dùng cột Code) ---
            # Đây là chỗ vừa rồi bị lỗi "Invalid column name 'MaLopHP'"
            sql_get_lecturers = f"""
                SELECT DISTINCT lh.MaCanBo 
                FROM tbl_Tkb_LopHocPhan_LichHoc lh
                INNER JOIN tbl_Tkb_LopHocPhan lhp ON lh.IdLopHocPhan = lhp.Id
                WHERE lhp.Code IN ({placeholders})
            """
            cursor.execute(sql_get_lecturers, list_target_ids)
            lecturer_ids = [str(r[0]).strip().upper().replace("CB", "") for r in cursor.fetchall() if r[0]]

            # --- BƯỚC 3: GỘP DANH SÁCH VÀ LỌC TRÙNG ---
            final_recipient_ids = list(set(student_ids + lecturer_ids))

            if not final_recipient_ids:
                return {"status": "error", "message": "Không tìm thấy ai để gửi tin."}

            # --- BƯỚC 4: LƯU VÀO QUEUE ---
            id_list_str = ",".join(final_recipient_ids)
            summary = (content[:197] + '...') if len(content) > 200 else content
            
            sql_queue = """
                INSERT INTO tbl_Notification_Queue 
                (StudentId, Title, Body, Category, Summary, IsSent, CreatedAt, IsRead, SenderId, Scope, IdNguoiHocs, ExternalId) 
                OUTPUT INSERTED.ID
                VALUES (NULL, ?, ?, ?, ?, 0, GETDATE(), 0, ?, 'LHP', ?, ?)
            """
            params = (title, content, category, summary, raw_sender_id, id_list_str, raw_target_ids[:250])
            cursor.execute(sql_queue, params)
            new_id = cursor.fetchone()[0]

            # --- BƯỚC 5: NẠP NHẬT KÝ CHI TIẾT ---
            sql_log = "INSERT INTO tbl_Notification_Log_Detail (QueueId, StudentId, IsRead, CreatedAt) VALUES (?, ?, 0, GETDATE())"
            cursor.executemany(sql_log, [(new_id, sid) for sid in final_recipient_ids])
            
            conn.commit()
            
            print(f"✅ Gửi thành công cho {len(student_ids)} SV và {len(lecturer_ids)} GV.")
            return {
                "status": "success", 
                "queue_id": new_id, 
                "total_recipients": len(final_recipient_ids)
            }

    except Exception as e:
        print(f"❌ Lỗi chi tiết: {str(e)}")
        return {"status": "error", "message": f"Lỗi SQL: {str(e)}"}
                
#Hàm láy sinh viên cùng CAN BỘ CỐ VẤN ĐỀ GUI TIN-API này giúp Cố vấn/Giảng viên thấy được tất cả các lớp mà Khoa mình đang quản lý.
@router.get("/lecturer/assigned-classes")
def get_lecturer_assigned_classes(lecturer_id: str = Query(..., description="Mã cán bộ hoặc HS_ID")):
    try:
        raw_id = lecturer_id.strip().upper().replace("CB", "")
        
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            
            # SQL: Lấy danh sách lớp và thống kê từ khoa của giảng viên
            sql = """
                SELECT 
                    sp.TenLopHanhChinh,
                    COUNT(sp.MaSinhVien) AS TongSoSV,
                    SUM(CASE WHEN sp.TenTrangThai = N'Đang học' THEN 1 ELSE 0 END) AS DangHoc,
                    SUM(CASE WHEN sp.TenTrangThai <> N'Đang học' THEN 1 ELSE 0 END) AS TrangThaiKhac
                FROM StudentProfiles sp
                INNER JOIN tbl_CANBO_HoSo cb ON sp.IdKhoa = cb.DV_ID_GiangDay
                WHERE (cb.HS_Ma = ? OR CAST(cb.HS_ID AS NVARCHAR(20)) = ?)
                  AND sp.IsDeleted = 0
                GROUP BY sp.TenLopHanhChinh
                ORDER BY sp.TenLopHanhChinh ASC
            """
            
            cursor.execute(sql, (lecturer_id, raw_id))
            rows = cursor.fetchall()
            
            data = [
                {
                    "ten_lop": r[0],
                    "tong_sv": int(r[1]),
                    "dang_hoc": int(r[2]),
                    "khac": int(r[3])
                } for r in rows
            ]
            
            return {"status": "success", "data": data}
            
    except Exception as e:
        return {"status": "error", "message": str(e)}
        
#Admin hoặc Cố vấn chọn một lớp từ danh sách trên, Flutter sẽ gọi API này để xem chi tiế
@router.get("/lecturer/class-details")
def get_class_details(ten_lop: str = Query(..., description="Tên lớp hành chính")):
    try:
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            
            # Truy vấn chi tiết sinh viên của lớp
            sql = """
                SELECT 
                    MaSinhVien, 
                    HoVaTen, 
                    TenTrangThai,
                    MaLopHanhChinh
                FROM StudentProfiles
                WHERE TenLopHanhChinh = ? 
                  AND IsDeleted = 0
                ORDER BY Ten, HoVaTen
            """
            
            cursor.execute(sql, (ten_lop,))
            rows = cursor.fetchall()
            
            data = [
                {
                    "ma_sv": r[0],
                    "ho_ten": r[1],
                    "trang_thai": r[2],
                    "ma_lop": r[3]
                } for r in rows
            ]
            
            return {"status": "success", "data": data}
            
    except Exception as e:
        return {"status": "error", "message": str(e)}        
        
#API: Lấy danh sách Khoa/Viện
@router.get("/admin/get-faculties/{lecturer_id}") # Chuyển sang Path Parameter
def get_faculties(lecturer_id: str):
    try:
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            # Lấy DV_ParentID làm ID Khoa chính thức
            sql = """
                SELECT TOP 1 RTRIM(DV_ParentID), TenDonVicap1 
                FROM tbl_CANBO_HoSo 
                WHERE (HS_Ma = ? OR CAST(HS_ID AS NVARCHAR(20)) = ?)
            """
            cursor.execute(sql, (lecturer_id, lecturer_id))
            row = cursor.fetchone()
            if row:
                return {"status": "success", "data": {"id_khoa": row[0], "ten_khoa": row[1]}}
            return {"status": "error", "message": "Cán bộ chưa được gán mã Khoa cha (ParentID)"}
    except Exception as e:
        return {"status": "error", "message": str(e)}
#Lấy danh sách lớp thuộc Khoa
@router.get("/lecturer/assigned-classes")
def get_assigned_classes(lecturer_id: str = Query(...)):
    try:
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            # Khớp IdKhoa của SV với DV_ParentID của Cán bộ
            sql = """
                SELECT 
                    sp.TenLopHanhChinh,
                    COUNT(sp.MaSinhVien) AS TongSoSV,
                    SUM(CASE WHEN sp.TenTrangThai = N'Đang học' THEN 1 ELSE 0 END) AS DangHoc
                FROM StudentProfiles sp
                INNER JOIN tbl_CANBO_HoSo cb ON LTRIM(RTRIM(sp.IdKhoa)) = LTRIM(RTRIM(cb.DV_ParentID))
                WHERE (cb.HS_Ma = ? OR CAST(cb.HS_ID AS NVARCHAR(20)) = ?)
                  AND sp.IsDeleted = 0
                GROUP BY sp.TenLopHanhChinh
                ORDER BY sp.TenLopHanhChinh ASC
            """
            cursor.execute(sql, (lecturer_id, lecturer_id))
            rows = cursor.fetchall()
            data = [{"ten_lop": r[0], "tong_sv": int(r[1]), "dang_hoc": int(r[2])} for r in rows]
            return {"status": "success", "data": data}
    except Exception as e:
        return {"status": "error", "message": str(e)}
        #Lấy danh sách lớp thuộc Khoa + Khóa
@router.get("/admin/get-classes-by-cohort")
def get_classes_by_cohort(id_khoa: str = Query(...), cohort: str = Query(...)):
    try:
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            # Lọc theo IdKhoa và tên lớp bắt đầu bằng số Khóa (VD: 63%)
            sql = """
                SELECT DISTINCT TenLopHanhChinh 
                FROM StudentProfiles 
                WHERE LTRIM(RTRIM(IdKhoa)) = ? 
                  AND TenLopHanhChinh LIKE ? 
                  AND IsDeleted = 0
                ORDER BY TenLopHanhChinh
            """
            cursor.execute(sql, (id_khoa, f"{cohort}%"))
            rows = cursor.fetchall()
            return {"status": "success", "data": [r[0] for r in rows]}
    except Exception as e:
        return {"status": "error", "message": str(e)}
        
#Gửi thông báo theo Khoa/Khóa
import uuid # Dùng để sinh mã ExternalId duy nhất
from datetime import datetime

@router.post("/admin/send-notification-dept-cohort")
def send_notification_dept_cohort(data: dict):
    print("\n🚀 [DEBUG] Bắt đầu gửi tin và ghi Log chi tiết")
    try:
        title = data.get("title", "").strip()
        content = data.get("content", "").strip()
        sender_id = data.get("sender_id", "Admin")
        
        summary = content[:97] + "..." if len(content) > 100 else content
        external_id = str(uuid.uuid4())
        
        target_id = data.get("target_id", "")
        ten_lop_tu_app = data.get("ten_lop")
        
        id_khoa = ""
        cohort = ""
        if "|" in target_id:
            parts = target_id.split("|")
            id_khoa = parts[0].strip()
            cohort = parts[1].replace("K", "").strip()

        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            
            # 1. Tìm MaSinhVien
            if ten_lop_tu_app and ten_lop_tu_app != "ALL":
                sql_sv = "SELECT MaSinhVien FROM StudentProfiles WHERE TenLopHanhChinh = ? AND IsDeleted = 0"
                cursor.execute(sql_sv, (ten_lop_tu_app,))
            else:
                sql_sv = """
                    SELECT MaSinhVien FROM StudentProfiles 
                    WHERE LTRIM(RTRIM(IdKhoa)) = ? AND TenLopHanhChinh LIKE ? AND IsDeleted = 0
                """
                cursor.execute(sql_sv, (id_khoa, f"{cohort}%"))
            
            recipient_ids = [str(r[0]) for r in cursor.fetchall() if r[0]]
            
            if not recipient_ids:
                return {"status": "error", "message": "Không tìm thấy sinh viên."}

            # 2. INSERT vào tbl_Notification_Queue và LẤY ID VỪA TẠO
            id_list_str = ",".join(recipient_ids)
            # Thêm OUTPUT INSERTED.Id để lấy ID ngay khi chèn
            sql_queue = """
                INSERT INTO tbl_Notification_Queue 
                (Title, Body, Summary, Category, IsSent, CreatedAt, 
                 ExternalId, IdNguoiHocs, Priority, SenderId, Scope, Sender, IsRead)
                OUTPUT INSERTED.Id
                VALUES (?, ?, ?, 'DEPT_NOTIF', 0, GETDATE(), ?, ?, 1, ?, 'DEPT', ?, 0)
            """
            
            sender_display = f"Cán bộ {sender_id}"
            
            cursor.execute(sql_queue, (
                title, content, summary, external_id, 
                id_list_str, sender_id, sender_display
            ))
            
            # Lấy ID của bản ghi vừa chèn
            new_id = cursor.fetchone()[0]
            print(f"📌 Đã tạo QueueId: {new_id}")

            # 3. Ghi vào bảng tbl_Notification_Log_Detail để xem được History/Report
            # Mỗi sinh viên là một dòng trong bảng này
            sql_log_detail = "INSERT INTO tbl_Notification_Log_Detail (QueueId, StudentId, IsRead) VALUES (?, ?, 0)"
            
            # Chuẩn bị dữ liệu: [(new_id, 'ma_sv_1'), (new_id, 'ma_sv_2'), ...]
            log_entries = [(new_id, sid) for sid in recipient_ids]
            
            cursor.executemany(sql_log_detail, log_entries)
            
            conn.commit()
            print(f"✅ Đã ghi Log Detail cho {len(recipient_ids)} sinh viên.")
            
            return {"status": "success", "sent_to": len(recipient_ids), "queue_id": new_id}

    except Exception as e:
        print(f"❌ Lỗi: {str(e)}")
        return {"status": "error", "message": str(e)} 
# # THONG BAO TOÀN TRƯỜNG CHO CÁN BỘ VÀ SINH VIÊN        
# @router.post("/admin/send-notification-all")
# async def send_notification_all(data: dict):
    # try:
        # title = data.get("title", "").strip()
        # content = data.get("content", "").strip()
        # sender_id = data.get("sender_id", "Admin")
        # # target_type: 'ALL' (Tất cả), 'STUDENT' (Chỉ SV), 'STAFF' (Chỉ Cán bộ)
        # target_type = data.get("target_type", "ALL") 

        # if not title or not content:
            # return {"status": "error", "message": "Tiêu đề và nội dung không được để trống!"}

        # with pyodbc.connect(REMOTE_CONN_STR) as conn:
            # cursor = conn.cursor()
            
            # # 1. Tạo bản ghi gốc trong Queue
            # summary = (content[:197] + '...') if len(content) > 200 else content
            # sql_queue = """
                # INSERT INTO tbl_Notification_Queue 
                # (Title, Body, Category, Summary, IsSent, CreatedAt, IsRead, SenderId, Scope, ExternalId) 
                # OUTPUT INSERTED.ID
                # VALUES (?, ?, 'ALL_SCHOOL', ?, 0, GETDATE(), 0, ?, 'GLOBAL', ?)
            # """
            # cursor.execute(sql_queue, (title, content, summary, sender_id, target_type))
            # new_id = cursor.fetchone()[0]

            # # 2. Dùng SQL chèn hàng loạt vào Log Detail (Cực nhanh)
            # # Không dùng vòng lặp Python ở đây Sơn nhé
            
            # sql_insert_logs = ""
            # if target_type == "STUDENT":
                # sql_insert_logs = f"""
                    # INSERT INTO tbl_Notification_Log_Detail (QueueId, StudentId, IsRead, CreatedAt)
                    # SELECT {new_id}, IdNguoiHoc, 0, GETDATE() 
                    # FROM StudentProfiles WHERE IsDeleted = 0
                # """
            # elif target_type == "STAFF":
                # sql_insert_logs = f"""
                    # INSERT INTO tbl_Notification_Log_Detail (QueueId, StudentId, IsRead, CreatedAt)
                    # SELECT {new_id}, RTRIM(UserCode), 0, GETDATE() 
                    # FROM tbl_Users WHERE UserType = 1 AND UserCode IS NOT NULL
                # """
            # else: # ALL
                # sql_insert_logs = f"""
                    # INSERT INTO tbl_Notification_Log_Detail (QueueId, StudentId, IsRead, CreatedAt)
                    # SELECT {new_id}, CAST(IdNguoiHoc AS NVARCHAR(50)), 0, GETDATE() FROM StudentProfiles WHERE IsDeleted = 0
                    # UNION
                    # SELECT {new_id}, RTRIM(UserCode), 0, GETDATE() FROM tbl_Users WHERE UserType = 1
                # """
            
            # cursor.execute(sql_insert_logs)
            # conn.commit()
            
            # return {
                # "status": "success", 
                # "message": f"Đã nạp thông báo {target_type} vào hàng đợi thành công.",
                # "queue_id": new_id
            # }

    # except Exception as e:
        # print(f"🔥 Lỗi gửi toàn trường: {e}")
        # return {"status": "error", "message": str(e)}        
@router.post("/admin/send-notification-all")
def send_notification_all(data: dict):
    print(f"\n📢 [GLOBAL] Gửi tin toàn trường: {data.get('target_type')}")
    try:
        title = data.get("title", "").strip()
        content = data.get("content", "").strip()
        sender_id = data.get("sender_id", "Admin")
        # target_type: 'ALL', 'STUDENT', 'STAFF'
        target_type = data.get("target_type", "ALL") 

        if not title or not content:
            return {"status": "error", "message": "Tiêu đề và nội dung không được để trống!"}

        # 1. Tạo Summary & ExternalId
        summary = (content[:197] + '...') if len(content) > 200 else content
        external_id = str(uuid.uuid4())
        
        # 2. Xác định cờ (Flag) đối tượng để lưu vào IdNguoiHocs
        # Thay vì liệt kê 20,000 mã SV, ta lưu một từ khóa để Service Push hiểu
        target_flag = {
            "STUDENT": "ALL_STUDENTS",
            "STAFF": "ALL_STAFF",
            "ALL": "ALL_SCHOOL"
        }.get(target_type, "ALL_SCHOOL")

        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            
            # 3. Chỉ chèn vào Queue, KHÔNG chèn vào Log Detail
            sql_queue = """
                INSERT INTO tbl_Notification_Queue 
                (Title, Body, Summary, Category, IsSent, CreatedAt, IsRead, 
                 SenderId, Scope, ExternalId, IdNguoiHocs, Priority, Sender) 
                VALUES (?, ?, ?, 'ALL_SCHOOL', 0, GETDATE(), 0, 
                 ?, 'GLOBAL', ?, ?, 1, ?)
            """
            
            sender_name = f"Thông báo hệ thống ({sender_id})"
            
            cursor.execute(sql_queue, (
                title, 
                content, 
                summary, 
                sender_id, 
                external_id, 
                target_flag, # Lưu flag đối tượng ở đây
                sender_name
            ))
            
            conn.commit()
            
            return {
                "status": "success", 
                "message": f"Đã nạp thông báo toàn trường ({target_type}) thành công.",
                "external_id": external_id
            }

    except Exception as e:
        print(f"🔥 Lỗi gửi toàn trường: {e}")
        return {"status": "error", "message": str(e)}        