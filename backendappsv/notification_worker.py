#notification_worker
import asyncio
import os
import firebase_admin
from firebase_admin import credentials, messaging
import pyodbc
import uvicorn
from fastapi import FastAPI
from fastapi.responses import HTMLResponse
from contextlib import asynccontextmanager
from datetime import datetime, timedelta
from core.settings import settings  # cấu hình tập trung (Pha 0)

# =====================================================
# 1. KHỞI TẠO FIREBASE & DATABASE
# =====================================================
try:
    cred = credentials.Certificate("vinhuni-portal-firebase-adminsdk.json")
    if not firebase_admin._apps:
        firebase_admin.initialize_app(cred)
except Exception as e:
    print(f"❌ Lỗi cấu hình Firebase: {e}")

DB_SERVER = settings.db.server
DB_NAME = settings.db.name
DB_USER = settings.db.user
DB_PASSWORD = settings.db.password
CONN_STR = settings.db.local_conn_str

# =====================================================
# 2. QUÉT LỊCH THI ĐỂ TỰ NẠP TIN (PROXIMITY)
# =====================================================

def scan_and_generate_proximity_alerts():
    try:
        with pyodbc.connect(CONN_STR) as conn:
            cursor = conn.cursor()
            # print(f"🔍 [SCANNER] Đang quét lịch thi sắp diễn ra...")

            # SQL JOIN đa tầng bốc lịch thi hôm nay
            sql_exams = """
                SELECT DISTINCT 
                    tsv.IdNguoiHoc, 
                    lhp.Ten, 
                    CAST(thi.NgayThi AS DATETIME) + CAST(ca.ThoiGianBatDau AS DATETIME) as FullEventTime,
                    s.LeadTimeMinutes,
                    tsv.IdDanhSachThi
                FROM tbl_Thi_SinhVien tsv 
                INNER JOIN tbl_Thi_DanhSachThi thi ON tsv.IdDanhSachThi = thi.Id 
                LEFT JOIN tbl_Thi_CaThi ca ON thi.IdCaThi = ca.Id 
                INNER JOIN tbl_Tkb_LopHocPhan lhp ON tsv.InstanceIdLopHocPhan = lhp.InstanceId
                JOIN tbl_Notification_User_Settings s ON 
                    REPLACE(REPLACE(tsv.IdNguoiHoc, 'SV', ''), 'CB', '') = s.UserId
                WHERE s.Category = 'LICH_THI' AND s.IsEnabled = 1
                  AND thi.NgayThi = CAST(GETDATE() AS DATE)
                  AND tsv.IsDeleted = 0 AND thi.IsDeleted = 0
                  AND ABS(DATEDIFF(minute, DATEADD(minute, -s.LeadTimeMinutes, (CAST(thi.NgayThi AS DATETIME) + CAST(ca.ThoiGianBatDau AS DATETIME))), GETDATE())) <= 10
                  AND NOT EXISTS (
                      SELECT 1 FROM tbl_Notification_Queue q 
                      WHERE q.StudentId = tsv.IdNguoiHoc AND q.Category = 'LICH_THI' 
                        AND q.ExternalId = CAST(tsv.IdDanhSachThi AS NVARCHAR)
                        AND CAST(q.CreatedAt AS DATE) = CAST(GETDATE() AS DATE)
                  )
            """
            cursor.execute(sql_exams)
            rows = cursor.fetchall()
            for r in rows:
                cursor.execute("""
                    INSERT INTO tbl_Notification_Queue (StudentId, Title, Body, Category, IsSent, CreatedAt, EventTime, Priority, ExternalId)
                    VALUES (?, ?, ?, 'LICH_THI', 0, GETDATE(), ?, 0, ?)
                """, (r[0], f"🔔 Nhắc lịch thi: {r[1]}", 
                      f"Bạn có lịch thi môn {r[1]} lúc {r[2].strftime('%H:%M')}. Chuẩn bị tốt nhé!",
                      r[2], str(r[4])))
            conn.commit()
            if rows: print(f"✅ [SCANNER] Đã nạp {len(rows)} tin nhắc lịch mới.")
    except Exception as e:
        print(f"❌ [SCANNER] Lỗi: {e}")

# =====================================================
# 3. GỬI TIN & BỘ LỌC CẤU HÌNH (LÔ 200 TOKEN)
# =====================================================

# ═══════════════════════════════════════════════════════════════════════
# ⛔ HAI HÀM DƯỚI ĐÂY KHÔNG CÒN ĐƯỢC GỌI — GIỮ LẠI ĐỂ ĐỐI CHIẾU
#
# Việc gửi thông báo đẩy nay do notification_system/ đảm nhiệm.
# ĐỪNG nối lại chúng vào vòng lặp: chạy song song sẽ gửi TRÙNG cho người dùng,
# và bản ở đây thiếu chia lô 450 token nên vỡ khi gửi toàn trường.
# ═══════════════════════════════════════════════════════════════════════

def fetch_and_send_notifications():
    try:
        with pyodbc.connect(CONN_STR) as conn:
            cursor = conn.cursor()
            
            # 🔥 LỌC 24H: Chỉ lấy tin trong vòng 24h qua
            sql_fetch = """
                SELECT TOP 50 ID, StudentId, Title, Body, Category, IdNguoiHocs, EventTime, ISNULL(Priority, 0)
                FROM tbl_Notification_Queue 
                WHERE IsSent = 0 AND CreatedAt >= DATEADD(hour, -24, GETDATE())
                ORDER BY Priority DESC, ID ASC
            """
            cursor.execute(sql_fetch)
            rows = cursor.fetchall()
            if not rows: return

            for nid, sid, title, body, cat, id_list, event_time, priority in rows:
                raw_ids = []
                if sid: raw_ids.append(str(sid).strip())
                if id_list: raw_ids.extend([x.strip() for x in str(id_list).split(',') if x.strip()])
                
                target_ids = list(set(raw_ids))
                valid_tokens = []

                for tid in target_ids:
                    clean_id = tid.replace('SV', '').replace('CB', '')
                    
                    # 1. Kiểm tra cấu hình
                    cursor.execute("SELECT IsEnabled, LeadTimeMinutes FROM tbl_Notification_User_Settings WHERE UserId = ? AND Category = ?", (clean_id, cat))
                    set_row = cursor.fetchone()
                    is_enabled = set_row[0] if set_row else True
                    lead_time = set_row[1] if set_row else 30

                    if not is_enabled: continue

                    # 2. Kiểm tra giờ nhắc (nếu là tin thường)
                    if event_time and priority == 0:
                        if datetime.now() < (event_time - timedelta(minutes=lead_time)):
                            continue

                    # 3. Lấy Token
                    cursor.execute("SELECT FCMToken FROM tbl_FCM_Tokens WHERE REPLACE(REPLACE(StudentId, 'SV', ''), 'CB', '') = ? AND IsActive = 1", (clean_id,))
                    t_rows = cursor.fetchall()
                    for t in t_rows:
                        if t[0]: valid_tokens.append(t[0])

                if valid_tokens:
                    # 🔥 GỬI THEO LÔ 200
                    send_to_firebase(nid, title, body, cat, valid_tokens, cursor)
                else:
                    # Nếu không có token hoặc quá 24h thì đóng tin
                    cursor.execute("UPDATE tbl_Notification_Queue SET IsSent = 1, Summary = N'Không có thiết bị nhận/Tắt TB' WHERE ID = ?", (nid,))

            conn.commit()
    except Exception as e:
        print(f"🔥 Lỗi Worker: {e}")

# def send_to_firebase(nid, title, body, cat, tokens, cursor):
    # try:
        # success_count = 0
        # # Chia lô 200 token
        # for i in range(0, len(tokens), 200):
            # chunk = tokens[i:i+200]
            # message = messaging.MulticastMessage(
                # notification=messaging.Notification(title=title, body=body[:200]),
                # tokens=chunk,
                # data={"nid": str(nid), "category": str(cat)},
                # # Thêm cấu hình ưu tiên cao để App nhận được ngay
                # android=messaging.AndroidConfig(priority='high'),
                # apns=messaging.APNSConfig(payload=messaging.APNSPayload(aps=messaging.Aps(content_available=True)))
            # )
            # response = messaging.send_each_for_multicast(message)
            # success_count += response.success_count
        
        # print(f"🚀 Gửi Tin #{nid}: Thành công {success_count}/{len(tokens)}")
        # cursor.execute("UPDATE tbl_Notification_Queue SET IsSent = 1, SentAt = GETDATE(), Summary = ? WHERE ID = ?", (f'Thành công {success_count} TB', nid))
    # except Exception as e:
        # print(f"❌ Firebase Error: {e}")
def send_to_firebase(nid, title, body, cat, tokens, cursor):
    try:
        # 🔥 FIX LỖI: Đảm bảo title và body không bao giờ là None
        safe_title = str(title or "Thông báo mới")
        safe_body = str(body or "")
        
        success_count = 0
        # Chia lô 200 token
        for i in range(0, len(tokens), 200):
            chunk = tokens[i:i+200]
            message = messaging.MulticastMessage(
                # Sử dụng chuỗi an toàn đã được check None
                notification=messaging.Notification(
                    title=safe_title, 
                    body=safe_body[:200] # Giờ thì không lo lỗi subscriptable nữa
                ),
                tokens=chunk,
                data={
                    "nid": str(nid or ""), 
                    "category": str(cat or "GENERAL")
                },
                # Cấu hình ưu tiên và âm thanh (Sound)
                android=messaging.AndroidConfig(
                    priority='high',
                    notification=messaging.AndroidNotification(
                        sound='default',
                        default_sound=True,
                        channel_id='vinhuni_alert'
                    )
                ),
                apns=messaging.APNSConfig(
                    payload=messaging.APNSPayload(
                        aps=messaging.Aps(sound='default', content_available=True)
                    )
                )
            )
            response = messaging.send_each_for_multicast(message)
            success_count += response.success_count
        
        print(f"🚀 Gửi Tin #{nid}: Thành công {success_count}/{len(tokens)}")
        cursor.execute("UPDATE tbl_Notification_Queue SET IsSent = 1, SentAt = GETDATE(), Summary = ? WHERE ID = ?", (f'Thành công {success_count} TB', nid))
    except Exception as e:
        # Nếu vẫn lỗi, ta đóng tin đó lại và ghi log lỗi vào Summary để tránh treo vòng lặp
        print(f"❌ Firebase Error: {e}")
        try:
            cursor.execute("UPDATE tbl_Notification_Queue SET IsSent = 1, Summary = ? WHERE ID = ?", (f"Lỗi: {str(e)[:100]}", nid))
        except: pass
# =====================================================
# 4. LIFESPAN & APP
# =====================================================

# ⚠️ ĐÃ GỠ PHẦN GỬI — 18/08/2026
#
# Tệp này trước đây làm HAI việc: quét sinh nhắc lịch, VÀ tự gửi thông báo đẩy.
# Phần gửi nay do notification_system/ đảm nhiệm, làm tốt hơn hẳn:
#   • chia lô 450 token — bản ở đây gửi cả nghìn token một lần, vượt giới hạn
#     cứng 500 của Firebase và làm mất tin
#   • chia nhỏ cho 5 worker chạy song song — quan trọng ở quy mô 15.000 sinh viên
#   • có hàng đợi "đang xử lý" nên worker chết không mất tin
#
# CHẠY CẢ HAI CÙNG LÚC SẼ GỬI TRÙNG cho người dùng. Vòng lặp gửi ở đây đã tắt.
#
# Còn giữ lại phần QUÉT vì nó làm một việc chưa nơi nào có: sinh nhắc lịch thi
# theo LeadTimeMinutes RIÊNG của từng người. Bản sync_and_notify_worker_new.py
# cũng nhắc lịch nhưng qua sp_AI_Remind_Upcoming_Events @MinutesBefore = 30 —
# cố định 30 phút cho tất cả, bỏ qua thiết lập cá nhân mà màn "Cấu hình nhận
# thông báo" đang ghi vào.

async def scanner_loop():
    while True:
        await asyncio.to_thread(scan_and_generate_proximity_alerts)
        await asyncio.sleep(300)

@asynccontextmanager
async def lifespan(app: FastAPI):
    print("=" * 62)
    print("🔍 BỘ QUÉT NHẮC LỊCH — chỉ SINH thông báo, KHÔNG gửi")
    print("   Việc gửi do notification_system/ đảm nhiệm")
    print("=" * 62)
    t = asyncio.create_task(scanner_loop())
    yield
    t.cancel()

app = FastAPI(lifespan=lifespan, title="VinhUni — Bộ quét nhắc lịch")

@app.get("/", response_class=HTMLResponse)
async def dashboard():
    history_html = ""
    try:
        with pyodbc.connect(CONN_STR) as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT TOP 30 ID, StudentId, Title, Summary, IsSent, CreatedAt, Category FROM tbl_Notification_Queue ORDER BY ID DESC")
            for r in cursor.fetchall():
                color = "green-text" if r[4] else "orange-text"
                history_html += f"<tr><td>{r[0]}</td><td>{r[1] or 'NHÓM'}</td><td>{r[2]}</td><td>{r[6]}</td><td class='{color}'>{r[3] or 'Đang xử lý'}</td><td>{r[5].strftime('%H:%M')}</td></tr>"
    except: history_html = "<tr><td colspan='6'>Lỗi load dữ liệu</td></tr>"
    
    return f"""
    <html><head><meta charset="UTF-8"><link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/materialize/1.0.0/css/materialize.min.css">
    <style>body{{padding:20px}} th{{background:#f5f5f5}}</style></head>
    <body><h4>🔍 Bộ quét nhắc lịch — theo dõi hàng đợi</h4><table class="striped">
    <thead><tr><th>ID</th><th>User</th><th>Tiêu đề</th><th>Loại</th><th>Trạng thái</th><th>Lúc tạo</th></tr></thead>
    <tbody>{history_html}</tbody></table><script>setTimeout(()=>location.reload(), 10000);</script></body></html>
    """

if __name__ == "__main__":
    # Cổng 8083. Bản cũ dùng 8081 — trùng với producer_app.py cũ nên hai bên
    # không chạy cùng lúc được. Nay: 8082 = bộ nạp, 8083 = bộ quét này.
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("SCANNER_PORT", "8083")))