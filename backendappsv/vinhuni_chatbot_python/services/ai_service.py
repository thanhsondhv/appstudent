from openai import OpenAI
from .. import CONFIG
import json

class AIService:
    def __init__(self):
        # Lấy API Key và Model từ file cấu hình appsettings.json
        self.api_key = CONFIG['OpenAI']['ApiKey']
        self.client = OpenAI(api_key=self.api_key)
        self.embed_model = CONFIG['OpenAI'].get('EmbeddingModel', 'text-embedding-3-small')
        self.chat_model = CONFIG['OpenAI'].get('ChatModel', 'gpt-4o-mini')

    def get_embedding(self, text: str):
        """Biến câu hỏi của sinh viên thành Vector để tìm kiếm RAG"""
        if not text:
            return None
        try:
            response = self.client.embeddings.create(
                input=text,
                model=self.embed_model
            )
            return response.data[0].embedding
        except Exception as e:
            print(f"🔥 Lỗi OpenAI Embedding: {e}")
            return None

    def chat_with_tools(self, system_instruction: str, user_message: str, tools_map: dict):
        """Gửi prompt cho OpenAI kèm theo định nghĩa các hàm (Tools)"""
        
        # 1. Định nghĩa "Bản đồ công cụ" cho AI
        tools_schema = [
            {
                "type": "function",
                "function": {
                    "name": "get_grades",
                    "description": "Lấy điểm số theo học kỳ hoặc năm học cụ thể.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "nam_hoc": {"type": "string", "description": "Ví dụ: '2024-2025'. Trả về 'ALL' nếu không nhắc đến."},
                            "hoc_ky": {"type": "string", "description": "Ví dụ: '1', '2'. Trả về 'ALL' nếu không nhắc đến."}
                        },
                        "required": ["nam_hoc", "hoc_ky"]
                    }
                }
            },
            {
                "type": "function",
                "function": {
                    "name": "execute_dynamic_sql",
                    "description": "Sử dụng khi cần truy vấn thông tin nâng cao như: danh sách môn nợ trong khung chương trình, số tín chỉ tích lũy, hoặc so sánh tiến độ học tập với quy chế.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "sql_query": {
                                "type": "string",
                                "description": "Câu lệnh T-SQL SELECT chuẩn xác. Lưu ý nối tbl_HocPhan.InstanceId với DiemHocPhan.IdHocPhan (GUID) và lọc theo {student_id}."
                            }
                        },
                        "required": ["sql_query"]
                    }
                }
            }
        ]

        messages = [
            {"role": "system", "content": system_instruction},
            {"role": "user", "content": user_message}
        ]

        try:
            # 2. Gọi OpenAI lần 1 (Kèm tools)
            response = self.client.chat.completions.create(
                model=self.chat_model,
                messages=messages,
                tools=tools_schema,
                tool_choice="auto",
                temperature=0.3
            )
            
            response_message = response.choices[0].message
            
            # 3. Kiểm tra xem AI có yêu cầu thực thi công cụ nào không
            if response_message.tool_calls:
                messages.append(response_message) 
                
                for tool_call in response_message.tool_calls:
                    function_name = tool_call.function.name
                    # Parse các tham số mà AI tự bóc tách/tạo ra
                    function_args = json.loads(tool_call.function.arguments)
                    
                    print(f"🤖 AI Tool Call: {function_name}({function_args})")
                    
                    if function_name in tools_map:
                        function_to_call = tools_map[function_name]
                        
                        # 4. Thực thi hàm động: Truyền toàn bộ tham số từ function_args
                        # Điều này giúp hàm get_grades nhận được nam_hoc, và execute_dynamic_sql nhận được sql_query
                        function_response = function_to_call(**function_args)
                        
                        # Chuyển kết quả về dạng chuỗi để gửi ngược lại cho AI
                        if isinstance(function_response, (dict, list)):
                            str_response = json.dumps(function_response, ensure_ascii=False)
                        else:
                            str_response = str(function_response)

                        if not str_response:
                            str_response = "Lỗi: Không tìm thấy dữ liệu từ hệ thống."

                        # 5. Gửi kết quả của Tool về lại cho AI
                        messages.append({
                            "tool_call_id": tool_call.id,
                            "role": "tool",
                            "name": function_name,
                            "content": str_response, 
                        })
                
                # 6. Gọi OpenAI lần 2 để nhận câu trả lời cuối cùng bằng ngôn ngữ tự nhiên
                second_response = self.client.chat.completions.create(
                    model=self.chat_model,
                    messages=messages,
                    temperature=0.3
                )
                return second_response.choices[0].message.content
            
            return response_message.content

        except Exception as e:
            print(f"🔥 Lỗi AIService: {e}")
            return "Xin lỗi, mình đang gặp chút trục trặc khi truy cập dữ liệu. Bạn thử lại sau nhé!"