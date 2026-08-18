# services/ai_generation_service.py
import re
from openai import OpenAI
from config.settings import OPENAI_API_KEY, CHAT_MODEL_FAST

class AIGenerationService:

    def __init__(self):
        self.client = OpenAI(api_key=OPENAI_API_KEY)

    def generate_sql(self, prompt, model=CHAT_MODEL_FAST):
        response = self.client.chat.completions.create(
            model=model,
            messages=[
                {
                    "role": "system",
                    "content": "Bạn là chuyên gia cơ sở dữ liệu SQL Server. CHỈ trả về câu lệnh SQL thuần túy bắt đầu bằng SELECT. TUYỆT ĐỐI KHÔNG giải thích, KHÔNG chào hỏi, KHÔNG nói thêm bất kỳ từ nào khác ngoài câu lệnh SQL."
                },
                {"role": "user", "content": prompt}
            ],
            temperature=0.0 # Ép AI không được "sáng tạo" lung tung
        )

        raw_reply = response.choices[0].message.content.strip()

        # 🔥 Đưa qua hàm bóc tách thông minh để lấy đúng câu SQL
        sql = self._extract_sql_safely(raw_reply)
        
        return sql

    def _extract_sql_safely(self, text: str) -> str:
        """Bộ lọc Regex cực mạnh để bóc tách câu SQL dù AI có lỡ sinh thêm chữ"""
        
        # 1. Tìm phần nằm giữa ```sql và ```
        match = re.search(r'```(?:sql)?\s*(.*?)\s*```', text, re.DOTALL | re.IGNORECASE)
        if match:
            return match.group(1).strip()
            
        # 2. Nếu AI không sinh dấu ``` mà sinh luôn câu SQL xen lẫn text thường
        # Ta sẽ tìm từ khóa SELECT đầu tiên và cắt từ đó trở đi
        upper_text = text.upper()
        if "SELECT " in upper_text:
            start_idx = upper_text.find("SELECT ")
            # Tạm thời trả về từ chữ SELECT cho đến hết chuỗi (vẫn an toàn hơn là lấy cả text chào hỏi)
            return text[start_idx:].strip()

        # 3. Quét dọn thủ công dự phòng nếu không rớt vào 2 trường hợp trên
        clean_text = text.replace("```sql", "").replace("```", "").strip()
        return clean_text