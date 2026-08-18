from fastapi import APIRouter, Request, HTTPException
from .models import ChatRequest, ChatResponse
from .services.ai_service import AIService
from .services.db_service import DBService
from datetime import datetime
import os
import random

router = APIRouter(prefix="/api/chatbot")
ai_service = AIService()
db_service = DBService()

# KHO GỢI Ý DỰ PHÒNG
master_pool = [
    "Môn nào chưa học trong khung?", 
    "Tính điểm trung bình tích lũy (GPA)", 
    "Lịch thi sắp tới thế nào?",
    "Còn nợ môn nào không?",
    "Quy chế xét học bổng",
    "Thủ tục rút hồ sơ gốc"
]

@router.post("/chat", response_model=ChatResponse)
async def chat(request: Request, chat_req: ChatRequest):
    # 1. XỬ LÝ MÃ SINH VIÊN
    raw_sid = chat_req.studentId or request.session.get("user_id")
    if not raw_sid:
        raise HTTPException(status_code=401, detail="Vui lòng đăng nhập")
    
    # 🔥 FIX LỖI: Định nghĩa student_id_num bằng cách làm sạch mã SV
    student_id_num = str(raw_sid).strip().upper().replace("SV", "")
    
    # 2. LẤY THÔNG TIN ĐỊNH DANH
    user_info = db_service.get_user_profile(student_id_num)

    # Kiểm tra an toàn: Nếu tìm thấy Profile trong DB
    if user_info:
        student_name = chat_req.fullName if chat_req.fullName else user_info.get('full_name', "sinh viên")
        program_code = user_info.get('program_code', "N/A")
        program_id = user_info.get('program_id') or 2201
    else:
        student_name = chat_req.fullName if chat_req.fullName else "sinh viên"
        program_code = "N/A"
        program_id = 2201

    # 3. LẤY THỐNG KÊ HỌC TẬP THỰC TẾ (GPA 2.73, Tín chỉ 142)
    # Gọi hàm mới trong db_service.py của bạn
    stats = db_service.get_student_academic_stats(student_id_num)
    
    # 4. SIÊU SCHEMA CHI TIẾT (SQL + RAG)
   # Trong main_chatbot.py
    db_schema = f"""
    ### 1. DỮ LIỆU ĐÀO TẠO (Dùng execute_dynamic_sql):
    - [tbl_HocPhan], [DiemHocPhan], [viewLichThiSinhVien].

    ### 2. TRA CỨU QUY CHẾ & THỦ TỤC (Dùng search_regulations - SEMANTIC SEARCH):
    - Bảng [DocumentChunks]: Lưu quy chế học vụ, học bổng, rèn luyện.
    - LƯU Ý: Với các câu hỏi như "Điều kiện học bổng", "Thủ tục rút hồ sơ", "Cách tính điểm rèn luyện", 
      hãy sử dụng công cụ 'search_regulations' để tìm nội dung thay vì viết lệnh SQL.
    """

    # Mapping Tools
    tools_mapping = {
        "get_grades": lambda nam_hoc="ALL", hoc_ky="ALL": db_service.tool_get_full_grades(student_id_num, nam_hoc, hoc_ky),
        "execute_dynamic_sql": lambda sql_query: db_service.tool_execute_dynamic_sql(student_id_num, sql_query),
        # Truyền thêm self.ai_service để hàm search có thể gọi get_embedding
        "search_regulations": lambda query: db_service.tool_search_documents(query, ai_service_instance=ai_service) 
    }

    # 5. BỘ QUY TẮC TƯ DUY NÂNG CAO
    ai_logic = f"""
    - TÍN CHỈ/GPA: LUÔN lấy SoTinChi từ [tbl_HocPhan].
    - MÔN NỢ: LEFT JOIN Khung với Điểm, lọc d.Diem IS NULL.
    - TRA CỨU QUY CHẾ: Nếu hỏi về thủ tục, quy định, hãy sử dụng thông tin từ bảng [DocumentChunks].
    - TRÌNH BÀY: TUYỆT ĐỐI KHÔNG hiện mã LaTeX, KHÔNG hiện câu SQL. 
    - Nếu có bảng điểm, hãy dùng bảng Markdown sạch sẽ.
    """

    system_instruction = f"""
    {db_schema}
    {ai_logic}
    - Mã SV: {student_id_num} | ID Khung: {program_id} | Hôm nay: {datetime.now().strftime('%d/%m/%Y')}
    """

    if stats:
        system_instruction += f"\n- Dữ liệu thực tế: GPA={stats['gpa']}, Tín chỉ={stats['total_credits']}, Đã xong {stats['passed_courses']}/{stats['total_courses']} môn."

    # 6. TỔNG HỢP PROMPT
    system_prompt = (
        f"Bạn là VinhUni AI Advisor - Chuyên gia SQL và Quy chế học vụ.\n"
        f"Đối tượng hỗ trợ: {student_name} ({student_id_num}), ngành {program_code}.\n"
        f"{system_instruction}\n"
        f"Hãy trả lời thân thiện, cá nhân hóa bằng cách gọi tên {student_name}.\n\n"
        "BẮT BUỘC: Đề xuất 2-3 câu hỏi tiếp theo ở dòng cuối: [GỢI Ý: Câu 1 | Câu 2 | Câu 3]"
    )

    # 7. MAPPING TOOLS
    tools_mapping = {
        "get_grades": lambda nam_hoc="ALL", hoc_ky="ALL": db_service.tool_get_full_grades(student_id_num, nam_hoc, hoc_ky),
        "execute_dynamic_sql": lambda sql_query: db_service.tool_execute_dynamic_sql(student_id_num, sql_query),
        # Giả định bạn dùng RAG qua ai_service hoặc db_service
    }

    # 8. QUẢN LÝ PHIÊN CHAT
    user_msg = chat_req.message
    is_initial = user_msg == "INITIAL_GREETING"
    session_id = chat_req.sessionId if chat_req.sessionId and chat_req.sessionId != 0 else db_service.create_session(student_id_num)

    # 9. XỬ LÝ TƯƠNG TÁC
    if is_initial:
        gpa_text = f"GPA hiện tại của bạn là **{stats['gpa']}** với **{stats['total_credits']}** tín chỉ tích lũy." if stats else ""
        reply = f"Xin chào {student_name}! 👋\n\n{gpa_text}\nBạn đã hoàn thành **{stats['passed_courses']}/{stats['total_courses']}** môn học trong khung chương trình rồi nhen. Mình có thể giúp gì thêm cho bạn?"   
        dynamic_suggestions = random.sample(master_pool, 3)
        
        return {
            "mainReply": reply,
            "suggestions": dynamic_suggestions,
            "sessionId": session_id
        }
    
    # Lưu tin nhắn người dùng
    db_service.save_message(session_id, "user", user_msg)
    
    # 10. GỌI AI XỬ LÝ
    reply = ai_service.chat_with_tools(system_prompt, user_msg, tools_mapping)

    # 11. BÓC TÁCH GỢI Ý TỪ AI
    dynamic_suggestions = []
    if "[GỢI Ý:" in reply:
        try:
            parts = reply.split("[GỢI Ý:")
            reply = parts[0].strip()
            sugg_str = parts[1].replace("]", "").strip()
            dynamic_suggestions = [s.strip() for s in sugg_str.split("|") if s.strip()]
        except:
            pass
            
    if not dynamic_suggestions:
        dynamic_suggestions = random.sample(master_pool, 3)

    # 12. LƯU LỊCH SỬ AI & TRẢ VỀ
    db_service.save_message(session_id, "assistant", reply)

    return {
        "mainReply": reply,
        "suggestions": dynamic_suggestions[:3],
        "sessionId": session_id
    }