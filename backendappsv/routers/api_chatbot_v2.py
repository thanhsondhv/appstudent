import json
import random
import re
from fastapi import APIRouter, Request, HTTPException, BackgroundTasks
from openai import OpenAI

# Import cấu hình và các Service lõi
from config.settings import OPENAI_API_KEY, CHAT_MODEL_FAST
from services.db_service import DBService
from services.chatbot_service import ChatbotService 
from fastapi.responses import JSONResponse
from auth.jwt_handler import get_current_user, Identity
from core.ai_guard import ai_guard, AiGuardError

router = APIRouter(prefix="/api/chatbot-v2")

# Khởi tạo các Core Services
db_service = DBService()
chatbot_service = ChatbotService(db_service) 
client = OpenAI(api_key=OPENAI_API_KEY)

# Danh sách Category chuẩn để lọc RAG
VALID_CATEGORIES = ["Quy chế đào tạo", "Quy chế một cửa", "Học phí & Học bổng", "Công tác sinh viên", "Khác"]

# ==========================================================
# 1. HÀM TRỢ GIÚP (HELPERS)
# ==========================================================
@router.get("/history/{student_id}")
async def get_history(student_id: str):
    # 1. Khởi tạo sạch sẽ ngay từ đầu
    clean_id = student_id.strip().upper().replace("SV", "").replace("CB", "")
    formatted_history = []
    
    try:
        # 2. Gọi DB (Đảm bảo db_service đã được import ở đầu file V2)
        raw_data = db_service.get_chat_history_by_student(clean_id, limit=20)
        
        # 3. Kiểm tra dữ liệu trả về
        if isinstance(raw_data, list):
            formatted_history = [
                {
                    "role": str(m.get("role", "user")), 
                    "content": str(m.get("content", ""))
                } 
                for m in raw_data
            ]
        
        return {"history": formatted_history}

    except Exception as e:
        print(f"❌ Lỗi lấy lịch sử tại V2: {e}")
        return {"history": []}
def get_user_intent(message: str, user_role: str = "STUDENT") -> str:
    """
    Phân loại ý định nâng cao sử dụng kỹ thuật Reasoning (CoT).
    Xử lý được cả tiếng lóng và ngữ cảnh đặc thù VinhUni.
    """
    vinhuni_context = """
    - 'tạch', 'bay màu', 'nợ', 'học lại': Liên quan đến SQL (Điểm số).
    - 'xin giấy', 'chốt đơn', 'mô hình 1 cửa': Liên quan đến RAG (Thủ tục).
    - 'check var', 'soi rank': Liên quan đến SQL (Xếp hạng).
    - 'vị trí', 'phòng nào', 'nhà D', 'nhà A': Liên quan đến NAV (Chỉ dẫn).
    """

    prompt = f"""
    Bạn là bộ não phân tích ý định của Chatbot VinhUni. Vai trò người dùng: {user_role}.
    Ngữ cảnh: {vinhuni_context}

    PHÂN LOẠI CÂU HỎI '{message}' VÀO 1 NHÃN:
    - SQL: Tra cứu điểm, GPA, nợ môn, xếp hạng, thống kê (BGH), tiến độ tốt nghiệp, dự báo điểm.
    - RAG: Quy định, chính sách, học bổng, hướng dẫn thủ tục hành chính.
    - NAV: Thông tin liên hệ, vị trí phòng ban, sơ đồ trường.
    - CHAT: Chào hỏi, cảm ơn, tán gẫu.

    YÊU CẦU: Chỉ trả về nhãn duy nhất (SQL, RAG, NAV, CHAT). Không giải thích.
    """
    try:
        res = client.chat.completions.create(
            model=CHAT_MODEL_FAST, 
            messages=[{"role": "system", "content": "Bạn là chuyên gia NLP phân loại ý định."},
                      {"role": "user", "content": prompt}],
            temperature=0
        )
        intent = res.choices[0].message.content.strip().upper()
        return "".join(filter(str.isalnum, intent))
    except:
        return "CHAT"

async def generate_student_memory(student_id: str):
    """Phân tích hội thoại và lưu 'Sự thật' vào trí nhớ dài hạn (MemoryChunks)"""
    history = db_service.get_chat_history_by_student(student_id, limit=8)
    if not history: return
    history_text = "\n".join([f"{m['role']}: {m['content']}" for m in history])
    
    prompt = f"Tóm tắt 2 dòng về: Môn học SV đang lo, mục tiêu điểm số và khó khăn hiện tại từ hội thoại sau:\n{history_text}"
    try:
        res = client.chat.completions.create(model=CHAT_MODEL_FAST, messages=[{"role": "user", "content": prompt}], temperature=0)
        summary = res.choices[0].message.content.strip()
        db_service.update_student_memory(student_id, summary)
    except: pass

# ==========================================================
# 2. API CHÍNH (LOGIC V3 - ADVISOR)
# ==========================================================

@router.post("/chat")
async def chat(
    request: Request,
    chat_req: dict,
    background_tasks: BackgroundTasks,
    me: Identity = Depends(get_current_user),
):
    user_msg = chat_req.get("message", "").strip()

    # ⚠️ SỬA LỖ HỔNG (18/08/2026) — giống hệt trường hợp ở api_chatbot_v3.py:
    # mã sinh viên trước đây lấy từ dữ liệu máy khách gửi lên, cho phép đọc dữ
    # liệu học tập của người khác. Nay lấy từ token đã xác thực.
    raw_sid = me.user_code
    incoming_session_id = chat_req.get("sessionId")

    try:
        guard_ctx = ai_guard.check_request(
            user_code=me.user_code, role=me.role, message=user_msg
        )
    except AiGuardError as exc:
        return JSONResponse(status_code=exc.http_status, content=exc.as_response())
    user_msg = guard_ctx.clean_message
    
    # 1. Lấy ngữ cảnh Chat chuyên biệt (Vai trò & Profile)
    user_context = db_service.get_chat_user_context(raw_sid)
    user_role = user_context['role'] # 'canbo', 'sinhvien', 'lanhdao', 'covan'...
    full_name = user_context['full_name']
    
    # ID định danh sạch để truy vấn DB (Dùng chung cho cả CB và SV)
    clean_id_num = str(raw_sid).strip().upper().replace("SV", "").replace("CB", "")
    
    # 2. Quản lý Session & Dữ liệu lịch sử
    session_id = int(incoming_session_id) if incoming_session_id and str(incoming_session_id).isdigit() else db_service.create_session(clean_id_num)
    
    # Load các dữ liệu nền
    stats = db_service.get_student_academic_stats(clean_id_num) or {}
    history = db_service.get_chat_history_by_student(clean_id_num, limit=6)
    memory = db_service.get_student_memory(clean_id_num) or "Chưa có dữ liệu trước đó."
    
    # 3. Xử lý câu chào INITIAL_GREETING (Cá nhân hóa sâu)
    if user_msg.upper() == "INITIAL_GREETING":
        if user_role in ['canbo', 'lanhdao', 'troly']:
            reply = f"Kính chào Thầy/Cô {full_name}! 👋 Mình là Trợ lý AI VinhUni. Thầy/Cô cần hỗ trợ tra cứu văn bản hay lịch công tác hôm nay không ạ?"
            suggestions = ["Văn bản đi/đến mới", "Quy trình ký số", "Lịch họp tuần này"]
        elif user_role == 'covan':
            reply = f"Chào Thầy/Cô {full_name}! 👋 Mình hỗ trợ Thầy/Cô theo dõi tiến độ học tập và nợ môn của lớp cố vấn."
            suggestions = ["SV nợ môn nhiều", "Cảnh báo học vụ lớp", "Danh sách lớp"]
        else:
            reply = f"Chào {full_name}! 👋 Mình là Cố vấn AI VinhUni. {memory if 'Chưa' not in memory else 'Mình đã sẵn sàng hỗ trợ bạn tra cứu điểm và quy chế.'}"
            suggestions = ["Tiến độ tốt nghiệp", "Môn nào dễ kéo GPA?", "Điều kiện học bổng"]
        
        return {"mainReply": reply, "suggestions": suggestions, "sessionId": session_id}

    db_service.save_message(session_id, "user", user_msg)
    
    # Phân loại ý định
    intent = get_user_intent(user_msg, user_role=user_role)
    card_type, card_data, citations, suggestions, reply = None, None, [], [], ""

    # --- TRƯỜNG HỢP SQL (TRA CỨU DỮ LIỆU SỐ) ---
    if intent == "SQL":
        db_result = chatbot_service.ask(user_msg, clean_id_num, user_context.get('program_id'), stats.get("gpa"))
        raw_data = db_result.get("data", "Không tìm thấy dữ liệu.")
        
        if user_role == 'sinhvien':
            card_type = "ACADEMIC"
            card_data = {"gpa": stats.get("gpa"), "rank": stats.get("rank", "N/A")}

        data_json = json.dumps(raw_data, ensure_ascii=False, default=str)
        system_prompt = f"Bạn là Trợ lý số VinhUni. Đối tượng: {user_role}. Dữ liệu: {data_json}. Hãy tư vấn dựa trên vai trò này. Định dạng: [Trả lời] --- [Gợi ý 1]|[Gợi ý 2]|[Gợi ý 3]"
        res = client.chat.completions.create(model=CHAT_MODEL_FAST, messages=[{"role": "system", "content": system_prompt}] + history + [{"role": "user", "content": user_msg}], temperature=0.3)
        reply_full = res.choices[0].message.content

    # --- TRƯỜNG HỢP RAG (TRA CỨU TRI THỨC) ---
    elif intent == "RAG":
        cat_prompt = f"Phân loại vào 1 nhóm: {VALID_CATEGORIES}. Câu hỏi: '{user_msg}'. Trả về tên nhóm."
        cat_res = client.chat.completions.create(model=CHAT_MODEL_FAST, messages=[{"role": "user", "content": cat_prompt}], temperature=0)
        detected_cat = cat_res.choices[0].message.content.strip().replace("**", "")

        # 🔥 SỬA: Luôn dùng target_role để hàm DB tự xử lý Hierarchy
        rag_res = db_service.tool_search_documents(user_msg, chatbot_service.embedding, detected_cat, target_role=user_role)
        
        if not rag_res or rag_res == "[]":
            rag_res = db_service.tool_search_documents(user_msg, chatbot_service.embedding, None, target_role=user_role)

        if not rag_res or rag_res == "[]":
            # 🔥 SỬA: Báo lỗi theo vai trò
            if user_role in ['canbo', 'lanhdao']:
                reply_full = "Kính thưa Thầy/Cô, hiện tại kho tri thức chưa có dữ liệu cụ thể về vấn đề này. Thầy/Cô vui lòng liên hệ Văn phòng Trường ạ. --- Lịch công tác|SĐT hỗ trợ|Vị trí phòng ban"
            else:
                reply_full = "Rất tiếc, mình chưa tìm thấy quy định này trong sổ tay sinh viên. Bạn hãy liên hệ Bộ phận Một cửa nhé. --- Thủ tục Một cửa|Xem điểm GPA|Học bổng"
        else:
            chunks = json.loads(rag_res)
            citations = [{"doc": c['doc'], "source": c['category']} for c in chunks[:2]]
            
            persona = "Chuyên gia quy trình Cán bộ" if user_role in ['canbo', 'lanhdao'] else "Chuyên gia Quy chế Sinh viên"
            system_prompt = f"Bạn là {persona}. Dữ liệu: {rag_res}. Trả lời + 3 gợi ý. Định dạng: [Trả lời] --- [Gợi ý 1]|[Gợi ý 2]|[Gợi ý 3]"
            res = client.chat.completions.create(model=CHAT_MODEL_FAST, messages=[{"role": "system", "content": system_prompt}] + history + [{"role": "user", "content": user_msg}], temperature=0.2)
            reply_full = res.choices[0].message.content

    # --- TRƯỜNG HỢP NAV & CHAT ---
    else:
        persona = "Trợ lý Cán bộ" if user_role in ['canbo', 'lanhdao'] else "Cố vấn Sinh viên"
        system_prompt = f"Bạn là {persona} VinhUni. Trả lời ngắn gọn. --- [Gợi ý 1]|[Gợi ý 2]|[Gợi ý 3]"
        res = client.chat.completions.create(model=CHAT_MODEL_FAST, messages=[{"role": "system", "content": system_prompt}, {"role": "user", "content": user_msg}])
        reply_full = res.choices[0].message.content

    # 4. Tách phản hồi và gợi ý
    if "---" in reply_full:
        reply, sug_part = reply_full.split("---", 1)
        suggestions = [s.strip() for s in sug_part.split("|")]
    else:
        reply = reply_full
        # 🔥 SỬA: Gợi ý mặc định theo vai trò
        suggestions = ["Lịch họp tuần", "Quy trình ký số"] if user_role in ['canbo', 'lanhdao'] else ["Xem điểm GPA", "Thủ tục Một cửa"]

    # 5. Lưu phản hồi & Task ngầm
    db_service.save_message(session_id, "assistant", reply.strip())
    background_tasks.add_task(generate_student_memory, clean_id_num)
    
    return {
        "mainReply": reply.strip(),
        "suggestions": [s for s in suggestions if s][:3],
        "cardType": card_type, "cardData": card_data, 
        "citations": citations, "sessionId": session_id,
        "role": user_role 
    }