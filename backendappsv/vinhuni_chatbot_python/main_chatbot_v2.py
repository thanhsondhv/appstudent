# routers/api_chatbot_v2.py
from fastapi import APIRouter, Request, HTTPException
import random

# Import từ thư mục services
from services.ai_service_v2 import AIServiceV2 
from database.db_service import DBService # Hoặc services.db_service tùy bạn đang để file này ở đâu
from services.chatbot_service import ChatbotService 

router = APIRouter(prefix="/api/chatbot-v2")

# Khởi tạo các Core Services
ai_service = AIServiceV2()
db_service = DBService()
chatbot_service = ChatbotService(db_service) # Khởi tạo trái tim AI

# Danh mục gợi ý "chuẩn đét" cho sinh viên (Giúp phân biệt rạch ròi Nợ và Chưa học)
master_pool = [
    "Danh sách các môn mình đang NỢ (rớt)?", 
    "Những môn trong khung mình CHƯA HỌC?",
    "Xem bảng điểm các môn đã qua", 
    "Tiến độ học tập của mình đến đâu rồi?",
    "Điều kiện nhận học bổng là gì?"
]

@router.post("/chat", response_model=ChatResponse)
async def chat(request: Request, chat_req: ChatRequest):
    # 1. XỬ LÝ ĐỊNH DANH
    raw_sid = chat_req.studentId or request.session.get("user_id")
    if not raw_sid:
        raise HTTPException(status_code=401, detail="Vui lòng đăng nhập")
    
    student_id_num = str(raw_sid).strip().upper().replace("SV", "")
    
    # 2. LẤY THÔNG TIN NGỮ CẢNH (PROFILE & GPA)
    user_info = db_service.get_user_profile(student_id_num)
    stats = db_service.get_student_academic_stats(student_id_num)
    
    student_name = user_info.get('full_name', "sinh viên") if user_info else "sinh viên"
    program_code = user_info.get('program_code', "N/A") if user_info else "N/A"
    current_gpa = stats.get('gpa', 'N/A') if stats else 'N/A'

    user_msg = chat_req.message
    session_id = chat_req.sessionId or db_service.create_session(student_id_num)

    # 3. XỬ LÝ LỜI CHÀO BAN ĐẦU
    if user_msg == "INITIAL_GREETING":
        reply = f"Xin chào {student_name}! GPA hiện tại của bạn là {current_gpa}. Mình có thể giúp bạn tra cứu nợ môn, môn chưa học hoặc lịch thi."
        return {
            "mainReply": reply, 
            "suggestions": random.sample(master_pool, 3), 
            "sessionId": session_id
        }

    # 4. 🔥 BƯỚC QUAN TRỌNG: GỌI "TRÁI TIM" AI XỬ LÝ DATABASE
    # Thay vì code lại rườm rà, ta ném thẳng cho ChatbotService làm hết mọi việc từ A-Z
    print(f"🚀 [API] Đang chuyển câu hỏi cho ChatbotService xử lý: '{user_msg}'")
    db_result = chatbot_service.ask(user_msg, student_id_num, program_code, current_gpa)

    # 5. DỊCH KẾT QUẢ SANG TIẾNG VIỆT CHO FLUTTER
    # db_result["data"] hiện đang là một mảng JSON [{'Ten': 'Môn A'}]. 
    # Flutter cần Tiếng Việt thân thiện, nên ta nhờ Agent đọc và "phát biểu" lại.
    if "error" in db_result:
        reply = "Xin lỗi, mình gặp chút vấn đề hoặc câu hỏi vi phạm quy tắc hệ thống nên chưa thể tra cứu được."
    else:
        raw_data = db_result["data"]
        
        # Mớm lời cho Agent để biến JSON thành câu nói thân thiện
        system_prompt = f"""
        BẠN LÀ TRỢ LÝ ẢO CỦA ĐẠI HỌC VINH. THÔNG TIN SV: {student_name}.
        Người dùng vừa hỏi: "{user_msg}"
        Dữ liệu hệ thống đã trích xuất được từ Database là: {raw_data}
        
        Nhiệm vụ: Dựa vào dữ liệu trên, hãy viết một câu trả lời tự nhiên, thân thiện để hiển thị trên App điện thoại.
        - Nếu dữ liệu rỗng ([]): Hãy chúc mừng sinh viên (không nợ môn) hoặc thông báo không có dữ liệu cần tìm.
        - Nếu có dữ liệu: Hãy liệt kê dạng gạch đầu dòng gọn gàng, dễ nhìn.
        TUYỆT ĐỐI KHÔNG giải thích về SQL, Database hay kỹ thuật. Không dùng markdown quá phức tạp.
        """
        
        # Lưu log người dùng
        db_service.save_message(session_id, "user", user_msg)
        
        # Sinh câu trả lời (Truyền tool rỗng {} vì ta đã có sẵn dữ liệu Data rồi)
        reply = ai_service.chat_with_v2_logic(system_prompt, user_msg, {}) 
        
        # Lưu log AI
        db_service.save_message(session_id, "assistant", reply)

    return {
        "mainReply": reply,
        "suggestions": random.sample(master_pool, 3),
        "sessionId": session_id
    }