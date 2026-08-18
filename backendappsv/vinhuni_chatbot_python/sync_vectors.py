import json
import os
import sys

# 1. TỰ ĐỘNG CẤU HÌNH ĐƯỜNG DẪN (PATH)
current_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.append(current_dir)

# Thử thêm các folder con vào path để tìm folder 'services'
for root, dirs, files in os.walk(current_dir):
    if 'services' in dirs:
        sys.path.append(root)

# 2. IMPORT MODULE (Với cơ chế dự phòng)
try:
    try:
        # Thử import trực tiếp nếu folder services nằm ngay tại gốc
        from services.db_service import DBService
        from services.ai_service_v2 import AIServiceV2
    except ImportError:
        # Thử import qua app.services nếu cấu trúc của bạn có folder app bao ngoài
        from app.services.db_service import DBService
        from app.services.ai_service_v2 import AIServiceV2
except ImportError as e:
    print(f"❌ Lỗi: Không thể tìm thấy các module dịch vụ. ({e})")
    print(f"📍 Thư mục đang chạy: {current_dir}")
    print("💡 Hãy đảm bảo bạn chạy lệnh: python sync_vectors.py ngay tại thư mục gốc dự án.")
    sys.exit()

def sync_knowledge_vectors():
    # Khởi tạo dịch vụ
    try:
        db = DBService()
        ai = AIServiceV2()
    except Exception as e:
        print(f"🔥 Lỗi khi khởi tạo dịch vụ (Kiểm tra appsettings.json): {e}")
        return
    
    print("🚀 Đang kiểm tra dữ liệu trong tbl_AI_SQL_Knowledge...")
    
    conn = db._get_conn()
    cursor = conn.cursor()
    
    try:
        # 1. Lấy các câu hỏi đang bị thiếu Vector (NULL)
        cursor.execute("SELECT Id, QuestionText FROM tbl_AI_SQL_Knowledge WHERE QuestionVector IS NULL")
        rows = cursor.fetchall()
        
        if not rows:
            print("✅ Tất cả tri thức đã có Vector. Không cần cập nhật thêm.")
            return

        print(f"🔄 Tìm thấy {len(rows)} câu hỏi cần tạo Vector. Đang xử lý...")

        for row_id, q_text in rows:
            if not q_text: continue
            print(f"   -> Đang tạo Vector cho câu: '{q_text}'...")
            
            # 2. Gọi OpenAI lấy Embedding (1536 chiều)
            vector = ai.get_embedding(q_text)
            
            if vector:
                # 3. Cập nhật vào Database (Lưu dưới dạng chuỗi JSON)
                vector_json = json.dumps(vector)
                cursor.execute(
                    "UPDATE tbl_AI_SQL_Knowledge SET QuestionVector = ? WHERE Id = ?",
                    (vector_json, row_id)
                )
                print(f"   ✅ Cập nhật thành công Id: {row_id}")
            else:
                print(f"   ❌ Lỗi: OpenAI không trả về Vector cho câu '{q_text}'")

        conn.commit()
        print("\n🎉 HOÀN THÀNH! Hệ thống tri thức đã được số hóa sang Vector.")
        
    except Exception as e:
        print(f"🔥 Lỗi hệ thống: {e}")
    finally:
        conn.close()

if __name__ == "__main__":
    sync_knowledge_vectors()