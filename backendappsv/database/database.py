"""Kết nối cơ sở dữ liệu dùng chung cho backend.

⚠️ SỬA 19/08/2026 — nguyên nhân khiến MỌI yêu cầu HTTP mất đúng 15 giây.

Đợt dọn khoá bí mật (Pha 0) chuyển tài khoản và mật khẩu sang cấu hình tập
trung nhưng ĐỂ NGUYÊN tên máy chủ viết cứng `AI2025\\SQLEXPRESS02`. Tên đó chỉ
phân giải được trên chính máy chủ trường. Ở bất kỳ máy nào khác, pyodbc chờ hết
15 giây mặc định rồi mới báo lỗi.

Vì middleware chặn truy cập của Main.py gọi hàm này trên MỌI yêu cầu, cái giá
15 giây đó cộng vào từng lượt truy cập — kể cả những lượt không đụng gì tới cơ
sở dữ liệu. Đo được ngày 19/08/2026: 15,02 giây cho mọi endpoint, rất đều.

Hai thay đổi:
  • Lấy trọn chuỗi kết nối từ cấu hình tập trung, không viết cứng gì nữa.
  • Đặt hạn chờ đăng nhập ngắn. Cơ sở dữ liệu nằm cùng mạng nội bộ; chờ 15 giây
    không cứu được gì, chỉ kéo dài thời gian hỏng. Hỏng thì phải hỏng NHANH để
    lộ ra ngay.
"""

import os

import pyodbc

from core.settings import settings  # cấu hình tập trung (Pha 0)

CONN_STR = settings.db.local_conn_str

# Giây chờ khi mở kết nối. Đủ rộng cho một máy chủ đang bận, đủ ngắn để sự cố
# mạng không biến thành hàng chờ kéo dài trên toàn hệ thống.
GIAY_CHO_KET_NOI = int(os.getenv("DB_LOGIN_TIMEOUT", "5"))


def get_db_conn():
    """Mở một kết nối mới. Bên gọi nên dùng `with` để chắc chắn đóng lại.

    NÉM ngoại lệ khi không kết nối được, thay vì trả `None` như bản cũ.

    Bản cũ trả `None`, mà mọi nơi đều viết `with get_db_conn() as conn:` — nên
    lỗi thật ("không kết nối được cơ sở dữ liệu") biến thành một dòng khó hiểu:
    `AttributeError: __enter__`. Nhật ký đầy những dòng đó mà không ai đoán ra
    nguyên nhân.
    """
    return pyodbc.connect(CONN_STR, autocommit=True, timeout=GIAY_CHO_KET_NOI)
