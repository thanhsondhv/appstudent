import os
import sys
import json

# 1. Tự động xác định đường dẫn dự án
# Lấy thư mục chứa file này (services)
current_dir = os.path.dirname(os.path.abspath(__file__)) 
# Lấy thư mục gốc (vinhuni_chatbot_python)
project_root = os.path.abspath(os.path.join(current_dir, ".."))

# 2. Thêm thư mục gốc vào đầu danh sách tìm kiếm của Python
if project_root not in sys.path:
    sys.path.insert(0, project_root)

# 3. Ép chuyển môi trường làm việc về thư mục gốc
os.chdir(project_root)

# 4. Nạp CONFIG trực tiếp từ vinhuni_chatbot_python
try:
    # Thử import CONFIG từ thư mục gốc
    import CONFIG
    print(f"✅ Đã tìm thấy CONFIG tại: {project_root}")
except ImportError:
    # Nếu lỗi, thử tìm trong file __init__.py ở gốc
    try:
        from __init__ import CONFIG
        print("✅ Đã nạp CONFIG từ __init__.py")
    except ImportError:
        print(f"🔥 LỖI: Không tìm thấy file CONFIG hoặc __init__.py chứa cấu hình tại {project_root}")
        sys.exit(1)

# 5. Import các Service (Sử dụng đường dẫn tuyệt đối trong gói)
try:
    from services.db_service import DatabaseService
    from services.ai_service_v2 import AIServiceV2
    print("✅ Kết nối Service thành công!")
except Exception as e:
    print(f"🔥 Lỗi nạp Service: {e}")
    sys.exit(1)

def update_missing_vectors():
    db = DatabaseService()
    ai = AIServiceV2()
    conn = db._get_conn()
    cursor = conn.cursor()
    
    print("\n🚀 ĐANG BẮT ĐẦU TẠO VECTOR...")
    try:
        cursor.execute("SELECT Id, QuestionText FROM tbl_AI_SQL_Knowledge WHERE QuestionVector IS NULL")
        rows = cursor.fetchall()
        
        if not rows:
            print("✨ Không có câu hỏi nào cần xử lý.")
            return

        for row_id, q_text in rows:
            if not q_text: continue
            print(f"➡️ Đang xử lý ID {row_id}: '{q_text}'")
            
            vector = ai.get_embedding(q_text)
            if vector:
                cursor.execute(
                    "UPDATE tbl_AI_SQL_Knowledge SET QuestionVector = ? WHERE Id = ?",
                    (json.dumps(vector), row_id)
                )
                print(f"   ✅ Đã nạp Vector thành công.")
            else:
                print(f"   ❌ Lỗi: OpenAI không trả về Vector.")
        
        conn.commit()
        print("\n🎉 HOÀN THÀNH! Kho tri thức đã được số hóa.")
    except Exception as e:
        print(f"🔥 Lỗi Database: {e}")
    finally:
        conn.close()

if __name__ == "__main__":
    update_missing_vectors()