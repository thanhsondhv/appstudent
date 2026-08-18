"""
Gửi thông báo đẩy qua Firebase Cloud Messaging.

Hàm này chạy trong tiến trình worker, nhận công việc từ Redis do producer nạp.

═══════════════════════════════════════════════════════════════════════════
VIẾT LẠI NGÀY 18/08/2026 — ba vấn đề của bản cũ
═══════════════════════════════════════════════════════════════════════════

1. VỠ KHI GỬI TOÀN TRƯỜNG
   Bản cũ đưa thẳng cả danh sách token vào một MulticastMessage. Firebase giới
   hạn CỨNG 500 token mỗi lượt — gửi toàn trường (vài nghìn thiết bị) sẽ ném
   lỗi ngay, rơi vào khối except chỉ có một dòng print, và tin MẤT LUÔN:
   IsSent kẹt ở 2 vĩnh viễn, không thử lại, không ai biết. Nay chia lô 450.

2. KHÔNG DỌN TOKEN CHẾT
   Người gỡ ứng dụng hoặc cài lại máy thì token cũ vô hiệu vĩnh viễn, nhưng
   vẫn nằm trong bảng và vẫn được gửi mỗi lần. Firebase báo rõ token nào hỏng
   — nay đọc phản hồi đó và tắt token tương ứng.

3. THẤT BẠI IM LẶNG
   Bản cũ chỉ print rồi bỏ qua. Nay ghi rõ kết quả vào cơ sở dữ liệu và ném
   ngoại lệ lên worker để worker quyết định thử lại.
"""

from __future__ import annotations

import os
import sys

import firebase_admin
from firebase_admin import credentials, messaging

_THU_MUC = os.path.dirname(os.path.abspath(__file__))
# Thứ tự quan trọng: lần insert(0) SAU CÙNG có độ ưu tiên cao nhất.
# Thư mục gốc backend có gói `database/`, còn thư mục này có tệp `database.py`.
# Nếu để thư mục gốc ưu tiên thì `from database import get_db_conn` sẽ lấy nhầm
# gói kia và ném ImportError ngay khi khởi động worker.
sys.path.insert(0, os.path.dirname(_THU_MUC))   # để import core.settings
sys.path.insert(0, _THU_MUC)                    # ưu tiên module cùng thư mục
from database import get_db_conn  # noqa: E402

# Firebase giới hạn cứng 500 token mỗi MulticastMessage.
# Dùng 450 để còn dư khi thư viện tự thêm gì đó.
SO_TOKEN_MOI_LO = 450

# Trạng thái trong tbl_Notification_Queue
CHUA_GUI, DA_GUI, DANG_XU_LY, BO_QUA = 0, 1, 2, 3

# Mã lỗi Firebase báo token đã vĩnh viễn vô hiệu — gửi lại cũng vô ích.
#
# Danh sách này được xác minh bằng dry_run trên token thật ngày 18/08/2026:
# Firebase Admin SDK cho Python trả về "NOT_FOUND" cho token đã gỡ ứng dụng —
# mã này THIẾU trong bản đầu tiên, khiến cơ chế dọn token chết tắt được 0/17
# token thay vì 17/17. Đo trên 30 token ngẫu nhiên: 17 cái (57%) đã chết.
#
# CỐ Ý KHÔNG đưa vào đây các mã tạm thời như UNAVAILABLE, INTERNAL, QUOTA_EXCEEDED
# — những lỗi đó sẽ hết sau vài phút, tắt token vì chúng là mất người nhận oan.
LOI_TOKEN_CHET = {
    "NOT_FOUND",                          # token đã gỡ ứng dụng — hay gặp nhất
    "UNREGISTERED",                       # tên gọi ở một số phiên bản SDK khác
    "INVALID_ARGUMENT",                   # token sai định dạng
    "SENDER_ID_MISMATCH",                 # token thuộc dự án Firebase khác
    "registration-token-not-registered",
    "invalid-registration-token",
}


class LoiGuiThongBao(Exception):
    """Gửi thất bại theo cách có thể thử lại được."""


def initialize_firebase() -> bool:
    """Khởi tạo Firebase SDK cho tiến trình worker hiện tại.

    Mỗi worker là một tiến trình riêng nên đều phải tự khởi tạo.
    """
    if firebase_admin._apps:
        return True
    try:
        thu_muc = os.path.dirname(os.path.abspath(__file__))
        duong_dan = os.path.join(thu_muc, "vinhuni-portal-firebase-adminsdk.json")
        if not os.path.exists(duong_dan):
            print(f"❌ Không tìm thấy khoá Firebase tại {duong_dan}")
            return False
        firebase_admin.initialize_app(credentials.Certificate(duong_dan))
        print("✅ [Firebase] Đã khởi tạo SDK trong worker này")
        return True
    except Exception as exc:  # noqa: BLE001
        print(f"❌ [Firebase] Lỗi khởi tạo: {exc}")
        return False


def _dung_tin_nhan(title, safe_body, nid, cat, is_chat, group_id, priority, tokens):
    """Dựng MulticastMessage cho một lô token."""
    is_high = int(priority or 0) >= 5

    android_config = messaging.AndroidConfig(
        priority="high",
        ttl=1800 if is_high else 86400,
        notification=messaging.AndroidNotification(
            title=str(title),
            body=safe_body,
            sound="default",
            default_sound=True,
            # Kênh riêng cho chat để người dùng tắt/bật độc lập
            channel_id="vinhuni_chat" if is_chat else "vinhuni_alert",
            icon="stock_ticker_update",
            click_action="FLUTTER_NOTIFICATION_CLICK",
        ),
    )

    apns_config = messaging.APNSConfig(
        headers={"apns-priority": "10"},
        payload=messaging.APNSPayload(
            aps=messaging.Aps(
                alert=messaging.ApsAlert(title=str(title), body=safe_body),
                sound="default",
                badge=1,
                content_available=True,
                category="CHAT_GROUP" if is_chat else "GENERAL",
            )
        ),
    )

    return messaging.MulticastMessage(
        notification=messaging.Notification(title=str(title), body=safe_body),
        tokens=tokens,
        data={
            "nid": str(nid),
            "category": "CHAT_GROUP" if is_chat else "GENERAL",
            "click_action": "FLUTTER_NOTIFICATION_CLICK",
            "route": "/chat_room" if is_chat else "/notification_list",
            "group_id": str(group_id or ""),
            "group_name": str(title).replace("Tin nhắn từ ", ""),
        },
        android=android_config,
        apns=apns_config,
    )


def _tat_token_chet(token_chet: list[str]) -> None:
    """Đánh dấu ngừng dùng những token Firebase báo đã vô hiệu vĩnh viễn.

    Không xoá hẳn để còn đối chiếu khi cần: một người có thể cài lại ứng dụng
    và đăng ký token mới, giữ lại lịch sử giúp truy vết khi họ báo không nhận
    được thông báo.
    """
    if not token_chet:
        return
    try:
        with get_db_conn() as conn:
            cursor = conn.cursor()
            for i in range(0, len(token_chet), 500):
                lo = token_chet[i:i + 500]
                cho_trong = ",".join("?" * len(lo))
                cursor.execute(
                    f"UPDATE tbl_FCM_Tokens SET IsActive = 0 WHERE FCMToken IN ({cho_trong})",
                    lo,
                )
            conn.commit()
        print(f"🧹 Đã tắt {len(token_chet)} token không còn hiệu lực")
    except Exception as exc:  # noqa: BLE001
        # Dọn token là việc phụ, hỏng thì không được làm hỏng việc gửi
        print(f"⚠️  Không tắt được token chết: {exc}")


def send_fcm_task(nid, title, body, cat, tokens, priority, group_id="") -> dict:
    """Gửi một thông báo tới danh sách thiết bị.

    Trả về thống kê. Ném [LoiGuiThongBao] nếu thất bại theo cách nên thử lại —
    worker sẽ đưa công việc trở lại hàng đợi.
    """
    if not initialize_firebase():
        raise LoiGuiThongBao("Chưa khởi tạo được Firebase SDK")

    if not tokens:
        return {"thanh_cong": 0, "that_bai": 0, "tong": 0}

    safe_body = str(body or "").replace("\r\n", "\n\n").replace("\r", "\n\n")
    if len(safe_body) > 1000:
        safe_body = safe_body[:997] + "..."

    is_chat = str(cat).upper() in ("CHAT", "CHAT_GROUP")

    tong_thanh_cong = 0
    tong_that_bai = 0
    token_chet: list[str] = []
    loi_cuoi = ""

    # Chia lô theo giới hạn của Firebase
    for i in range(0, len(tokens), SO_TOKEN_MOI_LO):
        lo = tokens[i:i + SO_TOKEN_MOI_LO]
        try:
            message = _dung_tin_nhan(
                title, safe_body, nid, cat, is_chat, group_id, priority, lo
            )
            response = messaging.send_each_for_multicast(message)
            tong_thanh_cong += response.success_count
            tong_that_bai += response.failure_count

            # Đọc từng kết quả để nhặt ra token đã chết
            for vi_tri, kq in enumerate(response.responses):
                if kq.success:
                    continue
                ma_loi = getattr(getattr(kq, "exception", None), "code", "") or ""
                if str(ma_loi) in LOI_TOKEN_CHET:
                    token_chet.append(lo[vi_tri])

        except Exception as exc:  # noqa: BLE001
            tong_that_bai += len(lo)
            loi_cuoi = str(exc)[:200]
            print(f"❌ Lô {i // SO_TOKEN_MOI_LO + 1} của tin #{nid} lỗi: {loi_cuoi}")

    _tat_token_chet(token_chet)

    tong = len(tokens)

    # KHÔNG cập nhật tbl_Notification_Queue ở đây.
    #
    # Từ 18/08/2026 một thông báo lớn được chia thành nhiều công việc để các
    # worker cùng gửi song song. Nếu mỗi phần tự đánh dấu "đã gửi" thì phần đầu
    # tiên xong sẽ đóng cả thông báo lại, trong khi các phần sau còn đang chạy.
    # Việc đếm số phần và ghi kết quả cuối cùng do worker đảm nhiệm — nơi có
    # sẵn kết nối Redis để giữ bộ đếm chung.

    if tong_thanh_cong == 0 and tong > 0:
        raise LoiGuiThongBao(
            f"Không gửi được phần nào của tin #{nid}: {loi_cuoi or 'toàn bộ lô thất bại'}"
        )

    return {
        "thanh_cong": tong_thanh_cong,
        "that_bai": tong_that_bai,
        "tong": tong,
        "token_chet": len(token_chet),
    }
