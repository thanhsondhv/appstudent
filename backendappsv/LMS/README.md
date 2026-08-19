# Thư mục `LMS/`

Đồng bộ dữ liệu với hệ thống học trực tuyến Moodle (`elearning.vinhuni.edu.vn`).

## Lấy token thế nào

Các tệp đang dùng thật (`sync_all_lms.py`, `fast_sync_lms_final.py`,
`services/lms_service.py`) lấy token **động** qua `login/token.php` mỗi lần
chạy. Không viết cứng token ở đâu cả — và không được viết cứng.

## Đã xoá: `test_lms.py`

Xoá ngày 19/08/2026. Đó là tệp nháp để thử API Moodle, không tệp nào import,
và 90% nội dung là mã đã bị chú thích.

Vấn đề thật: nó chứa **6 token dịch vụ web viết cứng**, một trong số đó đang
hoạt động. Token Moodle cho phép đọc dữ liệu học tập của người dùng qua API.
Kho mã này nằm trên GitHub, nên chúng coi như đã lộ.

**Việc cần làm**: thu hồi những token đó trong phần quản trị Moodle
(*Site administration → Server → Web services → Manage tokens*). Xoá khỏi mã
nguồn là chưa đủ — chúng vẫn nằm trong lịch sử git.

Muốn xem lại tệp cũ: `git log -p -- backendappsv/LMS/test_lms.py`
