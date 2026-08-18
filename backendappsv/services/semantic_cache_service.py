#services/semantic_cache_service 
import numpy as np
import json
import re
from config.settings import SIMILARITY_THRESHOLD
from .utils import normalize_vn
# 🔥 HÀM CHUẨN HÓA TIẾNG VIỆT (Fix lỗi chữ Đ -> o và mất dấu)


class SemanticCacheService:
    def __init__(self, db_service, embedding_service):
        self.db = db_service
        self.embedding = embedding_service

    def search(self, question: str):
        """Hàm tìm kiếm tri thức SQL linh hoạt: Keyword -> Vector"""
        # 1. Chuẩn hóa câu hỏi
        norm_user_q = normalize_vn(question)
        query_vector = self.embedding.get_embedding(norm_user_q)
        
        if not query_vector:
            return None

        # 2. Kết nối DB với cấu hình Encoding đã fix
        conn = self.db._get_conn()
        cursor = conn.cursor()

        try:
            # Lấy thêm QuestionText để so khớp Keyword
            cursor.execute("""
                SELECT QuestionText, QuestionVector, ValidatedSQL
                FROM tbl_AI_SQL_Knowledge
                WHERE QuestionVector IS NOT NULL
            """)

            best_sql = None
            max_sim = -1.0
            q_vec = np.array(query_vector)

            rows = cursor.fetchall()
            for q_text, v_json, v_sql in rows:
                try:
                    # --- A. KIỂM TRA KEYWORD (Chính xác tuyệt đối) ---
                    norm_db_q = normalize_vn(q_text)
                    if norm_user_q in norm_db_q or norm_db_q in norm_user_q:
                        print(f"🎯 Khớp Keyword trực tiếp: '{q_text}'")
                        return v_sql

                    # --- B. KIỂM TRA SEMANTIC (Ngữ nghĩa Vector) ---
                    db_vec = np.array(json.loads(v_json))
                    # Tính Cosine Similarity
                    sim = np.dot(q_vec, db_vec) / (np.linalg.norm(q_vec) * np.linalg.norm(db_vec))

                    if sim > max_sim:
                        max_sim = float(sim)
                        best_sql = v_sql
                except:
                    continue # Bỏ qua dòng bị lỗi Unicode, không làm sập cả hàm

            # 3. Kiểm tra ngưỡng tương đồng
            if max_sim >= SIMILARITY_THRESHOLD:
                print(f"🎯 Cache hit similarity={max_sim:.2f} (Normalized: '{norm_user_q}')")
                return best_sql

        except Exception as e:
            print(f"⚠️ Lỗi trong SemanticCache search: {e}")
            return None
        finally:
            conn.close()

        return None

    def learn_if_new(self, question, sql, vector):
        """Chỉ học nếu câu hỏi thực sự mới (Similarity < 0.9)"""
        # Kiểm tra trùng lặp trước
        existing = self.db.search_sql_knowledge_hybrid(question, vector)
        if existing and existing['score'] > 0.9:
            print(f"♻️ Tri thức tương đương đã tồn tại (Score: {existing['score']}), bỏ qua nạp mới.")
            return False
            
        # Nếu mới hoàn toàn thì nạp
        self.learn(question, sql)
        return True
    def learn(self, question: str, sql: str, role: str = 'sinhvien'):
        """Lưu tri thức mới vào bộ não của Bot với trạng thái chờ duyệt (IsApproved = 0)"""
        try:
            norm_question = normalize_vn(question)
            vector = self.embedding.get_embedding(norm_question)
            
            if not vector: return

            conn = self.db._get_conn()
            cursor = conn.cursor()

            # Mapping vai trò để lưu cho chuẩn
            target_role = 'STUDENT' if role == 'sinhvien' else 'CANBO'
            allowed_roles = 'sinhvien,all' if role == 'sinhvien' else 'canbo,all'

            # THÊM CỘT IsApproved = 0
            cursor.execute("""
                INSERT INTO tbl_AI_SQL_Knowledge
                (QuestionText, QuestionVector, ValidatedSQL, HitCount, CreatedAt, AllowedRoles, TargetRole, IsApproved)
                VALUES (?, ?, ?, 0, GETDATE(), ?, ?, 0)
            """, (question, json.dumps(vector), sql, allowed_roles, target_role))

            conn.commit()
            conn.close()
            print(f"🎓 [SELF-LEARNING] Đã học câu hỏi mới: '{question}' (Trạng thái: Chờ duyệt)")
        except Exception as e:
            print(f"❌ Lỗi lưu tri thức mới: {e}")