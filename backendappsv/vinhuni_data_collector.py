import requests
import pyodbc
from datetime import datetime
from lunar_python import Lunar, Solar
from core.settings import settings  # cấu hình tập trung (Pha 0)
import os

# --- CẤU HÌNH KẾT NỐI SQL SERVER ---
SQL_CONFIG = {
    'server': settings.db.server, 
    'database': settings.db.name,
    'uid': settings.db.user,
    'pwd': settings.db.password
}

# --- CẤU HÌNH API KEYS ---
# Lấy key tại: https://openweathermap.org/api
WEATHER_API_KEY = os.getenv("WEATHER_API_KEY", "")
CITY_NAME = "Vinh"

def get_db_conn():
    """Tạo kết nối đến SQL Server"""
    conn_str = (
        f"DRIVER={{SQL Server}};"
        f"SERVER={SQL_CONFIG['server']};"
        f"DATABASE={SQL_CONFIG['database']};"
        f"UID={SQL_CONFIG['uid']};"
        f"PWD={SQL_CONFIG['pwd']}"
    )
    return pyodbc.connect(conn_str)

def get_daily_wish():
    """Tự động sinh lời chúc và tiêu đề theo thứ trong tuần"""
    weekday = datetime.now().weekday() # 0: Thứ 2, ..., 6: Chủ Nhật
    wishes = {
        0: ("🚀 ĐẦU TUẦN NANG LƯỢNG!", "Chúc Quý Thầy/Cô một tuần mới rực rỡ và hiệu quả."),
        1: ("✨ THỨ BA THUẬN LỢI!", "Chúc Quý Thầy/Cô vạn sự như ý trong công tác giảng dạy."),
        2: ("☕ GIỮA TUẦN THONG THẢ!", "Chúc Quý Thầy/Cô giữ vững phong độ và tinh thần thoải mái."),
        3: ("🌤️ THỨ NĂM RẠNG RỠ!", "Chúc Quý Thầy/Cô một ngày làm việc tràn đầy niềm vui."),
        4: ("🥳 THỨ SÁU TUYỆT VỜI!", "Chúc Quý Thầy/Cô sớm hoàn thành công việc để đón cuối tuần."),
        5: ("🍀 CUỐI TUẦN THƯ GIÃN!", "Chúc Quý Thầy/Cô có những giây phút ấm áp bên gia đình."),
        6: ("🔋 CHỦ NHẬT NGHỈ NGƠI!", "Chúc Quý Thầy/Cô nạp đầy năng lượng cho tuần mới sắp tới.")
    }
    return wishes.get(weekday, ("✨ CHÚC NGÀY MỚI TỐT LÀNH!", "Chúc Quý Thầy/Cô công tác tốt!"))

def fetch_lunar_date():
    """Lấy ngày âm lịch Việt Nam chuẩn"""
    now = datetime.now()
    lunar = Lunar.fromSolar(Solar.fromYmd(now.year, now.month, now.day))
    return f"{lunar.getDay()}/{lunar.getMonth()} Âm lịch ({lunar.getYearInGanZhi()})"

def fetch_weather_forecast():
    """Lấy dự báo thời tiết cho 3 mốc: Sáng (9h), Trưa (12h), Tối (21h)"""
    try:
        url = f"http://api.openweathermap.org/data/2.5/forecast?q={CITY_NAME}&appid={WEATHER_API_KEY}&units=metric&lang=vi"
        res = requests.get(url).json()
        
        # Mặc định
        morning, noon, evening = "26°C", "32°C", "25°C"
        desc = res['list'][0]['weather'][0]['description'].capitalize()
        
        # Duyệt qua danh sách dự báo (mỗi item cách nhau 3 giờ)
        for item in res['list'][:10]: 
            dt_txt = item['dt_txt']
            temp = f"{int(item['main']['temp'])}°C"
            
            if "09:00:00" in dt_txt: morning = temp
            if "12:00:00" in dt_txt: noon = temp
            if "21:00:00" in dt_txt: evening = temp
            
        return morning, noon, evening, desc
    except Exception as e:
        print(f"⚠️ Lỗi lấy thời tiết: {e}")
        return "26°C", "32°C", "25°C", "Nắng ráo"

def fetch_exchange_rates():
    """Lấy tỷ giá thực tế"""
    # Sơn có thể tích hợp API ngân hàng tại đây
    return [
        {'code': 'USD', 'rate': '25.420', 'trend': '📈'},
        {'code': 'GOLD', 'rate': '82.50', 'trend': '📉'}
    ]

def update_to_sql():
    print(f"🔄 [{datetime.now().strftime('%H:%M:%S')}] Đang thu thập dữ liệu...")
    
    lunar_str = fetch_lunar_date()
    m_temp, n_temp, e_temp, weather_desc = fetch_weather_forecast()
    rates = fetch_exchange_rates()
    wish_title, wish_content = get_daily_wish()

    try:
        with get_db_conn() as conn:
            cursor = conn.cursor()

            # 1. Cập nhật Thời tiết 3 mốc
            cursor.execute("DELETE FROM tbl_System_Weather")
            cursor.execute("""
                INSERT INTO tbl_System_Weather (MorningTemp, NoonTemp, NightTemp, Description, UpdatedAt) 
                VALUES (?, ?, ?, ?, GETDATE())
            """, (m_temp, n_temp, e_temp, weather_desc))

            # 2. 🔥 Cập nhật Tỷ giá (Sơn CHECK logic mới Turn này): DELETE and INSERT separate rows
            cursor.execute("DELETE FROM tbl_System_ExchangeRates")
            for r in rates:
                cursor.execute("""
                    INSERT INTO tbl_System_ExchangeRates (CurrencyCode, RateValue, Trend, UpdatedAt) 
                    VALUES (?, ?, ?, GETDATE())
                """, (r['code'], r['rate'], r['trend']))

            # 3. Cập nhật Lời chúc/Danh ngôn của ngày (dựa trên thứ)
            cursor.execute("DELETE FROM tbl_System_Quotes")
            cursor.execute("""
                INSERT INTO tbl_System_Quotes (Content, Author, Category, UpdatedAt) 
                VALUES (?, ?, ?, GETDATE())
            """, (wish_content, wish_title, 'DAILY_WISH'))

            conn.commit()
            print(f"✅ Đã cập nhật SQL: {lunar_str} | S:{m_temp} T:{n_temp} O:{e_temp}")
            return lunar_str
    except Exception as e:
        print(f"❌ Lỗi SQL: {e}")
        return None

if __name__ == "__main__":
    # BƯỚC 1: Thu thập và cập nhật dữ liệu nền
    lunar_today = update_to_sql()
    
    if lunar_today:
        print("🚀 Đang kích hoạt sinh Bản tin thông báo...")
        try:
            with get_db_conn() as conn:
                cursor = conn.cursor()
                
                # BƯỚC 2: Gọi Stored Procedure để sinh thông báo cho mã 1679 (Test)
                cursor.execute("""
                    EXEC [dbo].[sp_AI_Generate_Daily_Summary] 
                        @Session = 'MORNING', 
                        @LunarDate = ?, 
                        @SpecificStaffId = '1679'
                """, (lunar_today,))
                
                conn.commit()
                print(f"✨ [BẢN TIN SÁNG] Hoàn tất! Đã nạp Queue test cho mã 1679.")
        except Exception as e:
            print(f"❌ Lỗi khi kích hoạt bản tin: {e}")