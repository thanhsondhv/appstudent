# services/document_service.py
from docxtpl import DocxTemplate
import os
import uuid

class DocumentService:
    def __init__(self):
        # Trỏ thẳng vào thư mục chứa mẫu đơn của bạn
        # Đường dẫn gốc tính từ nơi bạn chạy file main.py
        self.template_dir = os.path.join("templates", "maudon") 
        self.export_dir = os.path.join("static", "exports")
        
        # Tự động tạo thư mục export nếu chưa có
        os.makedirs(self.export_dir, exist_ok=True)

    def generate_dynamic_document(self, template_name, user_data):
        # Kết hợp: templates/maudon/mau_don_nghi_hoc.docx
        template_path = os.path.join(self.template_dir, template_name)
        
        file_id = uuid.uuid4().hex[:6]
        student_id = user_data.get('STUDENT_ID', 'Unk')
        output_filename = f"Don_{student_id}_{file_id}.docx"
        output_path = os.path.join(self.export_dir, output_filename)

        try:
            if not os.path.exists(template_path):
                print(f"❌ Không tìm thấy mẫu tại: {template_path}")
                return None

            doc = DocxTemplate(template_path)
            doc.render(user_data)
            doc.save(output_path)
            
            # Trả về URL để Flutter tải về
            return {
                "url": f"https://mobi.vinhuni.edu.vn/static/exports/{output_filename}",
                "name": output_filename
            }
        except Exception as e:
            print(f"🔥 Lỗi DocumentService: {e}")
            return None