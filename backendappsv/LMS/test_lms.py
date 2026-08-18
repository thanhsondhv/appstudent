# import requests
# import urllib3

# urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# # Dùng Token của bạn Phương mà bạn vừa lấy được
# TOKEN_PHUONG = "a0a826d195..." # Thay mã đầy đủ vào đây
# DOMAIN = "https://elearning.vinhuni.edu.vn/webservice/rest/server.php"

# def get_detailed_grades(course_id):
    # print(f"\n📊 ĐANG LẤY BẢNG ĐIỂM CHI TIẾT MÔN ID: {course_id}")
    
    # params = {
        # "wstoken": TOKEN_PHUONG,
        # "wsfunction": "gradereport_user_get_grade_items",
        # "courseid": course_id,
        # "moodlewsrestformat": "json"
    # }
    
    # try:
        # res = requests.post(DOMAIN, data=params, verify=False).json()
        
        # # Moodle trả về cấu hình usergrades là một list
        # if "usergrades" in res:
            # grade_data = res['usergrades'][0]
            # print(f"📘 Môn: {grade_data['coursefullname']}")
            # print("-" * 60)
            # print(f"{'HẠNG MỤC ĐIỂM':<40} | {'ĐIỂM'}")
            # print("-" * 60)
            
            # for item in grade_data['gradeitems']:
                # name = item.get('itemname')
                # grade = item.get('gradeformatted', '-')
                
                # # Chỉ in những mục có tên (bỏ qua các mục tổng kết thừa)
                # if name:
                    # print(f"{name:<40} | {grade}")
        # else:
            # print("❌ Không lấy được bảng điểm. Có thể môn này chưa có cột điểm.")
            
    # except Exception as e:
        # print(f"🔥 Lỗi: {e}")

# if __name__ == "__main__":
    # # Test thử môn Tiếng Pháp 2 (4138)
    # get_detailed_grades(4138)
# # import requests
# # import urllib3
# # import json

# # # 1. Tắt cảnh báo SSL
# # urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# # # --- THÔNG TIN CỦA SINH VIÊN CẦN LẤY ---
# # USER_72467 = "205714023110061"     # Thay bằng Mã SV của bạn Phương
# # PASS_72467 = "205714023110061" # Thay bằng Mật khẩu của bạn Phương

# # DOMAIN = "https://elearning.vinhuni.edu.vn"

# # def get_data_full_access():
    # # print(f"🔑 ĐANG XIN TOKEN MỚI CHO SINH VIÊN: {USER_72467}...")
    
    # # # BƯỚC 1: Lấy Token từ login/token.php
    # # # Sử dụng service 'moodle_mobile_app' vì đây là service mặc định có sẵn 296 hàm
    # # token_url = f"{DOMAIN}/login/token.php"
    # # token_params = {
        # # "username": USER_72467,
        # # "password": PASS_72467,
        # # "service": "moodle_mobile_app"
    # # }
    
    # # try:
        # # token_res = requests.get(token_url, params=token_params, verify=False).json()
        
        # # if "token" not in token_res:
            # # print(f"❌ Không lấy được Token. Lỗi: {token_res.get('error')}")
            # # return
        
        # # new_token = token_res["token"]
        # # print(f"✅ Lấy Token thành công: {new_token[:10]}...")

        # # # BƯỚC 2: Dùng Token mới để lấy Site Info (để lấy chuẩn UserID)
        # # service_url = f"{DOMAIN}/webservice/rest/server.php"
        # # info_params = {
            # # "wstoken": new_token,
            # # "wsfunction": "core_webservice_get_site_info",
            # # "moodlewsrestformat": "json"
        # # }
        # # site_info = requests.post(service_url, data=info_params, verify=False).json()
        # # real_uid = site_info.get('userid')
        # # fullname = site_info.get('fullname')

        # # print(f"📊 Đang truy vấn môn học cho: {fullname} (ID: {real_uid})")

        # # # BƯỚC 3: Lấy danh sách môn học (Lúc này sẽ ra 100% môn vì là Token chính chủ)
        # # course_params = {
            # # "wstoken": new_token,
            # # "wsfunction": "core_enrol_get_users_courses",
            # # "userid": real_uid,
            # # "moodlewsrestformat": "json"
        # # }
        # # courses = requests.post(service_url, data=course_params, verify=False).json()

        # # print("-" * 80)
        # # print(f"{'ID':<10} | {'TIẾN ĐỘ':<10} | {'TÊN MÔN HỌC'}")
        # # print("-" * 80)

        # # if isinstance(courses, list):
            # # for c in courses:
                # # cid = c.get('id')
                # # name = c.get('fullname')
                # # prog = c.get('progress', 0)
                # # print(f"{cid:<10} | {prog if prog else 0:<10}% | {name}")
        # # else:
            # # print("❌ Lỗi dữ liệu môn học:", courses)

    # # except Exception as e:
        # # print(f"🔥 Lỗi hệ thống: {e}")

# # if __name__ == "__main__":
    # # get_data_full_access()
# import requests
# import json
# from datetime import datetime

# #Cấu hình
# DOMAIN = "https://elearning.vinhuni.edu.vn/webservice/rest/server.php"
# WSTOKEN = "79c538250843fc1e09a068177db595f9"

# def get_user_courses_pro(target_userid):
    # params = {
        # "wstoken": WSTOKEN,
        # "wsfunction": "core_enrol_get_users_courses",
        # "userid": target_userid, # Tham số bắt buộc theo tài liệu
        # "moodlewsrestformat": "json"
    # }
    
    # try:
        # response = requests.post(DOMAIN, data=params, verify=False)
        # courses = response.json()

        # # Kiểm tra nếu trả về lỗi Exception (theo tài liệu Tin nhắn lỗi)
        # if isinstance(courses, dict) and "exception" in courses:
            # print(f"❌ Lỗi: {courses['message']}")
            # return

        # print(f"📚 DANH SÁCH MÔN HỌC CỦA USER ID: {target_userid}")
        # print("-" * 80)
        # print(f"{'ID':<6} | {'TÊN MÔN':<40} | {'TIẾN ĐỘ':<8} | {'BẮT ĐẦU'}")
        # print("-" * 80)

        # for c in courses:
            # cid = c.get('id')
            # fullname = c.get('fullname')
            # # Progress trả về kiểu Double (số thực)
            # progress = c.get('progress')
            # p_str = f"{progress:.1f}%" if progress is not None else "0.0%"
            
            # # Startdate trả về Timestamp (int), cần đổi sang ngày tháng
            # s_date = c.get('startdate', 0)
            # date_str = datetime.fromtimestamp(s_date).strftime('%d/%m/%Y') if s_date > 0 else "N/A"

            # print(f"{cid:<6} | {fullname[:40]:<40} | {p_str:<8} | {date_str}")
            
    # except Exception as e:
        # print(f"🔥 Lỗi kết nối: {e}")

# if __name__ == "__main__":
    # # Test với ID của chính bạn hoặc ID 191556
    # get_user_courses_pro(72467)
# import requests
# import urllib3
# import json

# urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# DOMAIN = "https://elearning.vinhuni.edu.vn/webservice/rest/server.php"
# WSTOKEN = "2e8e99693370bf2334171ad6c64fbc8a"

# def check_moodle_version():
    # print("🔍 ĐANG TRUY VẤN THÔNG TIN HỆ THỐNG LMS...")
    # payload = {
        # "wstoken": WSTOKEN,
        # "wsfunction": "core_webservice_get_site_info",
        # "moodlewsrestformat": "json"
    # }
    
    # try:
        # response = requests.post(DOMAIN, data=payload, verify=False, timeout=15)
        # res = response.json()
        
        # if "exception" in res:
            # print(f"❌ Không thể kiểm tra version: {res.get('message')}")
            # return

        # print("\n" + "="*50)
        # print(f"🏢 TÊN HỆ THỐNG: {res.get('sitename')}")
        # print(f"🚀 PHIÊN BẢN (RELEASE): {res.get('release', 'Không xác định')}")
        # print(f"🔢 MÃ VERSION (BUILD): {res.get('version', 'Không xác định')}")
        # print(f"👤 USER ĐANG TEST: {res.get('fullname')}")
        # print("="*50)

        # # Kiểm tra các tính năng nâng cao (Advanced Features)
        # features = res.get('advancedfeatures', [])
        # print("\n⚙️ CÁC TÍNH NĂNG NÂNG CAO ĐANG BẬT:")
        # for feature in features:
            # status = "✅ ON" if feature['value'] == 1 else "❌ OFF"
            # print(f" - {feature['name']:<25}: {status}")

        # # Kiểm tra danh sách hàm thực tế mà Token này "nhìn thấy"
        # functions = [f['name'] for f in res.get('functions', [])]
        # print(f"\n📦 TỔNG SỐ HÀM TOKEN ĐƯỢC PHÉP GỌI: {len(functions)}")
        
        # # Check nhanh 2 hàm Sơn cần
        # needed = ["core_user_get_users_by_field", "core_enrol_get_users_courses"]
        # print("\n🔍 KIỂM TRA HÀM ĐÃ CẤP:")
        # for n in needed:
            # msg = "✅ ĐÃ CÓ" if n in functions else "❌ THIẾU"
            # print(f" - {n:<40}: {msg}")

    # except Exception as e:
        # print(f"🔥 Lỗi kết nối: {e}")

# if __name__ == "__main__":
    # check_moodle_version()
    
# import requests
# import urllib3

# urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# DOMAIN = "https://elearning.vinhuni.edu.vn/webservice/rest/server.php"
# WSTOKEN = "2e8e99693370bf2334171ad6c64fbc8a" # Token Mobile Sơn vừa test thành công

# def get_real_data():
    # print("🚀 ĐANG TRUY VẤN DỮ LIỆU THỰC TẾ...")
    
    # # 1. Lấy UserID từ Site Info
    # res_info = requests.post(DOMAIN, data={
        # "wstoken": WSTOKEN, 
        # "wsfunction": "core_webservice_get_site_info", 
        # "moodlewsrestformat": "json"
    # }, verify=False).json()
    
    # # Kiểm tra xem có lỗi ở bước lấy Site Info không
    # if isinstance(res_info, dict) and "exception" in res_info:
        # print(f"❌ Lỗi Site Info: {res_info.get('message')}")
        # return

    # uid = res_info.get('userid')
    # fullname = res_info.get('fullname')
    # print(f"📊 Đang lấy dữ liệu cho: {fullname} (ID: {uid})\n")

    # # 2. Lấy danh sách môn học
    # res_courses = requests.post(DOMAIN, data={
        # "wstoken": WSTOKEN, 
        # "wsfunction": "core_enrol_get_users_courses", 
        # "userid": uid,
        # "moodlewsrestformat": "json"
    # }, verify=False).json()

    # # CHỐT CHẶN QUAN TRỌNG: Kiểm tra nếu kết quả KHÔNG PHẢI là một danh sách (List)
    # if not isinstance(res_courses, list):
        # print("❌ Lỗi: Server không trả về danh sách môn học.")
        # if isinstance(res_courses, dict):
            # print(f"📝 Thông báo từ LMS: {res_courses.get('message', 'Không rõ lỗi')}")
            # print(f"🔍 Mã lỗi: {res_courses.get('errorcode')}")
        # return

    # # Nếu là List, tiến hành in dữ liệu
    # print(f"{'ID':<10} | {'TIẾN ĐỘ':<10} | {'TÊN MÔN HỌC'}")
    # print("-" * 75)
    
    # for c in res_courses:
        # # Kiểm tra c có phải là dict không trước khi lấy id
        # if isinstance(c, dict):
            # cid = c.get('id')
            # name = c.get('fullname')
            # prog = c.get('progress', 0)
            # print(f"{cid:<10} | {prog if prog else 0:<10}% | {name}")

# if __name__ == "__main__":
    # get_real_data()
# import requests
# import urllib3
# import json

# urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# DOMAIN = "https://elearning.vinhuni.edu.vn/webservice/rest/server.php"
# WSTOKEN = "2e8e99693370bf2334171ad6c64fbc8a"
# TARGET_MASV = 191556 # Mã sinh viên cần kiểm tra

# def get_messages():
    # print(f"🔍 ĐANG KIỂM TRA HỘP THƯ CHO MSV: {TARGET_MASV}...")

    # BƯỚC 1: Tìm ID nội bộ của sinh viên từ Mã SV
    # res_user = requests.post(DOMAIN, data={
        # "wstoken": WSTOKEN,
        # "wsfunction": "core_user_get_users_by_field",
        # "field": "username", # Thường mã SV là username
        # "values[0]": TARGET_MASV,
        # "moodlewsrestformat": "json"
    # }, verify=False).json()

    # if not res_user or not isinstance(res_user, list):
        # print("❌ Không tìm thấy sinh viên này trên hệ thống.")
        # return

    # target_uid = res_user[0]['id']
    # target_name = res_user[0]['fullname']
    # print(f"✅ Đã xác định: {target_name} (Moodle ID: {target_id})")

    # BƯỚC 2: Truy vấn danh sách tin nhắn (Messages)
    # Hàm này lấy các tin nhắn chưa đọc gửi đến sinh viên này
    # res_messages = requests.post(DOMAIN, data={
        # "wstoken": WSTOKEN,
        # "wsfunction": "core_message_get_messages",
        # "useridto": target_uid, # Tin nhắn gửi ĐẾN sinh viên này
        # "type": "both",        # Lấy cả tin nhắn cá nhân và thông báo hệ thống
        # "read": 0,             # Chỉ lấy tin CHƯA ĐỌC (Sửa thành 1 để lấy tin đã đọc)
        # "moodlewsrestformat": "json"
    # }, verify=False).json()

    # print("\n📩 DANH SÁCH THƯ/THÔNG BÁO MỚI:")
    # print("-" * 60)

    # messages = res_messages.get('messages', [])
    # if not messages:
        # print("📭 Hộp thư trống (Không có tin nhắn mới).")
    # else:
        # for msg in messages:
            # sender = msg.get('userfromfullname', 'Hệ thống')
            # content = msg.get('text', '')
            # time_sent = msg.get('timecreated') 
            # Chuyển đổi thời gian nếu cần
            # print(f"📧 Từ: {sender}")
            # print(f"📝 Nội dung: {content[:100]}...") # In 100 ký tự đầu
            # print("-" * 30)

# if __name__ == "__main__":
    # get_messages()
    
import requests
import urllib3
import json

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

DOMAIN = "https://elearning.vinhuni.edu.vn/webservice/rest/server.php"
WSTOKEN = "5e8b942334d9f70b6d14aa6af4f265ee"
TARGET_UID = 72467 # ID lấy từ URL profile.php?id=191556

def get_data_for_other_user():
    print(f"🚀 ĐANG TRUY VẤN DỮ LIỆU CHO USER ID: {TARGET_UID}...")
    
    # 1. Bước kiểm tra thông tin User trước (Để xem Token có quyền "nhìn" thấy người này không)
    print("🔍 Bước 1: Kiểm tra thông tin định danh của User...")
    res_user = requests.post(DOMAIN, data={
        "wstoken": WSTOKEN,
        "wsfunction": "core_user_get_users_by_field",
        "field": "id",
        "values[0]": TARGET_UID,
        "moodlewsrestformat": "json"
    }, verify=False).json()

    if isinstance(res_user, list) and len(res_user) > 0:
        user = res_user[0]
        print(f"   ✅ Tìm thấy: {user.get('fullname')} - MSV: {user.get('username')}")
    else:
        print("   ❌ Lỗi: Token của bạn không có quyền xem thông tin người dùng khác.")
        print(f"   📝 Phản hồi: {res_user}")

    # 2. Bước lấy danh sách môn học của User đó
    print(f"\n🔍 Bước 2: Lấy danh sách môn học của ID {TARGET_UID}...")
    res_courses = requests.post(DOMAIN, data={
        "wstoken": WSTOKEN, 
        "wsfunction": "core_enrol_get_users_courses", 
        "userid": TARGET_UID, # Truyền ID người khác vào đây
        "moodlewsrestformat": "json"
    }, verify=False).json()

    if isinstance(res_courses, list):
        print(f"   🎉 THÀNH CÔNG! Đã lấy được {len(res_courses)} môn học.")
        print(f"{'ID':<10} | {'TÊN MÔN HỌC'}")
        print("-" * 50)
        for c in res_courses:
            print(f"{c.get('id'):<10} | {c.get('fullname')}")
    else:
        print("   ❌ THẤT BẠI: Server từ chối cho xem môn học của người này.")
        if isinstance(res_courses, dict):
            print(f"   📝 Thông báo lỗi: {res_courses.get('message')}")
            print(f"   🔍 Mã lỗi: {res_courses.get('errorcode')}")

if __name__ == "__main__":
    get_data_for_other_user()
    
    
# import requests
# import urllib3
# import json

# # Tắt cảnh báo SSL
# urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# # --- CẤU HÌNH ---
# DOMAIN = "https://elearning.vinhuni.edu.vn/webservice/rest/server.php"
# WSTOKEN = "79c538250843fc1e09a068177db595f9" 

# def test_get_user_grades(target_userid, course_id):
    # print(f"📊 Đang thử lấy ĐIỂM CHI TIẾT của User {target_userid} tại môn {course_id}...")
    # res = requests.post(DOMAIN, data={
        # "wstoken": WSTOKEN,
        # "wsfunction": "gradereport_user_get_grade_items",
        # "userid": target_userid,
        # "courseid": course_id,
        # "moodlewsrestformat": "json"
    # }, verify=False).json()
    
    # if "usergrades" in res:
        # print("✅ THÀNH CÔNG! Token này có quyền xem điểm người khác.")
        # # In thử điểm của item đầu tiên
        # grade_item = res['usergrades'][0]['gradeitems'][0]
        # print(f"📝 Cột điểm: {grade_item['itemname']} | Điểm: {grade_item['gradeformatted']}")
    # else:
        # print(f"❌ Bị chặn: {res.get('message', 'Không có quyền xem điểm')}")

# # Thử với môn LMS (2093) mà Sơn đã từng lấy được tiến độ
# test_get_user_grades(667,2093)


# Bước 1: Gán Role Manager ở cấp độ Hệ thống (System)


# Truy cập: Site administration > Users > Permissions > Assign system roles.

# Trong danh sách các Role, hãy nhấp chọn Manager.

# Ở ô bên phải (Potential users), tìm kiếm tên tài khoản mà Sơn dùng để lấy Token (ntson).

# Nhấn nút Add để đưa tài khoản đó sang cột bên trái (Existing users).



# Bước 2: Cấu hình Service cho phép User này truy cập
# Dù đã là Manager, nhưng Service vẫn phải xác nhận User này được phép sử dụng.

# Vào: Site administration > Server > Web services > External services.

# Tìm đến Service bạn đang dùng, nhấn vào Authorized users.

# Nếu tài khoản của Sơn chưa có ở cột bên phải, hãy Add nó vào.

# Quan trọng: Đảm bảo Service này đã được "Add" đủ các hàm như core_enrol_get_users_courses và gradereport_user_get_grade_items, gradereport_user_get_grade_items