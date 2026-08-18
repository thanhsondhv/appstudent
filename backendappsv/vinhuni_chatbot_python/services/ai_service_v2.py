import json
import os
from openai import OpenAI

# Tự động tìm và tải cấu hình từ appsettings.json thay cho 'from .. import CONFIG'
def load_vinhuni_config():
    paths = [
        os.path.join(os.getcwd(), '..', 'appsettings.json'), # Nếu chạy từ thư mục con
        os.path.join(os.getcwd(), 'appsettings.json')        # Nếu chạy từ gốc dự án
    ]
    for p in paths:
        if os.path.exists(p):
            with open(p, 'r', encoding='utf-8') as f:
                return json.load(f)
    raise FileNotFoundError("❌ Không tìm thấy file appsettings.json. Hãy đảm bảo file tồn tại.")

CONFIG = load_vinhuni_config()

class AIServiceV2:
    def __init__(self):
        # Khởi tạo các tham số từ file cấu hình chung
        self.api_key = CONFIG['OpenAI']['ApiKey']
        self.client = OpenAI(api_key=self.api_key)
        self.chat_model = CONFIG['OpenAI'].get('ChatModel', 'gpt-4o-mini')
        self.embed_model = CONFIG['OpenAI'].get('EmbeddingModel', 'text-embedding-3-small')

    def get_embedding(self, text: str):
        """Chuyển văn bản thành Vector - Phục vụ Semantic Cache và RAG"""
        if not text:
            return None
        try:
            response = self.client.embeddings.create(
                input=text, 
                model=self.embed_model
            )
            return response.data[0].embedding
        except Exception as e:
            print(f"🔥 Lỗi OpenAI Embedding V2: {e}")
            return None

    def chat_with_v2_logic(self, system_instruction: str, user_message: str, tools_map: dict, max_retries=2):
        """Vòng lặp Agentic tự sửa lỗi SQL"""
        messages = [
            {"role": "system", "content": system_instruction},
            {"role": "user", "content": user_message}
        ]
        
        attempts = 0
        while attempts <= max_retries:
            try:
                response = self.client.chat.completions.create(
                    model=self.chat_model,
                    messages=messages,
                    tools=self._get_tools_schema(),
                    tool_choice="auto",
                    temperature=0.2
                )
                
                resp_msg = response.choices[0].message
                
                if not resp_msg.tool_calls:
                    return resp_msg.content

                messages.append(resp_msg)
                
                for tool_call in resp_msg.tool_calls:
                    fn_name = tool_call.function.name
                    fn_args = json.loads(tool_call.function.arguments)
                    
                    print(f"🤖 [V2 Agent]: Đang gọi {fn_name} với tham số {fn_args}")
                    
                    if fn_name in tools_map:
                        res = tools_map[fn_name](**fn_args)
                        
                        # Tự sửa lỗi nếu SQL trả về thông báo lỗi
                        if fn_name == "execute_dynamic_sql" and "Lỗi truy vấn SQL" in str(res):
                            print(f"🔄 AI V2 đang tự sửa SQL lần {attempts + 1}...")
                            messages.append({
                                "tool_call_id": tool_call.id,
                                "role": "tool",
                                "name": fn_name,
                                "content": f"LỖI SQL: {res}. Hãy xem lại Schema và viết lại câu lệnh chuẩn."
                            })
                            attempts += 1
                            break # Ngắt vòng lặp hiện tại để quay lại while và yêu cầu AI suy luận lại

                        messages.append({
                            "tool_call_id": tool_call.id,
                            "role": "tool",
                            "name": fn_name,
                            "content": json.dumps(res, ensure_ascii=False) if isinstance(res, (dict, list)) else str(res)
                        })
                else:
                    final_resp = self.client.chat.completions.create(
                        model=self.chat_model, 
                        messages=messages
                    )
                    return final_resp.choices[0].message.content
                continue

            except Exception as e:
                print(f"🔥 Lỗi nghiêm trọng tại AI V2 Logic: {e}")
                return f"Hệ thống đang gặp sự cố: {str(e)}"

    def _get_tools_schema(self):
        return [
            {
                "type": "function",
                "function": {
                    "name": "get_grades",
                    "description": "Lấy điểm. KHÔNG dùng để tra cứu môn nợ hay môn chưa học.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "nam_hoc": {"type": "string"},
                            "hoc_ky": {"type": "string"}
                        }
                    }
                }
            },
            {
                "type": "function",
                "function": {
                    "name": "execute_dynamic_sql",
                    "description": "BẮT BUỘC dùng để tra cứu môn nợ, môn chưa học. PHẢI sử dụng mẫu SQL được gợi ý trong hệ thống.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "sql_query": {"type": "string", "description": "Câu lệnh SQL chuẩn."}
                        },
                        "required": ["sql_query"]
                    }
                }
            }
        ]