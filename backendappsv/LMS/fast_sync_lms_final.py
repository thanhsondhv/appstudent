from core.settings import settings  # cấu hình tập trung (Pha 0)
# import requests
# import pyodbc
# import urllib3
# import time
# from concurrent.futures import ThreadPoolExecutor

# # Tắt cảnh báo SSL
# urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# # --- CẤU HÌNH ---
# DOMAIN = "https://elearning.vinhuni.edu.vn"
# LOCAL_CONN_STR = settings.db.local_conn_str

# # Mốc thời gian: Chỉ lấy môn từ 01/01/2026 (Timestamp: 1767225600)
# CURRENT_TERM_START = 1767225600 

# def sync_grades(cursor, masv, token, course_id):
    # """Hàm lấy điểm chi tiết cho một môn học"""
    # url = f"{DOMAIN}/webservice/rest/server.php"
    # params = {
        # "wstoken": token,
        # "wsfunction": "gradereport_user_get_grade_items",
        # "courseid": course_id,
        # "moodlewsrestformat": "json"
    # }
    # try:
        # res = requests.post(url, data=params, verify=False, timeout=10).json()
        # if "usergrades" in res:
            # items = res['usergrades'][0].get('gradeitems', [])
            # for item in items:
                # name = item.get('itemname')
                # grade = item.get('gradeformatted', '-')
                # weight = item.get('weightraw', '')
                
                # if name: # Chỉ lưu những hạng mục có tên điểm
                    # # Cắt ngắn ItemName nếu quá dài (đề phòng)
                    # safe_name = name[:350]
                    # cursor.execute("""
                        # MERGE LMS_Grades AS target
                        # USING (SELECT ? AS MaSV, ? AS CourseID, ? AS ItemName) AS source
                        # ON (target.MaSV = source.MaSV AND target.CourseID = source.CourseID AND target.ItemName = source.ItemName)
                        # WHEN MATCHED THEN 
                            # UPDATE SET Grade = ?, Weight = ?, LastUpdate = GETDATE()
                        # WHEN NOT MATCHED THEN 
                            # INSERT (MaSV, CourseID, ItemName, Grade, Weight, LastUpdate)
                            # VALUES (?, ?, ?, ?, ?, GETDATE());
                    # """, (masv, course_id, safe_name, grade, str(weight), masv, course_id, safe_name, grade, str(weight)))
    # except Exception as e:
        # # print(f"⚠️ Lỗi điểm môn {course_id}: {e}")
        # pass

# def process_student(masv, password):
    # """Hàm xử lý cho từng sinh viên (để chạy đa luồng)"""
    # thread_conn = pyodbc.connect(LOCAL_CONN_STR)
    # thread_cursor = thread_conn.cursor()
    
    # try:
        # # 1. Lấy Token
        # token_url = f"{DOMAIN}/login/token.php"
        # res_token = requests.get(token_url, params={
            # "username": masv, "password": password, "service": "moodle_mobile_app"
        # }, verify=False, timeout=5).json()
        
        # token = res_token.get("token")
        
        # if not token:
            # thread_cursor.execute("UPDATE Students_LMS SET Status = 'Failed', ErrorMessage = 'Login Failed' WHERE MaSV = ?", (masv,))
        # else:
            # # 2. Lấy Site Info
            # api_url = f"{DOMAIN}/webservice/rest/server.php"
            # info = requests.post(api_url, data={
                # "wstoken": token, "wsfunction": "core_webservice_get_site_info", "moodlewsrestformat": "json"
            # }, verify=False, timeout=10).json()
            # uid = info.get('userid')
            # fullname = info.get('fullname')

            # # 3. Lấy danh sách Môn học
            # courses = requests.post(api_url, data={
                # "wstoken": token, "wsfunction": "core_enrol_get_users_courses", "userid": uid, "moodlewsrestformat": "json"
            # }, verify=False, timeout=10).json()

            # if isinstance(courses, list):
                # # LỌC NGAY: Chỉ giữ lại môn kỳ hiện tại
                # current_courses = [c for c in courses if c.get('startdate', 0) >= CURRENT_TERM_START]
                
                # print(f"📦 {masv}: Nhận {len(courses)} môn -> Lọc còn {len(current_courses)} môn kỳ này.")

                # for c in current_courses:
                    # # Lưu/Cập nhật thông tin môn
                    # thread_cursor.execute("""
                        # MERGE LMS_Courses AS target
                        # USING (SELECT ? AS MaSV, ? AS CourseID) AS source
                        # ON (target.MaSV = source.MaSV AND target.CourseID = source.CourseID)
                        # WHEN MATCHED THEN 
                            # UPDATE SET Progress = ?, Fullname = ?, LastUpdate = GETDATE()
                        # WHEN NOT MATCHED THEN 
                            # INSERT (MaSV, CourseID, Fullname, Progress, LastUpdate)
                            # VALUES (?, ?, ?, ?, GETDATE());
                    # """, (masv, c['id'], c.get('progress', 0), c['fullname'], masv, c['id'], c['fullname'], c.get('progress', 0)))
                    
                    # # Hốt luôn điểm chi tiết của môn này
                    # sync_grades(thread_cursor, masv, token, c['id'])
                
                # thread_cursor.execute("UPDATE Students_LMS SET Status = 'Success', FullName = ?, LastAttempt = GETDATE() WHERE MaSV = ?", (fullname, masv))
            
        # thread_conn.commit()
    # except Exception as e:
        # print(f"🔥 {masv} Lỗi: {e}")
    # finally:
        # thread_conn.close()

# def main():
    # conn = pyodbc.connect(LOCAL_CONN_STR)
    # cursor = conn.cursor()
    # # Lấy danh sách Pending
    # cursor.execute("SELECT MaSV, Password FROM Students_LMS WHERE Status = 'Pending'")
    # rows = cursor.fetchall()
    # conn.close()

    # print(f"🚀 Bắt đầu quét đa luồng cho {len(rows)} sinh viên...")
    
    # # Chạy song song 5 luồng
    # with ThreadPoolExecutor(max_workers=5) as executor:
        # for row in rows:
            # executor.submit(process_student, row[0], row[1])
            # time.sleep(0.1) 

# if __name__ == "__main__":
    # main()
    
    ###bổ sung truong
import requests
import pyodbc
import urllib3
import time
from concurrent.futures import ThreadPoolExecutor

# Tắt cảnh báo SSL
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# --- CẤU HÌNH ---
DOMAIN = "https://elearning.vinhuni.edu.vn"
LOCAL_CONN_STR = settings.db.local_conn_str

# Mốc thời gian: Chỉ lấy môn từ 01/01/2026 (Timestamp: 1767225600)
CURRENT_TERM_START = 1767225600 

def sync_grades(cursor, masv, token, course_id):
    """Hàm lấy điểm chi tiết cho một môn học"""
    url = f"{DOMAIN}/webservice/rest/server.php"
    params = {
        "wstoken": token,
        "wsfunction": "gradereport_user_get_grade_items",
        "courseid": course_id,
        "moodlewsrestformat": "json"
    }
    try:
        res = requests.post(url, data=params, verify=False, timeout=10).json()
        if "usergrades" in res:
            items = res['usergrades'][0].get('gradeitems', [])
            for item in items:
                name = item.get('itemname')
                grade = item.get('gradeformatted', '-')
                weight = item.get('weightraw', '')
                
                if name: # Chỉ lưu những hạng mục có tên điểm
                    safe_name = name[:350]
                    cursor.execute("""
                        MERGE LMS_Grades AS target
                        USING (SELECT ? AS MaSV, ? AS CourseID, ? AS ItemName) AS source
                        ON (target.MaSV = source.MaSV AND target.CourseID = source.CourseID AND target.ItemName = source.ItemName)
                        WHEN MATCHED THEN 
                            UPDATE SET Grade = ?, Weight = ?, LastUpdate = GETDATE()
                        WHEN NOT MATCHED THEN 
                            INSERT (MaSV, CourseID, ItemName, Grade, Weight, LastUpdate)
                            VALUES (?, ?, ?, ?, ?, GETDATE());
                    """, (masv, course_id, safe_name, grade, str(weight), masv, course_id, safe_name, grade, str(weight)))
    except:
        pass

def process_student(masv, password):
    """Hàm xử lý cho từng sinh viên"""
    thread_conn = pyodbc.connect(LOCAL_CONN_STR)
    thread_cursor = thread_conn.cursor()
    
    try:
        # 1. Lấy Token
        token_res = requests.get(f"{DOMAIN}/login/token.php", params={
            "username": masv, "password": password, "service": "moodle_mobile_app"
        }, verify=False, timeout=5).json()
        
        token = token_res.get("token")
        
        if not token:
            thread_cursor.execute("UPDATE Students_LMS SET Status = 'Failed', ErrorMessage = 'Login Failed' WHERE MaSV = ?", (masv,))
        else:
            # 2. Lấy Site Info
            api_url = f"{DOMAIN}/webservice/rest/server.php"
            info = requests.post(api_url, data={
                "wstoken": token, "wsfunction": "core_webservice_get_site_info", "moodlewsrestformat": "json"
            }, verify=False, timeout=10).json()
            uid = info.get('userid')
            fullname = info.get('fullname')

            # 3. Lấy danh sách Môn học
            courses = requests.post(api_url, data={
                "wstoken": token, "wsfunction": "core_enrol_get_users_courses", "userid": uid, "moodlewsrestformat": "json"
            }, verify=False, timeout=10).json()

            if isinstance(courses, list):
                # LỌC NGAY: Chỉ giữ lại môn kỳ hiện tại
                current_courses = [c for c in courses if c.get('startdate', 0) >= CURRENT_TERM_START]
                
                print(f"📦 {masv}: Nhận {len(courses)} môn -> Lọc còn {len(current_courses)} môn kỳ này.")

                for c in current_courses:
                    # Gán các giá trị mới từ API
                    short_name = c.get('shortname', '')
                    course_code = c.get('idnumber', '')
                    cat_id = c.get('category', 0)
                    end_date = c.get('enddate', 0)
                    summary = c.get('summary', '')

                    # MERGE vào bảng LMS_Courses với các cột mới
                    thread_cursor.execute("""
                        MERGE LMS_Courses AS target
                        USING (SELECT ? AS MaSV, ? AS CourseID) AS source
                        ON (target.MaSV = source.MaSV AND target.CourseID = source.CourseID)
                        WHEN MATCHED THEN 
                            UPDATE SET 
                                Progress = ?, 
                                Fullname = ?, 
                                ShortName = ?, 
                                CourseCode = ?, 
                                CategoryID = ?, 
                                EndDate = ?, 
                                Summary = ?, 
                                LastUpdate = GETDATE()
                        WHEN NOT MATCHED THEN 
                            INSERT (MaSV, CourseID, Fullname, Progress, ShortName, CourseCode, CategoryID, EndDate, Summary, LastUpdate)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, GETDATE());
                    """, (
                        masv, c['id'], # Join keys
                        c.get('progress', 0), c['fullname'], short_name, course_code, cat_id, end_date, summary, # Update values
                        masv, c['id'], c['fullname'], c.get('progress', 0), short_name, course_code, cat_id, end_date, summary # Insert values
                    ))
                    
                    # Lấy điểm chi tiết cho môn này
                    sync_grades(thread_cursor, masv, token, c['id'])
                
                thread_cursor.execute("UPDATE Students_LMS SET Status = 'Success', FullName = ?, LastAttempt = GETDATE() WHERE MaSV = ?", (fullname, masv))
            
        thread_conn.commit()
    except Exception as e:
        print(f"🔥 {masv} Lỗi: {e}")
    finally:
        thread_conn.close()

def main():
    conn = pyodbc.connect(LOCAL_CONN_STR)
    cursor = conn.cursor()
    # Chỉ quét những bạn chưa thành công (Pending)
    cursor.execute("SELECT MaSV, Password FROM Students_LMS WHERE Status = 'Pending'")
    rows = cursor.fetchall()
    conn.close()

    print(f"🚀 Bắt đầu quét {len(rows)} sinh viên...")
    
    with ThreadPoolExecutor(max_workers=5) as executor:
        for row in rows:
            executor.submit(process_student, row[0], row[1])
            time.sleep(0.1) 

if __name__ == "__main__":
    main()