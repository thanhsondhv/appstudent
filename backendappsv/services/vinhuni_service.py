import os
import re
import time
import hashlib
import requests
import pyodbc
import rookiepy
import unicodedata
from datetime import datetime
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
    "URL_ODOO": "https://qlvb.vinhuni.edu.vn"
}

class VinhUniFinalBoss:
    def __init__(self):
        if not os.path.exists(CONFIG["DOCS_PATH"]): os.makedirs(CONFIG["DOCS_PATH"])
        if not os.path.exists(CONFIG["TEMP_PROFILE"]): os.makedirs(CONFIG["TEMP_PROFILE"])

    def _log(self, msg):
        print(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}")

    def _clean_fn(self, text):
        if not text: return "document"
        text = unicodedata.normalize('NFKD', text).encode('ascii', 'ignore').decode('ascii')
        text = re.sub(r'[\\/*?:"<>|]', '-', text)
        return re.sub(r'\s+', '_', text).strip()[:130]

    def _parse_date(self, date_text):
        match = re.search(r'(\d{2})/(\d{2})/(\d{4})', date_text)
        if match:
            d, m, y = match.groups()
            return f"{y}-{m}-{d}"
        return None

    def _cleanup(self):
        os.system("taskkill /f /im msedgedriver.exe /t >nul 2>&1")

    # --- [PHẦN 1: QUÉT LỊCH TUẦN] ---
    def sync_weekly_schedule(self, week="current"):
        self._cleanup()
        self._log(f"📅 Bắt đầu quét lịch tuần: {week}")
        
        opts = Options()
        opts.add_argument("--headless=new")
        opts.add_argument("--disable-gpu")
        opts.add_argument(f"--user-data-dir={os.path.join(CONFIG['TEMP_PROFILE'], 'bot_runtime')}")
        
        service = Service(executable_path=CONFIG["DRIVER_PATH"])
        driver = webdriver.Edge(service=service, options=opts)

        try:
            driver.get(CONFIG["URL_CALENDAR"])
            wait = WebDriverWait(driver, 25)
            
            if week == "next":
                btn = wait.until(EC.element_to_be_clickable((By.CSS_SELECTOR, ".anticon-right")))
                driver.execute_script("arguments[0].click();", btn)
                time.sleep(3)

            wait.until(EC.presence_of_element_located((By.CLASS_NAME, "day-container")))
            days = driver.find_elements(By.CLASS_NAME, "day-container")
            
            conn = pyodbc.connect(CONFIG["DB"], autocommit=True)
            cursor = conn.cursor()

            for d_box in days:
                date_raw = d_box.find_element(By.CLASS_NAME, "day-title").text
                event_date = self._parse_date(date_raw)
                if not event_date: continue
                
                self._log(f"   ✓ Đang bóc tách ngày: {event_date}")
                slots = d_box.find_elements(By.XPATH, ".//div[contains(@class, '-slot')]")
                for slot in slots:
                    session = "Sáng" if "morning-slot" in slot.get_attribute("class") else "Chiều"
                    cards = slot.find_elements(By.CLASS_NAME, "event-card")
                    for card in cards:
                        try: time_val = card.find_element(By.CLASS_NAME, "ant-tag").text.strip()
                        except: time_val = "07:30" if session == "Sáng" else "14:00"

                        titles = card.find_elements(By.CLASS_NAME, "event-title")
                        content = titles[0].text.strip() if len(titles) > 0 else "N/A"
                        location = titles[-1].text.strip() if len(titles) > 1 else "Tại đơn vị"

                        details = card.find_elements(By.CLASS_NAME, "event-detail")
                        chair, parts = "", ""
                        for det in details:
                            txt = det.text.strip()
                            if "Chủ trì:" in txt or "CT:" in txt: chair = txt.replace("Chủ trì:","").replace("CT:","").strip()
                            elif "Thành phần:" in txt or "TP:" in txt: parts = txt.replace("Thành phần:","").replace("TP:","").strip()

                        h_str = f"{event_date}|{time_val}|{content[:50]}"
                        e_hash = hashlib.md5(h_str.encode('utf-8')).hexdigest()

                        sql = """
                            IF NOT EXISTS (SELECT 1 FROM tbl_WeeklySchedule WHERE EventHash = ?)
                            INSERT INTO tbl_WeeklySchedule (EventDate, Session, TimeValue, Content, Location, Chairperson, Participants, EventHash, CreatedAt)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, GETDATE())
                        """
                        cursor.execute(sql, (e_hash, event_date, session, time_val, content, location, chair, parts, e_hash))

            cursor.execute("EXEC sp_Sync_All_Org_Data")
            self._log("✅ Hoàn thành đồng bộ lịch và cơ cấu tổ chức.")
            conn.close()
        except Exception as e:
            self._log(f"❌ Lỗi Scraper: {e}")
        finally:
            driver.quit()

    # --- [PHẦN 2: TẢI VĂN BẢN PDF - ĐÃ SỬA LỖI IDENTITY] ---
    def sync_odoo_documents(self):
        self._log("📡 Đang lấy Cookie an toàn...")
        try:
            cookies = rookiepy.edge(["qlvb.vinhuni.edu.vn"])
            sid = next((c['value'] for c in cookies if c['name'] == 'session_id'), None)
            if not sid:
                cookies = rookiepy.chrome(["qlvb.vinhuni.edu.vn"])
                sid = next((c['value'] for c in cookies if c['name'] == 'session_id'), None)

            if not sid:
                self._log("❌ Thất bại. Hãy đăng nhập và tích 'Duy trì đăng nhập'."); return

            headers = {'Cookie': f'session_id={sid}; cids=1', 'User-Agent': 'Mozilla/5.0'}
            conn = pyodbc.connect(CONFIG["DB"], autocommit=True)
            cursor = conn.cursor()

            payload = {
                "jsonrpc": "2.0", "method": "call",
                "params": {
                    "model": "van_ban_noi_bo", "method": "search_read",
                    "args": [[["id", ">", 0]]],
                    "kwargs": {"fields": ["id", "so_ky_hieu", "trich_yeu", "tai_lieu_ids"], "limit": 40, "order": "id desc"}
                }, "id": 1
            }
            
            res = requests.post(f"{CONFIG['URL_ODOO']}/web/dataset/call_kw", json=payload, headers=headers).json()
            for doc in res.get('result', []):
                o_id = doc['id']
                if doc.get('tai_lieu_ids'):
                    fn = f"{self._clean_fn(doc['so_ky_hieu'])}.pdf"
                    cursor.execute("SELECT DocId FROM tbl_Document_Library WHERE DocId = ?", (o_id,))
                    if not cursor.fetchone():
                        self._log(f"🆕 Tải PDF mới: {doc['so_ky_hieu']}")
                        url_dl = f"{CONFIG['URL_ODOO']}/web/content?model=tai_lieu_chung&field=tai_lieu_dinh_kem_viewer&id={doc['tai_lieu_ids'][0]}&download=true"
                        rf = requests.get(url_dl, headers=headers)
                        if rf.status_code == 200 and len(rf.content) > 1000:
                            with open(os.path.join(CONFIG["DOCS_PATH"], fn), "wb") as f: f.write(rf.content)
                            
                            # 🎯 SỬA LỖI TẠI ĐÂY: Bật IDENTITY_INSERT trước khi chèn
                            try:
                                cursor.execute("SET IDENTITY_INSERT tbl_Document_Library ON")
                                cursor.execute("""
                                    INSERT INTO tbl_Document_Library (DocId, SoKyHieu, TrichYeu, FileName, IsActive) 
                                    VALUES (?, ?, ?, ?, 1)
                                """, (o_id, doc['so_ky_hieu'], doc['trich_yeu'], fn))
                                cursor.execute("SET IDENTITY_INSERT tbl_Document_Library OFF")
                            except Exception as ex_sql:
                                self._log(f"⚠️ Lỗi chèn DB cho {doc['so_ky_hieu']}: {ex_sql}")
                                # Đảm bảo tắt ngay cả khi lỗi để không ảnh hưởng lượt sau
                                cursor.execute("SET IDENTITY_INSERT tbl_Document_Library OFF")

            conn.close()
            self._log("✅ Hoàn thành đồng bộ văn bản PDF.")
        except Exception as e:
            self._log(f"❌ Lỗi Odoo Sync: {e}")

# --- [LAYER 3: CHẠY TỰ ĐỘNG VÔ TẬN] ---
if __name__ == "__main__":
    boss = VinhUniFinalBoss()
    
    # Cấu hình thời gian nghỉ (giây). 1800 giây = 30 phút
    INTERVAL = 1800 
    
    print("====================================================")
    print("🛡️ VINHUNI AUTO-SYNC SERVICE ĐANG BẮT ĐẦU CHẠY NGẦM...")
    print(f"⏰ Chu kỳ quét: {INTERVAL/60} phút một lần.")
    print("⚠️ Nhấn Ctrl + C để dừng dịch vụ.")
    print("====================================================")

    while True:
        try:
            start_run = datetime.now()
            print(f"\n🔔 [BATCH START] Bắt đầu chu kỳ quét lúc: {start_run.strftime('%H:%M:%S')}")
            
            # 1. Quét lịch tuần hiện tại
            boss.sync_weekly_schedule(week="current")
            
            # 2. Quét lịch tuần kế tiếp (Rất quan trọng để chuẩn bị trước)
            boss.sync_weekly_schedule(week="next")
            
            # 3. Đồng bộ văn bản PDF
            boss.sync_odoo_documents()
            
            end_run = datetime.now()
            duration = (end_run - start_run).total_seconds()
            
            print(f"✨ [BATCH FINISHED] Hoàn thành lúc: {end_run.strftime('%H:%M:%S')} (Mất {duration:.1f}s)")
            print(f"💤 Đang nghỉ {INTERVAL/60} phút trước lượt quét tới...")
            
            # Nghỉ ngơi
            time.sleep(INTERVAL)
            
        except KeyboardInterrupt:
            print("\n🛑 Đã dừng dịch vụ theo lệnh người dùng.")
            break
        except Exception as e:
            print(f"🔥 LỖI HỆ THỐNG NGOÀI Ý MUỐN: {e}")
            print("🕒 Sẽ thử lại sau 60 giây...")
            time.sleep(60) # Nếu lỗi thì đợi 1 phút rồi thử lại, tránh spam lỗi liên tục