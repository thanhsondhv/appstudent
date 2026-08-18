import os
import json
from openai import OpenAI
from langchain_text_splitters import RecursiveCharacterTextSplitter

# Đọc cấu hình từ appsettings.json ở thư mục gốc
config_path = os.path.join(os.getcwd(), 'appsettings.json')
with open(config_path, 'r', encoding='utf-8') as f:
    CONFIG = json.load(f)

# Lấy các thông số của OpenAI
OPENAI_API_KEY = CONFIG['OpenAI']['ApiKey']
EMBED_MODEL = CONFIG['OpenAI']['EmbeddingModel']
CHAT_MODEL = CONFIG['OpenAI']['ChatModel']

# Lấy cấu hình cắt văn bản (Chunking)
CHUNK_SIZE = CONFIG['RAGConfig']['ChunkSize']
CHUNK_OVERLAP = CONFIG['RAGConfig']['ChunkOverlap']

# Khởi tạo OpenAI Client
client = OpenAI(api_key=OPENAI_API_KEY)

class AIService:
    @staticmethod
    def split_text(text: str):
        """Cắt văn bản dựa trên cấu hình lấy từ JSON"""
        splitter = RecursiveCharacterTextSplitter(
            chunk_size=CHUNK_SIZE, 
            chunk_overlap=CHUNK_OVERLAP,
            separators=["\n\n", "\n", ".", " ", ""]
        )
        return splitter.split_text(text)

    @staticmethod
    def get_embedding(text: str):
        """Tạo Vector bằng model định nghĩa trong JSON"""
        try:
            response = client.embeddings.create(
                input=text,
                model=EMBED_MODEL
            )
            return response.data[0].embedding
        except Exception as e:
            print(f"❌ Lỗi OpenAI Embedding: {e}")
            raise e

    @staticmethod
    def get_answer(question: str, context: str):
        """Gửi Prompt cho ChatGPT"""
        try:
            prompt = f"""
            Bạn là trợ lý ảo AI của Đại học Vinh. 
            Dựa vào tài liệu quy chế dưới đây, hãy trả lời câu hỏi của sinh viên.
            Nếu trong tài liệu không có thông tin, hãy khuyên sinh viên liên hệ phòng Đào tạo.

            Tài liệu: {context}
            ---
            Câu hỏi: {question}
            """
            
            response = client.chat.completions.create(
                model=CHAT_MODEL,
                messages=[
                    {"role": "system", "content": "Bạn là trợ lý ảo AI chính thức của Đại học Vinh."},
                    {"role": "user", "content": prompt}
                ],
                temperature=0.3
            )
            return response.choices[0].message.content
        except Exception as e:
            print(f"❌ Lỗi OpenAI Chat: {e}")
            return "Xin lỗi, hiện tại hệ thống AI đang bảo trì. Bạn vui lòng thử lại sau nhé."