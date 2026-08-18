# core/socket_manager.py
import socketio
import json
from config.database import SessionLocal
from services.chatgroup import MessageService
from models.chat_model import ChatMessage, MessageAction, ChatGroup, User

#from services.ai_service import summarize_document, chat_with_ai
# Gọi đúng 2 hàm: 1 hàm lưu tri thức file, 1 hàm chat có bộ nhớ nhóm
from services.ai_service import summarize_and_store_document, chat_with_group_ai
import asyncio
# 1. Cấu hình Socket.io Server (ASGI mode cho FastAPI/Uvicorn)
sio = socketio.AsyncServer(
    async_mode='asgi',
    cors_allowed_origins='*',  # Cho phép tất cả để tránh lỗi CORS khi test Mobile
    check_static_nt=False      # Hỗ trợ chạy mượt trên Windows
)

# 🔥 CUỐN SỔ TAY LƯU TRỮ AI ĐANG MỞ APP (Online)
connected_users = {} # Lưu dưới dạng: { "sid_abc123": "1679" }

# 2. Xử lý khi có thiết bị kết nối
@sio.event
async def connect(sid, environ):
    print(f"🔗 Thiết bị kết nối: {sid}")

# 3. Xử lý khi thiết bị ngắt kết nối (Tắt App / Ẩn nền)
@sio.event
async def disconnect(sid):
    # Lấy ra và xóa user khỏi sổ tay khi ngắt kết nối
    user_code = connected_users.pop(sid, None)
    print(f"❌ Thiết bị ngắt kết nối: {sid} (User: {user_code})")

# 4. Tham gia vào phòng chat (Group Room)
@sio.event
async def join_room(sid, data):
    # data: {"group_id": "GROUP_ABC", "user_code": "CB001"}
    group_id = data.get("group_id")
    
    # Chuẩn hóa mã (xóa SV/CB) để so sánh cho chuẩn với logic push
    raw_user_code = str(data.get("user_code", "")).strip().upper()
    user_code = raw_user_code.replace('SV', '').replace('CB', '')
    
    if group_id:
        connected_users[sid] = user_code # Ghi vào sổ tay là thằng này đang Online
        await sio.enter_room(sid, group_id)
        print(f"🚪 User {user_code} (sid: {sid}) đã vào phòng: {group_id}")
# 5. Gửi tin nhắn (Hỗ trợ Text, Image, Video, File, Reply + AI Assistant)
@sio.event
async def send_message(sid, data):
    db = SessionLocal()
    try:
        sender_code = str(data.get("sender_code", "")).strip()
        group_id = data.get("group_id")
        content = data.get("content", "").strip()
        msg_type = data.get("message_type", "TEXT")
        file_url = data.get("file_url")
        raw_sender_name = data.get("sender_name")

        # 🔥 Hứng Token của Microsoft từ Flutter gửi lên để AI dùng tải file
        ms_token = data.get("ms_token")

        # 1. Tìm thông tin định danh người gửi
        u = db.query(User).filter(
            (User.UserCode == sender_code) | 
            (User.UserCode == 'CB' + sender_code) | 
            (User.UserCode == 'SV' + sender_code)
        ).first()
        
        sender_name = u.FullName if u else (raw_sender_name if raw_sender_name else "Thành viên")
        sender_role = u.UserRole if u else "Người dùng"
        
        # 2. Lưu tin nhắn vào Database
        new_msg = MessageService.save_new_message(
            db=db, sender_code=sender_code, group_id=group_id, content=content,
            sender_name=sender_name, sender_role=sender_role,
            msg_type=msg_type, file_url=file_url, reply_id=data.get("reply_to_id")
        )

        # 3. Phát tin nhắn gốc cho cả phòng
        await sio.emit("receive_message", {
            "MessageId": new_msg.MessageId,
            "SenderCode": sender_code,
            "SenderName": sender_name,
            "MessageContent": content,
            "SenderAvatar": f"https://mobi.vinhuni.edu.vn/api/get-avatar/?student_id={sender_code}",
            "CreatedAt": str(new_msg.CreatedAt),
            "MessageType": msg_type,
            "FileUrl": file_url
        }, room=group_id)

        # =======================================================
        # 🔥 TÍCH HỢP TRỢ LÝ AI (Tóm tắt file & @AI Chat)
        # =======================================================
        # core/socket_manager.py

        # core/socket_manager.py

        async def run_ai_task():
            db_ai = SessionLocal()
            try:
                ai_reply = ""
                user_msg = content.strip().upper()

                # --- [LỆNH MỚI]: TRUY VẤN DEADLINE TẬP THỂ ---
                if user_msg == "/DEADLINE":
                    from database.database import get_db_conn
                    conn = get_db_conn()
                    if conn:
                        try:
                            cursor = conn.cursor()
                            # Lọc deadline theo GroupId và Role (Sinh viên/Cán bộ)
                            # sender_role được lấy từ thông tin User ở đầu hàm send_message
                            u_role = sender_role.upper() if sender_role else "ALL"
                            
                            query = """
                                SELECT TaskDescription, DeadlineDate, SourceFile 
                                FROM tbl_Group_Deadlines 
                                WHERE GroupId = ? 
                                AND (TargetRole = ? OR TargetRole = 'ALL')
                                AND DeadlineDate >= CAST(GETDATE() AS DATE)
                                ORDER BY DeadlineDate ASC
                            """
                            cursor.execute(query, (group_id, u_role))
                            rows = cursor.fetchall()
                            
                            if rows:
                                role_label = "Cán bộ" if u_role == "CANBO" else "Sinh viên"
                                ai_reply = f"📅 **LỊCH TRÌNH SẮP TỚI ({role_label}):**\n\n"
                                for r in rows:
                                    date_str = r[1].strftime('%d/%m/%Y')
                                    ai_reply += f"🔹 **{date_str}**: {r[0]}\n   *(Nguồn: {r[2]})*\n\n"
                                ai_reply += "--- \n*Gõ @AI để hỏi chi tiết hơn về các tài liệu này.*"
                            else:
                                ai_reply = "✅ Hiện tại không có deadline hoặc lịch trình nào sắp tới cho bạn."
                        finally:
                            conn.close()

                # --- LOGIC CŨ: TÓM TẮT FILE ---
                elif msg_type == "FILE" and file_url:
                    ai_reply = await summarize_and_store_document(
                        file_url=file_url, 
                        file_name=content, 
                        group_id=group_id, 
                        sender_id=sender_code, 
                        token=ms_token
                    )

                # --- LOGIC CŨ: CHAT @AI ---
                elif "@AI" in user_msg:
                    recent_msgs = db_ai.query(ChatMessage).filter(
                        ChatMessage.GroupId == group_id, ChatMessage.IsDeleted == 0
                    ).order_by(ChatMessage.MessageId.desc()).limit(10).all()
                    context = "\n".join([f"[{m.SenderName}]: {m.MessageContent}" for m in reversed(recent_msgs)])
                    
                    ai_reply = await chat_with_group_ai(
                        user_query=content.upper().replace("@AI", "").strip(), 
                        group_id=group_id, 
                        context_history=context
                    )

                # --- PHÁT TIN NHẮN CỦA BOT ---
                if ai_reply:
                    bot_msg = MessageService.save_new_message(
                        db=db_ai, sender_code="BOT_AI_VINHUNI", group_id=group_id, content=ai_reply,
                        sender_name="Trợ lý AI VinhUni", sender_role="BOT",
                        msg_type="TEXT", file_url=None, reply_id=new_msg.MessageId
                    )
                    
                    await sio.emit("receive_message", {
                        "MessageId": bot_msg.MessageId,
                        "SenderCode": "BOT_AI_VINHUNI",
                        "SenderName": "Trợ lý AI VinhUni",
                        "MessageContent": ai_reply,
                        "SenderAvatar": "https://mobi.vinhuni.edu.vn/api/get-avatar/?student_id=BOT_AI_VINHUNI",
                        "CreatedAt": str(bot_msg.CreatedAt),
                        "MessageType": "TEXT",
                        "ReplyToId": new_msg.MessageId,
                        "ReplyToName": sender_name
                    }, room=group_id)

            except Exception as e:
                print(f"❌ [SOCKET AI ERROR]: {e}")
            finally:
                db_ai.close()

        sio.start_background_task(run_ai_task)

    except Exception as e:
        print(f"❌ [SOCKET ERROR] Lỗi tại send_message: {e}")
    finally:
        db.close()
# 5. Gửi tin nhắn (Hỗ trợ Text, Image, Video, File, Reply + Push Notification)
# @sio.event

# async def send_message(sid, data):
    # db = SessionLocal()
    # try:
        # sender_code = str(data.get("sender_code", "")).strip()
        # group_id = data.get("group_id")
        # content = data.get("content", "").strip()
        # raw_sender_name = data.get("sender_name")

        # # 1. Tìm thông tin định danh
        # u = db.query(User).filter(
            # (User.UserCode == sender_code) | 
            # (User.UserCode == 'CB' + sender_code) | 
            # (User.UserCode == 'SV' + sender_code)
        # ).first()
        
        # sender_name = u.FullName if u else (raw_sender_name if raw_sender_name else "Thành viên")
        # sender_role = u.UserRole if u else "Người dùng"
        
        # # 2. GỌI HÀM LƯU TIN NHẮN
        # new_msg = MessageService.save_new_message(
            # db=db,
            # sender_code=sender_code,
            # group_id=group_id,
            # content=content,
            # sender_name=sender_name,
            # sender_role=sender_role,
            # msg_type=data.get("message_type", "TEXT"),
            # file_url=data.get("file_url"),
            # reply_id=data.get("reply_to_id")
        # )

        # # 3. LẤY DANH SÁCH NHỮNG NGƯỜI ĐANG ONLINE TỪ SỔ TAY
        # online_user_codes = list(connected_users.values())

        # # 4. GỌI HÀM PUSH VÀ ĐƯA DANH SÁCH ONLINE VÀO ĐỂ NÓ CHẶN
        # MessageService.push_to_notification_queue(
            # db=db, 
            # group_id=group_id, 
            # sender_code=sender_code, 
            # sender_name=sender_name, 
            # content=content,
            # online_users=online_user_codes 
        # )

        # # 5. PHÁT REAL-TIME CHO CẢ PHÒNG
        # await sio.emit("receive_message", {
            # "MessageId": new_msg.MessageId,
            # "SenderCode": sender_code,
            # "SenderName": sender_name,
            # "MessageContent": content,
            # "SenderAvatar": f"https://mobi.vinhuni.edu.vn/api/get-avatar/?student_id={sender_code}",
            # "CreatedAt": str(new_msg.CreatedAt),
            # "MessageType": new_msg.MessageType,
            # "FileUrl": new_msg.FileUrl
        # }, room=group_id)

    # except Exception as e:
        # print(f"❌ [SOCKET ERROR] Lỗi tại send_message: {e}")
    # finally:
        # db.close()

# 6. Thu hồi (Xóa) tin nhắn
@sio.event
async def delete_message(sid, data):
    message_id = data.get("message_id")
    group_id = data.get("group_id")
    
    if message_id and group_id:
        db = SessionLocal()
        try:
            # 🔥 ÉP CẬP NHẬT VÀ LƯU TRỰC TIẾP XUỐNG SQL SERVER TẠI ĐÂY
            msg = db.query(ChatMessage).filter(ChatMessage.MessageId == message_id).first()
            if msg:
                msg.IsDeleted = 1  # Đánh dấu là đã thu hồi
                db.commit()        # 🔥 CHÌA KHÓA ĐÂY: Ép SQL Server ghi nhận vĩnh viễn!
                
                # Sau khi Database đã lưu thành công thì mới phát lệnh cho Flutter xóa trên màn hình
                await sio.emit("message_deleted", {"MessageId": message_id}, room=group_id)
                print(f"🗑️ Đã thu hồi tin nhắn ID: {message_id} vĩnh viễn!")
            else:
                print(f"⚠️ Không tìm thấy tin nhắn ID: {message_id} để xóa.")
                
        except Exception as e:
            print(f"❌ Lỗi khi xóa tin: {e}")
            db.rollback() # Hoàn tác nếu có lỗi
        finally:
            db.close()

# 7. Thả tim / Cảm xúc (Reaction) ĐÃ ĐƯỢC NÂNG CẤP ĐỂ LƯU XUỐNG DB
@sio.event
async def react_message(sid, data):
    """
    Data từ Flutter gửi lên: {"message_id": 123, "reaction_type": "❤️", "group_id": "...", "user_code": "..."}
    """
    try:
        message_id = data.get('message_id')
        reaction_type = data.get('reaction_type')
        group_id = data.get('group_id')
        
        if not group_id or not message_id or not reaction_type:
            return

        db = SessionLocal()
        
        # 1. Tìm tin nhắn trong Database
        msg = db.query(ChatMessage).filter(ChatMessage.MessageId == message_id).first()
        
        if msg:
            # 2. Xử lý cộng dồn cảm xúc bằng JSON
            current_reactions = {}
            if getattr(msg, 'Reaction', None):
                try:
                    current_reactions = json.loads(msg.Reaction)
                except:
                    pass
            
            # Tăng số đếm của icon vừa được bấm lên 1
            current_reactions[reaction_type] = current_reactions.get(reaction_type, 0) + 1
            
            # 3. Lưu ngược lại vào Database dưới dạng chuỗi JSON
            msg.Reaction = json.dumps(current_reactions)
            db.commit()
            
            # 4. Phản hồi lại cho tất cả máy điện thoại khác trong nhóm (bỏ qua máy vừa gửi để tránh lag)
            await sio.emit('message_reacted', data, room=group_id, skip_sid=sid)
            print(f"❤️ Reaction {reaction_type} cho tin nhắn {message_id} đã được lưu Database!")
            
    except Exception as e:
        print(f"❌ Lỗi Socket lưu cảm xúc: {e}")
    finally:
        if 'db' in locals():
            db.close()

# 8. Trạng thái đang nhập liệu (Typing...)
@sio.event
async def typing(sid, data):
    group_id = data.get("group_id")
    await sio.emit("user_typing", data, room=group_id, skip_sid=sid)

# 9. Rời phòng
@sio.event
async def leave_room(sid, data):
    group_id = data.get("group_id")
    if group_id:
        await sio.leave_room(sid, group_id)
        print(f"🚪 User {sid} đã rời phòng: {group_id}")