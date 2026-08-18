import requests
import urllib3
import json

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

DOMAIN = "https://elearning.vinhuni.edu.vn"
# Thử với 1 MaSV cụ thể
TEST_USER = "235751020516001" 
TEST_PASS = "235751020516001"

def peek_moodle_data():
    # 1. Lấy Token
    token_res = requests.get(f"{DOMAIN}/login/token.php", params={
        "username": TEST_USER, "password": TEST_PASS, "service": "moodle_mobile_app"
    }, verify=False).json()
    
    token = token_res.get("token")
    if not token:
        print("❌ Không lấy được token. Kiểm tra lại tài khoản!")
        return

    # 2. Lấy Site Info
    api_url = f"{DOMAIN}/webservice/rest/server.php"
    info = requests.post(api_url, data={
        "wstoken": token, "wsfunction": "core_webservice_get_site_info", "moodlewsrestformat": "json"
    }, verify=False).json()
    uid = info.get('userid')

    # 3. Lấy danh sách môn học - ĐÂY LÀ PHẦN QUAN TRỌNG
    courses = requests.post(api_url, data={
        "wstoken": token, "wsfunction": "core_enrol_get_users_courses", "userid": uid, "moodlewsrestformat": "json"
    }, verify=False).json()

    if isinstance(courses, list) and len(courses) > 0:
        first_course = courses[0]
        
        print("\n--- 📋 DANH SÁCH CÁC TRƯỜNG (COLUMNS) TRẢ VỀ ---")
        print(list(first_course.keys()))
        
        print("\n--- 🔍 DỮ LIỆU MẪU CỦA 1 MÔN HỌC ---")
        # In đẹp JSON để dễ soi
        print(json.dumps(first_course, indent=4, ensure_ascii=False))
        
        # Kiểm tra riêng các trường liên quan đến ngày tháng
        print("\n--- 📅 KIỂM TRA TRƯỜNG THỜI GIAN ---")
        print(f"Start Date: {first_course.get('startdate')} (Unix Timestamp)")
        print(f"End Date: {first_course.get('enddate')} (Unix Timestamp)")
        
        if first_course.get('enddate') == 0:
            print("❗ Cảnh báo: EndDate bằng 0 (Giáo viên không set ngày kết thúc).")
    else:
        print("❌ Không tìm thấy môn học nào.")

if __name__ == "__main__":
    peek_moodle_data()