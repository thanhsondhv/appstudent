import numpy as np
import json

class AIKnowledgeService:
    def __init__(self, db_service, ai_service):
        self.db = db_service
        self.ai = ai_service
        self.similarity_threshold = 0.85 # Ngưỡng tin cậy

    def get_semantic_sql(self, user_query: str):
        """Tìm SQL trong kho bằng Vector Similarity (Giống tìm chunk tài liệu)"""
        query_vector = self.ai.get_embedding(user_query)
        if not query_vector: return None

        conn = self.db._get_conn()
        cursor = conn.cursor()
        try:
            # Lấy toàn bộ kho tri thức để tính toán (Do SQL Server local thường không có Vector Index)
            cursor.execute("SELECT QuestionVector, ValidatedSQL, QuestionText FROM tbl_AI_SQL_Knowledge WHERE QuestionVector IS NOT NULL")
            rows = cursor.fetchall()
            
            best_sql = None
            max_sim = 0
            
            q_vec = np.array(query_vector)
            for v_json, sql, q_text in rows:
                db_vec = np.array(json.loads(v_json))
                # Tính Cosine Similarity
                sim = np.dot(q_vec, db_vec) / (np.linalg.norm(q_vec) * np.linalg.norm(db_vec))
                
                if sim > max_sim:
                    max_sim = sim
                    best_sql = sql
            
            if max_sim >= self.similarity_threshold:
                print(f"🎯 SEMANTIC MATCH ({max_sim:.2f}): Khớp với câu '{q_text}'")
                return best_sql
            
            return None
        finally:
            conn.close()

    def learn_new_sql(self, question: str, validated_sql: str):
        """Lưu câu lệnh thành công kèm Vector để lần sau không cần AI suy luận nữa"""
        vector = self.ai.get_embedding(question)
        if not vector: return

        conn = self.db._get_conn()
        cursor = conn.cursor()
        try:
            # Lưu QuestionVector dưới dạng JSON mảng số thực
            cursor.execute("""
                INSERT INTO tbl_AI_SQL_Knowledge (QuestionText, QuestionVector, ValidatedSQL, HitCount)
                VALUES (?, ?, ?, 1)
            """, (question, json.dumps(vector), validated_sql))
            conn.commit()
            print(f"🎓 Đã nạp tri thức mới: {question}")
        except Exception as e:
            print(f"⚠️ Lỗi lưu tri thức: {e}")
        finally:
            conn.close()