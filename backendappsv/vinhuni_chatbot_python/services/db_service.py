import pyodbc
import json
import numpy as np
from .. import CONFIG 

class DBService:
    def __init__(self):
        # Cập nhật: Dùng tài khoản ChatbotUser để bảo mật (chỉ SELECT)
        self.conn_str = (
            "DRIVER={ODBC Driver 17 for SQL Server};"
            "SERVER=AI2025\\SQLEXPRESS02;"
            "DATABASE=VinhUni_Local;"
            "UID=ChatbotUser;"
            "PWD=VinhUni@2026;"
        )

    def _get_conn(self):
        """Khởi tạo kết nối SQL Server"""
        return pyodbc.connect(self.conn_str)

    # --- 1. HÀM TỔNG HỢP DỮ LIỆU SINH VIÊN (Trang chủ) ---
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

    # --- 2. QUẢN LÝ PHIÊN & NHẬT KÝ ---
    def create_session(self, student_id: str):
        conn = self._get_conn()
        cursor = conn.cursor()
        cursor.execute("INSERT INTO dbo.ChatSessions (StudentId, StartTime) OUTPUT INSERTED.Id VALUES (?, GETDATE())", (student_id,))
        new_id = cursor.fetchone()[0]
        conn.commit()
        conn.close()
        return new_id

    def save_message(self, session_id: int, role: str, content: str):
        conn = self._get_conn()
        cursor = conn.cursor()
        cursor.execute("INSERT INTO dbo.ChatLogs (SessionId, [Role], Content, [Timestamp]) VALUES (?, ?, ?, GETDATE())", (session_id, role, content))
        conn.commit()
        conn.close()

    # --- 3. PROFILE SINH VIÊN ---
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

    # --- 4. THỐNG KÊ HỌC TẬP (GPA 2.73) ---
    def get_student_academic_stats(self, student_id: str):
        conn = self._get_conn()
        cursor = conn.cursor()
        try:
            clean_id = str(student_id).strip().upper().replace("SV", "")
            
            # Lấy Program ID động (Thêm IsDeleted = 0 cho ctdt)
            cursor.execute("""
                SELECT TOP 1 ctdt.Id 
                FROM dbo.StudentProfiles sp
                JOIN dbo.tbl_ChuongTrinhDaoTao ctdt ON RTRIM(sp.IdChuongTrinhDaoTao) = RTRIM(ctdt.Code)
                WHERE sp.MaSinhVien = ? AND ctdt.IsDeleted = 0
            """, (clean_id,))
            
            row_ctdt = cursor.fetchone()
            real_program_id = row_ctdt[0] if row_ctdt else 2201

            # Bổ sung IsDeleted = 0 cho bảng kh (Khung) và h (Học phần)
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
            INNER JOIN tbl_HocPhan h ON kh.IdHocPhan = h.Id 
            LEFT JOIN (
                SELECT h_sub.Id AS IdHocPhan_Int, d.Diem, d.DiemChu
                FROM DiemHocPhan d
                INNER JOIN tbl_HocPhan h_sub ON d.IdHocPhan = h_sub.InstanceId
                WHERE (RTRIM(d.IdNguoiHoc) = ? OR RTRIM(d.IdNguoiHoc) = 'SV' + ?)
                  AND d.IsDeleted = 0
            ) d ON h.Id = d.IdHocPhan_Int
            WHERE kh.IdChuongTrinhDaoTao = ?
              AND kh.IsDeleted = 0 
              AND h.IsDeleted = 0;
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
        except Exception as e:
            print(f"🔥 Lỗi get_student_academic_stats: {e}")
            return None
        finally:
            conn.close()

    # --- 5. CÔNG CỤ (TOOLS) CHO AI ---
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

    # --- 🔥 HÀM MỚI: TÌM KIẾM QUY CHẾ (RAG) ---
    def tool_search_documents(self, query_text: str, ai_service_instance=None):
        """Tìm kiếm quy chế bằng Vector Similarity (Semantic Search) với logic tối ưu"""
        if not ai_service_instance:
            return "Lỗi: Không thể kết nối dịch vụ Vector AI."
            
        conn = self._get_conn()
        cursor = conn.cursor()
        try:
            # 1. Chuyển câu hỏi của sinh viên sang Vector
            query_vector = ai_service_instance.get_embedding(query_text)
            if query_vector is None:
                return "Lỗi: Không thể tạo vector cho câu hỏi."
            
            # 2. Lấy toàn bộ kho tri thức từ bảng DocumentChunks
            cursor.execute("SELECT Content, VectorJson, DocumentName FROM dbo.DocumentChunks WHERE VectorJson IS NOT NULL")
            all_chunks = cursor.fetchall()
            
            results = []
            q_vec = np.array(query_vector)
            norm_q = np.linalg.norm(q_vec)

            for content, v_json, doc_name in all_chunks:
                try:
                    v_array = np.array(json.loads(v_json))
                    # Tính toán độ tương đồng Cosine
                    score = np.dot(q_vec, v_array) / (norm_q * np.linalg.norm(v_array))
                    
                    # 🔥 TỐI ƯU: Hạ ngưỡng từ 0.28 xuống 0.22 để bắt được nhiều ý liên quan hơn
                    if score > 0.22: 
                        results.append({"doc": doc_name, "content": content, "score": float(score)})
                except: continue

            # 3. Sắp xếp theo độ liên quan giảm dần và lấy 8 đoạn tốt nhất (thay vì 5)
            sorted_res = sorted(results, key=lambda x: x['score'], reverse=True)[:8]
            
            if not sorted_res: 
                print(f"🔍 RAG: Không tìm thấy nội dung nào khớp với '{query_text}'")
                return "Không tìm thấy quy định cụ thể nào trong hệ thống tài liệu. Hãy khuyên sinh viên liên hệ phòng Đào tạo."

            # In log ra Terminal để bạn theo dõi AI đang đọc tài liệu nào
            print(f"✅ RAG: Tìm thấy {len(sorted_res)} đoạn văn liên quan cho từ khóa '{query_text}'")
            
            return json.dumps(sorted_res, ensure_ascii=False)
        finally:
            conn.close()

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
        """Lấy cấu hình AI từ Database để không cần Restart Server"""
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
            conn.close()        