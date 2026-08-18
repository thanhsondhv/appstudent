import requests
import urllib3
import json

# 1. Tắt cảnh báo SSL để màn hình kết quả không bị rối
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# --- KHU VỰC CẤU HÌNH ---
DOMAIN = "https://elearning.vinhuni.edu.vn"

# Danh sách Token Sơn đã tìm thấy - Chọn 1 cái để chạy
# Ưu tiên dùng 'User_API' hoặc 'Mobile'
TOKENS = {
    "User_API": "0b9086112c4b0ed3818f1ff73ab3bcb2", 
    "Mobile": "2e8e99693370bf2334171ad6c64fbc8a",
    "Attendance": "fa5fced8752511028dcd38cb5407eb39"
}

# CHỌN MÃ MUỐN TEST Ở ĐÂY (Thay 'User_API' bằng 'Mobile' nếu muốn thử mã khác)
CURRENT_TOKEN = TOKENS["User_API"] 

def get_my_courses():
    try:
        url = f"{DOMAIN}/webservice/rest/server.php"
        
        # 2. Bước 1: Kiểm tra xem Token có "sống" không và lấy UserID
        params_info = {
            "wstoken": CURRENT_TOKEN,
            "wsfunction": "core_webservice_get_site_info",
            "moodlewsrestformat": "json"
        }
        
        print(f"📡 Đang kết nối tới LMS với mã: {CURRENT_TOKEN[:10]}...")
        response_info = requests.get(url, params=params_info, verify=False, timeout=15)
        user_info = response_info.json()
        
        # Nếu Moodle trả về lỗi exception
        if "exception" in user_info:
            print(f"❌ Lỗi Token: {user_info.get('message')}")
            return

        user_id = user_info.get('userid')
        print(f"✅ Xác thực thành công: {user_info.get('fullname')} (ID: {user_id})")

        # 3. Bước 2: Lấy danh sách môn học của tài khoản này
        params_courses = {
            "wstoken": CURRENT_TOKEN,
            "wsfunction": "core_enrol_get_users_courses",
            "moodlewsrestformat": "json",
            "userid": user_id
        }
        
        response_courses = requests.get(url, params=params_courses, verify=False, timeout=15)
        courses = response_courses.json()
        
        print("\n📚 DANH SÁCH MÔN HỌC ĐANG HỌC:")
        if not courses or not isinstance(courses, list):
            print("- Trống hoặc không có quyền xem danh sách môn.")
        else:
            for c in courses:
                # Lấy tên môn và tiến độ %
                name = c.get('fullname')
                progress = c.get('progress')
                p_str = f"{progress}%" if progress is not None else "0%"
                print(f"  + {name} | Tiến độ: {p_str}")

    except Exception as e:
        print(f"🔥 Lỗi phát sinh: {str(e)}")

if __name__ == "__main__":
    get_my_courses()