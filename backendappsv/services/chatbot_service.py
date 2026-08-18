# services/chatbot_service.py

from services.ai_generation_service import AIGenerationService
from services.ai_prompt_service import AIPromptService
from services.semantic_cache_service import SemanticCacheService
from services.sql_validator_service import SQLValidatorService
from services.embedding_service import EmbeddingService

class ChatbotService:

    def __init__(self, db_service):
        self.db = db_service
        self.embedding = EmbeddingService()
        self.ai = AIGenerationService()
        self.cache = SemanticCacheService(db_service, self.embedding)
        self.validator = SQLValidatorService()
        self.prompt_service = AIPromptService()

    # Đã đổi program_code thành program_id
    def ask(self, question, student_id, program_id, gpa):

        print("🟡 Question:", question)

        # 1. Tìm trong Cache trước
        sql_template = self.cache.search(question)
        is_from_cache = True

        # 2. Nếu không có trong Cache -> Gọi AI sinh SQL
        if not sql_template:
            is_from_cache = False
            print("⚡ No cache hit → generating SQL")

            prompt = self.prompt_service.build_prompt(
                question,
                student_id,
                program_id,
                gpa
            )

            sql_template = self.ai.generate_sql(prompt)

            print("🟢 RAW AI RESPONSE:\n", sql_template)

            if not self.validator.validate(sql_template):
                print("❌ SQL failed validation")
                return {"error": "SQL không hợp lệ", "sql": sql_template, "data": []}

        # 3. 🔥 BƯỚC QUAN TRỌNG: ĐIỀN DỮ LIỆU THẬT VÀO TEMPLATE SQL
        # Đã đổi {program_code} thành {program_id} để thay thế chuẩn xác
        final_sql = sql_template.replace("{student_id}", str(student_id)).replace("{program_id}", str(program_id))

        print(f"⚙️ [DEBUG] SQL THỰC TẾ GỬI VÀO DB:\n{final_sql}")

        # 4. Thực thi Database
        result = self.db.execute_query(final_sql)

        # 5. 🔥 HỌC KHÔN: CHỈ LƯU VÀO CACHE NẾU LỆNH CHẠY THÀNH CÔNG
        if not is_from_cache:
            # Kiểm tra: kết quả là list (thành công) HOẶC là chuỗi nhưng không chứa từ "Lỗi"
            if isinstance(result, list) or (isinstance(result, str) and "Lỗi" not in result):
                print("🎓 [CACHE] Lệnh chạy mượt mà! Đang lưu câu SQL chuẩn vào bộ nhớ...")
                self.cache.learn(question, sql_template) # Bắt buộc lưu bản GỐC chứa {student_id}
            else:
                print("⚠️ [CACHE] Lệnh bị lỗi DB, TỪ CHỐI lưu vào bộ nhớ để tránh học ngu!")

        return {
            "sql": final_sql, 
            "data": result
        }