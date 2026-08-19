import asyncio
import os
import re
import time
import hashlib
import requests
import pyodbc
import rookiepy
import unicodedata
import json
from datetime import datetime
from lunar_python import Lunar, Solar # Thư viện âm lịch chuẩn
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from selenium import webdriver
from selenium.webdriver.edge.service import Service
from selenium.webdriver.edge.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from core.settings import settings  # cấu hình tập trung (Pha 0)

# --- [LAYER 0: CẤU HÌNH HỆ THỐNG] ---
CONFIG = {
    "DB": settings.db.local_conn_str,
    "DOCS_PATH": r"E:\app_vinhuni\vanban\docs",
    "TEMP_PROFILE": r"C:\temp\vinhuni_worker",
    "DRIVER_PATH": r"C:\vinhuni_project\drivers\msedgedriver.exe", 
    "URL_CALENDAR": "https://vanphong.vinhuni.edu.vn/xem-lich-tuan/lich-cong-khai",
    "URL_ODOO": "https://qlvb.vinhuni.edu.vn",
    "WEATHER_API_KEY": os.getenv("WEATHER_API_KEY", ""),
    "CITY_NAME": "Vinh"
}

def get_db_conn():
    return pyodbc.connect(CONFIG["DB"], autocommit=True)

# --- [LAYER 1: TIỆN ÍCH BỔ TRỢ - WEATHER, LUNAR, RATES] ---

def fetch_lunar_date():
    """Lấy ngày âm lịch Việt Nam chuẩn"""
    now = datetime.now()
    lunar = Lunar.fromSolar(Solar.fromYmd(now.year, now.month, now.day))
    return f"{lunar.getDay()}/{lunar.getMonth()} Âm lịch ({lunar.getYearInGanZhi()})"

def fetch_weather_forecast():
    """Lấy dự báo thời tiết cho 3 mốc: Sáng, Trưa, Tối"""
    try:
        url = f"http://api.openweathermap.org/data/2.5/forecast?q={CONFIG['CITY_NAME']}&appid={CONFIG['WEATHER_API_KEY']}&units=metric&lang=vi"
        res = requests.get(url).json()
        m, n, e = "26°C", "32°C", "25°C"
        desc = res['list'][0]['weather'][0]['description'].capitalize()
        for item in res['list'][:10]:
            dt_txt = item['dt_txt']
            temp = f"{int(item['main']['temp'])}°C"
            if "09:00:00" in dt_txt: m = temp
            if "12:00:00" in dt_txt: n = temp
            if "21:00:00" in dt_txt: e = temp
        return m, n, e, desc
    except: return "26°C", "32°C", "25°C", "Nắng ráo"

def get_daily_wish():
    """Sinh lời chúc theo thứ"""
    w = datetime.now().weekday()
    wishes = {
        0: ("🚀 ĐẦU TUẦN NĂNG LƯỢNG!", "Chúc Quý Thầy/Cô một tuần mới rực rỡ và hiệu quả."),
        1: ("✨ THỨ BA THUẬN LỢI!", "Chúc Quý Thầy/Cô vạn sự như ý trong công tác."),
        2: ("☕ GIỮA TUẦN THONG THẢ!", "Chúc Quý Thầy/Cô giữ vững phong độ và tinh thần thoải mái."),
        3: ("🌤️ THỨ NĂM RẠNG RỠ!", "Chúc Quý Thầy/Cô một ngày làm việc tràn đầy niềm vui."),
        4: ("🥳 THỨ SÁU TUYỆT VỜI!", "Chúc Quý Thầy/Cô sớm hoàn thành công việc để đón cuối tuần."),
        5: ("🍀 CUỐI TUẦN THƯ GIÃN!", "Chúc Quý Thầy/Cô có những giây phút ấm áp bên gia đình."),
        6: ("🔋 CHỦ NHẬT NGHỈ NGƠI!", "Chúc Quý Thầy/Cô nạp đầy năng lượng cho tuần mới.")
    }
    return wishes.get(w, ("✨ CHÚC NGÀY MỚI TỐT LÀNH!", "Chúc Quý Thầy/Cô công tác tốt!"))

# --- [LAYER 2: LỚP BÓC TÁCH DỮ LIỆU - SCRAPER] ---
class WeeklyScraper:
    def __init__(self):
        if not os.path.exists(CONFIG["DOCS_PATH"]): os.makedirs(CONFIG["DOCS_PATH"])
        if not os.path.exists(CONFIG["TEMP_PROFILE"]): os.makedirs(CONFIG["TEMP_PROFILE"])

    def _clean_fn(self, text):
        if not text: return "document"
        text = unicodedata.normalize('NFKD', text).encode('ascii', 'ignore').decode('ascii')
        text = re.sub(r'[\\/*?:"<>|]', '-', text)
        return re.sub(r'\s+', '_', text).strip()[:130]

    def _parse_date(self, date_text):
        match = re.search(r'(\d{2})/(\d{2})/(\d{4})', date_text)
        return f"{match.group(3)}-{match.group(2)}-{match.group(1)}" if match else None

    def scrape_vinhuni_schedule(self, target_week="current"):
        print(f"📅 [SCRAPER] Đang bóc tách lịch tuần: {target_week}...")
        opts = Options()
        opts.add_argument("--headless=new")
        opts.add_argument("--disable-gpu")
        opts.add_argument(f"--user-data-dir={os.path.join(CONFIG['TEMP_PROFILE'], f'run_{target_week}')}")
        service = Service(executable_path=CONFIG["DRIVER_PATH"])
        driver = webdriver.Edge(service=service, options=opts)
        try:
            driver.get(CONFIG["URL_CALENDAR"])
            wait = WebDriverWait(driver, 20)
            if target_week == "next":
                btn = wait.until(EC.element_to_be_clickable((By.CSS_SELECTOR, ".anticon-right")))
                driver.execute_script("arguments[0].click();", btn)
                time.sleep(3)
            wait.until(EC.presence_of_element_located((By.CLASS_NAME, "day-container")))
            days = driver.find_elements(By.CLASS_NAME, "day-container")
            with get_db_conn() as conn:
                cursor = conn.cursor()
                for d_box in days:
                    date_raw = d_box.find_element(By.CLASS_NAME, "day-title").text
                    event_date = self._parse_date(date_raw)
                    if not event_date: continue
                    slots = d_box.find_elements(By.XPATH, ".//div[contains(@class, '-slot')]")
                    for slot in slots:
                        session = "Sáng" if "morning-slot" in slot.get_attribute("class") else "Chiều"
                        for card in slot.find_elements(By.CLASS_NAME, "event-card"):
                            try: time_val = card.find_element(By.CLASS_NAME, "ant-tag").text.strip()
                            except: time_val = "07:30" if session == "Sáng" else "14:00"
                            titles = card.find_elements(By.CLASS_NAME, "event-title")
                            content = titles[0].text.strip() if titles else "N/A"
                            location = titles[-1].text.strip() if len(titles) > 1 else "Tại đơn vị"
                            details = card.find_elements(By.CLASS_NAME, "event-detail")
                            chair, parts = "", ""
                            for det in details:
                                txt = det.text.strip()
                                if "Chủ trì:" in txt or "CT:" in txt: chair = txt.replace("Chủ trì:","").replace("CT:","").strip()
                                elif "Thành phần:" in txt or "TP:" in txt: parts = txt.replace("Thành phần:","").replace("TP:","").strip()
                            h_str = f"{event_date}|{time_val}|{content[:50]}"
                            e_hash = hashlib.md5(h_str.encode('utf-8')).hexdigest()
                            cursor.execute("""
                                IF NOT EXISTS (SELECT 1 FROM tbl_WeeklySchedule WHERE EventHash = ?)
                                INSERT INTO tbl_WeeklySchedule (EventDate, Session, TimeValue, Content, Location, Chairperson, Participants, EventHash, CreatedAt)
                                VALUES (?, ?, ?, ?, ?, ?, ?, ?, GETDATE())
                            """, (e_hash, event_date, session, time_val, content, location, chair, parts, e_hash))
            print(f"✅ [SCRAPER] Hoàn thành bóc tách tuần {target_week}.")
        except Exception as e: print(f"❌ [SCRAPER] Lỗi: {e}")
        finally: driver.quit()

# --- [LAYER 3: ĐỊNH NGHĨA CÁC JOB CHO NHẠC TRƯỞNG] ---
scraper = WeeklyScraper()

async def job_full_sync_cycle():
    """Chu kỳ quét dữ liệu tổng hợp (30 phút/lần)"""
    print(f"🚀 [{datetime.now().strftime('%H:%M:%S')}] BẮT ĐẦU CHU KỲ QUÉT TỔNG HỢP...")
    scraper.scrape_vinhuni_schedule(target_week="current")
    scraper.scrape_vinhuni_schedule(target_week="next")
    await job_sync_odoo_and_pdf()
    await job_sync_delta_data()

async def job_sync_odoo_and_pdf():
    """Đồng bộ Odoo - Săn lùng PDF"""
    print(f"📡 [{datetime.now().strftime('%H:%M:%S')}] Odoo Boss: Đang săn tệp tin...")
    try:
        cookies = rookiepy.edge(["qlvb.vinhuni.edu.vn"])
        sid = next((c['value'] for c in cookies if c['name'] == 'session_id'), None)
        if not sid: return
        headers = {'Cookie': f'session_id={sid}; cids=1', 'User-Agent': 'Mozilla/5.0'}
        url_rpc = f"{CONFIG['URL_ODOO']}/web/dataset/call_kw"
        payload = {"jsonrpc": "2.0", "method": "call", "params": {"model": "van_ban_noi_bo", "method": "search_read", "args": [[["id", ">", 0]]], "kwargs": {"fields": ["id", "so_ky_hieu", "trich_yeu", "tai_lieu_ids"], "limit": 50, "order": "id desc"}}, "id": 1}
        res = requests.post(url_rpc, json=payload, headers=headers).json()
        with get_db_conn() as conn:
            cursor = conn.cursor()
            for doc in res.get('result', []):
                o_id = doc['id']
                so_hieu = doc.get('so_ky_hieu') or f"SBN-{o_id}"
                cursor.execute("SELECT DocId, FileName FROM tbl_Document_Library WHERE DocId = ?", (o_id,))
                row = cursor.fetchone()
                if row and row.FileName: continue
                t_ids = doc.get('tai_lieu_ids', [])
                if t_ids:
                    fn = f"{scraper._clean_fn(so_hieu)}_-_{scraper._clean_fn(doc.get('trich_yeu'))[:80]}.pdf"
                    url_dl = f"{CONFIG['URL_ODOO']}/web/content/{t_ids[0]}?download=true"
                    rf = requests.get(url_dl, headers=headers)
                    if rf.status_code == 200:
                        with open(os.path.join(CONFIG["DOCS_PATH"], fn), "wb") as f: f.write(rf.content)
                        cursor.execute("UPDATE tbl_Document_Library SET FileName = ? WHERE DocId = ?", (fn, o_id))
            print("✅ [ODOO] Hoàn thành đồng bộ PDF.")
    except Exception as e: print(f"❌ [ODOO ERROR] {e}")

async def job_sync_delta_data():
    with get_db_conn() as conn:
        conn.cursor().execute("EXEC sp_Master_Sync_Delta")
        print("✅ [SQL] Đã chạy xong SP Master Sync Delta.")

async def job_daily_summary(sess):
    """
    NHẠC TRƯỞNG SOẠN BẢN TIN: 
    1. Lấy dữ liệu ngoại vi (Thời tiết, Âm lịch, Tỷ giá)
    2. Cập nhật SQL Helper Tables
    3. Gọi SP sinh bản tin Pro UI
    """
    print(f"☀️ [{datetime.now().strftime('%H:%M:%S')}] BẮT ĐẦU SOẠN BẢN TIN {sess}...")
    try:
        # 1. Thu thập dữ liệu
        lunar_str = fetch_lunar_date()
        m_temp, n_temp, e_temp, weather_desc = fetch_weather_forecast()
        wish_title, wish_content = get_daily_wish()
        
        with get_db_conn() as conn:
            cursor = conn.cursor()
            # 2. Cập nhật các bảng phụ
            cursor.execute("DELETE FROM tbl_System_Weather")
            cursor.execute("INSERT INTO tbl_System_Weather (MorningTemp, NoonTemp, NightTemp, Description, UpdatedAt) VALUES (?, ?, ?, ?, GETDATE())", 
                           (m_temp, n_temp, e_temp, weather_desc))
            
            # cursor.execute("DELETE FROM tbl_System_ExchangeRates")
            # cursor.execute("INSERT INTO tbl_System_ExchangeRates (CurrencyCode, RateValue, Trend, UpdatedAt) VALUES ('USD', '25.420', '📈', GETDATE()), ('GOLD', '82.50', '📉', GETDATE())")
            
            cursor.execute("DELETE FROM tbl_System_Quotes")
            cursor.execute("INSERT INTO tbl_System_Quotes (Content, Author, Category, UpdatedAt) VALUES (?, ?, 'DAILY_WISH', GETDATE())", (wish_content, wish_title))
            
            # 3. Kích hoạt SP sinh bản tin Pro
            # Mặc định gửi cho toàn trường (NULL), nếu test Sơn đổi thành '1679'
            cursor.execute("EXEC [dbo].[sp_AI_Generate_Daily_Summary] @Session = ?, @LunarDate = ?, @SpecificStaffId = NULL", (sess, lunar_str))
            print(f"✨ [BẢN TIN] Đã soạn xong bản tin {sess} thành công.")
    except Exception as e: print(f"❌ [SUMMARY ERROR] {e}")

async def job_reminder_30min():
    with get_db_conn() as conn:
        conn.cursor().execute("EXEC sp_AI_Remind_Upcoming_Events @MinutesBefore = 30")
async def job_cleanup_notification_queue():
    """
    DỌN DẸP HỆ THỐNG ĐỊNH KỲ:
    1. Xóa các tin của người dùng không có Token FCM (để tránh rác hàng đợi)
    2. Xóa các tin đã gửi thành công/lỗi quá 7 ngày
    """
    print(f"🧹 [{datetime.now().strftime('%H:%M:%S')}] Đang dọn dẹp bảng đợi thông báo...")
    try:
        with get_db_conn() as conn:
            cursor = conn.cursor()
            
            # 1. Xóa các tin 'Đang đợi' nhưng người dùng KHÔNG CÓ TOKEN hoặc TOKEN KHÔNG HOẠT ĐỘNG
            sql_delete_no_token = """
                DELETE FROM tbl_Notification_Queue
                WHERE IsSent = 0 
                AND NOT EXISTS (
                    SELECT 1 FROM tbl_FCM_Tokens t
                    WHERE REPLACE(REPLACE(t.StudentId, 'SV', ''), 'CB', '') = 
                          REPLACE(REPLACE(tbl_Notification_Queue.StudentId, 'SV', ''), 'CB', '')
                    AND t.IsActive = 1
                )
            """
            cursor.execute(sql_delete_no_token)
            deleted_no_token = cursor.rowcount
            
            # 2. Xóa các tin đã xử lý xong (IsSent = 1) đã cũ hơn 7 ngày để giảm dung lượng
            sql_delete_old = """
                DELETE FROM tbl_Notification_Queue
                WHERE IsSent = 1 AND CreatedAt < DATEADD(day, -7, GETDATE())
            """
            cursor.execute(sql_delete_old)
            deleted_old = cursor.rowcount
            
            print(f"✅ [CLEANUP] Đã xóa {deleted_no_token} tin không có token và {deleted_old} tin cũ.")
    except Exception as e:
        print(f"❌ [CLEANUP ERROR] {e}")
# =========================================================================
# [LAYER 3B] HAI VIỆC CHUYỂN TỪ master_worker.py — 18/08/2026
# =========================================================================
# Trước đây ba worker chạy song song và làm trùng việc nhau. Đã thống nhất giữ
# tệp này làm bản chính. Nhưng master_worker.py có hai việc mà tệp này chưa có,
# dừng nó mà không chuyển sang thì mất chức năng:
#
#   1. Biến lịch tuần đã bóc tách thành THÔNG BÁO. Tệp này vốn chỉ ghi vào
#      tbl_WeeklySchedule rồi dừng — không ai báo cho cán bộ biết.
#   2. Đồng bộ hồ sơ cán bộ từ máy chủ .26 về, và cập nhật tên/chức vụ/đơn vị
#      vào tbl_users.

def job_xu_ly_thong_bao_lich_tuan():
    """Biến các mục lịch tuần mới hoặc vừa sửa thành thông báo.

    Chuyển từ master_worker.task_process_weekly_notifications().
    Stored procedure sp_AI_Process_Weekly_Notification lo phần bóc tách thành
    phần tham gia rồi nạp vào tbl_Notification_Queue.
    """
    try:
        with get_db_conn() as conn:
            cursor = conn.cursor()
            cursor.execute(
                "SELECT EventHash FROM tbl_WeeklySchedule "
                "WHERE IsNotified = 0 OR IsModified = 1"
            )
            rows = cursor.fetchall()
            for row in rows:
                cursor.execute("{CALL sp_AI_Process_Weekly_Notification (?)}", (row[0],))
            if rows:
                print(f"📅 [LỊCH TUẦN] Đã sinh thông báo cho {len(rows)} mục lịch")
    except Exception as e:
        print(f"❌ [LỊCH TUẦN] Lỗi xử lý thông báo: {e}")


def job_dong_bo_ho_so_can_bo():
    """Kéo hồ sơ cán bộ từ máy chủ .26 về và cập nhật vào tbl_users.

    Chuyển từ master_worker.task_sync_canbo_daily().
    Dùng bảng tạm rồi thay một lần để không để bảng chính rỗng giữa chừng.
    """
    print("🌟 [CÁN BỘ] Bắt đầu đồng bộ hồ sơ...")
    try:
        with get_db_conn() as conn:
            cursor = conn.cursor()

            remote_sql = """
                SELECT h.*, dv.DV_Ten AS TenDonVi, dv.DV_ParentID,
                       cv.CV_Ten AS TenChucVu, td.TDCM_Ten AS TenTrinhDo
                FROM DBHOSOCANBO.dbo.tbl_CANBO_HoSo h
                LEFT JOIN DBHOSOCANBO.dbo.view_DM_Chung_DonVi dv ON h.DV_ID_BienChe = dv.DV_ID
                LEFT JOIN DBHOSOCANBO.dbo.view_DM_Chung_ChucVu cv ON h.CV_ID = cv.CV_ID
                LEFT JOIN DBHOSOCANBO.dbo.view_DM_CanBo_TrinhDoChuyenMon td ON h.TDCM_ID = td.TDCM_ID
            """
            formatted_sql = remote_sql.replace("'", "''")
            may_chu_can_bo = os.getenv("STAFF_LINKED_SERVER", "172.16.0.26\\vinhuni")

            cursor.execute(
                "IF OBJECT_ID('tbl_CANBO_HoSo_Temp', 'U') IS NOT NULL "
                "DROP TABLE tbl_CANBO_HoSo_Temp"
            )
            cursor.execute(
                f"SELECT * INTO tbl_CANBO_HoSo_Temp "
                f"FROM OPENQUERY([{may_chu_can_bo}], '{formatted_sql}')"
            )

            cursor.execute(
                "DELETE FROM tbl_CANBO_HoSo "
                "WHERE HS_ID IN (SELECT HS_ID FROM tbl_CANBO_HoSo_Temp)"
            )
            cursor.execute("INSERT INTO tbl_CANBO_HoSo SELECT * FROM tbl_CANBO_HoSo_Temp")

            cursor.execute("""
                UPDATE u
                SET u.FullName = LTRIM(RTRIM(ISNULL(t.HS_Ho, ''))) + ' ' + LTRIM(RTRIM(ISNULL(t.HS_Ten, ''))),
                    u.ChucVu = t.TenChucVu,
                    u.DonVi = t.TenDonVi,
                    u.FacultyName = t.DV_ParentID
                FROM tbl_users u
                INNER JOIN tbl_CANBO_HoSo_Temp t
                        ON u.UserCode = 'CB' + CAST(t.HS_ID AS NVARCHAR(50))
            """)

            cursor.execute("DROP TABLE tbl_CANBO_HoSo_Temp")
            print("✅ [CÁN BỘ] Đồng bộ hồ sơ thành công")
    except Exception as e:
        print(f"❌ [CÁN BỘ] Lỗi đồng bộ: {e}")


# --- [LAYER 4: CÀI ĐẶT NHẠC TRƯỞNG - SCHEDULER] ---
scheduler = AsyncIOScheduler()

# 1. Chu kỳ quét tổng hợp (Lịch tuần + Odoo + Delta SQL) - 30 phút/lần

# ===========================================================================
# Thông báo tự động theo sự kiện — sinh nhật và ngày lễ
# ===========================================================================
#
# Thêm 19/08/2026. Ứng dụng đã có màn hình "TỰ ĐỘNG & SỰ KIỆN" từ trước với hai
# công tắc, nhưng phía máy chủ không có gì cả — bật lên rồi chẳng bao giờ gửi.
# Đây là phần còn thiếu đó.
#
# Nguyên tắc:
#   • Chỉ gửi cho người CÒN CÀI ỨNG DỤNG. Cơ sở dữ liệu không phân biệt được
#     sinh viên đang học với người đã tốt nghiệp (cả 61.974 tài khoản đều
#     IsActive = 1), nên "có thiết bị đang hoạt động" là bộ lọc đúng và tự
#     nhiên nhất: người đã gỡ ứng dụng vốn không nhận được gì.
#   • Mỗi người mỗi năm đúng MỘT lời chúc cho mỗi loại. Tác vụ chạy mỗi giờ và
#     có thể chạy lại sau khi khởi động lại máy chủ, nên phải chống gửi trùng.
#   • Tôn trọng ai đã tắt loại thông báo này trong phần cài đặt.

MA_LOAI_TU_DONG = "CA_NHAN"   # để tin rơi vào tab "Cá nhân" của ứng dụng


def _lay_cau_hinh_tu_dong(cursor, ma_cau_hinh):
    """Đọc một cấu hình. Trả None nếu chưa bật hoặc chưa có bảng."""
    try:
        r = cursor.execute(
            "SELECT TieuDe, NoiDung, GioGui FROM tbl_ThongBao_TuDong "
            "WHERE MaCauHinh = ? AND BatTat = 1", ma_cau_hinh).fetchone()
    except Exception as e:  # noqa: BLE001 — chưa chạy kịch bản tạo bảng
        print(f"⏭️  [TựĐộng] Chưa có bảng cấu hình ({str(e)[:60]})")
        return None
    return r


def _gui_loi_chuc(cursor, ma_cau_hinh, tieu_de_mau, noi_dung_mau, nguoi_nhan):
    """Nạp lời chúc vào hàng đợi thông báo. Trả về số người thực sự được gửi."""
    nam = datetime.now().year
    da_gui = 0

    for ma_nguoi, ho_ten, tieu_de_rieng in nguoi_nhan:
        ten = (ho_ten or "bạn").strip()
        tieu_de = (tieu_de_rieng or tieu_de_mau).replace("{ten}", ten)
        noi_dung = noi_dung_mau.replace("{ten}", ten)
        if tieu_de_rieng:
            tieu_de = tieu_de_rieng
            noi_dung = noi_dung_mau.replace("{ten}", ten)

        try:
            ma_tin = cursor.execute("""
                INSERT INTO tbl_Notification_Queue
                  (StudentId, Title, Body, Category, Summary, IsSent, CreatedAt,
                   IsRead, Sender, SenderId, Scope, IdNguoiHocs)
                OUTPUT INSERTED.ID
                VALUES (?, ?, ?, ?, ?, 1, GETDATE(), 0, N'Trường Đại học Vinh',
                        '0', 'TU_DONG', ?)
            """, (ma_nguoi, tieu_de, noi_dung, MA_LOAI_TU_DONG,
                  noi_dung[:200], ma_nguoi)).fetchval()

            cursor.execute("""
                INSERT INTO tbl_ThongBao_TuDong_Log
                    (MaCauHinh, MaNguoiNhan, Nam, MaThongBao)
                VALUES (?, ?, ?, ?)
            """, (ma_cau_hinh, ma_nguoi, nam, ma_tin))
            da_gui += 1
        except Exception as e:  # noqa: BLE001
            # Một người hỏng thì bỏ qua người đó, không làm hỏng cả mẻ
            print(f"⚠️  [TựĐộng] Không gửi được cho {ma_nguoi}: {str(e)[:80]}")

    return da_gui


def job_chuc_mung_sinh_nhat():
    """Gửi lời chúc cho những người sinh nhật hôm nay."""
    gio_hien_tai = datetime.now().hour
    try:
        with get_db_conn() as conn:
            cursor = conn.cursor()

            cau_hinh = _lay_cau_hinh_tu_dong(cursor, "SINH_NHAT")
            if not cau_hinh:
                return
            tieu_de_mau, noi_dung_mau, gio_gui = cau_hinh
            if gio_hien_tai != int(gio_gui):
                return

            nguoi_nhan = cursor.execute("""
                SELECT DISTINCT
                    REPLACE(REPLACE(UPPER(RTRIM(u.UserCode)), 'SV', ''), 'CB', ''),
                    u.FullName,
                    CAST(NULL AS NVARCHAR(300))
                FROM tbl_users u
                WHERE u.Birthday IS NOT NULL
                  AND MONTH(u.Birthday) = MONTH(GETDATE())
                  AND DAY(u.Birthday)   = DAY(GETDATE())
                  AND u.IsActive = 1
                  -- chỉ người còn cài ứng dụng
                  AND EXISTS (
                        SELECT 1 FROM tbl_FCM_Tokens t
                        WHERE REPLACE(REPLACE(UPPER(RTRIM(t.StudentId)), 'SV', ''), 'CB', '')
                              = REPLACE(REPLACE(UPPER(RTRIM(u.UserCode)), 'SV', ''), 'CB', '')
                          AND t.IsActive = 1)
                  -- năm nay chưa gửi
                  AND NOT EXISTS (
                        SELECT 1 FROM tbl_ThongBao_TuDong_Log g
                        WHERE g.MaCauHinh = 'SINH_NHAT'
                          AND g.Nam = YEAR(GETDATE())
                          AND g.MaNguoiNhan
                              = REPLACE(REPLACE(UPPER(RTRIM(u.UserCode)), 'SV', ''), 'CB', ''))
                  -- người đã tắt loại thông báo này thì tôn trọng
                  AND NOT EXISTS (
                        SELECT 1 FROM tbl_Notification_User_Settings s
                        WHERE s.UserId
                              = REPLACE(REPLACE(UPPER(RTRIM(u.UserCode)), 'SV', ''), 'CB', '')
                          AND s.Category = 'SINH_NHAT' AND s.IsEnabled = 0)
            """).fetchall()

            if not nguoi_nhan:
                return

            n = _gui_loi_chuc(cursor, "SINH_NHAT", tieu_de_mau, noi_dung_mau, nguoi_nhan)
            conn.commit()
            print(f"🎂 [TựĐộng] Đã gửi lời chúc sinh nhật cho {n}/{len(nguoi_nhan)} người")
    except Exception as e:  # noqa: BLE001
        print(f"🔥 [TựĐộng] Lỗi gửi lời chúc sinh nhật: {str(e)[:150]}")


def job_chuc_mung_ngay_le():
    """Gửi lời chúc vào các ngày lễ đã khai trong tbl_NgayLe."""
    bay_gio = datetime.now()
    try:
        with get_db_conn() as conn:
            cursor = conn.cursor()

            cau_hinh = _lay_cau_hinh_tu_dong(cursor, "NGAY_LE")
            if not cau_hinh:
                return
            _, noi_dung_mau, gio_gui = cau_hinh
            if bay_gio.hour != int(gio_gui):
                return

            ngay_le = cursor.execute("""
                SELECT TenNgay, DoiTuong FROM tbl_NgayLe
                WHERE BatTat = 1 AND Ngay = ? AND Thang = ?
            """, (bay_gio.day, bay_gio.month)).fetchall()

            if not ngay_le:
                return

            for ten_ngay, doi_tuong in ngay_le:
                loc_vai_tro = ""
                if str(doi_tuong).upper() == "CB":
                    loc_vai_tro = ("AND UPPER(ISNULL(u.UserRole, '')) NOT IN "
                                   "('SINHVIEN', 'SV', 'STUDENT')")
                elif str(doi_tuong).upper() == "SV":
                    loc_vai_tro = ("AND UPPER(ISNULL(u.UserRole, '')) IN "
                                   "('SINHVIEN', 'SV', 'STUDENT')")

                ma_moc = f"NGAY_LE_{bay_gio.day:02d}{bay_gio.month:02d}"
                nguoi_nhan = cursor.execute(f"""
                    SELECT DISTINCT
                        REPLACE(REPLACE(UPPER(RTRIM(u.UserCode)), 'SV', ''), 'CB', ''),
                        u.FullName,
                        CAST(? AS NVARCHAR(300))
                    FROM tbl_users u
                    WHERE u.IsActive = 1
                      {loc_vai_tro}
                      AND EXISTS (
                            SELECT 1 FROM tbl_FCM_Tokens t
                            WHERE REPLACE(REPLACE(UPPER(RTRIM(t.StudentId)), 'SV', ''), 'CB', '')
                                  = REPLACE(REPLACE(UPPER(RTRIM(u.UserCode)), 'SV', ''), 'CB', '')
                              AND t.IsActive = 1)
                      AND NOT EXISTS (
                            SELECT 1 FROM tbl_ThongBao_TuDong_Log g
                            WHERE g.MaCauHinh = ?
                              AND g.Nam = YEAR(GETDATE())
                              AND g.MaNguoiNhan
                                  = REPLACE(REPLACE(UPPER(RTRIM(u.UserCode)), 'SV', ''), 'CB', ''))
                      AND NOT EXISTS (
                            SELECT 1 FROM tbl_Notification_User_Settings s
                            WHERE s.UserId
                                  = REPLACE(REPLACE(UPPER(RTRIM(u.UserCode)), 'SV', ''), 'CB', '')
                              AND s.Category = 'NGAY_LE' AND s.IsEnabled = 0)
                """, (ten_ngay, ma_moc)).fetchall()

                if not nguoi_nhan:
                    continue

                n = _gui_loi_chuc(cursor, ma_moc, ten_ngay, noi_dung_mau, nguoi_nhan)
                conn.commit()
                print(f"🎉 [TựĐộng] {ten_ngay}: đã gửi cho {n}/{len(nguoi_nhan)} người")
    except Exception as e:  # noqa: BLE001
        print(f"🔥 [TựĐộng] Lỗi gửi lời chúc ngày lễ: {str(e)[:150]}")


scheduler.add_job(job_full_sync_cycle, 'interval', minutes=30, next_run_time=datetime.now())

# 2. Quét nhắc lịch khẩn - 5 phút/lần
scheduler.add_job(job_reminder_30min, 'interval', minutes=5, next_run_time=datetime.now())

# 3. Mốc giờ cố định sinh Bản tin sáng/chiều (Tự động bốc thời tiết & âm lịch)
# Thông báo tự động: chạy mỗi giờ, tự bỏ qua nếu chưa tới giờ đã cấu hình.
# Chạy theo giờ thay vì đặt cứng một mốc để đổi giờ gửi trong ứng dụng là có
# hiệu lực ngay, không phải khởi động lại tiến trình.
scheduler.add_job(job_chuc_mung_sinh_nhat, 'cron', minute=5)
scheduler.add_job(job_chuc_mung_ngay_le, 'cron', minute=10)

scheduler.add_job(job_daily_summary, 'cron', hour=6, minute=30, args=['MORNING'])
scheduler.add_job(job_daily_summary, 'cron', hour=13, minute=0, args=['AFTERNOON'])

# 4. Tự động dọn dẹp bảng đợi vào 2 giờ sáng mỗi ngày
scheduler.add_job(job_cleanup_notification_queue, 'cron', hour=2, minute=0)

# 5. Biến lịch tuần thành thông báo — 15 phút/lần.
#    Chạy dày hơn chu kỳ bóc tách (30 phút) để lịch vừa cập nhật là báo ngay.
scheduler.add_job(job_xu_ly_thong_bao_lich_tuan, 'interval', minutes=15,
                  next_run_time=datetime.now())

# 6. Đồng bộ hồ sơ cán bộ — 48 giờ/lần, giữ nguyên nhịp của master_worker
scheduler.add_job(job_dong_bo_ho_so_can_bo, 'interval', hours=48, id='job_canbo')

# (Tùy chọn) Sơn có thể cho chạy ngay lúc khởi động để làm sạch hệ thống
scheduler.add_job(job_cleanup_notification_queue, 'date', run_date=datetime.now())
async def main():
    print("="*60); print("🚀 VINHUNI ULTIMATE ORCHESTRATOR IS LIVE!"); print("="*60)
    scheduler.start()
    while True:
        await asyncio.sleep(60)
        print(f"💓 [Heartbeat] {datetime.now().strftime('%H:%M:%S')} - System is healthy.")

if __name__ == "__main__":
    try: asyncio.run(main())
    except (KeyboardInterrupt, SystemExit): scheduler.shutdown()