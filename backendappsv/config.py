"""Tương thích ngược — giữ lại các tên biến cũ cho những script đang import từ đây.

Không còn viết cứng khoá bí mật. Mã mới nên import trực tiếp:
    from core.settings import settings
"""

from core.settings import settings

DB_SERVER = settings.db.server
DB_USER = settings.db.user
DB_PASSWORD = settings.db.password
DB_NAME = settings.db.name
REMOTE_CONN_STR = settings.db.local_conn_str
