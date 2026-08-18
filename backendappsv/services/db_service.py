#db_service.py
import pyodbc
import json
import numpy as np
import re
from database.db_config import DBConfig
from .utils import normalize_vn
class DBService:
    def __init__(self):
        # Đảm bảo lấy đúng chuỗi kết nối từ cấu hình
        self.conn_str = DBConfig.get_connection_string()

    def _get_conn(self):
        """Khởi tạo kết nối: Bản chuẩn nhất cho Windows để lưu/đọc tiếng Việt"""
        # Đảm bảo dùng đúng biến self.conn_str đã khai báo ở __init__
        conn = pyodbc.connect(self.conn_str)
        
        # 🔥 QUAN TRỌNG NHẤT: Ép Python gửi dữ liệu đi bằng chuẩn UTF-16LE
        # Đây là chuẩn mà các cột NVARCHAR của SQL Server Windows sử dụng.
        # conn.setencoding(encoding='utf-16le')
        
        # # Nhận dữ liệu về: Giải mã các cột Unicode bằng utf-16le
        # conn.setdecoding(pyodbc.SQL_CHAR, encoding='utf-8')
        # conn.setdecoding(pyodbc.SQL_WCHAR, encoding='utf-16le')
        # conn.setdecoding(pyodbc.SQL_WMETADATA, encoding='utf-16le')
        
        # return conn
        conn.setencoding(encoding='utf-16le')
        conn.setdecoding(pyodbc.SQL_CHAR, encoding='utf-8')
        conn.setdecoding(pyodbc.SQL_WCHAR, encoding='utf-16le')
        return conn
    # db_service.py
    # Trong file db_service.py
    def get_graduation_audit(self, student_id: str, program_id: int = None):
        sid = student_id.strip().upper().replace("SV", "").replace("CB", "")
        print(f"\n--- 🚀 [START DEBUG AUDIT] SV: {sid} | ProgramID: {program_id} ---")
        
        try:
            with self._get_conn() as conn:
                cursor = conn.cursor()
                
                # 1. LẤY ĐỊNH MỨC TỐT NGHIỆP TỪ BẢNG KHUNG
                sql_frame = """
                    SELECT TOP 1 ct.Id, ct.Ten, ct.SoTinChi, RTRIM(ct.Code)
                    FROM dbo.StudentProfiles sp
                    INNER JOIN dbo.tbl_ChuongTrinhDaoTao ct ON RTRIM(sp.IdChuongTrinhDaoTao) = RTRIM(ct.Code)
                    WHERE (RTRIM(sp.MaSinhVien) = ? OR RTRIM(sp.MaSinhVien) = 'SV' + ?)
                      AND ct.IsDeleted = 0
                """
                if program_id:
                    sql_frame += " AND ct.Id = ?"
                    cursor.execute(sql_frame, (sid, sid, program_id))
                else:
                    cursor.execute(sql_frame, (sid, sid))
                
                row = cursor.fetchone()
                if not row:
                    print(f"❌ [DEBUG] Không tìm thấy khung cho SV: {sid}")
                    return None
                
                prog_id_db, ten_nganh, tc_dinh_muc, ma_khung = row
                print(f"📊 [DEBUG 1] Ngành: {ten_nganh} ({ma_khung})")
                print(f"📊 [DEBUG 1] Số TC định mức (Cột SoTinChi): {tc_dinh_muc}")

                # [DEBUG ĐẶC BIỆT] - Kiểm tra xem tổng SUM toàn khung có phải 157 không
                cursor.execute("SELECT SUM(SoTinChi) FROM tbl_ChuongTrinhDaoTao_HocPhan WHERE IdChuongTrinhDaoTao = ?", (prog_id_db,))
                sum_total_khung = cursor.fetchone()[0]
                print(f"⚠️ [DEBUG 1.1] TỔNG SUM TOÀN KHUNG (Gồm cả tự chọn): {sum_total_khung}")

                # 2. LẤY TÍCH LŨY THỰC TẾ TỪ SERVER 200
                # 2. LẤY TÍCH LŨY THỰC TẾ (Sửa lại logic ORDER BY để lấy con số 126)
                sql_points = f"""
                    SELECT TOP 1 Tong_TC_TichLuy, Diem_CPA_He4, MaHocKy
                    FROM OPENQUERY([172.16.95.200], '
                        SELECT MaNguoiHoc, Tong_TC_TichLuy, Diem_CPA_He4, MaHocKy 
                        FROM DHVINH_Stagging_DBDiem.dbo.Diem_TichLuy
                        WHERE (RTRIM(MaNguoiHoc) = ''{sid}'' OR RTRIM(MaNguoiHoc) = ''SV{sid}'') 
                          AND IsDeleted = 0
                    ') AS dt
                    -- 🔥 QUAN TRỌNG: Sắp xếp theo số Tín chỉ giảm dần để lấy 126 thay vì 118
                    ORDER BY dt.Tong_TC_TichLuy DESC, dt.MaHocKy DESC 
                """
                cursor.execute(sql_points)
                p_row = cursor.fetchone()
                
                tc_thuc_te = p_row[0] if p_row else 0
                gpa = round(float(p_row[1]), 2) if p_row else 0.0
                print(f"📈 [DEBUG 2] Tích lũy thực tế từ Server 200: {tc_thuc_te}")
                print(f"📈 [DEBUG 2] Điểm GPA (CPA): {gpa}")

                # 3. KIỂM TRA MÔN BẮT BUỘC CÒN NỢ
                sql_missing_mandatory = """
                    SELECT hp.Ten, ct.SoTinChi
                    FROM dbo.tbl_ChuongTrinhDaoTao_HocPhan ct
                    INNER JOIN dbo.tbl_HocPhan hp ON ct.IdHocPhan = hp.Id
                    LEFT JOIN (
                        SELECT DISTINCT IdHocPhan FROM dbo.DiemHocPhan 
                        WHERE (RTRIM(IdNguoiHoc) = ? OR RTRIM(IdNguoiHoc) = 'SV' + ?) 
                          AND Diem >= 4 -- 🔥 SỬA 'DiemSo' THÀNH 'Diem' Ở ĐÂY
                    ) AS dh ON dh.IdHocPhan = hp.InstanceId
                    WHERE ct.IdChuongTrinhDaoTao = ? 
                      AND ct.IdDM_KhoiKienThuc = 1 
                      AND dh.IdHocPhan IS NULL 
                      AND ct.IsDeleted = 0 AND hp.IsDeleted = 0
                """
                cursor.execute(sql_missing_mandatory, (sid, sid, prog_id_db))
                rows_missing = cursor.fetchall()
                missing_subs = [{"ten": r[0], "tc": r[1]} for r in rows_missing]
                print(f"🚫 [DEBUG 3] Số môn bắt buộc còn nợ: {len(missing_subs)}")

                # 4. TÍNH TOÁN KẾT LUẬN
                tc_thieu_thuc_te = max(0, tc_dinh_muc - tc_thuc_te)
                is_eligible = (tc_thieu_thuc_te == 0 and len(missing_subs) == 0)
                
                print(f"🏁 [DEBUG 4] Kết quả: Thiếu {tc_thieu_thuc_te} TC | Đủ ĐK: {is_eligible}")
                print(f"--- 🔚 [END DEBUG AUDIT] ---\n")
                
                return {
                    "nganh": ten_nganh,
                    "ma_khung": ma_khung,
                    "tc_yeu_cau": tc_dinh_muc,
                    "tc_hien_tai": tc_thuc_te,
                    "gpa": gpa,
                    "mon_no_bat_buoc": missing_subs,
                    "tc_thieu": tc_thieu_thuc_te,
                    "is_eligible": is_eligible
                }
                
        except Exception as e:
            print(f"🔥 [DEBUG ERROR] Lỗi graduation_audit: {e}")
            return None
    # def get_graduation_audit(self, student_id: str, program_id: int = None):
        # """
        # Báo cáo tốt nghiệp: Hỗ trợ song bằng bằng cách lọc theo program_id.
        # Giữ nguyên logic OPENQUERY từ Server 200.
        # """
        # sid = student_id.strip().upper().replace("SV", "").replace("CB", "")
        
        # try:
            # with self._get_conn() as conn:
                # cursor = conn.cursor()
                
                # # 1. LẤY THÔNG TIN KHUNG (Điều chỉnh để lọc theo program_id nếu có)
                # sql_frame = """
                    # SELECT ct.Id, ct.Ten, ct.SoTinChi, RTRIM(ct.Code)
                    # FROM dbo.StudentProfiles sp
                    # INNER JOIN dbo.tbl_ChuongTrinhDaoTao ct ON RTRIM(sp.IdChuongTrinhDaoTao) = RTRIM(ct.Code)
                    # WHERE (RTRIM(sp.MaSinhVien) = ? OR RTRIM(sp.MaSinhVien) = 'SV' + ?)
                # """
                
                # # Nếu có truyền program_id từ chat_v3, ta ép SQL lọc đúng Id đó
                # if program_id:
                    # sql_frame += " AND ct.Id = ?"
                    # cursor.execute(sql_frame, (sid, sid, program_id))
                # else:
                    # cursor.execute(sql_frame, (sid, sid))
                
                # row = cursor.fetchone()
                
                # if not row:
                    # print(f"⚠️ Không tìm thấy khung cho SV: {sid} | ProgramId: {program_id}")
                    # return None
                
                # prog_id, ten_nganh, tc_khung, ma_khung = row

                # # 2. LẤY TÍCH LŨY THỰC TẾ TỪ SERVER 200 (Dùng ma_khung đã lọc đúng ngành)
                # # Giữ nguyên logic OPENQUERY của Sơn
                # sql_points = f"""
                    # SELECT TOP 1 Tong_TC_TichLuy, Diem_CPA_He4
                    # FROM OPENQUERY([172.16.95.200], '
                        # SELECT MaNguoiHoc, MaCTDT, Tong_TC_TichLuy, Diem_CPA_He4, MaHocKy 
                        # FROM DHVINH_Stagging_DBDiem.dbo.Diem_TichLuy
                        # WHERE IsDeleted = 0
                    # ') AS dt
                    # WHERE (RTRIM(dt.MaCTDT) = '{ma_khung}') 
                      # AND (RTRIM(dt.MaNguoiHoc) = '{sid}' OR RTRIM(dt.MaNguoiHoc) = 'SV{sid}')
                    # ORDER BY dt.MaHocKy DESC
                # """
                # cursor.execute(sql_points)
                # p_row = cursor.fetchone()
                
                # tc_thuc_te = p_row[0] if p_row else 0
                # gpa = round(float(p_row[1]), 2) if p_row else 0.0

                # # 3. LẤY MÔN BẮT BUỘC CÒN NỢ (Dùng prog_id đã xác định theo ngành chọn)
                # sql_missing = """
                    # SELECT hp.Ten, ct.SoTinChi, ct.PhanKy
                    # FROM dbo.tbl_ChuongTrinhDaoTao_HocPhan ct
                    # INNER JOIN dbo.tbl_HocPhan hp ON ct.IdHocPhan = hp.Id
                    # LEFT JOIN (
                        # SELECT DISTINCT IdHocPhan FROM dbo.DiemHocPhan 
                        # WHERE (RTRIM(IdNguoiHoc) = ? OR RTRIM(IdNguoiHoc) = 'SV' + ?)
                    # ) AS dh ON dh.IdHocPhan = hp.InstanceId
                    # WHERE ct.IdChuongTrinhDaoTao = ? 
                      # AND ct.IdDM_KhoiKienThuc = 1 -- Khối kiến thức bắt buộc
                      # AND dh.IdHocPhan IS NULL 
                      # AND ct.IsDeleted = 0
                      # AND hp.IsDeleted = 0
                # """
                # cursor.execute(sql_missing, (sid, sid, prog_id))
                # missing_subs = [
                    # {"ten": r[0], "tc": r[1], "ky": r[2]} 
                    # for r in cursor.fetchall()
                # ]

                # return {
                    # "nganh": ten_nganh,
                    # "ma_khung": ma_khung,
                    # "tc_yeu_cau": tc_khung,
                    # "tc_hien_tai": tc_thuc_te,
                    # "gpa": gpa,
                    # "mon_no_bat_buoc": missing_subs,
                    # "tc_thieu_tong_quat": max(0, tc_khung - tc_thuc_te)
                # }
        # except Exception as e:
            # print(f"🔥 Lỗi graduation_audit: {e}")
            # return None
    # # --- Thêm vào class DBService trong db_service.py ---

    def get_strict_db_suggestions(self, role: str, limit: int = 4):
        """
        Lấy gợi ý CHỈ TỪ DATABASE: 
        1. QuestionText từ tbl_AI_SQL_Knowledge 
        2. Keywords/Category từ DocumentChunks
        """
        db_role = "STUDENT" if role.lower() == "sinhvien" else "ADVISOR"
        suggestions = []
        
        try:
            with self._get_conn() as conn:
                cursor = conn.cursor()
                
                # Nguồn 1: Lấy các câu hỏi SQL thực tế (Sắp xếp theo độ phổ biến HitCount)
                sql_kb = """
                    SELECT TOP 3 QuestionText 
                    FROM dbo.tbl_AI_SQL_Knowledge 
                    WHERE (TargetRole = 'ALL' OR TargetRole LIKE ?)
                    ORDER BY HitCount DESC, NEWID()
                """
                cursor.execute(sql_kb, (f"%{db_role}%",))
                for r in cursor.fetchall():
                    if r[0]: suggestions.append(r[0].strip())
                
                # Nguồn 2: Lấy từ Keywords của các file Quy chế (DocumentChunks)
                sql_rag = """
                    SELECT TOP 3 Keywords 
                    FROM dbo.DocumentChunks 
                    WHERE (TargetRole = 'ALL' OR TargetRole LIKE ?) 
                      AND Keywords IS NOT NULL AND Keywords <> ''
                    ORDER BY NEWID()
                """
                cursor.execute(sql_rag, (f"%{db_role}%",))
                for r in cursor.fetchall():
                    # Nếu Keywords có nhiều câu cách nhau bằng dấu phẩy, lấy câu đầu tiên
                    first_kw = r[0].split(',')[0].strip()
                    if len(first_kw) > 5: suggestions.append(first_kw)

        except Exception as e:
            print(f"🔥 Lỗi get_strict_db_suggestions: {e}")
            
        return list(dict.fromkeys([s for s in suggestions if s]))[:limit]
    # --- Thêm/Cập nhật trong db_service.py ---

    def get_smart_db_suggestions(self, role: str, category_hint: str = None, exclude_texts: list = None, limit: int = 4):
        """
        Lấy gợi ý từ DB: Ép role cực kỳ nghiêm ngặt.
        """
        # 1. CHUẨN HÓA VAI TRÒ (Phải khớp 100% với chữ 'sinhvien'/'canbo' trong DB)
        u_role = role.lower().strip()
        if u_role not in ['sinhvien', 'canbo']:
            u_role = 'sinhvien' # Mặc định an toàn
            
        suggestions = []
        exclude_norms = [normalize_vn(ex) for ex in (exclude_texts or [])]

        try:
            with self._get_conn() as conn:
                cursor = conn.cursor()
                
                # Điều kiện Role: Phải là 'all' hoặc khớp chính xác vai trò người dùng
                # Dùng LOWER để tránh lỗi hoa thường
                role_filter = "(LOWER(TargetRole) = 'all' OR LOWER(TargetRole) = ?)"

                # --- CASE 1: HỌC TẬP (Quét bảng Know) ---
                if category_hint == "HOC_TAP":
                    sql = f"""
                        SELECT TOP 10 QuestionText FROM dbo.tbl_AI_SQL_Knowledge 
                        WHERE {role_filter} 
                        AND (LOWER(Category) LIKE N'%học%' OR LOWER(Category) LIKE N'%điểm%' OR Category IS NULL)
                        ORDER BY HitCount DESC, NEWID()
                    """
                    cursor.execute(sql, (u_role,))
                    for r in cursor.fetchall(): suggestions.append(r[0])

                # --- CASE 2: THỦ TỤC (Quét bảng Chunk) ---
                elif category_hint == "THU_TUC":
                    sql = f"""
                        SELECT TOP 10 Keywords FROM dbo.DocumentChunks 
                        WHERE {role_filter} 
                        AND (LOWER(Category) LIKE N'%thủ tục%' OR LOWER(Category) LIKE N'%hành chính%' OR LOWER(DocumentName) LIKE N'%quy che%')
                        ORDER BY NEWID()
                    """
                    cursor.execute(sql, (u_role,))
                    for r in cursor.fetchall():
                        # Tách chuỗi keywords nếu Sơn nhập nhiều câu cách nhau dấu phẩy
                        for kw in r[0].replace('\n', ',').replace('-', ',').split(','):
                            suggestions.append(kw.strip())

                # --- CASE 3: TƯ VẤN TỰ DO (Mix cả 2 nguồn) ---
                else:
                    # Lấy 2 câu từ mỗi bảng
                    sql_kb = f"SELECT TOP 5 QuestionText FROM dbo.tbl_AI_SQL_Knowledge WHERE {role_filter} ORDER BY NEWID()"
                    cursor.execute(sql_kb, (u_role,))
                    for r in cursor.fetchall(): suggestions.append(r[0])
                    
                    sql_ck = f"SELECT TOP 5 Keywords FROM dbo.DocumentChunks WHERE {role_filter} ORDER BY NEWID()"
                    cursor.execute(sql_ck, (u_role,))
                    for r in cursor.fetchall():
                        for kw in r[0].replace('\n', ',').replace('-', ',').split(','):
                            suggestions.append(kw.strip())

        except Exception as e:
            print(f"🔥 Lỗi gợi ý DB: {e}")

        # Lọc rác: Bỏ câu quá ngắn, quá dài và câu đã có trong lịch sử
        return self._clean_suggestions_final(suggestions, exclude_norms, limit)

    def _clean_suggestions_final(self, suggestions, exclude_norms, limit):
        final = []
        seen = set()
        for s in suggestions:
            if not s or len(s.strip()) < 8: continue
            s_clean = s.strip()
            s_norm = normalize_vn(s_clean)
            
            # Kiểm tra trùng lặp và né lịch sử
            if s_norm not in seen and not any(ex in s_norm for ex in exclude_norms):
                if len(s_clean) < 65: # Nút bấm không được quá dài
                    final.append(s_clean)
                    seen.add(s_norm)
        return final[:limit]
            
        return list(dict.fromkeys(suggestions))[:limit]    
    def get_template_by_intent(self, intent_key):
        """Tra cứu mẫu đơn, chấp nhận sai lệch dấu gạch dưới hoặc hoa thường"""
        try:
            # Làm sạch key: bỏ gạch dưới và viết thường để so sánh linh hoạt
            clean_key = intent_key.replace("_", "").lower()
            
            # SQL: Lọc bỏ gạch dưới trong DB để so khớp với clean_key
            query = """
                SELECT TemplateName, DisplayName 
                FROM DocumentTemplates 
                WHERE REPLACE(LOWER(IntentKey), '_', '') = ? AND IsActive = 1
            """
            result = self.execute_query(query, (clean_key,))
            return result[0] if result else None
        except Exception as e:
            print(f"🔥 Lỗi DB Get Template: {e}")
            return None
    def get_all_active_intents(self):
        """Lấy tất cả IntentKey để nạp vào Prompt của AI"""
        try:
            query = "SELECT IntentKey FROM DocumentTemplates WHERE IsActive = 1"
            rows = self.execute_query(query)
            if rows:
                return ", ".join([r['IntentKey'] for r in rows])
            return ""
        except:
            return ""
    def clean_text(self, text):
        """Hàm lột dấu chuẩn: đ -> d, fix lỗi mất chữ Đ"""
        if not text: return ""
        s1 = u'ÀÁÂÃÈÉÊÌÍÒÓÔÕÙÚÝàáâãèéêìíòóôõùúýĂăĐđĨĩŨũƠơƯưẠạẢảẤấẦầẨẩẪẫẬậẮắẰằẲẳẴẵẶặẸẹẺẻẼẽẾếỀềỂểỄễỆệỈỉỊịỌọỎỏỐốỒồỔổỖỗỘộỚớỜờỞởỠỡỢợỤụỦủỨứỪừỬửỮữỰựỴỵỶỷỸỹ'
        s0 = u'AAAAEEEIIOOOOUUYaaaaeeeiioooouuyAaDdIiUuOoUuAaAaAaAaAaAaAaAaAaAaAaAaEeEeEeEeEeEeEeEeIiIiOoOoOoOoOoOoOoOoOoOoOoOoUuUuUuUuUuUuUuYyYyYy'
        s = "".join(s0[s1.index(c)] if c in s1 else c for c in text)
        return re.sub(r'[^\w\s]', '', s).lower().strip()
        
    
    
    def execute_query(self, sql: str, params: tuple = None):
        """Thực thi SQL và trả về List[Dict]"""
        try:
            with self._get_conn() as conn:
                cursor = conn.cursor()
                cursor.execute(sql, params) if params else cursor.execute(sql)
                if cursor.description:
                    columns = [column[0] for column in cursor.description]
                    return [dict(zip(columns, row)) for row in cursor.fetchall()]
                conn.commit()
                return []
        except Exception as e:
            print(f"❌ Lỗi SQL: {e}")
            return str(e)
 
    def get_sql_knowledge_suggestions(self, target_role: str, limit: int = 3):
        """Lấy câu hỏi gợi ý chuẩn từ bảng Knowledge dựa trên vai trò canbo/sinhvien"""
        try:
            # Không dùng ADVISOR/STUDENT nữa, dùng trực tiếp vai trò từ hệ thống AUTH
            db_role = target_role.lower().strip() 
            
            with pyodbc.connect(self.conn_str) as conn:
                cursor = conn.cursor()
                # Tìm kiếm thông minh: Khớp với TargetRole hoặc AllowedRoles
                query = """
                    SELECT TOP (?) QuestionText 
                    FROM tbl_AI_SQL_Knowledge 
                    WHERE (LOWER(TargetRole) LIKE ? OR LOWER(AllowedRoles) LIKE ?)
                    ORDER BY HitCount DESC
                """
                role_param = f"%{db_role}%"
                cursor.execute(query, (limit, role_param, role_param))
                
                rows = cursor.fetchall()
                return [row[0] for row in rows]
        except Exception as e:
            print(f"❌ Lỗi lấy gợi ý Knowledge: {e}")
            return []
    def search_sql_knowledge_semantic(self, user_query: str, query_vector: list, target_role: str):
        """Tìm tri thức: Ưu tiên Khớp chuỗi -> Sau đó mới tới Vector"""
        try:
            role_map = {'sinhvien': 'STUDENT', 'canbo': 'ADVISOR', 'lanhdao': 'BGH'}
            db_role = role_map.get(target_role.lower(), 'STUDENT')
            u_clean = self.clean_text(user_query)
            
            with self._get_conn() as conn:
                cursor = conn.cursor()
                cursor.execute("SELECT QuestionText, QuestionVector, ValidatedSQL FROM tbl_AI_SQL_Knowledge WHERE (TargetRole LIKE ? OR AllowedRoles LIKE ?)", (f"%{db_role}%", f"%{db_role}%"))
                rows = cursor.fetchall()
                
                best_match = None
                max_sim = -1.0
                for q_text, v_json, v_sql in rows:
                    # 1. KHỚP CHUỖI TRỰC TIẾP (Chính xác tuyệt đối)
                    q_clean = self.clean_text(q_text)
                    if u_clean in q_clean or q_clean in u_clean:
                        return {"sql": v_sql, "text": q_text, "similarity": 1.0}

                    # 2. KHỚP VECTOR (Ngữ nghĩa)
                    if v_json:
                        db_vec = np.array(json.loads(v_json))
                        sim = np.dot(query_vector, db_vec) / (np.linalg.norm(query_vector) * np.linalg.norm(db_vec))
                        if sim > max_sim:
                            max_sim = float(sim)
                            best_match = {"sql": v_sql, "text": q_text, "similarity": max_sim}

                if max_sim >= 0.82: return best_match
        except Exception as e: print(f"❌ Lỗi search: {e}")
        return None
    #ham lay 2 nganh
    def get_chat_user_context(self, user_id: str):
        conn = self._get_conn()
        cursor = conn.cursor()
        try:
            raw_id = str(user_id).strip().upper()
            clean_id = raw_id.replace("SV", "").replace("CB", "")
            inferred_role = 'canbo' if raw_id.startswith('CB') else 'sinhvien'
            
            # 1. Lấy thông tin User (Tên và Vai trò gốc)
            sql_user = "SELECT userrole, FullName FROM dbo.tbl_Users WHERE UserCode = ? OR UserCode = 'SV'+? OR UserCode = 'CB'+? OR UserName = ?"
            cursor.execute(sql_user, (raw_id, clean_id, clean_id, user_id))
            u_row = cursor.fetchone()
            
            raw_role = str(u_row[0]).strip().lower() if u_row else inferred_role
            full_name = u_row[1] if u_row else "Người dùng"
            
            # 2. Truy vấn đa ngành (Song bằng)
            sql_programs = """
                SELECT sp.IdChuongTrinhDaoTao, ctdt.Id, ctdt.Ten, sp.HoVaTen
                FROM dbo.StudentProfiles sp
                LEFT JOIN dbo.tbl_ChuongTrinhDaoTao ctdt ON RTRIM(sp.IdChuongTrinhDaoTao) = RTRIM(ctdt.Code)
                WHERE sp.MaSinhVien = ? OR sp.MaSinhVien = 'SV' + ?
            """
            cursor.execute(sql_programs, (clean_id, clean_id))
            p_rows = cursor.fetchall()
            
            # Nếu tìm thấy tên trong Profile thì ưu tiên dùng tên này (thường đầy đủ hơn)
            if p_rows and p_rows[0][3]:
                full_name = p_rows[0][3]

            programs = []
            seen_ids = set()
            for r in p_rows:
                p_code, p_id, p_name = r[0], r[1], r[2]
                prog_id = p_id if p_id else p_code
                if prog_id and prog_id not in seen_ids:
                    programs.append({"id": prog_id, "name": p_name or f"Ngành {p_code}"})
                    seen_ids.add(prog_id)

            # 3. CHUẨN HÓA VAI TRÒ (Tích hợp từ hàm cũ của Sơn)
            user_role = raw_role
            if raw_role in ['cb', 'canbo', 'advisor', 'gv', 'troly', 'chuyenvien']: 
                user_role = 'canbo'
            elif raw_role in ['sv', 'sinhvien', 'student']: 
                user_role = 'sinhvien'
            
            # 4. PHÂN CẤP TRI THỨC (Tích hợp từ hàm cũ của Sơn)
            role_hierarchy = {
                'lanhdao': ['lanhdao', 'canbo', 'all'],
                'covan': ['covan', 'sinhvien', 'all'],
                'canbo': ['canbo', 'all'],
                'troly': ['troly', 'canbo', 'all'],
                'chuyenvien': ['chuyenvien', 'canbo', 'all'],
                'sinhvien': ['sinhvien', 'all']
            }
            allowed_roles = role_hierarchy.get(user_role, [user_role, 'all'])

            return {
                "role": user_role, # canbo hoặc sinhvien
                "raw_role": raw_role, # Vai trò chi tiết (lanhdao, covan...)
                "full_name": full_name,
                "programs": programs,
                "is_multi_program": len(programs) > 1,
                "allowed_roles": allowed_roles,
                "program_id": programs[0]['id'] if programs else 2201
            }
        except Exception as e:
            print(f"🔥 Lỗi get_chat_user_context: {e}")
            return {"role": "sinhvien", "full_name": "Người dùng", "programs": [], "allowed_roles": ['sinhvien', 'all']}
        finally:
            conn.close()
        

    def get_sql_knowledge_suggestions(self, target_role: str, limit: int = 3):
        try:
            # Ép kiểu để khớp tuyệt đối với dữ liệu 'canbo' trong SQL
            db_role = str(target_role).lower().strip() 
            
            with self._get_conn() as conn:
                cursor = conn.cursor()
                # Sử dụng LOWER để so sánh không phân biệt hoa thường
                query = """
                    SELECT TOP (?) QuestionText 
                    FROM tbl_AI_SQL_Knowledge 
                    WHERE LOWER(TargetRole) = ? OR LOWER(AllowedRoles) LIKE ?
                    ORDER BY HitCount DESC
                """
                cursor.execute(query, (limit, db_role, f"%{db_role}%"))
                return [row[0] for row in cursor.fetchall()]
        except:
            return []

    # def get_v3_suggestions(user_role: str, intent: str, stats: dict = None) -> list:
        # final_sugs = []
        
        # # Lấy từ DB Knowledge
        # db_sugs = db_service.get_sql_knowledge_suggestions(user_role)
        # if db_sugs:
            # print(f"📚 Đã lấy {len(db_sugs)} gợi ý từ bảng Knowledge")
            # final_sugs.extend(db_sugs)

        # # Gợi ý dựa trên học lực
        # if user_role == 'sinhvien' and stats:
            # if stats.get("gpa", 0) < 2.0:
                # final_sugs.insert(0, "Cách xóa điểm F")

        # # Mặc định phòng hờ
        # if not final_sugs:
            # final_sugs = ["Tiến độ tốt nghiệp", "Xem điểm GPA", "Học bổng"]

        # return list(dict.fromkeys(final_sugs))[:4]        
    # =======================================================
    # 1. HÀM TỔNG HỢP DỮ LIỆU SINH VIÊN (Trang chủ App)
    # =======================================================
    def get_student_summary(self, student_id: str):
        sid = student_id.strip()
        clean_sid = sid[2:] if sid.startswith("SV") else sid
        summary = {"notifs": [], "schedule": [], "grades": []}
        conn = self._get_conn()
        cursor = conn.cursor()
        
        try:
            # A. THÔNG BÁO
            cursor.execute("""
                SELECT TOP 3 TieuDe, NgayTao 
                FROM (
                    SELECT TieuDe, NgayTao FROM dbo.tbl_ThongBao_Admin 
                    WHERE LoaiDoiTuong = N'Toàn trường' 
                       OR (LoaiDoiTuong = N'Sinh viên cụ thể' AND MaDoiTuong = ?)
                    UNION ALL
                    SELECT TieuDe, NgayPhatHanh as NgayTao FROM dbo.tbl_ThongBao
                    WHERE (CAST(IdNguoiHocs AS NVARCHAR(MAX)) LIKE ? OR IdLoaiThongBao = 2)
                      AND NgayPhatHanh >= DATEADD(day, -30, GETDATE())
                ) AS AllNotifs
                ORDER BY NgayTao DESC
            """, (clean_sid, f'%{clean_sid}%'))
            summary["notifs"] = [{"title": r[0], "date": r[1].strftime("%d/%m/%Y")} for r in cursor.fetchall()]

            # B. LỊCH HỌC SẮP TỚI
            cursor.execute("""
                SELECT TOP 5 lhp.Ten, tkb.MaPhong, tkb.TietHoc,
                       DATEADD(DAY, (CAST(s.value AS INT) - 1) * 7 + (CASE WHEN tkb.NgayHoc = 0 THEN 6 ELSE tkb.NgayHoc - 1 END), hk.TuNgay) AS NgayHocXac
                FROM dbo.viewDSSinhVienDangKyHoc dk
                INNER JOIN dbo.tbl_Tkb_LopHocPhan lhp ON RTRIM(dk.MaLopHP) = RTRIM(lhp.Code)
                INNER JOIN dbo.tbl_HeThong_HocKy hk ON lhp.IdHocKy = hk.Id
                INNER JOIN dbo.tbl_Tkb_LopHocPhan_LichHoc tkb ON lhp.Id = tkb.IdLopHocPhan
                CROSS APPLY STRING_SPLIT(REPLACE(tkb.TuanHocFulls, ' ', ''), ',') s
                WHERE (RTRIM(dk.IdNguoiHoc) = ? OR RTRIM(dk.IdNguoiHoc) = 'SV' + ?)
                  AND DATEADD(DAY, (CAST(s.value AS INT) - 1) * 7 + (CASE WHEN tkb.NgayHoc = 0 THEN 6 ELSE tkb.NgayHoc - 1 END), hk.TuNgay) >= CAST(GETDATE() AS DATE)
                ORDER BY NgayHocXac ASC
            """, (clean_sid, clean_sid))
            summary["schedule"] = [{"mon": r[0], "phong": r[1], "tiet": r[2], "ngay": r[3].strftime("%d/%m/%Y")} for r in cursor.fetchall()]

            # C. ĐIỂM SỐ MỚI NHẤT
            cursor.execute("""
                SELECT TOP 5 lhp.Ten, d.Diem, d.DiemChu
                FROM dbo.DiemHocPhan d
                INNER JOIN dbo.tbl_Tkb_LopHocPhan lhp ON d.IdLopHocPhan = lhp.InstanceId 
                WHERE (RTRIM(d.IdNguoiHoc) = ? OR RTRIM(d.IdNguoiHoc) = 'SV' + ?)
                  AND d.Diem IS NOT NULL
                ORDER BY d.Created DESC, d.Id DESC
            """, (clean_sid, clean_sid))
            summary["grades"] = [{"mon": r[0], "diem": r[1], "chu": r[2]} for r in cursor.fetchall()]
        except Exception as e:
            print(f"🔥 Lỗi lấy dữ liệu tổng hợp: {e}")
        finally:
            conn.close()
        return summary

    # =======================================================
    # 2. QUẢN LÝ PHIÊN & PROFILE SINH VIÊN
    # =======================================================
    def create_session(self, student_id: str):
        conn = self._get_conn()
        cursor = conn.cursor()
        cursor.execute("INSERT INTO dbo.ChatSessions (StudentId, StartTime) OUTPUT INSERTED.Id VALUES (?, GETDATE())", (student_id,))
        new_id = cursor.fetchone()[0]
        conn.commit()
        conn.close()
        return new_id

    def save_message(self, session_id: int, role: str, content: str):
        try:
            with self._get_conn() as conn:
                cursor = conn.cursor()
                # Dùng ? thuần túy. Driver sẽ tự biến nó thành Unicode chuẩn.
                query = "INSERT INTO dbo.ChatLogs (SessionId, [Role], Content, [Timestamp]) VALUES (?, ?, ?, GETDATE())"
                
                # Đảm bảo nội dung truyền vào là chuỗi (str)
                cursor.execute(query, (int(session_id), str(role), str(content)))
                conn.commit()
        except Exception as e:
            print(f"❌ Lỗi lưu tin nhắn: {e}")

    def get_user_profile(self, student_id: str):
        conn = self._get_conn()
        cursor = conn.cursor()
        try:
            clean_id = str(student_id).strip().upper().replace("SV", "")
            cursor.execute("""
                SELECT sp.HoVaTen, sp.TenLopHanhChinh, sp.IdChuongTrinhDaoTao, ctdt.Id
                FROM dbo.StudentProfiles sp
                LEFT JOIN dbo.tbl_ChuongTrinhDaoTao ctdt ON RTRIM(sp.IdChuongTrinhDaoTao) = RTRIM(ctdt.Code)
                WHERE sp.MaSinhVien = ?
            """, (clean_id,))
            
            row = cursor.fetchone()
            if row:
                return {
                    "full_name": row[0], 
                    "class_name": row[1],
                    "program_code": row[2],
                    "program_id": row[3] or 2201
                }
            return None
        finally:
            conn.close()
    def get_student_memory(self, student_id: str):
        """Truy xuất trí nhớ dài hạn (tóm tắt các phiên chat trước) từ DB"""
        try:
            with pyodbc.connect(self.conn_str) as conn:
                cursor = conn.cursor()
                # Lấy bản tóm tắt gần nhất của sinh viên
                sql = "SELECT Summary FROM MemoryChunks WHERE StudentId = ?"
                cursor.execute(sql, (student_id,))
                row = cursor.fetchone()
                
                # Trả về nội dung tóm tắt hoặc None nếu chưa từng có lịch sử
                return row[0] if row else None
        except Exception as e:
            print(f"🔥 Lỗi get_student_memory: {e}")
            return None
    # =======================================================
    # 3. THỐNG KÊ HỌC TẬP (Context cho Agentic Tư Vấn)
    # =======================================================
    def get_student_academic_stats(self, student_id: str):
        conn = self._get_conn()
        cursor = conn.cursor()
        try:
            clean_id = str(student_id).strip().upper().replace("SV", "")
            
            # Lấy Program ID động
            cursor.execute("""
                SELECT TOP 1 ctdt.Id 
                FROM dbo.StudentProfiles sp
                JOIN dbo.tbl_ChuongTrinhDaoTao ctdt ON RTRIM(sp.IdChuongTrinhDaoTao) = RTRIM(ctdt.Code)
                WHERE sp.MaSinhVien = ?
            """, (clean_id,))
            
            row_ctdt = cursor.fetchone()
            real_program_id = row_ctdt[0] if row_ctdt else 2201

            sql = """
            SELECT 
                COUNT(*) AS TongMon,
                SUM(CASE WHEN d.Diem IS NOT NULL THEN 1 ELSE 0 END) AS DaDat,
                SUM(CASE WHEN d.Diem IS NOT NULL THEN h.SoTinChi ELSE 0 END) AS TinChi,
                ROUND(SUM(
                    CASE 
                        WHEN d.DiemChu = 'A'  THEN 4.0 * h.SoTinChi
                        WHEN d.DiemChu = 'B+' THEN 3.5 * h.SoTinChi
                        WHEN d.DiemChu = 'B'  THEN 3.0 * h.SoTinChi
                        WHEN d.DiemChu = 'C+' THEN 2.5 * h.SoTinChi
                        WHEN d.DiemChu = 'C'  THEN 2.0 * h.SoTinChi
                        WHEN d.DiemChu = 'D+' THEN 1.5 * h.SoTinChi
                        WHEN d.DiemChu = 'D'  THEN 1.0 * h.SoTinChi
                        ELSE 0 
                    END) / CAST(NULLIF(SUM(CASE WHEN d.Diem IS NOT NULL THEN h.SoTinChi ELSE 0 END), 0) AS FLOAT), 2) AS GPA
            FROM tbl_ChuongTrinhDaoTao_HocPhan kh
            LEFT JOIN tbl_HocPhan h ON kh.IdHocPhan = h.Id 
            LEFT JOIN (
                SELECT h_sub.Id AS IdHocPhan_Int, d.Diem, d.DiemChu
                FROM DiemHocPhan d
                INNER JOIN tbl_HocPhan h_sub ON d.IdHocPhan = h_sub.InstanceId
                WHERE (RTRIM(d.IdNguoiHoc) = ? OR RTRIM(d.IdNguoiHoc) = 'SV' + ?)
                  AND d.IsDeleted = 0
            ) d ON h.Id = d.IdHocPhan_Int
            WHERE kh.IdChuongTrinhDaoTao = ?;
            """
            cursor.execute(sql, (clean_id, clean_id, real_program_id))
            row = cursor.fetchone()
            
            if row:
                gpa = float(row[3]) if row[3] else 0.0
                rank = "Xuất sắc" if gpa >= 3.6 else "Giỏi" if gpa >= 3.2 else "Khá" if gpa >= 2.5 else "Trung bình"
                return {
                    "total_courses": row[0],
                    "passed_courses": row[1],
                    "total_credits": row[2] or 0,
                    "gpa": gpa,
                    "rank": rank,
                    "program_id": real_program_id
                }
            return None
        finally:
            conn.close()

    # =======================================================
    # 4. CÔNG CỤ (TOOLS) CHO AI TRỰC TIẾP GỌI
    # =======================================================
    def tool_get_full_grades(self, student_id: str, nam_hoc: str = "ALL", hoc_ky: str = "ALL"):
        sid = student_id.strip().upper().replace("SV", "")
        conn = self._get_conn()
        cursor = conn.cursor()
        try:
            params = [sid, sid]
            f_sql = ""
            if nam_hoc and nam_hoc != "ALL":
                f_sql += " AND hk.NamHoc = ?"
                params.append(nam_hoc.split('-')[0])
            if hoc_ky and hoc_ky != "ALL":
                f_sql += " AND hk.Ten LIKE ?"
                params.append(f"%{hoc_ky}%")

            sql = f"""
                SELECT lhp.Ten, d.Diem, d.DiemChu, hk.Ten as TenKy, hk.NamHoc
                FROM dbo.DiemHocPhan d
                INNER JOIN dbo.tbl_Tkb_LopHocPhan lhp ON d.IdLopHocPhan = lhp.InstanceId 
                LEFT JOIN dbo.tbl_HeThong_HocKy hk ON lhp.IdHocKy = hk.Id
                WHERE (RTRIM(d.IdNguoiHoc) = ? OR RTRIM(d.IdNguoiHoc) = 'SV' + ?) {f_sql}
                ORDER BY hk.NamHoc DESC, hk.Ten DESC, d.Created DESC
            """
            cursor.execute(sql, tuple(params))
            rows = cursor.fetchall()
            if not rows: return "Không tìm thấy dữ liệu điểm phù hợp."
            return "\n".join([f"- {r[0]}: {r[1]} ({r[2]}) - Kỳ: {r[3]}" for r in rows])
        finally:
            conn.close()

    def tool_execute_dynamic_sql(self, student_id: str, sql_query: str):
        """Công cụ AI dùng để chạy SQL và lấy dữ liệu trả về định dạng JSON text"""
        sid = student_id.strip().upper().replace("SV", "")
        clean_query = sql_query.replace('\\n', ' ').replace('\n', ' ').replace('\\', '')
        final_query = clean_query.replace("{student_id}", sid)
        conn = self._get_conn()
        cursor = conn.cursor()
        try:
            cursor.execute(final_query)
            if cursor.description is None: return "Thành công."
            columns = [column[0] for column in cursor.description]
            rows = cursor.fetchall()
            if not rows: return json.dumps({"summary": "0 kết quả.", "results": []})
            data = [dict(zip(columns, row)) for row in rows[:20]]
            return json.dumps({"summary": f"Tìm thấy {len(rows)} kết quả.", "displayed_results": data}, ensure_ascii=False, default=str)
        except Exception as e:
            return f"Lỗi SQL: {str(e)}"
        finally:
            conn.close()
    # --- THÊM VÀO Class DBService trong file db_service.py ---
    # def get_chat_user_context(self, user_id: str):
        # """
        # Hàm trung tâm nhận diện vai trò và quyền hạn tri thức cho Chatbot.
        # Hỗ trợ: sinhvien, canbo, covan, lanhdao, troly, chuyenvien.
        # """
        # conn = self._get_conn()
        # cursor = conn.cursor()
        # try:
            # # 1. Nhận diện vai trò sơ bộ từ tiền tố mã (Xử lý trường hợp DB chưa cập nhật kịp)
            # raw_id = str(user_id).strip().upper()
            # inferred_role = 'canbo' if raw_id.startswith('CB') else 'sinhvien'
            
            # # Làm sạch mã để truy vấn (ví dụ: CB1234 -> 1234)
            # clean_id = raw_id.replace("SV", "").replace("CB", "")
            
            # # 2. Truy vấn thông tin từ bảng Users và Profile
            # sql = """
                # SELECT 
                    # ISNULL(u.userrole, ?) as role, 
                    # ISNULL(sp.HoVaTen, u.FullName) as full_name,
                    # ctdt.Id as RealProgramId
                # FROM dbo.tbl_Users u
                # LEFT JOIN dbo.StudentProfiles sp ON u.UserCode = sp.MaSinhVien OR u.UserCode = 'SV' + sp.MaSinhVien
                # LEFT JOIN dbo.tbl_ChuongTrinhDaoTao ctdt ON RTRIM(sp.IdChuongTrinhDaoTao) = RTRIM(ctdt.Code)
                # WHERE u.UserCode = ? 
                   # OR u.UserCode = 'SV' + ? 
                   # OR u.UserCode = 'CB' + ?
                   # OR u.UserName = ?
            # """
            # # Truyền inferred_role vào làm giá trị mặc định nếu bảng Users trống role
            # cursor.execute(sql, (inferred_role, clean_id, clean_id, clean_id, user_id))
            # row = cursor.fetchone()
            
            # # 3. Gán giá trị mặc định
            # user_role = inferred_role
            # full_name = 'Người dùng'
            # program_id = 2201
            
            # if row:
                # user_role = str(row[0]).strip().lower()
                # full_name = row[1] or "Người dùng"
                # program_id = row[2] or 2201
            
            # # --- CHUẨN HÓA VAI TRÒ (Mapping về canbo/sinhvien) ---
            # # Giúp khớp với TargetRole trong SQL Knowledge/Chunks bạn đã UPDATE
            # if user_role in ['cb', 'canbo', 'advisor', 'gv']: 
                # user_role = 'canbo'
            # elif user_role in ['sv', 'sinhvien', 'student']: 
                # user_role = 'sinhvien'
            
            # print(f"✅ [AUTH] User: {full_name} | Role: {user_role}")

            # # 4. QUY HOẠCH PHÂN CẤP TRI THỨC (Hierarchy)
            # role_hierarchy = {
                # 'lanhdao': ['lanhdao', 'canbo', 'all'],     # Lãnh đạo xem được tri thức CB và Chung
                # 'covan': ['covan', 'sinhvien', 'all'],      # Cố vấn xem được tri thức SV và Chung
                # 'canbo': ['canbo', 'all'],                  # Cán bộ xem tri thức CB và Chung
                # 'troly': ['troly', 'canbo', 'all'],         # Trợ lý xem được tri thức CB
                # 'chuyenvien': ['chuyenvien', 'canbo', 'all'],
                # 'sinhvien': ['sinhvien', 'all']             # SV chỉ xem tri thức SV và Chung
            # }
            
            # allowed_roles = role_hierarchy.get(user_role, [user_role, 'all'])
            
            # return {
                # "role": user_role,
                # "full_name": full_name,
                # "program_id": program_id,
                # "allowed_roles": allowed_roles 
            # }
            
        # except Exception as e:
            # print(f"🔥 Lỗi get_chat_user_context: {e}")
            # return {
                # "role": "sinhvien", 
                # "full_name": "Người dùng", 
                # "program_id": 2201, 
                # "allowed_roles": ['sinhvien', 'all']
            # }
        # finally:
            # conn.close()
    def tool_search_documents(self, query_text: str, ai_service_instance=None, category_filter: str = None, target_role: str = "sinhvien"):
        """
        Tìm kiếm Hybrid (Vector + Keywords) có phân cấp quyền hạn.
        Hierarchy: lanhdao > canbo > all | covan > sinhvien > all
        """
        # Lưu ý: Tất cả code dưới đây lùi vào 8 dấu cách (2 tabs)
        if not ai_service_instance:
            return "Lỗi: Không thể kết nối dịch vụ Vector AI."
            
        conn = self._get_conn()
        cursor = conn.cursor()
        try:
            # 1. Tạo Vector cho câu hỏi
            query_vector = ai_service_instance.get_embedding(query_text)
            if query_vector is None: 
                return "Lỗi: Không thể tạo vector."
            
            # 2. XÁC ĐỊNH PHÂN CẤP QUYỀN (Hierarchy Mapping)
            role_map = {
                'lanhdao': ['lanhdao', 'canbo', 'all'],
                'covan': ['covan', 'sinhvien', 'all'],
                'canbo': ['canbo', 'all'],
                'sinhvien': ['sinhvien', 'all'],
                'all': ['all']
            }
            
            # Lấy danh sách các vai trò mà user này được phép xem
            current_role = target_role.lower().strip()
            allowed_roles = role_map.get(current_role, [current_role, 'all'])
            
            # 3. XÂY DỰNG SQL VỚI TOÁN TỬ IN
            # Tạo chuỗi (?, ?, ?) tương ứng với số lượng role
            placeholders = ", ".join(["?"] * len(allowed_roles))
            
            sql = f"""
                SELECT Content, VectorJson, DocumentName, Category, Keywords 
                FROM dbo.DocumentChunks 
                WHERE VectorJson IS NOT NULL 
                AND ISNULL(LOWER(TargetRole), 'all') IN ({placeholders})
            """
            
            params = list(allowed_roles)
            
            # Thêm lọc theo Category nếu có
            if category_filter and category_filter != "Khác":
                sql += " AND Category = ?"
                params.append(category_filter)
            
            cursor.execute(sql, params)
            all_chunks = cursor.fetchall()
            
            results = []
            q_vec = np.array(query_vector)
            norm_q = np.linalg.norm(q_vec)
            query_tokens = query_text.lower().split()

            # 4. TÍNH ĐIỂM HYBRID (70% Vector + 30% Keywords)
            for content, v_json, doc_name, cat, keywords in all_chunks:
                try:
                    # A. Cosine Similarity
                    v_array = np.array(json.loads(v_json))
                    v_norm = np.linalg.norm(v_array)
                    if v_norm == 0: continue
                    vector_score = np.dot(q_vec, v_array) / (norm_q * v_norm)
                    
                    # B. Keyword Match Score
                    keyword_score = 0
                    if keywords and query_tokens:
                        kw_lower = keywords.lower()
                        matches = sum(1 for token in query_tokens if len(token) > 2 and token in kw_lower)
                        keyword_score = matches / len(query_tokens)

                    # C. Final Score
                    final_score = (vector_score * 0.7) + (keyword_score * 0.3)
                    
                    if final_score > 0.25: 
                        results.append({
                            "doc": doc_name, 
                            "content": content, 
                            "score": float(final_score),
                            "category": cat
                        })
                except: continue

            # 5. Lấy Top 5 kết quả tốt nhất
            sorted_res = sorted(results, key=lambda x: x['score'], reverse=True)[:5]
            return json.dumps(sorted_res, ensure_ascii=False) if sorted_res else None
            
        finally:
            conn.close()

    # =======================================================
    # 5. TIỆN ÍCH HỆ THỐNG
    # =======================================================
    def check_student_exists(self, student_id: str):
        conn = self._get_conn()
        cursor = conn.cursor()
        try:
            cursor.execute("SELECT Email FROM StudentProfiles WHERE MaSinhVien = ?", (student_id,))
            row = cursor.fetchone()
            return row[0] if row else None
        finally:
            conn.close()
            
    def get_config(self, key: str):
        conn = self._get_conn()
        cursor = conn.cursor()
        try:
            cursor.execute("SELECT ConfigValue FROM tbl_AI_Config WHERE ConfigKey = ?", (key,))
            row = cursor.fetchone()
            return row[0] if row else None
        except Exception as e:
            print(f"🔥 Lỗi đọc Config từ DB: {e}")
            return None
        finally:
            # Lệnh này phải lùi vào 1 cấp so với 'finally'
            conn.close() 
    def get_sql_knowledge_suggestions_by_type(self, target_role: str, knowledge_type: str):
        """
        Lấy gợi ý từ bảng Knowledge lọc theo Vai trò và Loại (SQL hoặc RAG).
        knowledge_type: 'SQL' hoặc 'RAG'
        """
        try:
            u_role = target_role.lower().strip()
            # Mapping chuẩn để khớp hoàn toàn với SQL
            if u_role in ['cb', 'canbo', 'advisor']: u_role = 'canbo'
            if u_role in ['sv', 'sinhvien', 'student']: u_role = 'sinhvien'

            with self._get_conn() as conn:
                cursor = conn.cursor()
                
                # Phân loại: Nếu có ValidatedSQL thì là nhóm Học tập (SQL), ngược lại là Quy chế (RAG)
                if knowledge_type == "SQL":
                    where_clause = "AND (ValidatedSQL IS NOT NULL AND ValidatedSQL <> '')"
                else:
                    where_clause = "AND (ValidatedSQL IS NULL OR ValidatedSQL = '')"
                
                query = f"""
                    SELECT TOP 4 QuestionText 
                    FROM tbl_AI_SQL_Knowledge 
                    WHERE (LOWER(TargetRole) = ? OR LOWER(AllowedRoles) LIKE ?) {where_clause}
                    ORDER BY HitCount DESC
                """
                cursor.execute(query, (u_role, f"%{u_role}%"))
                
                rows = cursor.fetchall()
                # Nếu lọc theo loại bị rỗng, trả về gợi ý chung của vai trò đó
                if not rows:
                    return self.get_sql_knowledge_suggestions(u_role, limit=4)
                    
                return [row[0] for row in rows]
        except Exception as e:
            print(f"🔥 Lỗi get_sql_knowledge_suggestions_by_type: {e}")
            return []        
    def tool_search_documents_hybrid(self, query_text, ai_instance, target_role="sinhvien"):
        """RAG Hybrid Search: Keyword LIKE + Vector + RBAC"""
        conn = self._get_conn()
        cursor = conn.cursor()
        try:
            # 1. ĐỊNH NGHĨA allowed_roles TRƯỚC KHI DÙNG
            # Đảm bảo khớp với dữ liệu 'canbo', 'sinhvien', 'all' trong SQL
            role_map = {
                'sinhvien': "('sinhvien', 'all')", 
                'canbo': "('canbo', 'sinhvien', 'all')"
            }
            # Lấy chuỗi điều kiện, mặc định là ('all') nếu không khớp
            allowed_roles = role_map.get(target_role.lower().strip(), "('all')")

            # 2. Bước 1: Keyword LIKE (Dùng N'' để hỗ trợ tiếng Việt)
            kw_sql = f"""
                SELECT ChunkId, Content, DocumentName, Keywords, 1.0 as Score
                FROM dbo.DocumentChunks 
                WHERE (Content LIKE N'%{query_text}%' OR Keywords LIKE N'%{query_text}%')
                AND LOWER(TargetRole) IN {allowed_roles}
            """
            cursor.execute(kw_sql)
            
            results = {row.ChunkId: {"content": row.Content, "doc": row.DocumentName, "keywords": row.Keywords, "score": 0.95} for row in cursor.fetchall()}

            # 3. Bước 2: Vector Search (Semantic)
            query_vector = ai_instance.get_embedding(query_text)
            cursor.execute(f"SELECT ChunkId, Content, DocumentName, Keywords, VectorJson FROM dbo.DocumentChunks WHERE VectorJson IS NOT NULL AND UPPER(TargetRole) IN {allowed_roles}")
            all_vecs = cursor.fetchall()
            
            q_vec = np.array(query_vector)
            for row in all_vecs:
                if row.ChunkId in results: continue # Đã có trong Keyword rồi
                v_array = np.array(json.loads(row.VectorJson))
                sim = np.dot(q_vec, v_array) / (np.linalg.norm(q_vec) * np.linalg.norm(v_array))
                if sim > 0.5:
                    results[row.ChunkId] = {"content": row.Content, "doc": row.DocumentName, "keywords": row.Keywords, "score": float(sim)}

            return sorted(results.values(), key=lambda x: x['score'], reverse=True)[:3]
        finally: conn.close()

    def search_sql_knowledge_hybrid(self, query_text, query_vector, target_role="sinhvien"):
        """
        SQL Hybrid Search V3.5: LIKE (2 chiều) + Vector + IsApproved Filter.
        Chế độ này đảm bảo chỉ lấy tri thức đã duyệt và cực kỳ nhạy với từ khóa.
        """
        conn = self._get_conn()
        cursor = conn.cursor()
        try:
            # 1. Chuẩn hóa vai trò người dùng
            u_role = target_role.lower().strip()
            
            # 2. BƯỚC 1: TÌM KIẾM LIKE 2 CHIỀU (Keyword Matching)
            # Logic: (Cột LIKE Tin nhắn) HOẶC (Tin nhắn LIKE Cột)
            kw_sql = """
                SELECT QuestionText, ValidatedSQL, 1.0 as Score 
                FROM tbl_AI_SQL_Knowledge 
                WHERE (QuestionText LIKE N'%' + ? + '%' OR ? LIKE N'%' + QuestionText + '%')
                AND (LOWER(TargetRole) = ? OR AllowedRoles LIKE ?)
                AND IsApproved = 1
            """
            # Tham số truyền vào: user_msg, user_msg, vai_tro, %vai_tro%
            cursor.execute(kw_sql, (query_text, query_text, u_role, f"%{u_role}%"))
            row = cursor.fetchone()
            
            if row:
                print(f"🎯 [SQL_HIT_LIKE] Khớp từ khóa: {row[0]}")
                return {"text": row[0], "sql": row[1], "score": 1.0}

            # 3. BƯỚC 2: TÌM KIẾM VECTOR (Semantic Matching)
            # Chỉ chạy nếu tìm LIKE không ra kết quả
            cursor.execute("""
                SELECT QuestionText, QuestionVector, ValidatedSQL 
                FROM tbl_AI_SQL_Knowledge 
                WHERE QuestionVector IS NOT NULL 
                AND (LOWER(TargetRole) = ? OR AllowedRoles LIKE ?)
                AND IsApproved = 1
            """, (u_role, f"%{u_role}%"))
            
            best_match, max_sim = None, -1.0
            q_vec = np.array(query_vector)
            
            rows = cursor.fetchall()
            for text, v_json, v_sql in rows:
                try:
                    # Chuyển chuỗi JSON Vector trong DB thành mảng Numpy
                    v_array = np.array(json.loads(v_json))
                    
                    # Tính toán độ tương đồng Cosine
                    sim = np.dot(q_vec, v_array) / (np.linalg.norm(q_vec) * np.linalg.norm(v_array))
                    
                    if sim > max_sim:
                        max_sim = sim
                        best_match = {"text": text, "sql": v_sql, "score": float(sim)}
                except:
                    continue
            
            # Ngưỡng chấp nhận 0.75 (Hạ từ 0.82 xuống để tăng độ nhạy)
            if max_sim > 0.75:
                print(f"🎯 [SQL_HIT_VECTOR] Khớp ngữ nghĩa ({max_sim:.2f}): {best_match['text']}")
                return best_match
                
            return None
        except Exception as e:
            print(f"🔥 Lỗi tại search_sql_knowledge_hybrid: {e}")
            return None
        finally:
            conn.close()
    # 🔥 Đảm bảo hàm này lùi vào cùng cấp với 'def get_config' (cấp Class)
    def get_chat_history_by_student(self, student_id: str, limit: int = 10):
        """Lấy lịch sử chat - Bản fix lỗi NameError và Unicode"""
        # 1. Làm sạch ID
        sid = student_id.strip().upper().replace("SV", "").replace("CB", "")
        
        # 2. KHỞI TẠO BIẾN TRƯỚC (Rất quan trọng để tránh NameError)
        history_list = [] 
        
        try:
            # Sử dụng self.conn_str (đảm bảo ở __init__ đã gán biến này)
            with self._get_conn() as conn:
                cursor = conn.cursor()
                sql = """
                    SELECT TOP (?) L.[Role], L.[Content]
                    FROM dbo.ChatLogs L
                    INNER JOIN dbo.ChatSessions S ON L.SessionId = S.Id
                    WHERE S.StudentId = ?
                    ORDER BY L.Timestamp DESC
                """
                cursor.execute(sql, (limit, sid))
                rows = cursor.fetchall()
                
                # 3. Chuyển đổi dữ liệu từ tuple sang dict
                # Dùng .strip() để xóa khoảng trắng thừa từ DB
                for r in rows:
                    history_list.append({
                        "role": str(r[0]).strip() if r[0] else "user",
                        "content": str(r[1]) if r[1] else ""
                    })
                    
        except Exception as e:
            print(f"🔥 Lỗi tại db_service.get_chat_history_by_student: {e}")
            return [] # Trả về mảng rỗng nếu có bất kỳ lỗi SQL nào
            
        # Đảo ngược lại để đúng thứ tự thời gian (cũ -> mới)
        return history_list[::-1]
    
      