import uvicorn
import cv2
from starlette.concurrency import run_in_threadpool  # chạy mã đồng bộ ngoài vòng lặp sự kiện
import numpy as np
import pyodbc
from fastapi import FastAPI, UploadFile, File, Form
from insightface.app import FaceAnalysis
from core.settings import settings  # cấu hình tập trung (Pha 0)

app = FastAPI(title="VinhUni Internal AI - v3.0")

# Kết nối SQL nội bộ
DB_CONFIG = settings.db.local_conn_str

# Khởi tạo AI Engine
face_app = FaceAnalysis(name='buffalo_l', providers=['CPUExecutionProvider'])
face_app.prepare(ctx_id=0, det_size=(640, 640))

@app.post("/internal/verify_student")
async def verify_student(
    student_id: str = Form(...),
    photo_front: UploadFile = File(...), 
    photo_pose: UploadFile = File(...)
):
    try:
        # 1. Trích xuất Vector từ ảnh chụp
        img_bytes = await photo_front.read()
        # ⚠️ SỬA 19/08/2026: đẩy phần nặng sang LUỒNG RIÊNG.
        #
        # Bên dưới có hai việc đều CHẶN vòng lặp sự kiện nếu để nguyên trong
        # `async def`:
        #   • face_app.get() — nhận diện khuôn mặt, tốn CPU, thường lâu hơn cả
        #     truy vấn cơ sở dữ liệu.
        #   • pyodbc — thư viện đồng bộ.
        #
        # Một lần gọi chặn là CẢ máy chủ ngừng phục vụ, không riêng người đang
        # xác thực. Đã gặp thật hôm nay với một endpoint khác.
        #
        # Nội dung bên trong giữ nguyên từng dòng, chỉ lùi vào một cấp.
        def _doi_khop_khuon_mat():
            img_f = cv2.imdecode(np.frombuffer(img_bytes, np.uint8), cv2.IMREAD_COLOR)
            faces = face_app.get(img_f)
        
            if not faces:
                return {"status": "ERROR", "message": "Không tìm thấy mặt trong ảnh chính diện"}

            feat_new = faces[0].normed_embedding

            # 2. Truy vấn SQL với xử lý khoảng trắng (RTRIM) và kiểm tra đa dạng mã
            # Chúng ta dùng RTRIM(?) để loại bỏ dấu cách nếu App gửi lên dư thừa
            # Và dùng RTRIM(UserCode) để khớp chính xác dữ liệu trong SQL
            with pyodbc.connect(DB_CONFIG) as conn:
                cursor = conn.cursor()
            
                search_id = student_id.strip().upper()
                print(f"🔍 AI đang tìm tài khoản: '{search_id}'")

                sql = """
                    SELECT Vector_bin, FullName, UserRole, FacultyName 
                    FROM tbl_Users 
                    WHERE RTRIM(UserCode) = ? 
                       OR RTRIM(UserCode) = 'SV' + ? 
                       OR RTRIM(UserCode) = 'CB' + ?
                """
                cursor.execute(sql, (search_id, search_id, search_id))
                row = cursor.fetchone()

            # Kiểm tra sự tồn tại của dòng dữ liệu
            if not row:
                print(f"❌ Không tìm thấy mã '{search_id}' trong tbl_Users")
                return {"status": "ERROR", "message": f"Tài khoản {search_id} chưa đăng ký trên App"}

            # Kiểm tra xem có dữ liệu khuôn mặt mẫu chưa
            if not row[0]:
                return {"status": "ERROR", "message": "Tài khoản có tồn tại nhưng chưa có dữ liệu khuôn mặt mẫu"}

            # 3. Tính toán độ tương đồng (Similarity)
            feat_old = np.frombuffer(row[0], dtype=np.float32)
            similarity = float(np.dot(feat_old, feat_new))
        
            print(f"📊 Kết quả đối khớp [{search_id}]: {similarity:.4f}")

            # Ngưỡng chuẩn InsightFace: 0.42
            if similarity >= 0.80:
                return {
                    "status": "SUCCESS", 
                    "student_id": search_id,
                    "full_name": row[1].strip() if row[1] else "N/A",
                    "role": row[2] if row[2] else "SinhVien", # Trả về role: CanBo/SinhVien
                    "faculty": row[3] if row[3] else "Vinh University"
                }
        
            return {"status": "FAIL", "message": "Khuôn mặt không chính xác"}

        return await run_in_threadpool(_doi_khop_khuon_mat)

    except Exception as e:
        print(f"🔥 Lỗi hệ thống AI: {str(e)}")
        return {"status": "ERROR", "message": str(e)}
# --- THÊM VÀO FILE AI_INTERNAL.PY (Cổng 8011) ---
@app.post("/internal/extract_vector")
async def extract_vector(photo: UploadFile = File(...)):
    try:
        # Đọc ảnh người dùng gửi lên
        img_bytes = await photo.read()
        img = cv2.imdecode(np.frombuffer(img_bytes, np.uint8), cv2.IMREAD_COLOR)
        
        # Sử dụng Engine AI có sẵn để lấy vector
        faces = face_app.get(img)
        if not faces:
            return {"status": "ERROR", "message": "Không tìm thấy khuôn mặt trong ảnh"}

        # Trả về vector dạng list để Gateway 8080 có thể lưu vào SQL
        vector = faces[0].normed_embedding.tolist()
        return {"status": "SUCCESS", "vector": vector}
    except Exception as e:
        return {"status": "ERROR", "message": str(e)}
        
# --- CẬP NHẬT TRONG FILE AI_INTERNAL.PY (Cổng 8011) ---

# --- TRONG FILE AI_INTERNAL.PY (Cổng 8011) ---

@app.post("/internal/search_face_1n")
async def search_face_1n(photo_front: UploadFile = File(...)):
    try:
        # 1. Trích xuất Vector từ ảnh gửi lên
        img_bytes = await photo_front.read()
        # ⚠️ SỬA 19/08/2026: đẩy sang luồng riêng — cùng lý do với
        # verify_student ở trên. Chỗ này còn nặng hơn: nó tải TẤT CẢ vector
        # khuôn mặt trong cơ sở dữ liệu rồi so từng cái một.
        def _tim_khuon_mat():
            img = cv2.imdecode(np.frombuffer(img_bytes, np.uint8), cv2.IMREAD_COLOR)
            faces = face_app.get(img)
        
            if not faces:
                return {"status": "ERROR", "message": "Không tìm thấy khuôn mặt"}

            feat_new = faces[0].normed_embedding

            # 2. Lấy danh sách Vector + Role + UserType từ tbl_Users
            with pyodbc.connect(DB_CONFIG) as conn:
                cursor = conn.cursor()
                # 🔥 Đã thêm UserType để check Cán bộ
                sql = """
                    SELECT UserCode, Vector_bin, FullName, UserRole, FacultyName, UserType 
                    FROM tbl_Users 
                    WHERE Vector_bin IS NOT NULL AND IsActive = 1
                """
                cursor.execute(sql)
                rows = cursor.fetchall()

            if not rows:
                return {"status": "ERROR", "message": "Chưa có dữ liệu khuôn mặt mẫu"}

            best_match_data = None
            max_similarity = -1.0

            # 3. So sánh 1:N
            for row in rows:
                user_code, vector_bin, full_name, role_raw, faculty, user_type = row
                feat_old = np.frombuffer(vector_bin, dtype=np.float32)
                similarity = float(np.dot(feat_old, feat_new))

                if similarity > max_similarity:
                    max_similarity = similarity
                
                    # 🔥 LOGIC ÉP ROLE NGAY TẠI ENGINE AI (Dành cho 1679)
                    clean_id = str(user_code).strip().upper().replace("SV", "").replace("CB", "")
                    role_str = str(role_raw).strip() if role_raw else ""
                
                    if role_str == "CanBo" or str(user_code).upper().startswith("CB") or user_type == 1 or (clean_id.isdigit() and len(clean_id) < 6):
                        final_role = "CanBo"
                    else:
                        final_role = "SinhVien"

                    best_match_data = {
                        "student_id": clean_id,
                        "full_name": full_name.strip() if full_name else "N/A",
                        "role": final_role,
                        "user_role": final_role,
                        "faculty": faculty if faculty else "Vinh University"
                    }

            # 4. Kiểm tra ngưỡng 0.45
            if max_similarity >= 0.45:
                print(f"✅ AI Khớp: {best_match_data['student_id']} - Role: {best_match_data['role']}")
                return {
                    "status": "SUCCESS",
                    "match_score": max_similarity,
                    **best_match_data
                }
        
            return {"status": "FAIL", "message": "Khuôn mặt không khớp"}

        return await run_in_threadpool(_tim_khuon_mat)

    except Exception as e:
        print(f"🔥 Lỗi Search 1:N: {str(e)}")
        return {"status": "ERROR", "message": str(e)}        
if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8011)