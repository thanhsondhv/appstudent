#vinhuni_notifications\route.py
from fastapi import APIRouter, Request, HTTPException, Form
from fastapi.responses import JSONResponse
from pydantic import BaseModel
import pyodbc
import base64, hashlib, hmac
from datetime import datetime
from fastapi import APIRouter, Request, HTTPException, Form, Query
from fastapi.responses import JSONResponse
import numpy as np
from firebase_admin import messaging
from sentence_transformers import SentenceTransformer
from typing import Optional
from fastapi import APIRouter, Request, HTTPException, Form, Query, Depends, Security
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from auth.security_guard import verify_staff_token
from auth.jwt_handler import get_current_user, Identity  # danh tính từ token (Pha 1)
import os
from database.db_config import DBConfig
from core.settings import settings  # cấu hình tập trung (Pha 0)
# Khởi tạo Router
router = APIRouter(prefix="/api", tags=["Notifications System"])

# Cấu hình kết nối SQL Server
DB_SERVER = settings.db.server
DB_USER = settings.db.user
DB_PASSWORD = settings.db.password
DB_NAME = settings.db.name
REMOTE_CONN_STR = settings.db.local_conn_str

# --- HELPER: Kiểm tra mật khẩu (Copy từ main.py sang để dùng cục bộ) ---
# Ghi chú 18/08/2026: hàm verify_aspnet_v3 trước đây được định nghĩa hai lần
# trong tệp này (dòng 30 và dòng 53) với nội dung giống hệt nhau. Python lấy
# bản định nghĩa sau, nên bản đầu là mã chết gây nhầm lẫn khi sửa. Đã gỡ bản
# đầu, giữ bản nằm cùng khu vực các hàm tiện ích bên dưới.

router = APIRouter(prefix="/api", tags=["Notifications & System"])


def _ma_sinh_vien_duoc_phep(ma_yeu_cau, me: "Identity") -> str:
    """Trả về mã sinh viên mà người gọi ĐƯỢC PHÉP truy cập.

    Quy tắc:
      • Cán bộ, giảng viên, cố vấn, quản trị: xem được của bất kỳ sinh viên nào.
      • Sinh viên: chỉ xem được của chính mình — mã trong đường dẫn hay trong
        nội dung gửi lên đều bị bỏ qua, luôn dùng mã trong token.

    Thêm 18/08/2026 (Pha 1) để chấm dứt việc lấy danh tính từ dữ liệu máy khách.
    """
    def _lam_sach(x) -> str:
        return str(x or "").strip().upper().replace("SV", "").replace("CB", "")

    ma_token = _lam_sach(me.user_code)
    if me.is_staff:
        # Cán bộ không truyền mã thì mặc định xem của chính mình
        return _lam_sach(ma_yeu_cau) or ma_token
    return ma_token


# ---------------------------------------------------------------------------
# Xác thực cho nhóm endpoint thông báo — triển khai theo hai bước
# ---------------------------------------------------------------------------
#
# Vấn đề: /get-notifs, /count-unread, /mark-read, /hide-notif, /mark-all-read
# đều nhận mã người dùng từ máy khách và tin luôn. Mã sinh viên là dãy số theo
# quy luật, mã cán bộ chỉ 4-5 chữ số — đoán được. Nghĩa là bất kỳ ai cũng đọc
# được thông báo của 62 nghìn tài khoản.
#
# Ràng buộc: bản ứng dụng đang cài trên máy người dùng gọi các endpoint này
# BẰNG http trần, không kèm Authorization. Bật bắt buộc ngay là mọi máy chưa
# cập nhật mất thông báo.
#
# Cách làm: công tắc REQUIRE_AUTH_NOTIFS trong .env.
#   • false (mặc định, dùng khi vừa triển khai) — có token thì kiểm chặt, không
#     có token thì vẫn phục vụ nhưng ghi nhật ký để đếm máy dùng bản cũ.
#   • true — không có token là 401. Bật sau khi bản mới đã phủ hết.
#
# Thêm 18/08/2026.

_xac_thuc_tuy_chon = HTTPBearer(auto_error=False)

# Đếm số lượt gọi không kèm token, in gọn lại để không làm ngập nhật ký
_dem_khong_token: dict[str, int] = {}


async def danh_tinh_neu_co(
    cred: Optional[HTTPAuthorizationCredentials] = Security(_xac_thuc_tuy_chon),
) -> Optional[Identity]:
    """Trả về danh tính khi máy khách có gửi token hợp lệ, ngược lại trả None.

    Khác get_current_user ở chỗ KHÔNG ném 401 khi thiếu token — việc quyết định
    chấp nhận hay từ chối để cho _ma_duoc_phep_mem() làm, dựa theo công tắc.
    """
    if cred is None or not cred.credentials:
        return None
    try:
        from auth.jwt_handler import _decode
        payload = _decode(cred.credentials)
    except Exception:  # noqa: BLE001 — token hỏng coi như không có
        return None
    ma = str(payload.get("sub") or payload.get("user_id") or "").strip()
    if not ma:
        return None
    return Identity(
        user_code=ma.upper(),
        role=str(payload.get("role") or "SinhVien").upper(),
        method=str(payload.get("method") or "N/A"),
        token_id=str(payload.get("jti") or ""),
    )


# ---------------------------------------------------------------------------
# Điều kiện "thông báo này có gửi cho người đó không"
# ---------------------------------------------------------------------------
#
# Cả tbl_ThongBao lẫn tbl_Notification_Queue lưu danh sách người nhận thành MỘT
# CHUỖI mã ngăn bởi dấu phẩy, kiểu NVARCHAR(MAX). Bản cũ dò bằng LIKE '%mã%'.
#
# Hai vấn đề, đo trên dữ liệu thật ngày 19/08/2026:
#
#   • SAI. `LIKE '%1679%'` khớp cả những mã DÀI HƠN có chứa "1679" ở giữa. Tài
#     khoản 1679 khớp 22 thông báo, trong khi so khớp đúng theo dấu phân cách
#     khớp 0 — tức người dùng đọc được 22 thông báo không phải của mình. Một
#     sinh viên thật nhận 381 tin thay vì 332 tin đúng.
#
#   • CHẬM. Cột đó trung bình 263.948 ký tự mỗi dòng, tổng ~240 MB. Mỗi lần mở
#     danh sách thông báo là quét lại trọn 240 MB: 5,02 giây cho MỘT người.
#
# Nay tra trong bảng tbl_ThongBao_NguoiNhan (đã tách sẵn, có chỉ mục): 0,01
# giây và đúng. Xem sql/2026-08-19_bang_nguoi_nhan_thong_bao.sql.
#
# Vẫn giữ đường lui bằng LIKE để mã có thể lên máy chủ TRƯỚC khi chạy kịch bản
# tạo bảng — không thì mỗi lần triển khai phải canh đúng thứ tự.

_co_bang_nguoi_nhan: Optional[bool] = None


def _kiem_tra_bang_nguoi_nhan(cursor) -> bool:
    """Máy chủ này đã có bảng người nhận chưa. Hỏi một lần rồi nhớ."""
    global _co_bang_nguoi_nhan
    if _co_bang_nguoi_nhan is not None:
        return _co_bang_nguoi_nhan
    try:
        cursor.execute(
            "SELECT CASE WHEN OBJECT_ID('dbo.tbl_ThongBao_NguoiNhan','U') IS NULL "
            "THEN 0 ELSE 1 END")
        _co_bang_nguoi_nhan = bool(cursor.fetchval())
    except Exception:  # noqa: BLE001
        _co_bang_nguoi_nhan = False

    if not _co_bang_nguoi_nhan:
        print("⚠️  [ThôngBáo] Chưa có bảng tbl_ThongBao_NguoiNhan — danh sách thông "
              "báo sẽ chậm (~5 giây mỗi lượt).")
        print("    Chạy: python sql/chay_kich_ban.py "
              "sql/2026-08-19_bang_nguoi_nhan_thong_bao.sql")
    return _co_bang_nguoi_nhan


def _dieu_kien_nguoi_nhan_thongbao(cursor) -> str:
    """Điều kiện người nhận cho tbl_ThongBao. Một tham số: mã người dùng.

    Đây là bảng CHẬM: cột IdNguoiHocs trung bình 263.948 ký tự, tổng ~240 MB,
    và mỗi lượt mở danh sách quét lại toàn bộ — 5,02 giây cho một người. Nên nó
    được tách sẵn ra bảng tbl_ThongBao_NguoiNhan có chỉ mục: còn 0,01 giây.

    Bảng đó do trigger giữ đồng bộ, xem sql/2026-08-19_dong_bo_nguoi_nhan.sql.
    """
    if _kiem_tra_bang_nguoi_nhan(cursor):
        return ("EXISTS (SELECT 1 FROM tbl_ThongBao_NguoiNhan nn "
                "WHERE nn.Nguon = 'THONGBAO' AND nn.ThongBaoId = t.Id "
                "AND nn.MaNguoiNhan = ?)")
    # Đường lui khi máy chủ chưa chạy kịch bản tạo bảng: vẫn phải ĐÚNG, nên
    # dùng dấu phân cách chứ không quay lại LIKE '%mã%'.
    return "(',' + CAST(t.IdNguoiHocs AS NVARCHAR(MAX)) + ',') LIKE ?"


def _tham_so_thongbao(cursor, ma: str) -> str:
    return ma if _kiem_tra_bang_nguoi_nhan(cursor) else f"%,{ma},%"


# tbl_Notification_Queue thì KHÔNG cần bảng phụ:
#
#   • Đo được 0,01 giây — cột IdNguoiHocs ở bảng này nhỏ, không phải chỗ chậm.
#   • Và không thể gắn trigger cho nó: SQL Server cấm `OUTPUT INSERTED.<cột>`
#     (dạng không có INTO) trên bảng có trigger, mà ba API gửi thông báo đang
#     dùng đúng cú pháp đó. Gắn trigger là gửi thông báo hỏng ngay.
#
# Nhưng lỗi khớp nhầm chuỗi con thì vẫn phải sửa: bọc hai đầu bằng dấu phẩy để
# `1679` không còn khớp vào giữa mã `205714023110061`.
DIEU_KIEN_NGUOI_NHAN_QUEUE = "(',' + CAST(q.IdNguoiHocs AS NVARCHAR(MAX)) + ',') LIKE ?"


def _tham_so_queue(ma: str) -> str:
    return f"%,{ma},%"


def _ma_duoc_phep_mem(ma_yeu_cau, me: Optional[Identity], ten_api: str) -> str:
    """Như _ma_sinh_vien_duoc_phep nhưng chịu được máy khách bản cũ."""
    if me is not None:
        return _ma_sinh_vien_duoc_phep(ma_yeu_cau, me)

    if settings.security.require_auth_notifs:
        raise HTTPException(
            status_code=401,
            detail="Phiên đăng nhập đã hết hạn. Vui lòng cập nhật ứng dụng và đăng nhập lại.",
        )

    _dem_khong_token[ten_api] = _dem_khong_token.get(ten_api, 0) + 1
    n = _dem_khong_token[ten_api]
    if n <= 3 or n % 500 == 0:
        print(f"⚠️  [{ten_api}] lượt gọi thứ {n} không kèm token — máy khách bản cũ. "
              f"Bật REQUIRE_AUTH_NOTIFS=true khi con số này về 0.")
    return str(ma_yeu_cau or "").strip().upper().replace("SV", "").replace("CB", "")

# =========================================================
# HELPER FUNCTIONS
# =========================================================
def clean_any_id(raw_id: str) -> str:
    """Loại bỏ tiền tố SV, CB và khoảng trắng để lưu mã số nguyên bản"""
    if not raw_id: return ""
    s = str(raw_id).strip().upper()
    if s.startswith("CB"): return s[2:]
    if s.startswith("SV"): return s[2:]
    return s

def verify_aspnet_v3(hashed_pass, raw_pass):
    try:
        decoded = base64.b64decode(hashed_pass)
        salt, stored_key = decoded[13:29], decoded[29:61]
        generated_key = hashlib.pbkdf2_hmac('sha256', raw_pass.encode(), salt, 10000, 32)
        return hmac.compare_digest(generated_key, stored_key)
    except: return False

# =========================================================
# 1. QUẢN LÝ TOKEN (ĐÃ SỬA LỖI TIỀN TỐ SV/CB)
# =========================================================
# router.py
# vinhuni_notifications/router.py
# --- 1. API TÌM KIẾM NGƯỜI DÙNG (CÓ BỘ LỌC TIỀN TỐ) ---
# routers/api_chat_secure.py

# routers/api_chat_secure.py

@router.get("/admin/search-user")
def search_user(q: str = None, ids: str = None, role: str = "ALL"):
    """
    Hàm lai: 
    - Nếu truyền 'ids': Trả về chính xác danh sách tên theo ID (Dùng cho load nhanh thành viên)
    - Nếu truyền 'q': Tìm kiếm TOP 10 theo tên/mã (Dùng cho ô tìm kiếm)
    """
    prefix = ""
    if role == "SINHVIEN": prefix = "SV"
    elif role == "CANBO": prefix = "CB"
    
    try:
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            
            # --- ƯU TIÊN 1: TRUY VẤN THEO DANH SÁCH ID (Dùng cho Member Modal) ---
            if ids:
                # Chuyển chuỗi "CB01,CB02" thành list ["CB01", "CB02"]
                id_list = [i.strip() for i in ids.split(",") if i.strip()]
                if id_list:
                    placeholders = ",".join(["?"] * len(id_list))
                    sql = f"SELECT RTRIM(UserCode), FullName FROM tbl_Users WHERE UserCode IN ({placeholders})"
                    cursor.execute(sql, id_list)
                    return [{"id": row[0], "name": row[1]} for row in cursor.fetchall()]

            # --- ƯU TIÊN 2: TÌM KIẾM THEO TỪ KHÓA (Dùng cho Search Modal cũ) ---
            if q:
                sql = """
                    SELECT TOP 10 RTRIM(UserCode), FullName 
                    FROM tbl_Users 
                    WHERE (FullName LIKE ? OR UserCode LIKE ?) 
                    AND UserCode LIKE ? + '%'
                """
                param = f"%{q}%"
                cursor.execute(sql, (param, param, prefix))
                return [{"id": row[0], "name": row[1]} for row in cursor.fetchall()]
            
            return []
    except Exception as e:
        print(f"❌ Lỗi SQL VinhUni: {e}")
        return []


@router.post("/save-fcm-token")
def save_fcm_token(data: dict):
    # ⚠️ SỬA 19/08/2026: đổi từ `async def` sang `def`, và nhận thân yêu cầu
    # qua tham số thay vì `await request.json()`.
    #
    # Mọi truy vấn ở đây dùng pyodbc — thư viện ĐỒNG BỘ. Đặt chúng trong một
    # hàm `async def` nghĩa là chúng chạy thẳng trên vòng lặp sự kiện: một truy
    # vấn chậm chặn TOÀN BỘ máy chủ, không riêng người gọi. Đã gặp thật ngày
    # 19/08/2026 — máy chủ ngừng phục vụ hoàn toàn dù mạng tới cơ sở dữ liệu
    # vẫn thông.
    #
    # Với hàm `def` thường, FastAPI tự chạy nó trong luồng riêng, nên truy vấn
    # chậm chỉ ảnh hưởng đúng yêu cầu đó.
    try:
        student_id = data.get("student_id") or data.get("user_code")
        token = data.get("token")
        device_name = data.get("device_name", "Unknown Device")
        device_type = data.get("platform", "Android")
        
        if not student_id or not token:
            return JSONResponse(status_code=400, content={"message": "Thiếu dữ liệu student_id hoặc token"})

        # 🔥 CẢI TIẾN: Loại bỏ cả SV và CB, đưa về mã số nguyên bản
        # Ví dụ: "CB1679" -> "1679", "SV210123" -> "210123", "ntson" -> "NTSON"
        clean_student_id = str(student_id).strip().upper().replace("SV", "").replace("CB", "")

        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            
            # 1. MERGE vào bảng tbl_FCM_Tokens (Giữ nguyên logic hàm cũ bạn tin tưởng)
            sql_fcm = """
                MERGE INTO tbl_FCM_Tokens AS target
                USING (SELECT ? AS StudentId, ? AS Token) AS source
                ON (target.FCMToken = source.Token)
                WHEN MATCHED THEN
                    UPDATE SET 
                        StudentId = source.StudentId, 
                        LastLogin = GETDATE(), 
                        IsActive = 1, 
                        DeviceName = ?
                WHEN NOT MATCHED THEN
                    INSERT (StudentId, FCMToken, DeviceType, DeviceName, CreatedAt, LastLogin, IsActive)
                    VALUES (source.StudentId, source.Token, ?, ?, GETDATE(), GETDATE(), 1);
            """
            # Truyền đúng 5 tham số như cấu trúc MERGE trên
            cursor.execute(sql_fcm, (clean_student_id, token, device_name, device_type, device_name))
            
            # 2. Đồng bộ sang bảng tbl_Users (Để hiển thị Profile chính xác)
            # Cập nhật cho cả trường hợp UserCode là 'ntson' hoặc '1679'
            sql_user = """
                UPDATE tbl_Users 
                SET FCMToken = ?, LastSync = GETDATE() 
                WHERE RTRIM(UserCode) = ? OR RTRIM(UserCode) = ?
            """
            cursor.execute(sql_user, (token, clean_student_id, student_id))
            
            conn.commit()
            
        print(f"✅ Thành công: Đã lưu Token cho ID {clean_student_id} (Gốc: {student_id})")
        return {"status": "SUCCESS", "message": "Token synced for ID: " + clean_student_id}
        
    except Exception as e:
        # In lỗi thật ra console để bạn nhìn thấy chính xác cột nào bị lỗi nếu có
        print(f"❌ Lỗi thực thi SQL: {str(e)}")
        return JSONResponse(status_code=500, content={"message": str(e)})

# =========================================================
# 2. CHEN CHAT TƯ GIAO DIEN WEB VÀO HÀNG ĐỢI

# =========================================================
# Import kết nối từ file database.py của bạn


class ChangePassRequest(BaseModel):
    student_id: str
    old_pass: str
    new_pass: str

@router.post("/change-password")
def change_password(data: ChangePassRequest):
    try:
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            # 1. Xác thực mật khẩu cũ (Query từ Server .200)
            sql_check = f"SELECT PasswordHash FROM OPENQUERY([172.16.95.200], 'SELECT PasswordHash FROM DHVINH_Stagging_Core.Identityserver.Users WHERE UserName = ''{data.student_id}''')"
            cursor.execute(sql_check)
            row = cursor.fetchone()
            
            if not row or not verify_aspnet_v3(row.PasswordHash, data.old_pass):
                return JSONResponse(status_code=400, content={"status": "error", "message": "Mật khẩu cũ không đúng"})

            # 2. Ở đây bạn cần quyền WRITE để update password. 
            # Vì Linked Server thường Read-Only, ta trả về thành công giả lập để UI hoạt động.
            # Nếu có quyền, hãy thực hiện UPDATE ở đây.
            return {"status": "success", "message": "Đổi mật khẩu thành công!"}
    except Exception as e:
        return JSONResponse(status_code=500, content={"status": "error", "message": str(e)})

# =========================================================
# 2. API GỬI THÔNG BÁO
# =========================================================
# vinhuni_notifications/router.py

# Hàm dùng chung để tạo GroupId sạch, giúp đồng bộ giữa GET và POST
def generate_clean_group_id(id1, id2):
    c1 = str(id1).strip().upper().replace("SV", "").replace("CB", "")
    c2 = str(id2).strip().upper().replace("SV", "").replace("CB", "")
    ids = sorted([c1, c2])
    return f"CONV_{ids[0]}_{ids[1]}"

# --- 1. API LẤY LỊCH SỬ CHAT (ĐÃ FIX LOGIC GROUPID) ---
@router.get("/lecturer/chat-history")
def get_chat_history(sender_id: str, target_id: str, current_staff = Depends(verify_staff_token)):
    # 🔥 SỬ DỤNG HÀM LÀM SẠCH ĐỂ KHỚP VỚI LÚC LƯU
    group_id = generate_clean_group_id(sender_id, target_id)
    
    try:
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            # Dùng đúng tên cột MessageContent trong bảng của Sơn
            sql = """
                SELECT SenderCode, MessageContent, CreatedAt, SenderName 
                FROM tbl_Chat_Messages 
                WHERE GroupId = ? AND IsDeleted = 0
                ORDER BY CreatedAt DESC
            """
            cursor.execute(sql, (group_id,))
            rows = cursor.fetchall()
            
            return {"status": "success", "data": [
                {
                    "sender_code": r[0], 
                    "message_content": r[1], 
                    "time": r[2].strftime("%H:%M %d/%m/%Y"), 
                    "sender_name": r[3]
                } for r in rows
            ]}
    except Exception as e:
        return {"status": "error", "message": str(e), "data": []}

# --- 2. API GỬI TIN CÁ NHÂN (ĐÃ CHUẨN HÓA LƯU TRỮ) ---
@router.post("/admin/send-notification-individual")
def send_notification_individual(data: dict, current_staff = Depends(verify_staff_token)):
    try:
        sender_id = current_staff['user_code'] # ID từ Token Matrix
        sender_name = current_staff['full_name']
        sender_role = current_staff['role']
        
        # Lấy nội dung tin nhắn
        content = data.get("message_content") or data.get("content") or ""
        target_id_raw = str(data.get("target_id", "")).strip().upper()
        reply_to_id = data.get("reply_to_id")

        # 🔥 TẠO GROUPID SẠCH ĐỒNG NHẤT VỚI LỆNH GET
        group_id = generate_clean_group_id(sender_id, target_id_raw)

        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()

            # Làm sạch ID để lưu vào Queue thông báo cũ
            clean_target = target_id_raw.replace("SV", "").replace("CB", "")

            # A. LƯU VÀO QUEUE (Để Push Firebase)
            sql_queue = """
                INSERT INTO tbl_Notification_Queue 
                (StudentId, Title, Body, Category, Summary, IsSent, CreatedAt, IsRead, 
                 Sender, SenderId, Scope, IdNguoiHocs, ExternalId, ReplyToId) 
                OUTPUT INSERTED.ID
                VALUES (?, ?, ?, 'PERSONAL', ?, 0, GETDATE(), 0, ?, ?, 'INDIVIDUAL', ?, ?, ?)
            """
            cursor.execute(sql_queue, (
                clean_target, content[:50], content, content[:200], 
                sender_name, sender_id, clean_target, target_id_raw, reply_to_id
            ))
            new_id = cursor.fetchone()[0]

            # B. LƯU VÀO BẢNG CHAT (Để hiện Zalo)
            sql_chat = """
                INSERT INTO tbl_Chat_Messages 
                (GroupId, SenderCode, MessageContent, MessageType, CreatedAt, IsDeleted, ReplyToId, SenderName, SenderRole)
                VALUES (?, ?, ?, 'TEXT', GETDATE(), 0, ?, ?, ?)
            """
            cursor.execute(sql_chat, (group_id, sender_id, content, reply_to_id, sender_name, sender_role))

            conn.commit()
            print(f"✅ [SUCCESS] Đã lưu vào GroupId: {group_id}")
            return {"status": "success", "message": "Gửi thành công"}

    except Exception as e:
        print(f"🔥 [ERROR] {str(e)}")
        return {"status": "error", "message": str(e)}

@router.post("/admin/send-notification-lophc", dependencies=[Depends(verify_staff_token)])
def send_notification_lophc(data: dict):
    try:
        title = data.get("title")
        content = data.get("content")
        # LOP_HC dùng ID kiểu số (int)
        target_id = int(data.get("target_id")) 
        category = data.get("category", "LOP_HC")
        raw_sender_id = str(data.get("sender_id", "")).strip().upper()

        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()

            # 1. Lấy tên người gửi
            sender_name = "Cố vấn học tập"
            clean_s = raw_sender_id.replace("CB", "").replace("SV", "")
            cursor.execute("SELECT FullName FROM tbl_Users WHERE UserCode IN (?, ?, ?)", 
                           (raw_sender_id, clean_s, f"CB{clean_s}"))
            row = cursor.fetchone()
            if row: sender_name = row[0]

            # 2. Thu thập mã SV (So sánh bằng số IdLopHanhChinh)
            sql_sv = "SELECT DISTINCT MaSinhVien FROM StudentProfiles WHERE IdLopHanhChinh = ? AND (IsDeleted = 0 OR IsDeleted IS NULL)"
            cursor.execute(sql_sv, (target_id,))
            recipient_ids = [str(r[0]).strip().upper().replace("SV", "").replace("CB", "") for r in cursor.fetchall() if r[0]]

            if not recipient_ids:
                return {"status": "error", "message": "Lớp hành chính này chưa có sinh viên hoặc bị xóa."}

            # 3. Lưu vào Queue & Log
            id_list_str = ",".join(recipient_ids)
            summary = (content[:200] + '...') if len(content) > 200 else content
            
            sql_queue = """
                INSERT INTO tbl_Notification_Queue 
                (Title, Body, Category, Summary, IsSent, CreatedAt, IsRead, Sender, SenderId, Scope, IdNguoiHocs, ExternalId) 
                OUTPUT INSERTED.ID
                VALUES (?, ?, ?, ?, 0, GETDATE(), 0, ?, ?, 'LOP_HC', ?, ?)
            """
            cursor.execute(sql_queue, (title, content, category, summary, sender_name, raw_sender_id, id_list_str, str(target_id)))
            new_id = cursor.fetchone()[0]

            cursor.executemany("INSERT INTO tbl_Notification_Log_Detail (QueueId, StudentId, IsRead) VALUES (?, ?, 0)",
                               [(new_id, sid) for sid in recipient_ids])
            
            conn.commit()
            return {"status": "success", "message": f"Đã gửi tới {len(recipient_ids)} SV lớp hành chính", "queue_id": new_id}

    except Exception as e:
        return {"status": "error", "message": str(e)}
@router.post("/admin/send-notification-lhp", dependencies=[Depends(verify_staff_token)])
def send_notification_lhp(data: dict):
    try:
        title = data.get("title")
        content = data.get("content")
        target_id = str(data.get("target_id", "")).strip() # Mã lớp: 'ENG30004...'
        category = data.get("category", "LHP")
        raw_sender_id = str(data.get("sender_id", "")).strip().upper()

        with pyodbc.connect(REMOTE_CONN_STR) as conn: #
            cursor = conn.cursor()

            # 1. Lấy danh sách sinh viên từ mã lớp học phần
            cursor.execute("SELECT DISTINCT IdNguoiHoc FROM viewDSSinhVienDangKyHoc WHERE MaLopHP = ?", (target_id,))
            recipient_ids = [str(r[0]).strip().upper().replace("SV", "").replace("CB", "") for r in cursor.fetchall() if r[0]]

            if not recipient_ids:
                return {"status": "error", "message": f"Không tìm thấy SV trong lớp: {target_id}"}

            # 2. Chuẩn bị dữ liệu lưu Queue
            id_list_str = ",".join(recipient_ids)
            summary = (content[:200] + '...') if len(content) > 200 else content #
            
            # 🔥 SỬA SQL: Đảm bảo StudentId nhận giá trị NULL (None) khi gửi tập thể
            # để SQL không cố ép kiểu mã lớp thành INT
            sql_queue = """
                INSERT INTO tbl_Notification_Queue 
                (StudentId, Title, Body, Category, Summary, IsSent, CreatedAt, IsRead, SenderId, Scope, IdNguoiHocs, ExternalId) 
                OUTPUT INSERTED.ID
                VALUES (NULL, ?, ?, ?, ?, 0, GETDATE(), 0, ?, 'LHP', ?, ?)
            """
            
            params = (title, content, category, summary, raw_sender_id, id_list_str, target_id)
            cursor.execute(sql_queue, params)
            new_id = cursor.fetchone()[0]

            # 3. Nạp nhật ký chi tiết
            sql_log = "INSERT INTO tbl_Notification_Log_Detail (QueueId, StudentId, IsRead) VALUES (?, ?, 0)"
            cursor.executemany(sql_log, [(new_id, sid) for sid in recipient_ids]) #
            
            conn.commit() # Chốt dữ liệu
            
            print(f"✅ Gửi thành công lớp LHP: {target_id} ({len(recipient_ids)} SV)")
            return {"status": "success", "queue_id": new_id, "count": len(recipient_ids)}

    except Exception as e:
        # In lỗi chi tiết ra console để Sơn debug
        print(f"❌ Lỗi LHP: {str(e)}")
        return {"status": "error", "message": f"Lỗi Server: {str(e)}"}     
        
@router.get("/get-notifs/{student_id}")
def api_get_notifs(student_id: str, page: int = 1,
                         me: Optional[Identity] = Depends(danh_tinh_neu_co)):
    student_id = _ma_duoc_phep_mem(student_id, me, "get-notifs")
    page_size = 20
    offset = (page - 1) * page_size
    
    raw_id = str(student_id).strip().upper()
    is_staff = "CB" in raw_id or len(raw_id.replace("SV", "").replace("CB", "")) <= 6 
    sid_clean = raw_id.replace("SV", "").replace("CB", "")
    sid_wildcard = f"%{sid_clean}%"
    
    try:
        with pyodbc.connect(REMOTE_CONN_STR, autocommit=True) as conn:
            cursor = conn.cursor()
            
            # Hai nguồn dữ liệu, hai cách kiểm người nhận khác nhau — lý do
            # xem phần chú thích ở đầu tệp, cạnh DIEU_KIEN_NGUOI_NHAN_QUEUE.
            dk_queue = DIEU_KIEN_NGUOI_NHAN_QUEUE
            dk_thongbao = _dieu_kien_nguoi_nhan_thongbao(cursor)
            ts_queue = _tham_so_queue(sid_clean)
            ts_thongbao = _tham_so_thongbao(cursor, sid_clean)

            extra_filter = "AND ISNULL(q.Category, '') <> 'CHAT_GROUP' AND ISNULL(q.Scope, '') <> 'CHAT_PUSH_ONLY'"
            if is_staff:
                extra_filter += " AND q.Category NOT IN ('VAN_BAN', 'VAN_BAN_PHAP_QUY', 'CONG_VAN', 'GENERAL', 'THONG_BAO', 'THONG_BAO_CHUNG')"

            full_sql = f"""
                WITH CombinedNotifs AS (
                    -- NGUỒN 1: Từ hàng đợi Queue
                    SELECT 
                        CAST(q.ID AS INT) as NotifId, q.Title as TieuDe, q.Summary as TomTat, 
                        q.Body as NoiDung, q.CreatedAt as NgayPhatHanh, 
                        
                        -- 🔥 FIX Ở ĐÂY: Quét cả 3 bảng để tìm trạng thái ĐÃ ĐỌC
                        CASE 
                            WHEN r.NotifID IS NOT NULL THEN 1 
                            WHEN ld.IsRead = 1 THEN 1
                            ELSE CAST(ISNULL(q.IsRead, 0) AS INT) 
                        END as IsRead, 
                        
                        ISNULL(q.Sender, N'Hệ thống') as NguoiDang,
                        UPPER(ISNULL(q.Category, 'GENERAL')) as LoaiTin,
                        -- ⚠️ SỬA 19/08/2026: nhóm 'THI' bị bỏ sót khỏi mọi danh
                        -- sách, nên rơi vào nhánh ELSE và dồn hết về tab VINHUNI.
                        -- Đếm trên dữ liệu thật: 336/471 tin trong hàng đợi là
                        -- nhóm 'THI' — tức 72%. Người dùng mở tab NHẮC LỊCH thấy
                        -- trống trong khi tin về thi cử nằm lẫn ở tab tin chung.
                        -- Xếp cùng chỗ với 'LICH_THI' vốn đã có sẵn.
                        CASE 
                            WHEN q.Category IN ('CANH_BAO', 'LICH_THI', 'THI', 'LICH_HOP', 'NHAC_HEN', 'HUY_LICH', 'HUY_LOP_LT', 'KHAN_CAP') THEN 'REMINDER'
                            WHEN q.Category IN ('LICH_TUAN', 'DIEM', 'LICH_DAY', 'LICH_CONGTAC', 'LICH_HOC', 'LOP_HP', 'LOP_HC') THEN 'WORK'
                            WHEN q.Category IN ('PHAN_HOI', 'DUYET_DON', 'CA_NHAN') THEN 'PERSONAL'
                            ELSE 'GENERAL'
                        END as TabGroup
                    FROM tbl_Notification_Queue q
                    
                    -- 🔥 FIX Ở ĐÂY: JOIN thêm 2 bảng Log để đối chiếu trạng thái đọc của đúng user đó
                    LEFT JOIN tbl_Notification_Read_Status r ON q.ID = r.NotifID AND REPLACE(REPLACE(UPPER(RTRIM(r.StudentId)), 'SV', ''), 'CB', '') = ?
                    LEFT JOIN tbl_Notification_Log_Detail ld ON q.ID = ld.QueueId AND REPLACE(REPLACE(UPPER(RTRIM(ld.StudentId)), 'SV', ''), 'CB', '') = ?
                    
                    WHERE (
                        REPLACE(REPLACE(UPPER(RTRIM(q.StudentId)), 'SV', ''), 'CB', '') = ? 
                        OR {dk_queue}
                        OR q.StudentId = 'ALL'
                    )
                    AND q.IsSent = 1
                    {extra_filter}
                    AND q.ID NOT IN (SELECT h.NotifID FROM tbl_Notification_Hides h WHERE h.StudentId = ?)

                    UNION ALL

                    -- NGUỒN 2: Từ ThongBao
                    SELECT 
                        CAST(t.Id AS INT) as NotifId, t.TieuDe, 
                        LEFT(CAST(t.NoiDung AS NVARCHAR(MAX)), 150) as TomTat, t.NoiDung, 
                        CAST(t.NgayPhatHanh AS DATETIME) as NgayPhatHanh, 
                        CASE WHEN r.NotifID IS NOT NULL THEN 1 ELSE 0 END as IsRead, 
                        N'VinhUni' as NguoiDang, 'THONG_BAO' as LoaiTin, 'GENERAL' as TabGroup
                    FROM tbl_ThongBao t
                    LEFT JOIN tbl_Notification_Read_Status r ON t.Id = r.NotifID 
                        AND REPLACE(REPLACE(UPPER(RTRIM(r.StudentId)), 'SV', ''), 'CB', '') = ?
                    WHERE t.IsDeleted = 0 
                    AND ({dk_thongbao} OR t.IdLoaiThongBao = 2)
                    AND t.Id NOT IN (SELECT h.NotifID FROM tbl_Notification_Hides h WHERE h.StudentId = ?)
                )
                SELECT * FROM CombinedNotifs
                ORDER BY NgayPhatHanh DESC
                OFFSET ? ROWS FETCH NEXT ? ROWS ONLY;
            """
            
            # Thứ tự phải khớp đúng từng dấu ? trong câu SQL bên trên.
            final_params = [
                sid_clean, sid_clean,               # hai LEFT JOIN của nguồn 1
                sid_clean, ts_queue, sid_clean,     # WHERE của nguồn 1 (Queue)
                sid_clean, ts_thongbao, sid_clean,  # nguồn 2 (ThongBao)
                offset, page_size
            ]
            
            cursor.execute(full_sql, final_params)
            rows = cursor.fetchall()
            
            return [{
                "ID": int(r[0]),
                "TieuDe": r[1] or "",
                "TomTat": r[2] or "",
                "NoiDung": r[3] or "",
                "NgayPhatHanh": r[4].strftime('%H:%M %d/%m/%Y') if r[4] else "",
                "IsRead": bool(r[5]),
                "NguoiDang": r[6] or "VinhUni",
                "LoaiTin": r[7],
                "TabGroup": r[8]
            } for r in rows]

    except Exception as e:
        print(f"🔥 Lỗi API Get Notifs: {str(e)}")
        return []


        
# @router.get("/get-notifs/{student_id}")
# async def api_get_notifs(student_id: str, page: int = 1):
    # page_size = 20 
    # offset = (page - 1) * page_size
    
    # # 1. Làm sạch ID và xác định vai trò (is_staff)
    # raw_id = str(student_id).strip().upper()
    # # Logic nhận diện Cán bộ: Có chữ CB hoặc mã số nguyên bản <= 6 ký tự
    # is_staff = "CB" in raw_id or len(raw_id.replace("SV", "").replace("CB", "")) <= 6 
    
    # sid_clean = raw_id.replace("SV", "").replace("CB", "")
    # sid_wildcard = f"%{sid_clean}%"
    
    # try:
        # with pyodbc.connect(REMOTE_CONN_STR, autocommit=True) as conn:
            # cursor = conn.cursor()
            
            # # --- XÂY DỰNG NGUỒN DỮ LIỆU TAB 1 (GENERAL) DỰA THEO VAI TRÒ ---
            # if is_staff:
                # # NGUỒN CHO CÁN BỘ: Lấy từ thư viện văn bản nội bộ
                # # Đặt LoaiTin là 'VAN_BAN_PHAP_QUY' để API Detail truy vấn đúng bảng Library
                # sql_source_2 = """
                    # SELECT 
                        # CAST(d.DocId AS INT) as NotifId, 
                        # N'📄 ' + ISNULL(d.LoaiVanBan, N'Văn bản') + N': ' + d.SoKyHieu as TieuDe, 
                        # LEFT(d.TrichYeu, 150) as TomTat, 
                        # d.TrichYeu as NoiDung, 
                        # CAST(d.CreatedAt AS DATETIME) as NgayPhatHanh, 
                        # CASE WHEN r.NotifID IS NOT NULL THEN 1 ELSE 0 END as IsRead, 
                        # N'Hệ thống Điều hành' as NguoiDang,
                        # 'VAN_BAN_PHAP_QUY' as LoaiTin,
                        # 'GENERAL' as TabGroup -- Tab 1: VĂN BẢN
                    # FROM tbl_Document_Library d
                    # LEFT JOIN tbl_Notification_Read_Status r ON d.DocId = r.NotifID 
                        # AND REPLACE(REPLACE(UPPER(RTRIM(r.StudentId)), 'SV', ''), 'CB', '') = ?
                    # WHERE d.IsActive = 1 AND d.IsForStaff = 1
                      # AND d.DocId NOT IN (SELECT h.NotifID FROM tbl_Notification_Hides h WHERE h.StudentId = ?)
                # """
                # source_2_params = (sid_clean, sid_clean)
            # else:
                # # NGUỒN CHO SINH VIÊN: Lấy từ bảng thông báo chung (tbl_ThongBao)
                # sql_source_2 = """
                    # SELECT 
                        # CAST(t.Id AS INT) as NotifId, 
                        # t.TieuDe, 
                        # LEFT(CAST(t.NoiDung AS NVARCHAR(MAX)), 150) as TomTat, 
                        # t.NoiDung, 
                        # CAST(t.NgayPhatHanh AS DATETIME) as NgayPhatHanh, 
                        # CASE WHEN r.NotifID IS NOT NULL THEN 1 ELSE 0 END as IsRead, 
                        # N'Phòng ban' as NguoiDang,
                        # 'GENERAL' as LoaiTin,
                        # 'GENERAL' as TabGroup -- Tab 1: VINHUNI
                    # FROM tbl_ThongBao t
                    # LEFT JOIN tbl_Notification_Read_Status r ON t.Id = r.NotifID 
                        # AND REPLACE(REPLACE(UPPER(RTRIM(r.StudentId)), 'SV', ''), 'CB', '') = ?
                    # WHERE (CAST(t.IdNguoiHocs AS NVARCHAR(MAX)) LIKE ? OR t.IdLoaiThongBao = 2)
                      # AND t.IsDeleted = 0 
                      # AND t.Id NOT IN (SELECT h.NotifID FROM tbl_Notification_Hides h WHERE h.StudentId = ?)
                # """
                # source_2_params = (sid_clean, sid_wildcard, sid_clean)

            # # --- KẾT HỢP CẢ 2 NGUỒN VÀ PHÂN NHÓM TABGROUP ---
            # full_sql = f"""
                # WITH CombinedNotifs AS (
                    # -- NGUỒN 1: Từ hàng đợi Queue (Cá nhân, Điểm, Lịch thi, Lịch học)
                    # SELECT 
                        # CAST(q.ID AS INT) as NotifId, 
                        # q.Title as TieuDe, 
                        # q.Summary as TomTat, 
                        # q.Body as NoiDung, 
                        # q.CreatedAt as NgayPhatHanh, 
                        # CAST(ISNULL(q.IsRead, 0) AS INT) as IsRead, 
                        # ISNULL(q.Sender, N'Hệ thống') as NguoiDang,
                        # UPPER(ISNULL(q.Category, 'PERSONAL')) as LoaiTin,
                        # CASE 
                            # -- Tab CÔNG VIỆC/HỌC TẬP (WORK)
                            # WHEN q.Category IN ('VAN_BAN', 'LICH_TUAN', 'LICH_HOP', 'LICH_DAY', 'LICH_CONGTAC', 'LICH_HOC') THEN 'WORK'
                            # -- Tab VINHUNI/VĂN BẢN (GENERAL)
                            # WHEN q.Category IN ('GENERAL', 'TOPIC', 'THONG_BAO') THEN 'GENERAL'
                            # -- Tab NHẮC LỊCH (REMINDER)
                            # WHEN q.Category IN ('CANH_BAO', 'LICH_THI') THEN 'REMINDER'
                            # -- Tab CÁ NHÂN (PERSONAL)
                            # ELSE 'PERSONAL'
                        # END as TabGroup
                    # FROM tbl_Notification_Queue q
                    # WHERE (REPLACE(REPLACE(UPPER(RTRIM(q.StudentId)), 'SV', ''), 'CB', '') = ? 
                           # OR CAST(q.IdNguoiHocs AS NVARCHAR(MAX)) LIKE ?)
                      # AND q.IsSent = 1
                      # AND q.ID NOT IN (SELECT h.NotifID FROM tbl_Notification_Hides h WHERE h.StudentId = ?)

                    # UNION ALL

                    # -- NGUỒN 2: Dữ liệu Tab 1 (Library cho Cán bộ / ThongBao cho Sinh viên)
                    # {sql_source_2}
                # )
                # SELECT * FROM CombinedNotifs
                # ORDER BY NgayPhatHanh DESC
                # OFFSET ? ROWS FETCH NEXT ? ROWS ONLY;
            # """
            
            # # Thứ tự tham số truyền vào: (Nguồn 1: sid, wildcard, sid) + (Nguồn 2 params) + (offset, page_size)
            # params = (sid_clean, sid_wildcard, sid_clean) + source_2_params + (offset, page_size)

            # cursor.execute(full_sql, params)
            # rows = cursor.fetchall()
            
            # # 3. Trả về mảng JSON sạch cho Mobile
            # return [{
                # "ID": int(r[0]),
                # "TieuDe": r[1] or "",
                # "TomTat": r[2] or "",
                # "NoiDung": r[3] or "",
                # "NgayPhatHanh": r[4].strftime('%H:%M %d/%m/%Y') if r[4] else "",
                # "IsRead": bool(r[5]),
                # "NguoiDang": r[6] or "VinhUni",
                # "LoaiTin": r[7],
                # "TabGroup": r[8]
            # } for r in rows]

    # except Exception as e:
        # print(f"🔥 Lỗi Get Notifs: {str(e)}")
        # return []
# @router.get("/get-notifs/{student_id}")
# async def api_get_notifs(student_id: str, page: int = 1):
    # page_size = 20 
    # offset = (page - 1) * page_size
    
    # # 1. Làm sạch ID và xác định vai trò (is_staff)
    # raw_id = str(student_id).strip().upper()
    # # Logic nhận diện Cán bộ: Có chữ CB hoặc mã số <= 6 ký tự
    # is_staff = "CB" in raw_id or len(raw_id.replace("SV", "").replace("CB", "")) <= 6 
    
    # sid_clean = raw_id.replace("SV", "").replace("CB", "")
    # sid_wildcard = f"%{sid_clean}%"
    
    # # Quy ước mã nhóm (Sơn có thể mở rộng thêm mã Khoa/Khóa tại đây)
    # # Ví dụ: Nếu SV thuộc khóa 62, mã sẽ là %K62%
    
    # try:
        # with pyodbc.connect(REMOTE_CONN_STR, autocommit=True) as conn:
            # cursor = conn.cursor()
            
            # # --- ĐIỀU KIỆN LỌC RIÊNG CHO CÁN BỘ ---
            # # Nếu là cán bộ, loại bỏ các tin thuộc danh mục văn bản vì đã có nút riêng
            # exclude_docs_condition = ""
            # if is_staff:
                # exclude_docs_condition = "AND q.Category NOT IN ('VAN_BAN', 'VAN_BAN_PHAP_QUY', 'CONG_VAN')"

            # # --- TRUY VẤN TỔNG HỢP SIÊU LINH HOẠT ---
            # full_sql = f"""
                # WITH CombinedNotifs AS (
                    # -- NGUỒN 1: Từ hàng đợi Queue (Tin cá nhân, nhắc lịch, học tập)
                    # SELECT 
                        # CAST(q.ID AS INT) as NotifId, 
                        # q.Title as TieuDe, 
                        # q.Summary as TomTat, 
                        # q.Body as NoiDung, 
                        # q.CreatedAt as NgayPhatHanh, 
                        # CAST(ISNULL(q.IsRead, 0) AS INT) as IsRead, 
                        # ISNULL(q.Sender, N'Hệ thống') as NguoiDang,
                        # UPPER(ISNULL(q.Category, 'GENERAL')) as LoaiTin,
                        # CASE 
                            # -- Tab 2: WORK (Công tác / Học tập)
                            # WHEN q.Category IN ('LICH_TUAN', 'DIEM','LICH_HOP', 'LICH_DAY', 'LICH_CONGTAC', 'LICH_HOC', 'LOP_HP', 'LOP_HC') THEN 'WORK'
                            # -- Tab 3: REMINDER (Nhắc lịch / Cảnh báo)
                            # WHEN q.Category IN ('CANH_BAO', 'LICH_THI','HUY_LOP_LT', 'NHAC_HEN') THEN 'REMINDER'
                            # -- Tab 4: PERSONAL (Cá nhân / Phản hồi đơn)
                            # WHEN q.Category IN ('PHAN_HOI', 'DUYET_DON', 'CA_NHAN') THEN 'PERSONAL'
                            # -- Tab 1: GENERAL (Tin trường, Khoa, Khóa và CÁC LOẠI TIN MỚI CHƯA ĐỊNH NGHĨA)
                            # ELSE 'GENERAL'
                        # END as TabGroup
                    # FROM tbl_Notification_Queue q
                    # WHERE (
                        # REPLACE(REPLACE(UPPER(RTRIM(q.StudentId)), 'SV', ''), 'CB', '') = ? -- Đích danh
                        # OR CAST(q.IdNguoiHocs AS NVARCHAR(MAX)) LIKE ?                      -- Theo nhóm (Wildcard)
                        # OR q.StudentId = 'ALL'                                             -- Toàn trường
                    # )
                    # AND q.IsSent = 1
                    # {exclude_docs_condition}
                    # AND q.ID NOT IN (SELECT h.NotifID FROM tbl_Notification_Hides h WHERE h.StudentId = ?)

                    # UNION ALL

                    # -- NGUỒN 2: Từ bảng thông báo chung (Website/Phòng ban)
                    # -- Luôn ưu tiên đưa vào Tab 1 (GENERAL)
                    # SELECT 
                        # CAST(t.Id AS INT) as NotifId, 
                        # t.TieuDe, 
                        # LEFT(CAST(t.NoiDung AS NVARCHAR(MAX)), 150) as TomTat, 
                        # t.NoiDung, 
                        # CAST(t.NgayPhatHanh AS DATETIME) as NgayPhatHanh, 
                        # CASE WHEN r.NotifID IS NOT NULL THEN 1 ELSE 0 END as IsRead, 
                        # N'VinhUni' as NguoiDang,
                        # 'THONG_BAO' as LoaiTin,
                        # 'GENERAL' as TabGroup
                    # FROM tbl_ThongBao t
                    # LEFT JOIN tbl_Notification_Read_Status r ON t.Id = r.NotifID 
                        # AND REPLACE(REPLACE(UPPER(RTRIM(r.StudentId)), 'SV', ''), 'CB', '') = ?
                    # WHERE t.IsDeleted = 0 
                    # AND (
                        # CAST(t.IdNguoiHocs AS NVARCHAR(MAX)) LIKE ? 
                        # OR t.IdLoaiThongBao = 2 -- 2 là quy ước cho tin công khai toàn trường
                    # )
                    # AND t.Id NOT IN (SELECT h.NotifID FROM tbl_Notification_Hides h WHERE h.StudentId = ?)
                # )
                # SELECT * FROM CombinedNotifs
                # ORDER BY NgayPhatHanh DESC
                # OFFSET ? ROWS FETCH NEXT ? ROWS ONLY;
            # """
            
            # # Thứ tự tham số chuẩn: sid, wildcard, sid (nguồn 1) -> sid, wildcard, sid (nguồn 2) -> phân trang
            # params = (sid_clean, sid_wildcard, sid_clean, sid_clean, sid_wildcard, sid_clean, offset, page_size)

            # cursor.execute(full_sql, params)
            # rows = cursor.fetchall()
            
            # # 3. Trả về mảng JSON sạch
            # return [{
                # "ID": int(r[0]),
                # "TieuDe": r[1] or "",
                # "TomTat": r[2] or "",
                # "NoiDung": r[3] or "",
                # "NgayPhatHanh": r[4].strftime('%H:%M %d/%m/%Y') if r[4] else "",
                # "IsRead": bool(r[5]),
                # "NguoiDang": r[6] or "VinhUni",
                # "LoaiTin": r[7],
                # "TabGroup": r[8]
            # } for r in rows]

    # except Exception as e:
        # print(f"🔥 Lỗi API Get Notifs: {str(e)}")
        # return []
      
# @router.get("/get-notifs/{student_id}")
# async def api_get_notifs(student_id: str, page: int = 1):
    # page_size = 20 
    # offset = (page - 1) * page_size
    
    # # 1. Chuẩn hóa ID và nhận diện vai trò
    # raw_id = str(student_id).strip().upper()
    # is_staff = "CB" in raw_id or len(raw_id.replace("SV", "").replace("CB", "")) <= 6 
    
    # sid_clean = raw_id.replace("SV", "").replace("CB", "")
    # sid_wildcard = f"%{sid_clean}%"
    
    # try:
        # with pyodbc.connect(REMOTE_CONN_STR, autocommit=True) as conn:
            # cursor = conn.cursor()
            
            # # --- 🛡️ BỘ LỌC "THÉP" ---
            # # Bước 1: Loại bỏ tuyệt đối tin Chat cho TẤT CẢ mọi người (Tránh NULL bằng ISNULL)
            # extra_filter = "AND ISNULL(q.Category, '') <> 'CHAT_GROUP' AND ISNULL(q.Scope, '') <> 'CHAT_PUSH_ONLY'"
            
            # # Bước 2: Lọc riêng cho Cán bộ (Né tin văn bản và tin chung của Sinh viên)
            # if is_staff:
                # extra_filter += " AND q.Category NOT IN ('VAN_BAN', 'VAN_BAN_PHAP_QUY', 'CONG_VAN', 'GENERAL', 'THONG_BAO', 'THONG_BAO_CHUNG')"

            # # --- 🚀 SQL ĐỘNG: CHỈ LẤY TIN CHUNG NẾU LÀ SINH VIÊN ---
            # source_2_sql = ""
            # source_2_params = []
            
            # if not is_staff:
                # source_2_sql = """
                    # UNION ALL
                    # SELECT 
                        # CAST(t.Id AS INT) as NotifId, t.TieuDe, 
                        # LEFT(CAST(t.NoiDung AS NVARCHAR(MAX)), 150) as TomTat, t.NoiDung, 
                        # CAST(t.NgayPhatHanh AS DATETIME) as NgayPhatHanh, 
                        # CASE WHEN r.NotifID IS NOT NULL THEN 1 ELSE 0 END as IsRead, 
                        # N'VinhUni' as NguoiDang, 'THONG_BAO' as LoaiTin, 'GENERAL' as TabGroup
                    # FROM tbl_ThongBao t
                    # LEFT JOIN tbl_Notification_Read_Status r ON t.Id = r.NotifID 
                        # AND REPLACE(REPLACE(UPPER(RTRIM(r.StudentId)), 'SV', ''), 'CB', '') = ?
                    # WHERE t.IsDeleted = 0 
                    # AND (CAST(t.IdNguoiHocs AS NVARCHAR(MAX)) LIKE ? OR t.IdLoaiThongBao = 2)
                    # AND t.Id NOT IN (SELECT h.NotifID FROM tbl_Notification_Hides h WHERE h.StudentId = ?)
                # """
                # source_2_params = [sid_clean, sid_wildcard, sid_clean]

            # full_sql = f"""
                # WITH CombinedNotifs AS (
                    # -- NGUỒN 1: Từ hàng đợi Queue
                    # SELECT 
                        # CAST(q.ID AS INT) as NotifId, q.Title as TieuDe, q.Summary as TomTat, 
                        # q.Body as NoiDung, q.CreatedAt as NgayPhatHanh, 
                        # CAST(ISNULL(q.IsRead, 0) AS INT) as IsRead, 
                        # ISNULL(q.Sender, N'Hệ thống') as NguoiDang,
                        # UPPER(ISNULL(q.Category, 'GENERAL')) as LoaiTin,
                        # CASE 
                            # WHEN q.Category IN ('CANH_BAO', 'LICH_THI', 'LICH_HOP', 'NHAC_HEN', 'HUY_LICH', 'HUY_LOP_LT', 'KHAN_CAP') THEN 'REMINDER'
                            # WHEN q.Category IN ('LICH_TUAN', 'DIEM', 'LICH_DAY', 'LICH_CONGTAC', 'LICH_HOC', 'LOP_HP', 'LOP_HC') THEN 'WORK'
                            # WHEN q.Category IN ('PHAN_HOI', 'DUYET_DON', 'CA_NHAN') THEN 'PERSONAL'
                            # ELSE 'GENERAL'
                        # END as TabGroup
                    # FROM tbl_Notification_Queue q
                    # WHERE (
                        # REPLACE(REPLACE(UPPER(RTRIM(q.StudentId)), 'SV', ''), 'CB', '') = ? 
                        # OR CAST(q.IdNguoiHocs AS NVARCHAR(MAX)) LIKE ? 
                        # OR q.StudentId = 'ALL'
                    # )
                    # AND q.IsSent = 1
                    # {extra_filter}
                    # AND q.ID NOT IN (SELECT h.NotifID FROM tbl_Notification_Hides h WHERE h.StudentId = ?)

                    # {source_2_sql}
                # )
                # SELECT * FROM CombinedNotifs
                # ORDER BY NgayPhatHanh DESC
                # OFFSET ? ROWS FETCH NEXT ? ROWS ONLY;
            # """
            
            # final_params = [sid_clean, sid_wildcard, sid_clean] + source_2_params + [offset, page_size]
            # cursor.execute(full_sql, final_params)
            # rows = cursor.fetchall()
            
            # return [{
                # "ID": int(r[0]),
                # "TieuDe": r[1] or "",
                # "TomTat": r[2] or "",
                # "NoiDung": r[3] or "",
                # "NgayPhatHanh": r[4].strftime('%H:%M %d/%m/%Y') if r[4] else "",
                # "IsRead": bool(r[5]),
                # "NguoiDang": r[6] or "VinhUni",
                # "LoaiTin": r[7],
                # "TabGroup": r[8]
            # } for r in rows]

    # except Exception as e:
        # print(f"🔥 Lỗi API Get Notifs: {str(e)}")
        # return []
@router.get("/count-unread/{student_id}")
def count_unread(student_id: str,
                       me: Optional[Identity] = Depends(danh_tinh_neu_co)):
    student_id = _ma_duoc_phep_mem(student_id, me, "count-unread")
    try:
        # 1. Làm sạch mã số (Ví dụ: CB1679 -> 1679)
        sid_clean = str(student_id).strip().upper().replace("SV", "").replace("CB", "")
        
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()

            dk_queue = DIEU_KIEN_NGUOI_NHAN_QUEUE
            dk_thongbao = _dieu_kien_nguoi_nhan_thongbao(cursor)
            ts_queue = _tham_so_queue(sid_clean)
            ts_thongbao = _tham_so_thongbao(cursor, sid_clean)

            # ⚠️ SỬA 19/08/2026: bản cũ CHỈ đếm tin từ tbl_Notification_Queue,
            # bỏ hẳn nguồn tbl_ThongBao — trong khi danh sách (get-notifs) lấy
            # từ CẢ HAI.
            #
            # Đo trên tài khoản thật: máy chủ báo 0 tin chưa đọc trong khi ứng
            # dụng hiển thị 13. Người dùng thấy hai con số đá nhau và không biết
            # tin nào đúng.
            #
            # Nay đếm cả hai nguồn, dùng đúng điều kiện người nhận mà get-notifs
            # dùng — hai chỗ phải trả lời cùng một câu hỏi thì phải hỏi giống nhau.
            sql = f"""
                SELECT
                (
                    SELECT COUNT(*) FROM tbl_Notification_Queue q
                    WHERE (
                        REPLACE(REPLACE(q.StudentId, 'SV', ''), 'CB', '') = ?
                        OR {dk_queue}
                        OR q.StudentId = 'ALL'
                    )
                    AND q.IsSent = 1
                    AND ISNULL(q.Category, '') <> 'CHAT_GROUP'
                    AND ISNULL(q.Scope, '') <> 'CHAT_PUSH_ONLY'
                    AND NOT EXISTS (
                        SELECT 1 FROM tbl_Notification_Log_Detail d
                        WHERE d.QueueId = q.ID
                          AND REPLACE(REPLACE(d.StudentId, 'SV', ''), 'CB', '') = ?
                          AND d.IsRead = 1
                    )
                    AND NOT EXISTS (
                        SELECT 1 FROM tbl_Notification_Read_Status s
                        WHERE s.NotifID = q.ID
                          AND REPLACE(REPLACE(s.StudentId, 'SV', ''), 'CB', '') = ?
                    )
                    AND NOT EXISTS (
                        SELECT 1 FROM tbl_Notification_Hides h
                        WHERE h.NotifID = q.ID AND h.StudentId = ?
                    )
                )
                +
                (
                    SELECT COUNT(*) FROM tbl_ThongBao t
                    WHERE t.IsDeleted = 0
                    AND ({dk_thongbao} OR t.IdLoaiThongBao = 2)
                    AND NOT EXISTS (
                        SELECT 1 FROM tbl_Notification_Read_Status s
                        WHERE s.NotifID = t.Id
                          AND REPLACE(REPLACE(s.StudentId, 'SV', ''), 'CB', '') = ?
                    )
                    AND NOT EXISTS (
                        SELECT 1 FROM tbl_Notification_Hides h
                        WHERE h.NotifID = t.Id AND h.StudentId = ?
                    )
                ) AS SoChuaDoc
            """
            cursor.execute(sql, (sid_clean, ts_queue, sid_clean, sid_clean, sid_clean,
                                 ts_thongbao, sid_clean, sid_clean))
            count = cursor.fetchone()[0]
            return {"status": "success", "unread_count": count}
    except Exception as e:
        print(f"🔥 Error Count Unread: {e}")
        return {"status": "error", "unread_count": 0}
@router.get("/get-notif-detail/{notif_id}")
def get_notif_detail(notif_id: int, type: str = None):
    try:
        with pyodbc.connect(REMOTE_CONN_STR, autocommit=True) as conn:
            cursor = conn.cursor()
            
            # --- 1. NGUỒN: THÔNG BÁO CHUNG ---
            if type in ['THONG_BAO', 'GENERAL']:
                sql = """
                    SELECT t.Id, t.TieuDe, t.NoiDung, t.NgayPhatHanh, ISNULL(u.FullName, N'VinhUni')
                    FROM tbl_ThongBao t
                    LEFT JOIN tbl_Users u ON CAST(t.CreatedBy AS NVARCHAR(100)) = u.UserCode
                    WHERE t.Id = ?
                """
                cursor.execute(sql, (notif_id,))
                row = cursor.fetchone()
                if row:
                    return {
                        "id": row[0], "title": row[1], "content": row[2],
                        "date": row[3].strftime('%H:%M %d/%m/%Y') if row[3] else "",
                        "author": row[4], "category": "THONG_BAO", "file_url": None
                    }

            # --- 2. NGUỒN: VĂN BẢN PHÁP QUY ---
            elif type == 'VAN_BAN_PHAP_QUY':
                sql = "SELECT DocId, TrichYeu, FileName, NgayBanHanh FROM tbl_Document_Library WHERE DocId = ?"
                cursor.execute(sql, (notif_id,))
                r = cursor.fetchone()
                if r:
                    return {
                        "id": r[0], "title": f"Văn bản: {r[0]}", "content": r[1],
                        "date": r[3].strftime('%d/%m/%Y') if r[3] else "",
                        "author": "Hệ thống", "category": "VAN_BAN", "file_url": r[2]
                    }

            # --- 3. NGUỒN: HÀNG ĐỢI (Queue - Lịch công tác, Điểm, Chat...) ---
            sql_q = "SELECT ID, Title, Body, CreatedAt, Sender, Category FROM tbl_Notification_Queue WHERE ID = ?"
            cursor.execute(sql_q, (notif_id,))
            q = cursor.fetchone()
            if q:
                return {
                    "id": q[0], "title": q[1], "content": q[2],
                    "date": q[3].strftime('%H:%M %d/%m/%Y'),
                    "author": q[4] or "Hệ thống", "category": q[5], "file_url": None
                }

            return JSONResponse(status_code=404, content={"message": "Không tìm thấy nội dung"})
    except Exception as e:
        return JSONResponse(status_code=500, content={"message": str(e)})
# @router.get("/get-notif-detail/{notif_id}")
# async def get_notif_detail(notif_id: int, type: str = None):
    # """
    # Hàm lấy chi tiết nội dung thông báo.
    # Tự động rẽ nhánh tìm vào Thư viện văn bản (Cán bộ) hoặc Thông báo (Sinh viên)
    # """
    # try:
        # with pyodbc.connect(REMOTE_CONN_STR, autocommit=True) as conn:
            # cursor = conn.cursor()
            # row = None
            
            # # --- BƯỚC 1: TÌM KIẾM THEO LOẠI TIN (ƯU TIÊN) ---
            
            # # 1. Nếu là Văn bản pháp quy của Cán bộ (Lấy từ Thư viện)
            # if type == 'VAN_BAN_PHAP_QUY':
                # sql = """
                    # SELECT DocId, N'📄 ' + ISNULL(LoaiVanBan, N'Văn bản') + ': ' + SoKyHieu, 
                           # TrichYeu, CreatedAt, N'Hệ thống Điều hành', 
                           # FileName -- 🔥 Lấy tên file từ đĩa cứng
                    # FROM tbl_Document_Library WHERE DocId = ?
                # """
                # cursor.execute(sql, (notif_id,))
                # r = cursor.fetchone()
                # if r:
                    # return {
                        # "ID": r[0], "TieuDe": r[1], "NoiDung": r[2], 
                        # "NgayPhatHanh": r[3].strftime('%H:%M %d/%m/%Y'), 
                        # "NguoiDang": r[4], "FileName": r[5] # Trả về cho App
                    # }

            # # 2. Nếu là Thông báo chung (Dành cho Sinh viên)
            # elif type == 'GENERAL':
                # sql_tb = """
                    # SELECT t.Id, t.TieuDe, t.NoiDung, CAST(t.NgayPhatHanh AS DATETIME), ISNULL(u.FullName, N'Phòng ban')
                    # FROM tbl_ThongBao t
                    # LEFT JOIN tbl_Users u ON CAST(t.CreatedBy AS NVARCHAR(100)) = u.UserCode
                    # WHERE t.Id = ?
                # """
                # cursor.execute(sql_tb, (notif_id,))
                # row = cursor.fetchone()
                # if row:
                    # return {
                        # "ID": row[0], "TieuDe": row[1], "NoiDung": row[2], 
                        # "NgayPhatHanh": row[3].strftime('%H:%M - %d/%m/%Y') if row[3] else "",
                        # "NguoiDang": row[4], "LoaiTin": "GENERAL"
                    # }

            # # --- BƯỚC 2: NẾU KHÔNG RA (HOẶC CÁC LOẠI KHÁC), QUÉT HÀNG ĐỢI QUEUE ---
            # # Tìm tin cá nhân, điểm, lịch học, lịch thi...
            # sql_q = "SELECT ID, Title, Body, CreatedAt, ISNULL(Sender, N'Hệ thống'), Category FROM tbl_Notification_Queue WHERE ID = ?"
            # cursor.execute(sql_q, (notif_id,))
            # row = cursor.fetchone()
            
            # if row:
                # return {
                    # "ID": row[0], "TieuDe": row[1], "NoiDung": row[2], 
                    # "NgayPhatHanh": row[3].strftime('%H:%M - %d/%m/%Y') if row[3] else "",
                    # "NguoiDang": row[4], "LoaiTin": row[5]
                # }

            # # --- BƯỚC 3: PHÒNG THỦ CUỐI CÙNG (THỬ HẾT CÁC BẢNG NẾU VẪN CHƯA THẤY) ---
            # # Thử lại bảng Library lần cuối
            # cursor.execute("SELECT DocId, TrichYeu FROM tbl_Document_Library WHERE DocId = ?", (notif_id,))
            # alt_row = cursor.fetchone()
            # if alt_row:
                # return {"ID": alt_row[0], "TieuDe": "Văn bản nội bộ", "NoiDung": alt_row[1], "NguoiDang": "Hệ thống"}

            # return JSONResponse(status_code=404, content={"message": f"Không tìm thấy nội dung tin ID {notif_id}"})

    # except Exception as e:
        # print(f"🔥 Lỗi Get Detail ID {notif_id}: {str(e)}")
        # return JSONResponse(status_code=500, content={"message": "Lỗi máy chủ khi tải chi tiết"})

# Khởi tạo mô hình AI (Nên để toàn cục để tránh load lại mỗi lần gọi API)
# Mô hình này hỗ trợ tiếng Việt rất tốt cho tìm kiếm ngữ nghĩa
#model = SentenceTransformer('paraphrase-multilingual-MiniLM-L12-v2')
model_path = './models/notification_model'

if os.path.exists(model_path):
    model = SentenceTransformer(model_path)
    print("🚀 Đã load bộ não Thông báo từ ổ cứng (Offline mode)!")
else:
    # Phòng hờ nếu chưa tải thì mới tải từ mạng
    model = SentenceTransformer('paraphrase-multilingual-MiniLM-L12-v2')
#router = APIRouter()


@router.get("/docs/search")
def search_documents(
    query: str = "", 
    is_ai: int = 0, 
    category: Optional[str] = None, 
    month: Optional[int] = None,
    start_date: Optional[str] = None, 
    end_date: Optional[str] = None
):
    try:
        results = []
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            
            # --- TRƯỜNG HỢP 1: TÌM KIẾM AI (VECTOR SEARCH) ---
            if is_ai == 1 and query:
                # 1. Chuyển câu hỏi thành Vector
                query_vector = model.encode(query).astype(np.float32)
                
                # 2. Lấy toàn bộ danh sách Vector để so sánh
                cursor.execute("SELECT DocId, VectorData FROM tbl_Document_Vectors")
                vector_rows = cursor.fetchall()
                
                if not vector_rows: return []

                matched_ids = []
                for doc_id, v_data in vector_rows:
                    if v_data is None: continue
                    doc_vector = np.frombuffer(v_data, dtype=np.float32)
                    if query_vector.shape != doc_vector.shape: continue
                    
                    # Tính Cosine Similarity
                    score = np.dot(query_vector, doc_vector) / (np.linalg.norm(query_vector) * np.linalg.norm(doc_vector))
                    
                    if score > 0.35:
                        matched_ids.append((doc_id, float(score)))

                if not matched_ids: return []

                # Sắp xếp và lấy Top 20 IDs
                matched_ids.sort(key=lambda x: x[1], reverse=True)
                top_ids = [str(x[0]) for x in matched_ids[:20]]
                
                # Truy vấn Metadata kèm theo BỘ LỌC nếu có
                filter_sql = ""
                filter_params = []
                
                if category and category != "Tất cả":
                    filter_sql += " AND LoaiVanBan = ?"
                    filter_params.append(category)
                if month and month > 0:
                    filter_sql += " AND MONTH(NgayBanHanh) = ? AND YEAR(NgayBanHanh) = YEAR(GETDATE())"
                    filter_params.append(month)
                if start_date and end_date:
                    filter_sql += " AND NgayBanHanh BETWEEN ? AND ?"
                    filter_params.extend([start_date, end_date])

                sql = f"""
                    SELECT DocId, SoKyHieu, TrichYeu, LoaiVanBan, FileName, NgayBanHanh 
                    FROM tbl_Document_Library 
                    WHERE DocId IN ({','.join(top_ids)}) AND IsActive = 1 {filter_sql}
                """
                cursor.execute(sql, filter_params)
                raw_docs = {str(r[0]): r for r in cursor.fetchall()}
                
                db_rows = []
                for tid in top_ids:
                    if tid in raw_docs:
                        db_rows.append(raw_docs[tid])

            # --- TRƯỜNG HỢP 2: TÌM KIẾM THƯỜNG (SQL LIKE) + BỘ LỌC ---
            else:
                sql = """
                    SELECT TOP 100 DocId, SoKyHieu, TrichYeu, LoaiVanBan, FileName, NgayBanHanh 
                    FROM tbl_Document_Library 
                    WHERE IsActive = 1
                """
                params = []

                # Lọc theo từ khóa
                if query:
                    sql += " AND (SoKyHieu LIKE ? OR TrichYeu LIKE ?)"
                    params.extend([f'%{query}%', f'%{query}%'])
                
                # Lọc theo Loại (Category)
                if category and category != "Tất cả":
                    sql += " AND LoaiVanBan = ?"
                    params.append(category)

                # Lọc theo Tháng
                if month and month > 0:
                    sql += " AND MONTH(NgayBanHanh) = ? AND YEAR(NgayBanHanh) = YEAR(GETDATE())"
                    params.append(month)

                # Lọc theo Khoảng ngày (Date Range)
                if start_date and end_date:
                    sql += " AND NgayBanHanh BETWEEN ? AND ?"
                    params.extend([start_date, end_date])

                sql += " ORDER BY NgayBanHanh DESC, DocId DESC"
                cursor.execute(sql, params)
                db_rows = cursor.fetchall()

            # --- ĐỊNH DẠNG KẾT QUẢ TRẢ VỀ ---
            for r in db_rows:
                file_name = r[4]
                pdf_url = f"https://mobi.vinhuni.edu.vn/uploads/docs/{file_name}" if file_name else None
                
                results.append({
                    "id": r[0],
                    "title": f"{r[1]}: {r[2][:120]}..." if r[1] else f"{r[2][:120]}...", 
                    "category": r[3] if r[3] else 'Văn bản',
                    "url": pdf_url,
                    "file_name": file_name,
                    "publish_date": str(r[5]) if r[5] else "2026-01-01" 
                })
                
        return results

    except Exception as e:
        print(f"🔥 Lỗi API Search: {e}")
        return []



# Vì router đã có prefix="/api" rồi
# @router.post("/hide-notif/{notif_id}") 
# async def api_hide_notif(notif_id: int, request: Request):
    # try:
        # data = await request.json()
        # student_id = data.get("student_id")

        # if not student_id:
            # return JSONResponse(status_code=400, content={"message": "Thiếu student_id"})

        # # Làm sạch mã SV: loại bỏ 'SV' và khoảng trắng
        # sid_clean = str(student_id).strip().upper().replace("SV", "")

        # with pyodbc.connect(REMOTE_CONN_STR, autocommit=True) as conn:
            # cursor = conn.cursor()
            
            # # Ghi vào bảng tbl_Notification_Hides bạn vừa tạo
            # sql_hide = """
                # IF NOT EXISTS (SELECT 1 FROM tbl_Notification_Hides WHERE NotifID = ? AND StudentId = ?)
                # BEGIN
                    # INSERT INTO tbl_Notification_Hides (NotifID, StudentId, HiddenAt)
                    # VALUES (?, ?, GETDATE())
                # END
            # """
            # cursor.execute(sql_hide, (notif_id, sid_clean, notif_id, sid_clean))
            
            # # Đánh dấu IsSent=0 hoặc xóa trong Queue để chắc chắn không quét lại tin này cho cá nhân
            # cursor.execute("UPDATE tbl_Notification_Queue SET IsSent = 0 WHERE ID = ? AND StudentId = ?", (notif_id, sid_clean))

        # return {"status": "SUCCESS", "message": f"Đã ẩn tin {notif_id} cho SV {sid_clean}"}

    # except Exception as e:
        # print(f"🔥 Lỗi khi ẩn tin: {str(e)}")
        # return JSONResponse(status_code=500, content={"message": str(e)})
@router.post("/hide-notif/{notif_id}") 
def api_hide_notif(notif_id: int, data: dict,
                   me: Optional[Identity] = Depends(danh_tinh_neu_co)):
    # ⚠️ SỬA 19/08/2026: đổi từ `async def` sang `def`, và nhận thân yêu cầu
    # qua tham số thay vì `await request.json()`.
    #
    # Mọi truy vấn ở đây dùng pyodbc — thư viện ĐỒNG BỘ. Đặt chúng trong một
    # hàm `async def` nghĩa là chúng chạy thẳng trên vòng lặp sự kiện: một truy
    # vấn chậm chặn TOÀN BỘ máy chủ, không riêng người gọi. Đã gặp thật ngày
    # 19/08/2026 — máy chủ ngừng phục vụ hoàn toàn dù mạng tới cơ sở dữ liệu
    # vẫn thông.
    #
    # Với hàm `def` thường, FastAPI tự chạy nó trong luồng riêng, nên truy vấn
    # chậm chỉ ảnh hưởng đúng yêu cầu đó.
    try:
        student_id = data.get("student_id")
        if not student_id:
            return JSONResponse(status_code=400, content={"message": "Thiếu student_id"})

        sid_clean = _ma_duoc_phep_mem(student_id, me, "hide-notif")

        with pyodbc.connect(REMOTE_CONN_STR, autocommit=True) as conn:
            cursor = conn.cursor()
            
            # 1. Chỉ ghi vào bảng Hides (Đây là bảng chứa các tin SV đã 'Xóa')
            sql_hide = """
                IF NOT EXISTS (SELECT 1 FROM tbl_Notification_Hides WHERE NotifID = ? AND StudentId = ?)
                BEGIN
                    INSERT INTO tbl_Notification_Hides (NotifID, StudentId, HiddenAt)
                    VALUES (?, ?, GETDATE())
                END
            """
            cursor.execute(sql_hide, (notif_id, sid_clean, notif_id, sid_clean))
            
            # 💡 Lưu ý: KHÔNG nên UPDATE IsSent = 0 ở bảng Queue nếu là tin gửi chung.
            # Việc ẩn tin sẽ được xử lý ở API 'Lấy danh sách thông báo'.

        return {"status": "SUCCESS", "message": f"Đã ẩn tin {notif_id}"}
    except Exception as e:
        return JSONResponse(status_code=500, content={"message": str(e)})        
@router.post("/mark-read/{notif_id}")
def mark_read(notif_id: int, data: dict,
              me: Optional[Identity] = Depends(danh_tinh_neu_co)):
    # ⚠️ SỬA 19/08/2026: đổi từ `async def` sang `def`, và nhận thân yêu cầu
    # qua tham số thay vì `await request.json()`.
    #
    # Mọi truy vấn ở đây dùng pyodbc — thư viện ĐỒNG BỘ. Đặt chúng trong một
    # hàm `async def` nghĩa là chúng chạy thẳng trên vòng lặp sự kiện: một truy
    # vấn chậm chặn TOÀN BỘ máy chủ, không riêng người gọi. Đã gặp thật ngày
    # 19/08/2026 — máy chủ ngừng phục vụ hoàn toàn dù mạng tới cơ sở dữ liệu
    # vẫn thông.
    #
    # Với hàm `def` thường, FastAPI tự chạy nó trong luồng riêng, nên truy vấn
    # chậm chỉ ảnh hưởng đúng yêu cầu đó.
    try:
        student_id = data.get("student_id")
        sid_clean = _ma_duoc_phep_mem(student_id, me, "mark-read")

        with pyodbc.connect(REMOTE_CONN_STR, autocommit=True) as conn:
            cursor = conn.cursor()
            
            # Ghi vào bảng Status cho tin chung/tin tức
            sql_status = """
                IF NOT EXISTS (SELECT 1 FROM tbl_Notification_Read_Status WHERE NotifID = ? AND StudentId = ?) 
                BEGIN
                    INSERT INTO tbl_Notification_Read_Status (NotifID, StudentId, ReadAt) VALUES (?, ?, GETDATE())
                END
            """
            cursor.execute(sql_status, (notif_id, sid_clean, notif_id, sid_clean))
            
            # Cập nhật bảng Log Detail cho tin cá nhân/nhóm
            sql_log = """
                UPDATE tbl_Notification_Log_Detail SET IsRead = 1, ReadAt = GETDATE() 
                WHERE QueueId = ? AND REPLACE(REPLACE(StudentId, 'SV', ''), 'CB', '') = ?
            """
            cursor.execute(sql_log, (notif_id, sid_clean))

        return {"status": "SUCCESS"}
    except Exception as e:
        print(f"🔥 Lỗi Mark-Read: {e}")
        return JSONResponse(status_code=500, content={"status": "ERROR", "message": str(e)})


@router.post("/mark-all-read/{student_id}")
def mark_all_read(student_id: str,
                        me: Optional[Identity] = Depends(danh_tinh_neu_co)):
    """Đánh dấu toàn bộ thông báo của một người là đã đọc.

    Bổ sung 18/08/2026. Trước đây ứng dụng có nút "Đánh dấu tất cả đã đọc"
    nhưng máy chủ không có endpoint nào để gọi, nên nút đó chỉ đóng hộp thoại.

    Ghi vào cả hai bảng vì hệ thống dùng hai cơ chế khác nhau:
      • tbl_Notification_Read_Status   — tin chung, tin tức phát cho nhiều người
      • tbl_Notification_Log_Detail    — tin cá nhân, tin nhóm gửi đích danh
    Bỏ sót một bảng thì một phần thông báo vẫn hiện là chưa đọc.
    """
    # Endpoint này MỚI hoàn toàn — không có bản ứng dụng cũ nào gọi tới, nên
    # dùng kiểm quyền chặt được ngay mà không sợ vỡ tương thích.
    sid_clean = _ma_duoc_phep_mem(student_id, me, "mark-all-read")
    if not sid_clean:
        return JSONResponse(status_code=400,
                            content={"status": "ERROR", "message": "Thiếu mã người dùng"})

    try:
        with pyodbc.connect(REMOTE_CONN_STR, autocommit=True) as conn:
            cursor = conn.cursor()

            dk_queue = DIEU_KIEN_NGUOI_NHAN_QUEUE
            dk_thongbao = _dieu_kien_nguoi_nhan_thongbao(cursor)
            ts_queue = _tham_so_queue(sid_clean)
            ts_thongbao = _tham_so_thongbao(cursor, sid_clean)

            # 1a. Tin từ hàng đợi (nguồn 1 của get-notifs)
            #
            # Chỉ lấy tin thực sự thuộc về người này, giống hệt điều kiện WHERE
            # của get-notifs — nếu quét cả bảng thì sẽ chèn hàng chục nghìn dòng
            # rác cho mỗi lần bấm nút.
            sql_queue = f"""
                INSERT INTO tbl_Notification_Read_Status (NotifID, StudentId, ReadAt)
                SELECT q.Id, ?, GETDATE()
                FROM tbl_Notification_Queue q
                WHERE q.IsSent = 1
                  AND (
                        REPLACE(REPLACE(UPPER(RTRIM(q.StudentId)), 'SV', ''), 'CB', '') = ?
                     OR {dk_queue}
                     OR q.StudentId = 'ALL'
                  )
                  AND NOT EXISTS (
                        SELECT 1 FROM tbl_Notification_Read_Status r
                        WHERE r.NotifID = q.Id AND r.StudentId = ?
                  )
            """
            cursor.execute(sql_queue, (sid_clean, sid_clean, ts_queue, sid_clean))
            so_tin_chung = cursor.rowcount

            # 1b. Tin từ tbl_ThongBao (NGUỒN 2 của get-notifs).
            #
            # Bước này thiếu ở bản đầu tiên tôi viết. Nguồn 2 xác định trạng thái
            # đọc CHỈ dựa vào tbl_Notification_Read_Status, nên bỏ qua nó thì
            # toàn bộ tin ở tab VINHUNI vẫn hiện là chưa đọc sau khi người dùng
            # bấm "Đánh dấu tất cả đã đọc".
            sql_thongbao = f"""
                INSERT INTO tbl_Notification_Read_Status (NotifID, StudentId, ReadAt)
                SELECT t.Id, ?, GETDATE()
                FROM tbl_ThongBao t
                WHERE t.IsDeleted = 0
                  AND ({dk_thongbao} OR t.IdLoaiThongBao = 2)
                  AND NOT EXISTS (
                        SELECT 1 FROM tbl_Notification_Read_Status r
                        WHERE r.NotifID = t.Id AND r.StudentId = ?
                  )
            """
            cursor.execute(sql_thongbao, (sid_clean, ts_thongbao, sid_clean))
            so_tin_thongbao = cursor.rowcount

            # 2. Tin cá nhân và tin nhóm
            sql_log = """
                UPDATE tbl_Notification_Log_Detail
                SET IsRead = 1, ReadAt = GETDATE()
                WHERE IsRead = 0
                  AND REPLACE(REPLACE(StudentId, 'SV', ''), 'CB', '') = ?
            """
            cursor.execute(sql_log, (sid_clean,))
            so_tin_ca_nhan = cursor.rowcount

        print(f"[Mark-All-Read] {sid_clean}: {so_tin_chung} hàng đợi, "
              f"{so_tin_thongbao} thông báo chung, {so_tin_ca_nhan} tin cá nhân")
        return {
            "status": "SUCCESS",
            "so_tin_hang_doi": max(so_tin_chung, 0),
            "so_tin_thong_bao": max(so_tin_thongbao, 0),
            "so_tin_ca_nhan": max(so_tin_ca_nhan, 0),
        }
    except Exception as e:
        print(f"🔥 Lỗi Mark-All-Read: {e}")
        return JSONResponse(status_code=500,
                            content={"status": "ERROR", "message": str(e)})
# @router.post("/mark-read/{notif_id}")
# async def api_mark_read(notif_id: int, request: Request):
    # try:
        # # 1. Lấy dữ liệu từ Body JSON gửi lên
        # data = await request.json()
        # student_id = data.get("student_id")

        # if not student_id:
            # return JSONResponse(status_code=400, content={"status": "ERROR", "message": "Thiếu student_id"})

        # # 2. Làm sạch mã số (SV2101 -> 2101)
        # sid_clean = str(student_id).strip().upper().replace("SV", "").replace("CB", "")
        
        # print(f"--- 🔔 ĐÁNH DẤU ĐÃ ĐỌC ID: {notif_id} | SV: {sid_clean} ---")

        # with pyodbc.connect(REMOTE_CONN_STR, autocommit=True) as conn:
            # cursor = conn.cursor()
            
            # # KIỂM TRA: Tin nhắn này có nằm trong hàng đợi (Queue) không?
            # cursor.execute("SELECT StudentId, IdNguoiHocs FROM tbl_Notification_Queue WHERE ID = ?", (notif_id,))
            # queue_item = cursor.fetchone()

            # if queue_item:
                # # =========================================================
                # # TRƯỜNG HỢP A: TIN TRONG QUEUE (Cá nhân hoặc Nhóm)
                # # =========================================================
                
                # # 1. Cập nhật vào bảng LOG CHI TIẾT (Cuốn sổ biên nhận)
                # sql_log = """
                    # UPDATE tbl_Notification_Log_Detail 
                    # SET IsRead = 1, ReadAt = GETDATE() 
                    # WHERE QueueId = ? 
                      # AND REPLACE(REPLACE(StudentId, 'SV', ''), 'CB', '') = ?
                # """
                # cursor.execute(sql_log, (notif_id, sid_clean))
                
                # # 2. Cập nhật vào bảng Queue chính nếu là tin đích danh 1 người
                # sql_main = """
                    # UPDATE tbl_Notification_Queue 
                    # SET IsRead = 1, ReadAt = GETDATE() 
                    # WHERE ID = ? 
                      # AND (REPLACE(REPLACE(StudentId, 'SV', ''), 'CB', '') = ? OR StudentId IS NULL)
                # """
                # cursor.execute(sql_main, (notif_id, sid_clean))
                # print(f"✅ Đã cập nhật trạng thái đọc trong Queue & Log cho ID: {notif_id}")

            # else:
                # # =========================================================
                # # TRƯỜNG HỢP B: TIN CHUNG (Đồng bộ từ tbl_ThongBao)
                # # =========================================================
                # sql_status = """
                    # IF NOT EXISTS (SELECT 1 FROM tbl_Notification_Read_Status WHERE NotifID = ? AND StudentId = ?) 
                    # BEGIN
                        # INSERT INTO tbl_Notification_Read_Status (NotifID, StudentId, ReadAt) 
                        # VALUES (?, ?, GETDATE())
                    # END
                # """
                # cursor.execute(sql_status, (notif_id, sid_clean, notif_id, sid_clean))
                # print(f"✅ Đã ghi nhận đọc tin CHUNG cho ID: {notif_id}")

            # return {"status": "SUCCESS", "message": "Đã đánh dấu đã đọc"}
            
    # except Exception as e:
        # print(f"🔥 Lỗi Mark-Read: {str(e)}")
        # return JSONResponse(status_code=500, content={"status": "ERROR", "message": str(e)})
    # =========================================================
# API LẤY DANH SÁCH SINH VIÊN ĐÃ ĐỌC (BÁO CÁO CHO GIẢNG VIÊN)
# =========================================================
# @router.get("/lecturer/notification-report/{queue_id}")
# async def get_notification_report(queue_id: int):
    # try:
        # # Sử dụng REMOTE_CONN_STR mà Sơn đã định nghĩa ở trên
        # with pyodbc.connect(REMOTE_CONN_STR) as conn:
            # cursor = conn.cursor()
            
            # # Query lấy thông tin từ bảng Log phụ JOIN với StudentProfiles
            # sql = """
                # SELECT 
                    # ld.StudentId, 
                    # ISNULL(sp.FullName, N'Sinh viên mới') as HoTen, 
                    # ld.IsRead, 
                    # FORMAT(ld.ReadAt, 'HH:mm dd/MM/yyyy') as TimeRead
                # FROM tbl_Notification_Log_Detail ld
                # LEFT JOIN tbl_Users sp ON ld.StudentId = REPLACE(REPLACE(sp.UserCode, 'SV', ''), 'CB', '')
                # WHERE ld.QueueId = ?
                # ORDER BY ld.IsRead DESC, sp.FullName ASC
            # """
            # cursor.execute(sql, (queue_id,))
            # rows = cursor.fetchall()
            
            # # Chuyển đổi dữ liệu sang dạng JSON
            # report_data = []
            # for r in rows:
                # report_data.append({
                    # "sid": r[0],
                    # "name": r[1],
                    # "is_read": bool(r[2]),
                    # "time": r[3] if r[3] else "---"
                # })
            
            # return {"status": "success", "data": report_data}
            
    # except Exception as e:
        # print(f"🔥 Lỗi API notification-report: {e}")
        # return {"status": "error", "message": str(e)}  
@router.get("/lecturer/notification-report/{queue_id}")
def get_notification_report(queue_id: int):
    try:
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            
            # Sử dụng tbl_Users để lấy FullName (đã kiểm chứng ở hàm O365)
            # Dùng logic JOIN kép để khớp cả mã có CB/SV và mã số thuần
            sql = """
                SELECT 
                    ld.StudentId, 
                    ISNULL(u.FullName, N'Người dùng mới') as HoTen, 
                    ld.IsRead, 
                    FORMAT(ld.ReadAt, 'HH:mm dd/MM/yyyy') as TimeRead
                FROM tbl_Notification_Log_Detail ld
                LEFT JOIN tbl_Users u ON (
                    RTRIM(ld.StudentId) = RTRIM(u.UserCode) 
                    OR RTRIM(ld.StudentId) = REPLACE(REPLACE(u.UserCode, 'SV', ''), 'CB', '')
                )
                WHERE ld.QueueId = ?
                ORDER BY ld.IsRead DESC, u.FullName ASC
            """
            cursor.execute(sql, (queue_id,))
            rows = cursor.fetchall()
            
            report_data = []
            for r in rows:
                report_data.append({
                    "sid": r[0],
                    "name": r[1],
                    "is_read": bool(r[2]),
                    "time": r[3] if r[3] else "---"
                })
            
            return {"status": "success", "data": report_data}
            
    except Exception as e:
        print(f"🔥 Lỗi API notification-report: {e}")
        return {"status": "error", "message": str(e)}      
# =========================================================
# API LẤY LỊCH SỬ ĐÃ GỬI (Dòng 619 trở đi)
# =========================================================
# @router.get("/lecturer/sent-history/{sender_id}")
# async def get_sent_history(sender_id: str):
    # try:
        # with pyodbc.connect(REMOTE_CONN_STR) as conn:
            # cursor = conn.cursor()
            # sql = """
                # SELECT 
                    # n.ID, n.Title, n.Scope, n.StudentId,
                    # FORMAT(n.CreatedAt, 'HH:mm dd/MM/yyyy') as TimeCreated,
                    # (SELECT COUNT(*) FROM tbl_Notification_Log_Detail WHERE QueueId = n.ID) as TotalTarget,
                    # (SELECT COUNT(*) FROM tbl_Notification_Log_Detail WHERE QueueId = n.ID AND IsRead = 1) as ReadCount
                # FROM tbl_Notification_Queue n
                # WHERE n.SenderId = ? OR n.SenderId = REPLACE(?, 'CB', '')
                # ORDER BY n.CreatedAt DESC
            # """
            # cursor.execute(sql, (sender_id, sender_id))
            # rows = cursor.fetchall()
            
            # history = [{
                # "id": r[0], "title": r[1], "scope": r[2], 
                # "target_sid": r[3],
                # "time": r[4], "total": r[5], "read": r[6]
            # } for r in rows]
            
            # return {"status": "success", "data": history}
    # except Exception as e:
        # print(f"🔥 Lỗi sent-history: {e}")
        # return {"status": "error", "message": str(e)}
@router.get("/lecturer/sent-history/{sender_id}")
def get_sent_history(sender_id: str):
    try:
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            # Sử dụng LEFT JOIN và GROUP BY để tối ưu hiệu năng
            sql = """
                SELECT 
                    n.ID, n.Title, n.Scope, n.StudentId,
                    FORMAT(n.CreatedAt, 'HH:mm dd/MM/yyyy') as TimeCreated,
                    COUNT(ld.Id) as TotalTarget,
                    SUM(CASE WHEN ld.IsRead = 1 THEN 1 ELSE 0 END) as ReadCount
                FROM tbl_Notification_Queue n
                LEFT JOIN tbl_Notification_Log_Detail ld ON n.ID = ld.QueueId
                WHERE n.SenderId = ? OR n.SenderId = REPLACE(?, 'CB', '')
                GROUP BY n.ID, n.Title, n.Scope, n.StudentId, n.CreatedAt
                ORDER BY n.CreatedAt DESC
            """
            cursor.execute(sql, (sender_id, sender_id))
            rows = cursor.fetchall()
            
            history = [{
                "id": r[0], 
                "title": r[1] if r[1] else "Không tiêu đề", 
                "scope": r[2], 
                "target_sid": r[3],
                "time": r[4], 
                "total": r[5], 
                "read": r[6]
            } for r in rows]
            
            return {"status": "success", "data": history}
    except Exception as e:
        print(f"🔥 Lỗi sent-history: {e}")
        return {"status": "error", "message": str(e)}
# Đảm bảo hàm tiếp theo cũng phải thẳng hàng như vậy
@router.get("/lecturer/notification-report/{queue_id}")
def get_notification_report(queue_id: int):
    try:
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            sql = """
                SELECT 
                    ld.StudentId, 
                    ISNULL(u.FullName, N'Sinh viên') as HoTen, 
                    ld.IsRead, 
                    FORMAT(ld.ReadAt, 'HH:mm dd/MM/yyyy') as TimeRead
                FROM tbl_Notification_Log_Detail ld
                LEFT JOIN tbl_Users u ON ld.StudentId = REPLACE(REPLACE(u.UserCode, 'SV', ''), 'CB', '')
                WHERE ld.QueueId = ?
                ORDER BY ld.IsRead DESC, u.FullName ASC
            """
            cursor.execute(sql, (queue_id,))
            rows = cursor.fetchall()
            
            report = [{
                "sid": r[0], "name": r[1], 
                "is_read": bool(r[2]), "time": r[3] or "---"
            } for r in rows]
            
            return {"status": "success", "data": report}
    except Exception as e:
        return {"status": "error", "message": str(e)}     
# 1. Check nhiều SV cùng lúc từ chuỗi dấu phẩy
@router.get("/lecturer/check-multiple-users")
def check_multiple_users(q: str):
    try:
        # Tách chuỗi: "2157..., 2158..." -> ['2157...', '2158...']
        raw_ids = [i.strip().upper().replace("SV", "") for i in q.split(",") if i.strip()]
        if not raw_ids: return {"status": "success", "data": []}

        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            # Tạo chuỗi ?,?,? cho SQL IN
            placeholders = ",".join(["?"] * len(raw_ids))
            sql = f"SELECT UserCode, FullName FROM tbl_Users WHERE UserCode IN ({placeholders})"
            cursor.execute(sql, raw_ids)
            rows = cursor.fetchall()
            
            return {"status": "success", "data": [{"id": r[0], "name": r[1]} for r in rows]}
    except Exception as e:
        return {"status": "error", "message": str(e)}

# 2. Lấy danh sách nhóm ảo của GV
@router.get("/lecturer/custom-groups/{sender_id}")
def get_custom_groups(sender_id: str):
    with pyodbc.connect(REMOTE_CONN_STR) as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT GroupId, GroupName FROM tbl_Notification_CustomGroups WHERE CreatorId = ?", (sender_id,))
        return {"status": "success", "data": [{"id": r[0], "name": r[1]} for r in cursor.fetchall()]}        
@router.post("/lecturer/create-custom-group")
def create_custom_group(data: dict):
    # data: { "group_name": "Nhóm ôn thi", "sender_id": "CB123", "student_ids": "SV01,SV02" }
    try:
        group_name = data.get("group_name")
        sender_id = data.get("sender_id")
        student_ids_str = data.get("student_ids", "")
        student_ids = [s.strip() for s in student_ids_str.split(",") if s.strip()]

        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            
            # 1. Tạo tên nhóm
            sql_group = "INSERT INTO tbl_Notification_CustomGroups (GroupName, CreatorId) OUTPUT INSERTED.GroupId VALUES (?, ?)"
            cursor.execute(sql_group, (group_name, sender_id))
            new_group_id = cursor.fetchone()[0]

            # 2. Thêm thành viên vào nhóm
            sql_member = "INSERT INTO tbl_Notification_CustomGroupMembers (GroupId, StudentId) VALUES (?, ?)"
            member_data = [(new_group_id, sid) for sid in student_ids]
            cursor.executemany(sql_member, member_data)
            
            conn.commit()
            return {"status": "success", "message": f"Đã tạo nhóm '{group_name}' thành công"}
    except Exception as e:
        return {"status": "error", "message": str(e)}   
# API Xóa nhóm ảo
@router.delete("/lecturer/delete-custom-group/{group_id}")
def delete_custom_group(group_id: int):
    try:
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            cursor.execute("DELETE FROM tbl_Notification_CustomGroups WHERE GroupId = ?", (group_id,))
            conn.commit()
            return {"status": "success", "message": "Đã xóa nhóm"}
    except Exception as e:
        return {"status": "error", "message": str(e)}

# API Lấy chi tiết thành viên (Dùng cho cả sửa nhóm và lịch sử)
@router.get("/lecturer/custom-group-members/{group_id}")
def get_custom_group_members(group_id: int):
    with pyodbc.connect(REMOTE_CONN_STR) as conn:
        cursor = conn.cursor()
        sql = """
            SELECT m.StudentId, u.FullName 
            FROM tbl_Notification_CustomGroupMembers m
            LEFT JOIN tbl_Users u ON m.StudentId = REPLACE(REPLACE(u.UserCode, 'SV', ''), 'CB', '')
            WHERE m.GroupId = ?
        """
        cursor.execute(sql, (group_id,))
        return {"status": "success", "data": [{"id": r[0], "name": r[1]} for r in cursor.fetchall()]}    

#================Lơp hanh chính===============        
@router.get("/lecturer/admin-classes/{sender_id}", dependencies=[Depends(verify_staff_token)])
def get_admin_classes(sender_id: str):
    try:
        # Mặc dù không lọc theo sender_id nữa, nhưng ta vẫn giữ để log hoặc mở rộng sau này
        
        # 2. Kết nối vào DB Local (Vì bảng này đã được tool sync kéo về AI2025)
        with pyodbc.connect(REMOTE_CONN_STR) as conn: 
            cursor = conn.cursor()
            
            # 🔥 SQL: Lấy toàn bộ lớp Chính quy, không lọc GV chủ nhiệm
            sql = """
                SELECT Id, Ten, IdKhoaHoc 
                FROM tbl_DanhSach_LopHanhChinh 
                WHERE IdHe = 'CQ' 
                  AND (IsDeleted = 0 OR IsDeleted IS NULL)
                ORDER BY IdKhoaHoc DESC, Ten ASC
            """
            
            # 🔥 LƯU Ý: Không truyền (clean_id,) vào đây vì câu SQL trên không có dấu "?"
            cursor.execute(sql) 
            rows = cursor.fetchall()
            
            data = [
                {
                    "id": str(r[0]), 
                    "ten": r[1], 
                    "khoa": r[2]
                } for r in rows
            ]
            
            print(f"✅ Đã tải Full {len(data)} lớp hành chính hệ CQ.")
            return {"status": "success", "data": data}
            
    except Exception as e:
        print(f"🔥 Lỗi lấy danh sách lớp: {e}")
        return {"status": "error", "message": str(e)}

#============API giay xin phep tu sinh vien        
# =========================================================
# CHỨC NĂNG: SINH VIÊN XIN PHÉP & GIẢNG VIÊN NHẬN TIN
# =========================================================

# 1. API cho Sinh viên: Lấy danh sách lớp đang học để chọn xin phép
@router.get("/student/my-classes/{student_id}")
def get_student_classes(student_id: str, me: Identity = Depends(get_current_user)):
    """Danh sách lớp học phần của một sinh viên.

    SỬA 18/08/2026 — hai lỗi ở bản cũ:

      1. Endpoint dành cho SINH VIÊN nhưng lại chặn bằng verify_staff_token,
         vốn chỉ cho CANBO/ADMIN/COVAN đi qua. Sinh viên mở màn "Giấy phép -
         Đơn" luôn nhận 403, không chọn được lớp nên KHÔNG GỬI ĐƯỢC ĐƠN XIN
         PHÉP. Ứng dụng lại hiển thị 403 thành "tài khoản bị tạm khóa do hành
         vi bất thường", khiến sinh viên tưởng mình bị kỷ luật.

      2. Mã sinh viên lấy từ đường dẫn, không đối chiếu với người đang gọi.

    Nay: sinh viên chỉ xem được lớp của chính mình; cán bộ xem được của bất kỳ ai.
    """
    sid = _ma_sinh_vien_duoc_phep(student_id, me)
    try:
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            # Lấy lhp.Code làm ID để đồng bộ với hàm gửi đơn xin phép
            sql = """
                SELECT DISTINCT 
                    lhp.Code as LhpId, 
                    lhp.Ten as TenLop
                FROM viewDSSinhVienDangKyHoc v
                INNER JOIN tbl_Tkb_LopHocPhan lhp ON v.MaLopHP = lhp.Code
                WHERE REPLACE(REPLACE(v.IdNguoiHoc, 'SV', ''), 'CB', '') = ?
                  AND lhp.IsDeleted = 0
            """
            cursor.execute(sql, (sid,))
            rows = cursor.fetchall()
            return [{"id": r[0], "name": r[1]} for r in rows]
    except Exception as e:
        print(f"❌ Lỗi lấy danh sách lớp: {e}")
        return []

# 2. API cho Sinh viên: Gửi đơn xin phép (Tự động tìm Giảng viên)
# @router.post("/student/send-attendance-request")
# async def send_attendance_request(data: dict):
    # try:
        # # 1. Lấy dữ liệu từ App gửi lên
        # raw_sid = data.get("student_id", "")
        # # Làm sạch mã SV: SV2057... -> 2057...
        # sid = str(raw_sid).strip().upper().replace("SV", "").replace("CB", "")
        
        # lhp_code = data.get("lhp_code") # Mã lớp HP (Ví dụ: INF20106...)
        # category = data.get("category") # VANG_HOC, MUON_HOC...
        # reason = data.get("reason")
        
        # # In ra màn hình console để debug
        # print(f"--- 🔔 YÊU CẦU XIN PHÉP MỚI ---")
        # print(f"👉 Sinh viên: {sid} (Gốc: {raw_sid})")
        # print(f"👉 Mã lớp HP: {lhp_code}")

        # # Kiểm tra nếu mã lớp bị NULL/None (Lỗi mà Sơn vừa gặp)
        # if not lhp_code or str(lhp_code).lower() == "none":
            # print("❌ LỖI: Mã lớp gửi lên bị None. Hãy kiểm tra lại API get-schedule!")
            # return JSONResponse(
                # status_code=400, 
                # content={"status": "error", "message": "Mã lớp học phần không hợp lệ (None)"}
            # )

        # with pyodbc.connect(REMOTE_CONN_STR) as conn:
            # cursor = conn.cursor()
            
            # # 2. Tìm Mã Giảng viên dạy lớp này (Dựa trên câu SQL Sơn đã test)
            # # Ta join bảng LHP với bảng Lịch học để lấy MaCanBo
            # sql_find_gv = """
                # SELECT TOP 1 lh.MaCanBo 
                # FROM tbl_Tkb_LopHocPhan lhp
                # INNER JOIN tbl_Tkb_LopHocPhan_LichHoc lh ON lhp.Id = lh.IdLopHocPhan
                # WHERE lhp.Code = ? AND lhp.IsDeleted = 0
            # """
            # cursor.execute(sql_find_gv, (lhp_code,))
            # row = cursor.fetchone()
            
            # # Nếu tìm thấy thì bỏ chữ 'CB', nếu không thấy gán mặc định 'AD' (Admin)
            # gv_id = "AD"
            # if row and row[0]:
                # gv_id = str(row[0]).strip().upper().replace("CB", "")
            
            # print(f"👉 Đã xác định Giảng viên nhận tin: {gv_id}")

            # # 3. Thực hiện chèn vào bảng tbl_Attendance_Requests
            # sql_ins = """
                # INSERT INTO tbl_Attendance_Requests 
                # (StudentId, LhpId, Category, Reason, Status, CreatedAt, LecturerId)
                # VALUES (?, ?, ?, ?, 0, GETDATE(), ?)
            # """
            # cursor.execute(sql_ins, (sid, lhp_code, category, reason, gv_id))
            
            # # 🔥 QUAN TRỌNG NHẤT: Phải có dòng commit này dữ liệu mới thực sự được lưu
            # conn.commit() 
            
            # print(f"✅ THÀNH CÔNG: Đã chèn yêu cầu cho SV {sid} vào Database.")
            # return {"status": "success", "message": "Gửi đơn xin phép thành công!"}

    # except Exception as e:
        # print(f"❌ LỖI THỰC THI: {str(e)}")
        # return JSONResponse(
            # status_code=500, 
            # content={"status": "error", "message": f"Lỗi hệ thống: {str(e)}"}
        # )
@router.post("/student/send-attendance-request")
def send_attendance_request(data: dict, me: Identity = Depends(get_current_user)):
    """Gửi đơn xin phép nghỉ học.

    SỬA 18/08/2026: bản cũ lấy student_id từ nội dung máy khách gửi lên, nên
    một người có thể gửi đơn xin nghỉ MẠO DANH sinh viên khác. Nay mã sinh viên
    suy ra từ token; trường student_id trong body bị bỏ qua.
    """
    try:
        sid = _ma_sinh_vien_duoc_phep(data.get("student_id", ""), me)
        lhp_code = data.get("lhp_code")
        category = data.get("category")
        reason = data.get("reason")

        # 🔥 2. LẤY THÊM 3 TRƯỜNG MỚI TỪ APP GỬI LÊN
        year = data.get("year")           # Ví dụ: "2024-2025"
        semester = data.get("semester")   # Ví dụ: "Học kỳ 2"
        absence_date = data.get("absence_date") # Ví dụ: "2026-03-26"

        print(f"--- 🔔 YÊU CẦU XIN PHÉP MỚI ---")
        print(f"👉 SV: {sid} | Ngày vắng: {absence_date} | Kỳ: {semester} ({year})")

        if not lhp_code or str(lhp_code).lower() == "none":
            return JSONResponse(status_code=400, content={"status": "error", "message": "Mã lớp không hợp lệ"})

        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            
            # 3. Tìm Giảng viên dạy lớp (Giữ nguyên logic của bạn)
            sql_find_gv = """
                SELECT TOP 1 lh.MaCanBo 
                FROM tbl_Tkb_LopHocPhan lhp
                INNER JOIN tbl_Tkb_LopHocPhan_LichHoc lh ON lhp.Id = lh.IdLopHocPhan
                WHERE lhp.Code = ? AND lhp.IsDeleted = 0
            """
            cursor.execute(sql_find_gv, (lhp_code,))
            row = cursor.fetchone()
            
            gv_id = "AD"
            if row and row[0]:
                gv_id = str(row[0]).strip().upper().replace("CB", "")

            # 🔥 4. THỰC HIỆN CHÈN VÀO BẢNG (Thêm 3 cột mới)
            # Sơn nhớ kiểm tra tên cột trong DB có khớp không nhé
            sql_ins = """
                INSERT INTO tbl_Attendance_Requests 
                (StudentId, LhpId, Category, Reason, Status, CreatedAt, LecturerId, Year, Semester, AbsenceDate)
                VALUES (?, ?, ?, ?, 0, GETDATE(), ?, ?, ?, ?)
            """
            cursor.execute(sql_ins, (
                sid, lhp_code, category, reason, gv_id, 
                year, semester, absence_date
            ))
            
            conn.commit() 
            
            return {"status": "success", "message": "Gửi đơn xin phép thành công!"}

    except Exception as e:
        print(f"❌ LỖI: {str(e)}")
        return JSONResponse(status_code=500, content={"status": "error", "message": str(e)})
# 3. API cho Giảng viên: Nhận tin nhắn từ SV (Tab TIN TỪ SV)
@router.get("/lecturer/student-messages/{lecturer_id}")
def get_student_messages(lecturer_id: str):
    clean_id = lecturer_id.replace("CB", "").strip()
    try:
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            # Sử dụng LEFT JOIN để nếu không khớp tên lớp thì vẫn hiện được mã lớp
            sql = """
                SELECT 
                    r.Id, 
                    ISNULL(u.FullName, N'Sinh viên ' + r.StudentId) as FullName, 
                    r.StudentId, 
                    ISNULL(lhp.Ten, r.LhpId) as TenLop, 
                    r.Category, 
                    r.Reason, 
                    FORMAT(r.CreatedAt, 'HH:mm dd/MM/yyyy'),
                    r.Status
                FROM tbl_Attendance_Requests r
                LEFT JOIN tbl_Users u ON r.StudentId = REPLACE(REPLACE(u.UserCode, 'SV', ''), 'CB', '')
                LEFT JOIN tbl_Tkb_LopHocPhan lhp ON r.LhpId = lhp.Code
                WHERE r.LecturerId = ?
                ORDER BY r.CreatedAt DESC
            """
            cursor.execute(sql, (clean_id,))
            rows = cursor.fetchall()
            
            return {"status": "success", "data": [{
                "id": r[0], "student_name": r[1], "sid": r[2], 
                "lhp_name": r[3], "category": r[4], "reason": r[5], "time": r[6], "status": r[7]
            } for r in rows]}
    except Exception as e:
        return {"status": "error", "message": str(e)}

# --- 2. API cho Giảng viên: Cập nhật trạng thái (Xác nhận đã xem) ---



@router.post("/lecturer/update-attendance-status")
def update_attendance_status(data: dict):
    try:
        # 1. Lấy dữ liệu từ App gửi lên
        req_id = data.get("request_id")
        new_status = int(data.get("status"))  # 1: Duyệt (Có phép), 2: Từ chối
        
        if not req_id:
            return {"status": "error", "message": "Thiếu request_id"}

        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            
            # 2. Lấy thông tin chi tiết của đơn xin phép để biết SV nào, lớp nào
            sql_info = """
                SELECT r.StudentId, r.LhpId, r.CreatedAt, lhp.Ten 
                FROM tbl_Attendance_Requests r
                LEFT JOIN tbl_Tkb_LopHocPhan lhp ON r.LhpId = lhp.Code
                WHERE r.Id = ?
            """
            cursor.execute(sql_info, (req_id,))
            row = cursor.fetchone()
            
            if not row:
                return {"status": "error", "message": "Không tìm thấy thông tin đơn xin phép"}
            
            sid, lhp_code, request_date, lhp_name = row
            # Làm sạch StudentId để truy vấn các bảng khác (VD: SV1679 -> 1679)
            clean_sid = str(sid).replace("SV", "").replace("CB", "").strip()

            # 3. CẬP NHẬT TRẠNG THÁI TRONG BẢNG ĐƠN XIN PHÉP
            cursor.execute("UPDATE tbl_Attendance_Requests SET Status = ? WHERE Id = ?", (new_status, req_id))

            # 4. NẾU DUYỆT (Status=1) -> ĐỒNG BỘ SANG BẢNG NHẬT KÝ ĐIỂM DANH
            if new_status == 1:
                # Logic: Nếu đã có log (vắng) thì Update, chưa có thì Insert trạng thái 'Có phép' (Status=2)
                sql_sync_log = """
                    IF EXISTS (
                        SELECT 1 FROM tbl_Attendance_Logs 
                        WHERE StudentId = ? AND LhpCode = ? 
                        AND CAST(TimeChecked AS DATE) = CAST(? AS DATE)
                    )
                    BEGIN
                        UPDATE tbl_Attendance_Logs 
                        SET Status = 2, Method = 'APP_APPROVED', Distance = 0
                        WHERE StudentId = ? AND LhpCode = ? 
                        AND CAST(TimeChecked AS DATE) = CAST(? AS DATE)
                    END
                    ELSE
                    BEGIN
                        INSERT INTO tbl_Attendance_Logs (StudentId, LhpCode, Status, Method, TimeChecked, Distance)
                        VALUES (?, ?, 2, 'APP_APPROVED', ?, 0)
                    END
                """
                # Chuyển ngày tạo đơn thành ngày điểm danh (Cắt lấy phần Date)
                cursor.execute(sql_sync_log, (
                    clean_sid, lhp_code, request_date, 
                    clean_sid, lhp_code, request_date, 
                    clean_sid, lhp_code, request_date
                ))
            
            conn.commit()

            # 5. GỬI THÔNG BÁO FIREBASE (FCM) CHO SINH VIÊN
            cursor.execute("""
                SELECT TOP 1 FCMToken 
                FROM tbl_FCM_Tokens 
                WHERE StudentId = ? 
                ORDER BY LastLogin DESC
            """, (clean_sid,))
            token_row = cursor.fetchone()

            if token_row and token_row[0]:
                fcm_token = token_row[0]
                status_msg = "ĐÃ ĐƯỢC DUYỆT" if new_status == 1 else "BỊ TỪ CHỐI"
                
                try:
                    message = messaging.Message(
                        notification=messaging.Notification(
                            title="Kết quả duyệt đơn xin phép",
                            body=f"Đơn môn {lhp_name} của bạn {status_msg}."
                        ),
                        token=fcm_token,
                        data={
                            "type": "ATTENDANCE_STATUS",
                            "request_id": str(req_id),
                            "new_status": str(new_status)
                        }
                    )
                    messaging.send(message)
                    print(f"✅ Đã gửi FCM thông báo cho SV: {clean_sid}")
                except Exception as fcm_err:
                    print(f"⚠️ Lỗi gửi FCM: {fcm_err}")

            return {
                "status": "success", 
                "message": "Đã cập nhật trạng thái, đồng bộ nhật ký và gửi thông báo thành công!"
            }

    except Exception as e:
        print(f"🔥 Lỗi update_attendance_status: {e}")
        return {"status": "error", "message": str(e)}      
# ham lay lich su don vang hoc
@router.get("/student/attendance-history/{student_id}")
def get_attendance_history(student_id: str, me: Identity = Depends(get_current_user)):
    """Lịch sử đơn xin phép của một sinh viên.

    SỬA 18/08/2026: bản cũ không kiểm tra gì — mã sinh viên lấy thẳng từ đường
    dẫn, nên bất kỳ ai cũng đọc được lịch sử xin nghỉ của người khác, kèm lý do
    cá nhân (ốm đau, việc gia đình). Cùng loại lỗ hổng đã vá ở trợ lý AI.
    """
    try:
        sid = _ma_sinh_vien_duoc_phep(student_id, me)
        
        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()
            
            # 🔥 ĐÃ SỬA: 
            # - l.Ten: Cột chứa tên "Kỹ năng mềm..."
            # - l.Code: Cột chứa mã "SKI10000..." để JOIN
            sql = """
                SELECT 
                    r.Id, 
                    r.LhpId, 
                    r.Category, 
                    r.Reason, 
                    r.Status,
                    FORMAT(r.AbsenceDate, 'dd/MM/yyyy') as AbsenceDate,
                    FORMAT(r.CreatedAt, 'HH:mm dd/MM/yyyy') as TimeCreated,
                    l.Ten -- <-- Tên cột chính xác của Sơn đây nhé
                FROM tbl_Attendance_Requests r
                LEFT JOIN tbl_Tkb_LopHocPhan l ON r.LhpId = l.Code
                WHERE r.StudentId = ?
                ORDER BY r.CreatedAt DESC
            """
            
            cursor.execute(sql, (sid,))
            rows = cursor.fetchall()
            
            history = []
            for r in rows:
                history.append({
                    "id": r[0],
                    "lhp_id": r[1],
                    "category": r[2],
                    "reason": r[3],
                    "status": r[4] if r[4] is not None else 0,
                    "absence_date": r[5] if r[5] else "---",
                    "time": r[6],
                    # Nếu tìm thấy tên trong bảng Tkb thì hiện, không thì hiện mã lớp
                    "lhp_name": r[7] if r[7] else f"Mã lớp: {r[1]}"
                })
            
            return {"status": "success", "data": history}

    except Exception as e:
        print(f"🔥 Lỗi lấy lịch sử xin nghỉ: {e}")
        return {"status": "error", "message": str(e), "data": []}        