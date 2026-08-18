import json
import re
from fastapi import APIRouter, Request, BackgroundTasks, HTTPException, Depends
from openai import OpenAI
from config.settings import OPENAI_API_KEY, CHAT_MODEL_FAST
from services.db_service import DBService
from services.chatbot_service import ChatbotService
from services.document_service import DocumentService
from datetime import datetime
from fastapi.responses import JSONResponse
from auth.jwt_handler import get_current_user, Identity
from core.ai_guard import ai_guard, AiGuardError

router = APIRouter(prefix="/api/chatbot-v3")

# Khởi tạo các dịch vụ lõi
db_service = DBService()
chatbot_service = ChatbotService(db_service)
client = OpenAI(api_key=OPENAI_API_KEY)
doc_service = DocumentService()

# --- [V3 LOGIC: GỢI Ý ĐỘNG THEO NGỮ CẢNH AI] ---
def get_v3_suggestions(user_role: str, intent: str, current_reply: str = None, history: list = None, programs: list = None) -> list:
    """
    Tạo gợi ý thông minh đa tầng:
    1. Chọn ngành (Cho SV học song bằng)
    2. Menu chính (Phân loại theo Role)
    3. Menu phụ & Tư vấn động (Quét từ Database Knowledge/Chunks)
    """
    u_role = user_role.lower().strip()
    
    # --- PHẦN 1: XỬ LÝ CHỌN NGÀNH ---
    if intent == "SELECT_PROGRAM" and programs:
        return [p['name'] for p in programs]

    # Lấy lịch sử để tránh gợi ý lại
    exclude_texts = [h.get('content', '') for h in (history or [])[-3:]]
    if current_reply: 
        exclude_texts.append(current_reply)

    final_sugs = []

    # A. CẤP ĐỘ GỐC (Menu chính)
    if intent == "MENU_CHINH":
        if u_role != "sinhvien":
            return ["📁 Thủ tục hành chính", "🎓 Giảng dạy - Nghiên cứu"]
        return ["📁 Thủ tục hành chính", "📊 Tình hình học tập"]

    # B. CẤP ĐỘ MENU PHỤ
    elif intent == "THU_TUC_MENU":
        final_sugs = db_service.get_smart_db_suggestions(u_role, "THU_TUC", exclude_texts, limit=3)
    
    elif intent == "HOC_TAP_MENU":
        final_sugs = db_service.get_smart_db_suggestions(u_role, "HOC_TAP", exclude_texts, limit=3)
        
    elif intent == "DAY_NCKH_MENU":
        # Gợi ý chuyên biệt cho Cán bộ (Dạy - NCKH)
        final_sugs = db_service.get_smart_db_suggestions(u_role, "NCKH", exclude_texts, limit=3)
    
    else:
        # Tư vấn tự do
        final_sugs = db_service.get_smart_db_suggestions(u_role, None, exclude_texts, limit=3)

    # Thêm nút quay lại menu chính
    if intent != "MENU_CHINH" and "🏠 Menu chính" not in final_sugs:
        final_sugs.append("🏠 Menu chính")

    return list(dict.fromkeys(final_sugs))[:4]

# --- [V3 LOGIC: PHÂN LOẠI Ý ĐỊNH] ---
def get_v3_user_intent(message: str, user_role: str) -> str:
    try:
        active_intents = db_service.get_all_active_intents() 
        vinhuni_context = f"Chuyên gia VinhUni. Danh sách đơn: {active_intents}. SQL (Cá nhân), RAG (Quy chế), CHAT (Chào hỏi)."
        
        prompt = f"""
        Phân loại câu hỏi: '{message}' (Vai trò: {user_role}).
        Yêu cầu:
        - Nếu hỏi đơn từ/giấy tờ, chọn trong: {active_intents}.
        - Nếu hỏi điểm/lịch/tốt nghiệp, chọn SQL.
        - Nếu hỏi quy định, chọn RAG.
        - Trả về duy nhất 1 từ viết hoa.
        """

        res = client.chat.completions.create(
            model=CHAT_MODEL_FAST,
            messages=[{"role": "system", "content": vinhuni_context}, {"role": "user", "content": prompt}],
            temperature=0
        )
        return "".join(filter(str.isalnum, res.choices[0].message.content.strip().upper()))
    except:
        return "CHAT"

# --- [V3 API: CHAT ENTRYPOINT] ---
@router.post("/chat")
async def chat_v3(
    request: Request,
    chat_req: dict,
    me: Identity = Depends(get_current_user),
):
    user_msg = chat_req.get("message", "").strip()

    # ⚠️ SỬA LỖ HỔNG NGHIÊM TRỌNG (18/08/2026)
    # Bản cũ:  raw_sid = chat_req.get("studentId") or request.session.get("user_id")
    # Mã sinh viên được lấy từ chính dữ liệu máy khách gửi lên, rồi dùng để tra
    # bảng điểm và học phí. Bất kỳ ai cũng chỉ cần đổi một con số trong yêu cầu
    # là đọc được toàn bộ dữ liệu học tập của người khác.
    # Nay danh tính suy ra TỪ TOKEN đã xác thực, máy khách không can thiệp được.
    raw_sid = me.user_code

    # Kiểm tra an toàn đầu vào: tần suất, độ dài, dấu hiệu chèn lệnh
    try:
        guard_ctx = ai_guard.check_request(
            user_code=me.user_code,
            role=me.role,
            message=user_msg,
        )
    except AiGuardError as exc:
        return JSONResponse(status_code=exc.http_status, content=exc.as_response())
    user_msg = guard_ctx.clean_message
    
    # 1. KHỞI TẠO NGỮ CẢNH
    user_context = db_service.get_chat_user_context(raw_sid)
    user_role = user_context['role']
    full_name = user_context['full_name']
    all_programs = user_context.get('programs', []) 
    clean_id = str(raw_sid).strip().upper().replace("SV", "").replace("CB", "")

    # 🎯 XỬ LÝ XƯNG HÔ ĐỘNG
    xung_ho = "bạn" if user_role == "sinhvien" else "Thầy/Cô"

    # --- LOGIC NHẬN DIỆN NGÀNH ---
    selected_program_id = chat_req.get("selected_program_id")
    if not selected_program_id and all_programs:
        for p in all_programs:
            if p['name'].lower() == user_msg.lower():
                selected_program_id = p['id']
                break
    
    current_program_id = selected_program_id if selected_program_id else (all_programs[0]['id'] if all_programs else (None if user_role == "canbo" else 2201))

    # 2. DỮ LIỆU NỀN
    history = db_service.get_chat_history_by_student(clean_id, limit=5)
    session_id = db_service.create_session(clean_id)
    stats = db_service.get_student_academic_stats(clean_id) if user_role == "sinhvien" else {}

    # =======================================================
    # 3. ĐIỀU HƯỚNG MENU (CHẶN LUỒNG SỚM - EARLY RETURN)
    # =======================================================

    # A. RESET VỀ MENU CHÍNH
    if user_msg.upper() in ["INITIAL_GREETING", "MENU CHÍNH"] or "menu chính" in user_msg.lower():
        reply = f"Chào {xung_ho} {full_name}! 👋 Mình là Trợ lý VinhUni. Hôm nay {xung_ho} cần hỗ trợ gì? Bạn có thể nhấn vào menu chủ để gợi ý hoặc nhập câu hỏi"
        sugs = get_v3_suggestions(user_role, "MENU_CHINH")
        return {"mainReply": reply, "suggestions": sugs, "role": user_role, "ui_type": "BANNER_MENU", "sessionId": session_id}

    # B. MENU CẤP 2: THỦ TỤC HÀNH CHÍNH
    if "thủ tục hành chính" in user_msg.lower():
        reply = f"Mời {xung_ho} chọn thủ tục cần hỗ trợ hoặc nhập câu hỏi chi tiết:"
        sugs = get_v3_suggestions(user_role, "THU_TUC_MENU")
        return {"mainReply": reply, "suggestions": sugs, "role": user_role, "ui_type": "TEXT"}

    # C. MENU CẤP 2: TÌNH HÌNH HỌC TẬP (Sinh viên)
    if "tình hình học tập" in user_msg.lower() and user_role == "sinhvien":
        # Xử lý song bằng trước khi hiện menu học tập
        if len(all_programs) > 1 and not selected_program_id:
            reply = f"Chào {full_name}! Bạn đang học song bằng, hãy chọn ngành muốn xem thông tin:"
            sugs = get_v3_suggestions(user_role, "SELECT_PROGRAM", programs=all_programs)
            return {"mainReply": reply, "suggestions": sugs, "role": user_role, "ui_type": "SELECT_PROGRAM", "programs": all_programs}
        
        reply = "Mời bạn chọn thông tin học tập muốn tra cứu:"
        sugs = get_v3_suggestions(user_role, "HOC_TAP_MENU")
        return {"mainReply": reply, "suggestions": sugs, "role": user_role, "ui_type": "TEXT"}

    # D. MENU CẤP 2: GIẢNG DẠY - NGHIÊN CỨU (Cán bộ)
    if any(w in user_msg.lower() for w in ["giảng dạy", "nghiên cứu", "dạy - nckh"]):
        reply = "Mời Thầy/Cô chọn tác vụ chuyên môn hoặc nhập câu hỏi:"
        sugs = get_v3_suggestions(user_role, "DAY_NCKH_MENU")
        return {"mainReply": reply, "suggestions": sugs, "role": user_role, "ui_type": "TEXT"}

    # =======================================================
    # 4. XỬ LÝ TRA CỨU SÂU & AI (KHI KHÔNG PHẢI MENU)
    # =======================================================
    db_service.save_message(session_id, "user", user_msg)
    raw_intent = get_v3_user_intent(user_msg, user_role)
    
    # --- LUỒNG TẠO ĐƠN ---
    template_info = db_service.get_template_by_intent(raw_intent)
    action_keywords = ["tạo", "soạn", "viết", "làm", "tải", "mẫu", "đơn"]
    if template_info and any(w in user_msg.lower() for w in action_keywords):
        data_to_fill = {
            "FULL_NAME": full_name, "STUDENT_ID": clean_id,
            "CLASS": stats.get("class_name", "N/A"), "DAY": datetime.now().day, "MONTH": datetime.now().month, "YEAR": datetime.now().year
        }
        file_res = doc_service.generate_dynamic_document(template_info['TemplateName'], data_to_fill)
        if file_res:
            reply = f"✅ Mình đã soạn xong **{template_info['DisplayName']}** cho {xung_ho}."
            return {"mainReply": reply, "ui_type": "DOWNLOAD_CARD", "file_info": {"file_name": file_res["name"], "file_url": file_res["url"]}, "suggestions": ["🏠 Menu chính"]}
    # --- B. TRA CỨU THỰC TẾ (FUSION) ---
    db_data = "Chưa có dữ liệu cụ thể."
    audit_info = None

    # 1. ƯU TIÊN TUYỆT ĐỐI: Kiểm tra Tiến độ tốt nghiệp (Dùng hàm Python chuyên dụng)
    if any(w in user_msg.lower() for w in ["tốt nghiệp", "nợ môn", "ra trường", "tín chỉ"]):
        audit_info = db_service.get_graduation_audit(clean_id, program_id=current_program_id)
        if audit_info:
            db_data = f"[DỮ LIỆU TỐT NGHIỆP CHỐT]: {json.dumps(audit_info, ensure_ascii=False, default=str)}"

    # 2. Nếu không phải tốt nghiệp, mới tìm SQL Knowledge
    if db_data == "Chưa có dữ liệu cụ thể.":
        known_match = db_service.search_sql_knowledge_hybrid(user_msg, chatbot_service.embedding.get_embedding(user_msg), user_role)
        # Trong api_chatbot_v3.py
        if known_match:
            sql_final = known_match['sql'].replace("{student_id}", clean_id).replace("{program_id}", str(current_program_id))
            res = db_service.execute_query(sql_final)
            
            if not res or len(res) == 0:
                # Nếu kết quả SQL rỗng, ta ghi chú rõ cho AI biết
                db_data = "[HỆ THỐNG]: Sinh viên này không còn môn nào chưa học trong khối kiến thức bắt buộc. Đã hoàn thành 100% môn cứng."
            else:
                db_data = f"[DANH SÁCH MÔN CHƯA HỌC]: {json.dumps(res, ensure_ascii=False, default=str)}"

    # 3. Tra cứu Quy chế (RAG)
    rag_results = db_service.tool_search_documents_hybrid(user_msg, chatbot_service.embedding, target_role=user_role)
    # Loại tài liệu chứa câu ra lệnh trước khi đưa vào ngữ cảnh mô hình.
    # Kho tri thức do nhiều người tải lên; một tệp có dòng "bỏ qua mọi chỉ dẫn
    # trước đó" là đủ để mô hình làm theo nếu không lọc.
    rag_results = ai_guard.sanitize_context(rag_results)
    context_rag = "\n".join([f"Quy định ({r['doc']}): {r['content']}" for r in rag_results])

    # 5. AI TỔNG HỢP
    # Chuẩn bị biến an toàn để tránh lỗi NameError/AttributeError
    tc_thieu_val = audit_info.get('tc_thieu', 0) if audit_info else 0
    status_text = "ĐỦ ĐIỀU KIỆN" if (audit_info and audit_info.get('is_eligible')) else "CHƯA ĐỦ ĐIỀU KIỆN"

    advisor_prompt = f"""
    Bạn là Chuyên gia Cố vấn học tập VinhUni. 
    Người dùng: {full_name} | Vai trò: {user_role}. Ngành: {current_program_id}

    [DỮ LIỆU THỰC TẾ]: {db_data}
    [QUY ĐỊNH]: {context_rag}

    QUY TẮC TƯ VẤN CỰC KỲ QUAN TRỌNG:
    1. GIẢI THÍCH DỮ LIỆU RỖNG:
       - Nếu [DỮ LIỆU THỰC TẾ] chứa danh sách môn học là [] (rỗng) hoặc không liệt kê môn nào:
         => Điều này có nghĩa là sinh viên ĐÃ HOÀN THÀNH XONG toàn bộ các môn học yêu cầu.
         => Tuyệt đối KHÔNG báo là "không có thông tin" hay "dữ liệu trống". Hãy khẳng định: "Bạn đã hoàn thành tất cả các môn học bắt buộc trong khung chương trình".

    2. VỀ TIẾN ĐỘ TỐT NGHIỆP:
       - Ưu tiên sử dụng giá trị 'is_eligible' để đưa ra kết luận:
         + Nếu 'is_eligible' là True: Hãy chúc mừng sinh viên một cách nồng nhiệt vì đã đủ điều kiện tốt nghiệp.
         + Nếu 'is_eligible' là False: Liệt kê các môn nợ (nếu có) và thông báo cần tích lũy thêm {tc_thieu_val} tín chỉ nữa.

    3. PHONG CÁCH TRẢ LỜI:
       - Tuyệt đối dựa trên con số thực tế, không tự suy diễn sai lệch.
       - Trình bày bằng Markdown chuyên nghiệp (sử dụng Bold cho các thông số quan trọng, dùng bảng nếu liệt kê nhiều môn).
       - Luôn kết thúc bằng một lời khuyên hoặc lời động viên phù hợp với tình hình học tập.
    """
    
    try:
        res = client.chat.completions.create(model=CHAT_MODEL_FAST, messages=[{"role": "system", "content": advisor_prompt}, {"role": "user", "content": user_msg}])
        reply = res.choices[0].message.content
    except Exception as exc:
        print(f"⚠️ [V3] Lỗi gọi mô hình: {exc}")
        reply = "Hệ thống đang đối chiếu dữ liệu, bạn vui lòng đợi nhé!"

    # Lọc câu trả lời: che khoá bí mật lỡ lọt ra, chặn câu lệnh SQL ghi dữ liệu,
    # nhắc người dùng khi câu trả lời chưa đối chiếu được với văn bản của trường.
    guarded = ai_guard.check_response(guard_ctx, reply, sources=rag_results)
    reply = guarded["mainReply"]

    db_service.save_message(session_id, "assistant", reply.strip())
    print(f"🚀 [V3 FUSION] {clean_id} | SQL: {'Yes' if 'DỮ LIỆU' in db_data else 'No'}")

    return JSONResponse(content={"mainReply": reply.strip(), "suggestions": get_v3_suggestions(user_role, raw_intent, reply, history, all_programs), "role": user_role, "sessionId": session_id, "ui_type": "TEXT"})
    # --- [API LỊCH SỬ CHAT] ---
@router.get("/history/{student_id}")
async def get_history_v3(student_id: str):
    clean_id = student_id.strip().upper().replace("SV", "").replace("CB", "")
    try:
        raw_history = db_service.get_chat_history_by_student(clean_id, limit=20)
        return {"status": "SUCCESS", "history": raw_history}
    except Exception as e:
        return {"status": "ERROR", "history": [], "message": str(e)}