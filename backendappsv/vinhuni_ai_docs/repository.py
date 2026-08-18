# vinhuni_ai_docs/repository.py
import pyodbc
import json
import numpy as np

class DocRepository:
    def __init__(self, conn_str):
        self.conn_str = conn_str

    def save_chunk(self, doc_name, index, content, vector):
        with pyodbc.connect(self.conn_str) as conn:
            cursor = conn.cursor()
            sql = "INSERT INTO DocumentChunks (DocumentName, ChunkIndex, Content, VectorJson) VALUES (?, ?, ?, ?)"
            # Chuyển list vector thành chuỗi JSON
            cursor.execute(sql, (doc_name, index, content, json.dumps(vector)))
            conn.commit()

    def search_similar(self, query_vector, top_k=3):
        with pyodbc.connect(self.conn_str) as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT Content, VectorJson FROM DocumentChunks")
            rows = cursor.fetchall()

        if not rows: return ""

        results = []
        q_vec = np.array(query_vector)
        
        for content, v_json in rows:
            db_vec = np.array(json.loads(v_json))
            # Tính Cosine Similarity bằng tay (Vì SQL Server không hỗ trợ sẵn)
            similarity = np.dot(q_vec, db_vec) / (np.linalg.norm(q_vec) * np.linalg.norm(db_vec))
            results.append((content, similarity))
        
        results.sort(key=lambda x: x[1], reverse=True)
        return " ".join([r[0] for r in results[:top_k]])