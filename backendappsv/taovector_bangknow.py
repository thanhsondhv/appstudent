# Script cập nhật Vector cho tri thức mới nạp
from services.db_service import DBService
from services.embedding_service import EmbeddingService
import json

db = DBService()
emb = EmbeddingService()

# 1. Lấy các câu chưa có Vector
conn = db._get_conn()
cursor = conn.cursor()
cursor.execute("SELECT Id, QuestionText FROM tbl_AI_SQL_Knowledge WHERE QuestionVector IS NULL")
rows = cursor.fetchall()

print(f"🔄 Đang tạo Vector cho {len(rows)} câu hỏi mẫu...")

for row_id, text in rows:
    # Tạo vector từ OpenAI
    vector = emb.get_embedding(text)
    # Lưu lại vào DB
    cursor.execute(
        "UPDATE tbl_AI_SQL_Knowledge SET QuestionVector = ? WHERE Id = ?",
        (json.dumps(vector), row_id)
    )
    conn.commit()
    print(f"✅ Đã cập nhật Vector cho: {text[:30]}...")

conn.close()
print("🎉 Hoàn tất! AI của bạn hiện đã sẵn sàng trả lời 10 nhóm câu hỏi chuyên sâu.")