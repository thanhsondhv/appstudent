import json
import os
import sys

# 1. ĐỊNH NGHĨA GỐC DỰ ÁN (C:\vinhuni_project)
# Lấy thư mục cha của thư mục hiện tại
current_dir = os.path.dirname(os.path.abspath(__file__)) # ...\vinhuni_chatbot_python
root_project = os.path.dirname(current_dir) # C:\vinhuni_project

# Thêm cả 2 vào PATH để Python tìm thấy cả 'main.py' và 'services'
sys.path.insert(0, root_project)
sys.path.insert(0, current_dir)

print(f"📍 Root Project: {root_project}")

try:
    # Import theo cấu trúc thư mục thực tế
    from services.db_service import DBService
    from services.ai_service_v2 import AIServiceV2
    print("✅ Đã tìm thấy module dịch vụ.")
except ImportError as e:
    print(f"❌ Lỗi Import: {e}")
    # Backup: Thử import nếu coi chatbot là một package con
    try:
        from vinhuni_chatbot_python.services.db_service import DBService
        from vinhuni_chatbot_python.services.ai_service_v2 import AIServiceV2
        print("✅ Đã tìm thấy module dịch vụ (qua package path).")
    except:
        sys.exit()

def sync_knowledge_vectors():
    db = DBService()
    ai = AIServiceV2()
    
    conn = db._get_conn()
    cursor = conn.cursor()
    
    try:
        # Lấy dữ liệu chưa có vector
        cursor.execute("SELECT Id, QuestionText FROM tbl_AI_SQL_Knowledge WHERE QuestionVector IS NULL")
        rows = cursor.fetchall()
        
        if not rows:
            print("✅ Dữ liệu đã đầy đủ Vector.")
            return

        print(f"🔄 Đang tạo Vector cho {len(rows)} câu hỏi...")

        for row_id, q_text in rows:
            if not q_text: continue
            print(f"   -> Đang xử lý: '{q_text}'")
            vector = ai.get_embedding(q_text)
            
            if vector:
                cursor.execute(
                    "UPDATE tbl_AI_SQL_Knowledge SET QuestionVector = ? WHERE Id = ?",
                    (json.dumps(vector), row_id)
                )
                print(f"   ✅ Xong Id: {row_id}")
        
        conn.commit()
        print("\n🎉 HOÀN THÀNH ĐỒNG BỘ VECTOR!")
    finally:
        conn.close()

if __name__ == "__main__":
    sync_knowledge_vectors()