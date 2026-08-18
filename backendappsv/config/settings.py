# config/settings.py
import os
from dotenv import load_dotenv
from core.settings import settings as core_settings  # cấu hình tập trung (Pha 0)

# Load các biến môi trường từ file .env (nếu có)
load_dotenv()

# Gán trực tiếp chuỗi API Key vào biến (Dùng để chạy test ở máy Local)
OPENAI_API_KEY = core_settings.ai.openai_api_key

# Cấu hình các Model của OpenAI
EMBEDDING_MODEL = "text-embedding-3-small"
CHAT_MODEL_FAST = "gpt-4o-mini"
CHAT_MODEL_SMART = "gpt-4o"

# Ngưỡng độ chính xác khi tìm kiếm bằng Semantic Cache (Vector)
SIMILARITY_THRESHOLD = 0.85

# Danh sách đen: Cấm AI sinh ra các lệnh phá hoại Database
FORBIDDEN_SQL = [
    "DROP", "DELETE", "UPDATE", "INSERT", "ALTER", "TRUNCATE"
]
#============ CHAT GROUP & SYSTEM SETTINGS ============
import firebase_admin
from firebase_admin import credentials
from openai import OpenAI
import json
import os
import urllib

class Settings:
    # 1. SQL nội bộ (VinhUni_Local) - Nơi lưu dữ liệu Chat
    REMOTE_CONN_STR = core_settings.db.local_conn_str
    
    # 2. SQL xác thực Cán bộ gốc (.26)
    STAFF_DB_CONN = core_settings.staff_db.conn_str
    
    # 3. SQLAlchemy URL (Dành cho models/ORM sau này)
    # Chuyển đổi connection string sang định dạng SQLAlchemy
    params = urllib.parse.quote_plus(REMOTE_CONN_STR)
    SQLALCHEMY_DATABASE_URL = f"mssql+pyodbc:///?odbc_connect={params}"

    # 4. Đường dẫn file cấu hình
    BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    APP_SETTINGS_PATH = os.path.join(BASE_DIR, "appsettings.json")
    FIREBASE_JSON_PATH = os.path.join(BASE_DIR, "vinhuni-portal-firebase-adminsdk.json")

    # 5. Cấu hình Chat Real-time
    SOCKET_CORS_ORIGINS = "*" # Cho phép mọi nguồn kết nối (hoặc giới hạn list domain)
    CHAT_PAGINATION_LIMIT = 20 # Số tin nhắn mỗi lần load (Load more)

    def __init__(self):
        self.OPENAI_API_KEY = self._load_openai_key()

    def _load_openai_key(self):
        """Khoá OpenAI, ưu tiên .env rồi mới đến appsettings.json.

        ⚠️ SỬA 18/08/2026 — lỗi phát sinh từ chính đợt dọn khoá bí mật (Pha 0).
        Đợt đó chuyển mọi khoá sang .env và chặn appsettings.json khỏi git, nhưng
        hàm này vẫn CHỈ đọc appsettings.json. Máy chủ đang chạy còn tệp cũ nên
        không ai thấy gì; cài mới từ kho mã thì hàm trả None, `OpenAI(api_key=None)`
        ném lỗi ngay lúc nạp module, và CẢ backend không khởi động được.

        Vẫn đọc appsettings.json làm phương án dự phòng để những máy chủ chưa kịp
        tạo .env không bị gãy khi cập nhật.
        """
        khoa = (core_settings.ai.openai_api_key or "").strip()
        if khoa:
            return khoa

        try:
            if os.path.exists(self.APP_SETTINGS_PATH):
                with open(self.APP_SETTINGS_PATH, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    # Hỗ trợ cả 2 định dạng key trong appsettings
                    return data.get("OpenAI", {}).get("ApiKey") or data.get("OPENAI_API_KEY")
        except Exception:
            pass
        return None

# Khởi tạo instance
settings = Settings()

# Khởi tạo OpenAI Client.
#
# Không có khoá thì để client = None thay vì ném lỗi. Trước đây thiếu khoá là
# `OpenAI(api_key=None)` ném ngay lúc nạp module, kéo theo cả backend không khởi
# động nổi — chỉ vì một chức năng phụ. Nay các phần khác vẫn chạy, riêng chỗ nào
# dùng AI thì tự báo lỗi của nó.
client = OpenAI(api_key=settings.OPENAI_API_KEY) if settings.OPENAI_API_KEY else None
if client is None:
    print("⚠️  [config] Không có OPENAI_API_KEY — các chức năng AI sẽ không hoạt động. "
          "Đặt OPENAI_API_KEY trong .env để bật lại.")

# Khởi tạo Firebase Admin SDK (Chỉ khởi tạo 1 lần duy nhất)
# if not firebase_admin._apps:
    # if os.path.exists(settings.FIREBASE_JSON_PATH):
        # try:
            # cred = credentials.Certificate(settings.FIREBASE_JSON_PATH)
            # firebase_admin.initialize_app(cred)
            # print("✅ [Firebase] Khởi tạo thành công!")
        # except Exception as e:
            # print(f"❌ [Firebase] Lỗi khởi tạo: {e}")
    # else:
        # print("⚠️ [Firebase] Không tìm thấy file JSON cấu hình.")