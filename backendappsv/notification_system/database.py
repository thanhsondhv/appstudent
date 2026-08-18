"""Kết nối cơ sở dữ liệu cho các tiến trình của hệ thống thông báo.

Sửa 18/08/2026: bản trước vẫn viết cứng tên máy chủ, tên cơ sở dữ liệu và tài
khoản — đợt gỡ khoá bí mật chỉ thay được dòng mật khẩu. Hệ quả là đổi máy chủ
phải sửa mã ở hai nơi, và dễ quên một nơi. Nay lấy trọn từ cấu hình tập trung.
"""

import os
import sys

import pyodbc

_THU_MUC = os.path.dirname(os.path.abspath(__file__))
# Thứ tự quan trọng: lần insert(0) SAU CÙNG có độ ưu tiên cao nhất.
# Thư mục gốc backend có gói `database/`, còn thư mục này có tệp `database.py`.
# Nếu để thư mục gốc ưu tiên thì `from database import get_db_conn` sẽ lấy nhầm
# gói kia và ném ImportError ngay khi khởi động worker.
sys.path.insert(0, os.path.dirname(_THU_MUC))   # để import core.settings
sys.path.insert(0, _THU_MUC)                    # ưu tiên module cùng thư mục
from core.settings import settings  # noqa: E402

CONN_STR = settings.db.local_conn_str


def get_db_conn():
    """Mở một kết nối mới. Bên gọi chịu trách nhiệm đóng, tốt nhất là dùng `with`."""
    return pyodbc.connect(CONN_STR)
