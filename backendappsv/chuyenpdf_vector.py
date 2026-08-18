import fitz  # PyMuPDF
import os
import pyodbc
import numpy as np
from sentence_transformers import SentenceTransformer
from core.settings import settings  # cấu hình tập trung (Pha 0)

# 1. Khai báo Model AI (Bản đa ngôn ngữ của Google/VinAI cực tốt cho tiếng Việt)
model = SentenceTransformer('paraphrase-multilingual-MiniLM-L12-v2')

# 2. Cấu hình đường dẫn ổ E của Sơn
PDF_FOLDER = r"E:\app_vinhuni\vanban\docs"
CONN_STR = settings.db.local_conn_str

def process_vectors():
    conn = pyodbc.connect(CONN_STR, autocommit=True)
    cursor = conn.cursor()
    
    # Lấy văn bản có file nhưng chưa có Vector (VectorStatus = 0)
    cursor.execute("SELECT DocId, FileName FROM tbl_Document_Library WHERE FileName IS NOT NULL AND VectorStatus = 0")
    rows = cursor.fetchall()
    
    print(f"🤖 AI bắt đầu đọc {len(rows)} văn bản...")

    for doc_id, file_name in rows:
        path = os.path.join(PDF_FOLDER, file_name)
        if not os.path.exists(path): continue

        try:
            # A. Đọc chữ từ PDF
            pdf = fitz.open(path)
            text = " ".join([page.get_text() for page in pdf])
            
            if len(text.strip()) < 20: continue # Bỏ qua file rỗng

            # B. AI chuyển chữ thành Vector (Dãy số 384 chiều)
            vector = model.encode(text)
            vector_binary = vector.astype(np.float32).tobytes() # Chuyển sang binary để lưu SQL

            # C. Lưu vào bảng Vectors
            cursor.execute("""
                IF EXISTS (SELECT 1 FROM tbl_Document_Vectors WHERE DocId = ?)
                    UPDATE tbl_Document_Vectors SET VectorData = ?, LastUpdated = GETDATE() WHERE DocId = ?
                ELSE
                    INSERT INTO tbl_Document_Vectors (DocId, VectorData) VALUES (?, ?)
            """, (doc_id, vector_binary, doc_id, doc_id, vector_binary))

            # Đánh dấu đã xong
            cursor.execute("UPDATE tbl_Document_Library SET VectorStatus = 1 WHERE DocId = ?", (doc_id,))
            print(f"✅ Đã số hóa nội dung ID: {doc_id}")

        except Exception as e:
            print(f"🔥 Lỗi file {file_name}: {e}")
    conn.close()

if __name__ == "__main__":
    process_vectors()