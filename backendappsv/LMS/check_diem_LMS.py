import requests
import urllib3
import json

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

DOMAIN = "https://elearning.vinhuni.edu.vn"
TEST_USER = "245714011410023"
TEST_PASS = "245714011410023" # Giả định pass = masv

def test_student_grades():
    print(f"🚀 Đang kiểm tra cho SV: {TEST_USER}...")
    
    # 1. Lấy Token
    token_url = f"{DOMAIN}/login/token.php"
    res_token = requests.get(token_url, params={
        "username": TEST_USER, "password": TEST_PASS, "service": "moodle_mobile_app"
    }, verify=False).json()
    
    token = res_token.get("token")
    if not token:
        print("❌ Lỗi: Không lấy được Token. Kiểm tra lại mật khẩu!")
        return

    # 2. Lấy Site Info để biết UserID nội bộ (BẮT BUỘC)
    api_url = f"{DOMAIN}/webservice/rest/server.php"
    info = requests.post(api_url, data={
        "wstoken": token, "wsfunction": "core_webservice_get_site_info", "moodlewsrestformat": "json"
    }, verify=False).json()
    
    lms_uid = info.get('userid')
    fullname = info.get('fullname')
    print(f"✅ Đã đăng nhập: {fullname} (LMS ID: {lms_uid})")

    # 3. Lấy 1 môn học bất kỳ để test điểm
    courses = requests.post(api_url, data={
        "wstoken": token, "wsfunction": "core_enrol_get_users_courses", "userid": lms_uid, "moodlewsrestformat": "json"
    }, verify=False).json()

    if not isinstance(courses, list) or len(courses) == 0:
        print("❌ Không tìm thấy môn học nào để test.")
        return

    test_course = courses[0]
    cid = test_course['id']
    print(f"🔍 Đang thử lấy điểm môn: {test_course['fullname']} (ID: {cid})")

    # --- THỬ CÁCH 1: gradereport_user_get_grade_items ---
    print("\n--- [THỬ CÁCH 1: gradereport_user_get_grade_items] ---")
    p1 = {
        "wstoken": token,
        "wsfunction": "gradereport_user_get_grade_items",
        "courseid": cid,
        "userid": lms_uid, # Truyền chính xác ID của mình vào
        "moodlewsrestformat": "json"
    }
    res1 = requests.post(api_url, data=p1, verify=False).json()
    if "exception" in res1:
        print(f"❌ Cách 1 thất bại: {res1.get('message')}")
    else:
        print(f"✅ Cách 1 THÀNH CÔNG! Đã thấy {len(res1['usergrades'][0]['gradeitems'])} mục điểm.")

    # --- THỬ CÁCH 2: core_grades_get_user_grades ---
    print("\n--- [THỬ CÁCH 2: core_grades_get_user_grades] ---")
    p2 = {
        "wstoken": token,
        "wsfunction": "core_grades_get_user_grades",
        "courseid": cid,
        "userids[0]": lms_uid, 
        "moodlewsrestformat": "json"
    }
    res2 = requests.post(api_url, data=p2, verify=False).json()
    if "exception" in res2:
        print(f"❌ Cách 2 thất bại: {res2.get('message')}")
    else:
        print(f"✅ Cách 2 THÀNH CÔNG! Đã lấy được bảng điểm.")
        # In thử 1 dòng điểm
        item = res2['usergrades'][0]['gradeitems'][0]
        print(f"📊 Ví dụ: {item.get('itemname')} = {item.get('gradeformatted')}")

if __name__ == "__main__":
    test_student_grades()