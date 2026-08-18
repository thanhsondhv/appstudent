import json
import numpy as np
from services.db_service import DBService
from services.embedding_service import EmbeddingService
from services.utils import normalize_vn # Đảm bảo Sơn đã tạo file utils.py như mình hướng dẫn

def reindex_all_knowledge():
    db = DBService()
    embedding = EmbeddingService()
    
    print("🚀 Bắt đầu quá trình tạo lại Vector cho bảng Knowledge...")
    
    try:
        # 1. Kết nối và lấy tất cả câu hỏi hiện có
        conn = db._get_conn()
        cursor = conn.cursor()
        cursor.execute("SELECT Id, QuestionText FROM tbl_AI_SQL_Knowledge")
        rows = cursor.fetchall()
        
        if not rows:
            print("⚠️ Không có dữ liệu trong bảng tbl_AI_SQL_Knowledge.")
            return

        print(f"📊 Tìm thấy {len(rows)} câu hỏi cần xử lý.")
        
        count = 0
        for q_id, q_text in rows:
            if not q_text: continue
            
            # 2. Chuẩn hóa theo logic mới (đ -> d)
            clean_text = normalize_vn(q_text)
            
            # 3. Tạo Vector mới từ OpenAI
            new_vector = embedding.get_embedding(clean_text)
            
            if new_vector:
                # 4. Cập nhật lại vào Database
                cursor.execute("""
                    UPDATE tbl_AI_SQL_Knowledge 
                    SET QuestionVector = ? 
                    WHERE Id = ?
                """, (json.dumps(new_vector), q_id))
                
                count += 1
                print(f"✅ Đã cập nhật Id {q_id}: '{q_text}' -> '{clean_text}'")
            else:
                print(f"❌ Lỗi tạo vector cho Id {q_id}")

        conn.commit()
        conn.close()
        print(f"\n✨ HOÀN THÀNH! Đã cập nhật thành công {count}/{len(rows)} câu hỏi.")
        print("Bây giờ Sơn có thể quay lại Chat V3 để tận hưởng tốc độ 'nổ' Cache 🎯 chuẩn đét!")

    except Exception as e:
        print(f"🔥 Lỗi nghiêm trọng: {e}")

if __name__ == "__main__":
    reindex_all_knowledge()