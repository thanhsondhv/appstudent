import pyodbc
import json
import time
from openai import OpenAI
from core.openai_client import tao_client  # thiếu khoá thì trả None, không làm chết backend
from core.settings import settings  # cấu hình tập trung (Pha 0)

# ==========================================================
# 1. CẤU HÌNH HỆ THỐNG
# ==========================================================
DB_CONFIG = {
    "server": settings.db.server,
    "database": settings.db.name,
    "uid": settings.db.user,
    "pwd": settings.db.password
}

OPENAI_API_KEY = settings.ai.openai_api_key
client = tao_client(OPENAI_API_KEY, ten_chuc_nang="gắn nhãn tự động")

# ==========================================================
# 2. CÁC HÀM XỬ LÝ CHÍNH
# ==========================================================

def get_conn():
    """Kết nối SQL Server với cấu hình UTF-16LE chuẩn cho tiếng Việt"""
    conn_str = (
        f"DRIVER={{ODBC Driver 17 for SQL Server}};"
        f"SERVER={DB_CONFIG['server']};"
        f"DATABASE={DB_CONFIG['database']};"
        f"UID={DB_CONFIG['uid']};"
        f"PWD={DB_CONFIG['pwd']};"
        "TrustServerCertificate=yes;"
    )
    conn = pyodbc.connect(conn_str)
    # Cấu hình encoding để ghi NVARCHAR không lỗi dấu
    conn.setencoding(encoding='utf-16le')
    conn.setdecoding(pyodbc.SQL_WCHAR, encoding='utf-16le')
    return conn

def analyze_content_pro(doc_name, content):
    """Sử dụng AI để phân loại động, xác định đối tượng và trích xuất Keywords"""
    prompt = f"""
    Bạn là chuyên gia quản lý tri thức tại Đại học Vinh (VinhUni).
    Tài liệu: "{doc_name}"
    Nội dung: "{content[:1200]}"
    
    NHIỆM VỤ:
    1. Category: Tự đặt tên nhóm chuyên môn súc tích (2-4 từ). KHÔNG dùng nhóm "Khác" trừ khi không thể phân loại. 
       Ví dụ: Nghỉ phép, Giảng dạy, Học bổng, Khen thưởng, Tuyển sinh...
    2. TargetRole: Xác định đối tượng đọc là 'SV' (Sinh viên), 'CB' (Cán bộ/Giảng viên), hoặc 'ALL' (Cả hai). 
       - Dựa vào ngôn ngữ: "Người học", "Sinh viên" -> SV; "Giảng viên", "Đơn vị" -> CB.
    3. Keywords: Trích xuất 5-7 cụm từ khóa quan trọng nhất. 
       YÊU CẦU: Ưu tiên cụm từ bắt đầu bằng ĐỘNG TỪ để làm nút bấm gợi ý. 
       Ví dụ: "Đăng ký học hè", "Xin phúc khảo điểm", "Thủ tục chuyển lớp".

    TRẢ VỀ ĐỊNH DẠNG JSON NGHIÊM NGẶT:
    {{
        "category": "Tên nhóm tự chọn",
        "target_role": "SV/CB/ALL",
        "keywords": "từ khóa 1, từ khóa 2, ..."
    }}
    """
    try:
        response = client.chat.completions.create(
            model=settings.ai.ten_mo_hinh_chat,  # theo AI_PROVIDER trong .env
            messages=[
                {"role": "system", "content": "Bạn là chuyên gia phân loại dữ liệu hành chính đại học."},
                {"role": "user", "content": prompt}
            ],
            response_format={ "type": "json_object" },
            temperature=0.3
        )
        return json.loads(response.choices[0].message.content)
    except Exception as e:
        print(f"❌ Lỗi AI: {e}")
        return None

def process_tagging_pro():
    """Quét dữ liệu và cập nhật nhãn thông minh"""
    conn = get_conn()
    cursor = conn.cursor()
    
    # Lấy các bản ghi chưa có Keywords hoặc chưa phân loại đúng TargetRole
    # Sơn có thể xóa điều kiện WHERE để chạy lại toàn bộ nếu muốn chuẩn hóa lại
    cursor.execute("""
        SELECT ChunkId, DocumentName, Content 
        FROM DocumentChunks 
        WHERE Keywords IS NULL OR TargetRole = 'ALL'
    """)
    rows = cursor.fetchall()
    
    print(f"🚀 Bắt đầu xử lý {len(rows)} bản ghi bằng trí tuệ nhân tạo Pro...")
    
    for i, row in enumerate(rows):
        cid, name, content = row
        
        # Phân tích nội dung
        res = analyze_content_pro(name, content)
        
        if res:
            cat = res.get("category", "Quy định chung")
            role = res.get("target_role", "ALL").upper()
            kw = res.get("keywords", "")
            
            try:
                # Cập nhật DB
                cursor.execute("""
                    UPDATE DocumentChunks 
                    SET Category = ?, TargetRole = ?, Keywords = ? 
                    WHERE ChunkId = ?
                """, (cat, role, kw, cid))
                
                # Commit mỗi 10 bản ghi để tối ưu hiệu suất
                if (i + 1) % 10 == 0:
                    conn.commit()
                    print(f"✅ [{i+1}/{len(rows)}] -> {cat} | {role} | KW: {kw[:40]}...")
            except Exception as sql_e:
                print(f"❌ Lỗi SQL tại Chunk {cid}: {sql_e}")
        
        # Nghỉ ngắn để tránh Rate Limit API nếu số lượng bản ghi quá lớn
        time.sleep(0.05)

    conn.commit()
    conn.close()
    print("\n✨ TỐI ƯU HÓA DỮ LIỆU HOÀN TẤT! Dữ liệu của Sơn giờ đã sẵn sàng cho RAG Pro.")

if __name__ == "__main__":
    process_tagging_pro()