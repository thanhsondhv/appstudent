# services/ai_service.py
# import google.generativeai as genai

# # Cấu hình API Key (đã có của bạn)
# genai.configure(api_key="AIzaSyDht1KUzyvngU0r7gXRf_QuWE5KwkcZ0Vs")

# # Hàm tóm tắt (đang có)
# def summarize_text(text_content: str) -> str:
    # model = genai.GenerativeModel('gemini-pro')
    # response = model.generate_content(f"Tóm tắt nội dung sau một cách súc tích và trình bày bằng gạch đầu dòng: {text_content}")
    # return response.text

# # 🔥 THÊM HÀM NÀY: Để hỗ trợ tính năng @AI hỏi đáp theo bối cảnh
# def chat_with_ai(user_query: str, context_history: str) -> str:
    # model = genai.GenerativeModel('gemini-pro')
    # prompt = f"""
    # Bạn là Trợ lý AI của trường Đại học Vinh.
    # Bối cảnh cuộc trò chuyện gần nhất:
    # {context_history}
    
    # Người dùng hỏi: {user_query}
    # """
    # response = model.generate_content(prompt)
    # return response.texts
    
    
# services/ai_service.py
import aiohttp
import pdfplumber
import docx
import io
import google.generativeai as genai
import urllib.parse
from models.chat_model import GroupKnowledge # Import model vừa tạo
from database.database import get_db_conn

# 🔥 ĐIỀN API KEY CỦA GOOGLE GEMINI VÀO ĐÂY
genai.configure(api_key="AIzaSyDUB0ELQXnjIw6mvZB8GoybI4OqWLo6iQ8")


async def summarize_and_store_document(file_url: str, file_name: str, group_id: str, sender_id: str, token: str = None):
    try:
        # 1. Tải và bóc tách nội dung file
        file_bytes = await download_file_bytes(file_url, file_name, token)
        doc_text = extract_text_from_bytes(file_bytes, file_name)
        
        if not doc_text or len(doc_text) < 50:
            return "Nội dung tài liệu quá ngắn hoặc không thể đọc được chữ để phân tích."

        # 2. Gọi Model AI
        model = genai.GenerativeModel(get_best_model_name())
        
        # 🔥 PROMPT NÂNG CẤP: Yêu cầu AI phân loại Role và xuất JSON ẩn
        prompt = f"""
        Bạn là Thư ký học thuật VinhUni. Hãy đọc tài liệu '{file_name}' và thực hiện:
        
        PHẦN 1: NỘI DUNG HIỂN THỊ (Markdown)
        - Tóm tắt ý chính.
        - Liệt kê LỊCH TRÌNH & DEADLINE (Bold mốc thời gian).
        - 3 câu hỏi Quiz ôn tập nhanh.

        PHẦN 2: DỮ LIỆU HỆ THỐNG (JSON)
        Trích xuất các mốc thời gian vào cấu trúc sau và đặt ở cuối cùng:
        JSON_START 
        {{
          "deadlines": [
            {{
              "date": "YYYY-MM-DD", 
              "task": "nội dung công việc", 
              "target_role": "SINHVIEN/CANBO/ALL"
            }}
          ]
        }} 
        JSON_END

        NỘI DUNG TÀI LIỆU:
        {doc_text}
        """
        
        response = model.generate_content(prompt)
        full_res = response.text

        # 3. TÁCH DỮ LIỆU JSON ĐỂ LƯU BẢNG DEADLINE
        clean_summary = full_res
        try:
            # Tìm mảng JSON nằm giữa JSON_START và JSON_END
            json_match = re.search(r"JSON_START\s*(\{.*?\})\s*JSON_END", full_res, re.DOTALL)
            if json_match:
                json_str = json_match.group(1)
                data = json.loads(json_str)
                
                # Lưu vào bảng tbl_Group_Deadlines
                save_extracted_deadlines(group_id, data.get('deadlines', []), file_name)
                
                # Xóa phần JSON thô khỏi tin nhắn hiển thị để sạch sẽ
                clean_summary = re.sub(r"JSON_START.*?JSON_END", "", full_res, flags=re.DOTALL).strip()
        except Exception as e:
            print(f"⚠️ Không thể trích xuất JSON Deadline: {e}")

        # 4. LƯU VÀO KHO TRI THỨC CHUNG (tbl_Group_Knowledge)
        conn = get_db_conn()
        if conn:
            try:
                cursor = conn.cursor()
                query = """
                    INSERT INTO tbl_Group_Knowledge 
                    (GroupId, SenderId, SourceType, FileName, FileUrl, RawContent, SummaryContent, CreatedAt, IsDeleted) 
                    VALUES (?, ?, 'FILE', ?, ?, ?, ?, GETDATE(), 0)
                """
                cursor.execute(query, (group_id, sender_id, file_name, file_url, doc_text, clean_summary))
                conn.commit()
                print(f"✅ [MEMORY] Đã lưu tri thức file '{file_name}' vào SQL Server.")
            except Exception as db_e:
                print(f"❌ Lỗi Insert tbl_Group_Knowledge: {db_e}")
            finally:
                conn.close()

        return clean_summary
    except Exception as e:
        return f"Lỗi xử lý AI: {str(e)}"

def save_extracted_deadlines(group_id: str, deadlines: list, source_file: str):
    """Hàm phụ hỗ trợ lưu danh sách deadline vào SQL Server"""
    if not deadlines:
        return
        
    conn = get_db_conn()
    if conn:
        try:
            cursor = conn.cursor()
            for item in deadlines:
                # Kiểm tra định dạng ngày hợp lệ trước khi insert
                try:
                    query = """
                        INSERT INTO tbl_Group_Deadlines 
                        (GroupId, TargetRole, DeadlineDate, TaskDescription, SourceFile, CreatedAt, IsCompleted)
                        VALUES (?, ?, ?, ?, ?, GETDATE(), 0)
                    """
                    cursor.execute(query, (
                        group_id, 
                        item.get('target_role', 'ALL'), 
                        item.get('date'), 
                        item.get('task'), 
                        source_file
                    ))
                except: continue
            conn.commit()
            print(f"📅 [AUTO-DEADLINE] Đã trích xuất thành công {len(deadlines)} lịch trình.")
        except Exception as e:
            print(f"❌ Lỗi lưu bảng Deadline: {e}")
        finally:
            conn.close()


def get_best_model_name():
    """Bắt Google tự nộp danh sách Model được phép dùng và chọn cái tốt nhất"""
    available_models = []
    
    # 1. Quét toàn bộ model của Google
    for m in genai.list_models():
        if 'generateContent' in m.supported_generation_methods:
            # Tên trả về thường có chữ "models/...", ta cắt bỏ đi cho chuẩn
            clean_name = m.name.replace("models/", "")
            available_models.append(clean_name)
            
    print(f"🌟 [AI_SERVICE] Danh sách Model khả dụng của bạn: {available_models}")

    # 2. Ưu tiên 1: Tìm bản Flash 1.5 (Bản free tốt nhất)
    for name in available_models:
        if '1.5-flash' in name: 
            return name
            
    # 3. Ưu tiên 2: Nếu không có Flash, tìm bản Pro 1.0 hoặc Pro thường (né bản Pro 1.5 vì bị đòi tiền)
    for name in available_models:
        if 'gemini-1.0-pro' in name or name == 'gemini-pro': 
            return name
            
    # 4. Bí quá thì bốc đại cái đầu tiên trong danh sách
    if available_models:
        return available_models[0]
        
    return "gemini-1.5-flash" # Fallback cuối cùng

# 🔥 ĐÃ KHAI BÁO THAM SỐ `token`
async def download_file_bytes(file_url: str, file_name: str, token: str = None) -> bytes:
    headers = {}
    if token:
        headers["Authorization"] = f"Bearer {token}"
        
    # 🎯 Bí quyết ở đây: Tự động chế link tải trực tiếp y hệt code Flutter của Sơn!
    safe_name = urllib.parse.quote(file_name)
    graph_api_url = f"https://graph.microsoft.com/v1.0/me/drive/root:/VinhUni_Chat/{safe_name}:/content"
    
    # Nếu URL truyền vào không phải là Graph API, ta ép nó xài Graph API
    target_url = graph_api_url if "graph.microsoft.com" not in file_url else file_url

    async with aiohttp.ClientSession() as session:
        async with session.get(target_url, headers=headers) as response:
            file_bytes = await response.read()
            
            # In ra log nếu Microsoft trả về lỗi (401, 404, 403...)
            if response.status != 200:
                print(f"⚠️ [GRAPH API LỖI] Status: {response.status} - Chi tiết: {file_bytes[:150]}")
                
            if file_bytes.startswith(b'<!DOCTYPE') or file_bytes.startswith(b'<html') or file_bytes.startswith(b'{'):
                print(f"⚠️ CẢNH BÁO: Bị Microsoft chặn! Nội dung không phải là file vật lý.")
                
            return file_bytes



def extract_text_from_bytes(file_bytes: bytes, file_name: str) -> str:
    text = ""
    file_ext = file_name.lower()
    print(f"📄 [AI_SERVICE] Đang bóc tách chữ từ file: {file_name}")
    
    try:
        if file_ext.endswith('.pdf'):
            with pdfplumber.open(io.BytesIO(file_bytes)) as pdf:
                for page in pdf.pages[:10]: # Đọc tối đa 10 trang
                    extracted = page.extract_text()
                    if extracted: # Chống lỗi trang trống
                        text += extracted + "\n"
                        
        elif file_ext.endswith('.docx'):
            doc = docx.Document(io.BytesIO(file_bytes))
            for para in doc.paragraphs[:50]:
                if para.text:
                    text += para.text + "\n"
                    
        elif file_ext.endswith('.txt'):
            text = file_bytes.decode('utf-8')[:5000]
            
        else:
            print(f"⚠️ [AI_SERVICE] Chưa hỗ trợ đọc đuôi file: {file_ext}")
            
    except Exception as e:
        print(f"❌ Lỗi bóc tách file {file_name}: {e}")
        
    print(f"✅ [AI_SERVICE] Đã bóc được {len(text)} ký tự từ file.")
    return text.strip()

# 🔥 ĐÃ KHAI BÁO THAM SỐ `token` VÀO HÀM TÓM TẮT
# 🔥 CẬP NHẬT 2: Truyền thêm file_name vào hàm download
async def summarize_document(file_url: str, file_name: str, token: str = None) -> str:
    try:
        # Nhét thêm file_name vào để hàm tải file phía trên tự chế link Graph API
        file_bytes = await download_file_bytes(file_url, file_name, token)
        doc_text = extract_text_from_bytes(file_bytes, file_name)
        
        if not doc_text:
            return f"⚠️ Trợ lý AI không thể đọc được chữ trong file `{file_name}`.\n\n(Nguyên nhân: File định dạng chưa hỗ trợ, hoặc là file ảnh scan không chứa văn bản)."
            
        if len(doc_text) < 50:
            return f"⚠️ Nội dung file `{file_name}` quá ngắn, không đủ thông tin để tóm tắt."

        best_model = get_best_model_name()
        print(f"🚀 Đang gọi AI bằng Model: {best_model}")
        
        model = genai.GenerativeModel(best_model)
        prompt = f"""
        Bạn là một trợ lý AI của trường Đại học Vinh (VinhUni). 
        Hãy đọc tài liệu sau và tóm tắt lại những ý chính quan trọng nhất một cách ngắn gọn, súc tích, trình bày bằng gạch đầu dòng dễ hiểu:
        
        NỘI DUNG TÀI LIỆU:
        {doc_text}
        """
        response = model.generate_content(prompt)
        return response.text

    except Exception as e:
        print(f"❌ Lỗi AI Tóm tắt: {e}")
        return "Xin lỗi, Trợ lý AI đang bận hoặc gặp lỗi khi xử lý tài liệu này."

async def chat_with_group_ai(user_query: str, group_id: str, context_history: str) -> str:
    knowledge_context = ""
    
    # 🗄️ TRUY VẤN TRI THỨC CŨ BẰNG PYODBC
    conn = get_db_conn()
    if conn:
        try:
            cursor = conn.cursor()
            # Lấy 3 tài liệu gần nhất của nhóm
            query = "SELECT TOP 3 FileName, SummaryContent FROM tbl_Group_Knowledge WHERE GroupId = ? AND IsDeleted = 0 ORDER BY CreatedAt DESC"
            cursor.execute(query, (group_id,))
            rows = cursor.fetchall()
            
            if rows:
                knowledge_context = "\nTHÔNG TIN TỪ TÀI LIỆU TRONG NHÓM:\n"
                for row in rows:
                    knowledge_context += f"- File {row[0]}: {row[1]}\n"
        finally:
            conn.close()

    try:
        model = genai.GenerativeModel(get_best_model_name())
        prompt = f"""
            Bạn là Trợ lý AI VinhUni. Bạn có khả năng kết nối tri thức từ nhiều tài liệu trong nhóm.
            
            {knowledge_context}
            ---
            LỊCH SỬ CHAT: {context_history}
            ---
            CÂU HỎI: "{user_query}"
            
            YÊU CẦU ĐẶC BIỆT:
            - Nếu người dùng hỏi về sự thay đổi (ví dụ: "Lịch thi mới có gì khác lịch cũ?"), hãy so sánh các file trong 'TRI THỨC NHÓM' để trả lời.
            - Nếu thông tin chưa có trong tài liệu, hãy trả lời dựa trên kiến thức chung của bạn nhưng có ghi chú rõ.
            """
        response = model.generate_content(prompt)
        return response.text
    except Exception as e:
        return "Xin lỗi, mình đang gặp chút trục trặc khi kết nối bộ nhớ nhóm."