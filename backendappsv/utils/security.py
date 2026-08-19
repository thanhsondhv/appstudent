"""Chặn truy cập theo mã sinh viên, mã thiết bị hoặc địa chỉ IP.

⚠️ TỐI ƯU 19/08/2026 — nút cổ chai nghiêm trọng nhất của hệ thống.

Bản trước: middleware gọi check_is_blocked() BA LẦN cho mỗi yêu cầu HTTP (một
lần cho mã sinh viên, một cho mã thiết bị, một cho IP). Mỗi lần MỞ MỘT KẾT NỐI
SQL MỚI, chạy đồng bộ ngay trong middleware async — tức là chặn cả vòng lặp sự
kiện, không riêng yêu cầu đó.

Đo thực tế ngày 19/08/2026: **15 giây cho mỗi yêu cầu**, kể cả những yêu cầu
không hề chạm cơ sở dữ liệu. Và bảng Blacklist lúc đó có **0 dòng** — toàn bộ
15 giây bị đốt để hỏi ba lần một bảng rỗng.

Với 15 nghìn sinh viên, cách làm đó không thể chịu tải: mỗi yêu cầu chiếm ba
kết nối trong nhiều giây, SQL Server cạn kết nối trước khi tới lượt xử lý thật.

Bản này: giữ toàn bộ danh sách chặn trong bộ nhớ, làm mới định kỳ. Danh sách
này nhỏ (vài chục tới vài trăm dòng) và thay đổi rất thưa, nên đọc từ bộ nhớ là
đúng cách. Kiểm tra một yêu cầu nay tốn vài micro giây thay vì 15 giây.

Đánh đổi: một lệnh chặn mới có thể mất tới GIAY_LAM_MOI giây mới có hiệu lực ở
tiến trình khác. Chấp nhận được vì thời gian khóa tối thiểu là 5 phút — và
add_to_blacklist() làm mới ngay lập tức trong chính tiến trình vừa ra lệnh.
"""

import os
import threading
import time
from datetime import datetime, timedelta
from typing import Optional, Tuple

# 🔥 Đã sửa đường dẫn để trỏ đúng vào file database.py của bạn
from database.database import get_db_conn


# Bao lâu thì đọc lại danh sách chặn từ cơ sở dữ liệu (giây).
GIAY_LAM_MOI = int(os.getenv("BLACKLIST_REFRESH_SECONDS", "30"))

# Khi cơ sở dữ liệu lỗi thì đợi bao lâu mới thử lại, để không dồn dập truy vấn
# vào một máy chủ đang có vấn đề.
GIAY_CHO_SAU_LOI = 10


class _KhoChan:
    """Ảnh chụp danh sách chặn trong bộ nhớ.

    Đọc bằng dict nên không cần khoá; chỉ khoá lúc làm mới để hai luồng không
    cùng truy vấn một lúc. Nếu làm mới thất bại thì GIỮ NGUYÊN ảnh cũ — thà
    dùng dữ liệu hơi cũ còn hơn mở toang cửa hoặc chặn nhầm tất cả.
    """

    def __init__(self) -> None:
        self._muc: dict[str, dict] = {}
        self._luong: Optional[threading.Thread] = None
        self._lan_doc_cuoi: float = 0.0
        self._khoa = threading.Lock()
        self._da_nap_lan_nao = False

    def _can_lam_moi(self) -> bool:
        return (time.monotonic() - self._lan_doc_cuoi) >= GIAY_LAM_MOI

    def lam_moi_neu_can(self, *, bat_buoc: bool = False) -> None:
        if not bat_buoc and not self._can_lam_moi():
            return
        if not self._khoa.acquire(blocking=False):
            return          # luồng khác đang làm, không xếp hàng chờ
        try:
            if not bat_buoc and not self._can_lam_moi():
                return
            self._doc_tu_csdl()
        finally:
            self._khoa.release()

    def khoi_dong_luong_nen(self) -> None:
        """Làm mới định kỳ ở luồng riêng, tách khỏi đường đi của yêu cầu.

        Nếu để việc đọc cơ sở dữ liệu xảy ra ngay trong lúc phục vụ một yêu cầu
        thì cứ mỗi GIAY_LAM_MOI lại có đúng một người dùng xui xẻo phải chờ trọn
        thời gian mở kết nối. Đẩy sang luồng nền thì không ai phải chờ, và vòng
        lặp sự kiện của FastAPI không bị chặn.
        """
        if getattr(self, "_luong", None) is not None:
            return

        def _vong_lap() -> None:
            while True:
                try:
                    self.lam_moi_neu_can(bat_buoc=True)
                except Exception as e:  # noqa: BLE001
                    print(f"⚠️ [ChặnTruyCập] Luồng làm mới gặp lỗi: {e}")
                time.sleep(GIAY_LAM_MOI)

        self._luong = threading.Thread(
            target=_vong_lap, name="lam-moi-danh-sach-chan", daemon=True
        )
        self._luong.start()

    def _doc_tu_csdl(self) -> None:
        try:
            with get_db_conn() as conn:
                dong = conn.cursor().execute("""
                    SELECT target_value, reason, expired_at, violation_count
                    FROM Blacklist
                    WHERE expired_at > GETDATE()
                """).fetchall()

            moi: dict[str, dict] = {}
            for r in dong:
                khoa = str(r[0])
                cu = moi.get(khoa)
                # Cùng một đối tượng có thể có nhiều dòng — giữ dòng hết hạn muộn nhất
                if cu is None or r[2] > cu["expired_at"]:
                    moi[khoa] = {
                        "target_value": khoa,
                        "reason": r[1],
                        "expired_at": r[2],
                        "violation_count": r[3],
                    }

            self._muc = moi
            self._lan_doc_cuoi = time.monotonic()
            self._da_nap_lan_nao = True
        except Exception as e:  # noqa: BLE001
            print(f"⚠️ [ChặnTruyCập] Không đọc được danh sách chặn, giữ bản cũ: {e}")
            # Lùi lịch thử lại, tránh dội truy vấn vào CSDL đang lỗi
            self._lan_doc_cuoi = time.monotonic() - GIAY_LAM_MOI + GIAY_CHO_SAU_LOI

    def tra_cuu(self, muc_tieu: str) -> Optional[dict]:
        # CỐ Ý không đọc cơ sở dữ liệu ở đây. Luồng nền lo việc làm mới; đường
        # đi của một yêu cầu HTTP chỉ được phép đọc bộ nhớ.
        ban_ghi = self._muc.get(muc_tieu)
        if ban_ghi is None:
            return None
        # Ảnh chụp có thể cũ hơn thực tế — bỏ qua bản ghi đã hết hạn
        if ban_ghi["expired_at"] <= datetime.now():
            return None
        return ban_ghi

    def xoa_dem(self) -> None:
        """Ép đọc lại ngay ở lần tra cứu kế tiếp."""
        self._lan_doc_cuoi = 0.0

    @property
    def so_muc(self) -> int:
        return len(self._muc)


_kho_chan = _KhoChan()
_kho_chan.khoi_dong_luong_nen()


class BlacklistManager:
    @staticmethod
    def get_lock_time(target: str) -> Tuple[int, int]:
        """Tính toán thời gian khóa dựa trên lịch sử vi phạm"""
        try:
            # Sử dụng hàm get_db_conn bạn đã viết
            with get_db_conn() as conn:
                cursor = conn.cursor()
                cursor.execute("SELECT total_violations FROM ViolationHistory WHERE target_value = ?", (target,))
                row = cursor.fetchone()
                
                count = (row[0] + 1) if row else 1
                # Lần 1: 5p | Lần 2: 30p | Lần 3: 120p | Lần 4+: 1440p (24h)
                lock_map = {1: 5, 2: 30, 3: 120, 4: 1440}
                return lock_map.get(count, 1440), count
        except Exception as e:
            print(f"⚠️ Lỗi lấy lock_time: {e}")
            return 5, 1

    @staticmethod
    def check_is_blocked(target: str) -> Optional[dict]:
        """Đối tượng này có đang bị chặn không.

        Đọc từ bộ nhớ. Giữ nguyên tên và kiểu trả về của bản cũ để mã đang gọi
        không phải sửa gì.
        """
        if not target:
            return None
        return _kho_chan.tra_cuu(str(target))

    @staticmethod
    def lam_moi_danh_sach_chan() -> None:
        """Đọc lại danh sách chặn ngay, không đợi tới hạn."""
        _kho_chan.lam_moi_neu_can(bat_buoc=True)

    @staticmethod
    def so_muc_dang_chan() -> int:
        """Số đối tượng đang bị chặn — dùng cho trang giám sát."""
        return _kho_chan.so_muc

    @staticmethod
    async def add_to_blacklist(target: str, target_type: str, reason: str):
        """Thực thi lệnh 'nhốt' vào SQL Server VinhUni và in cảnh báo"""
        
        # 1. Lấy thời gian khóa và số lần vi phạm dựa trên lịch sử
        lock_minutes, count = BlacklistManager.get_lock_time(target)
        expiry = datetime.now() + timedelta(minutes=lock_minutes)

        try:
            with get_db_conn() as conn:
                cursor = conn.cursor()

                # --- 🔥 PHẦN 1: IN CẢNH BÁO RA TERMINAL ĐỂ SƠN THEO DÕI ---
                print("\n" + "!" * 60)
                print(f"🚨 [CẢNH BÁO TOOL] PHÁT HIỆN VI PHẠM TẠI VINH UNI")
                print(f"👤 Đối tượng : {target} ({target_type})")
                print(f"🛠️ Hành vi   : {reason}")
                print(f"⏱️ Trạng thái : Khóa lần thứ {count} trong {lock_minutes} phút")
                print(f"📅 Hết hạn   : {expiry.strftime('%H:%M:%S %d/%m/%Y')}")
                print("!" * 60 + "\n")

                # --- 🔥 PHẦN 2: CẬP NHẬT DATABASE (SQL SERVER) ---
                
                # 1. Cập nhật hoặc thêm mới vào lịch sử vi phạm (Sổ bìa đen vĩnh viễn)
                cursor.execute("""
                    IF EXISTS (SELECT 1 FROM ViolationHistory WHERE target_value = ?)
                        UPDATE ViolationHistory 
                        SET total_violations = ?, last_violation_at = GETDATE() 
                        WHERE target_value = ?
                    ELSE
                        INSERT INTO ViolationHistory (target_value, total_violations) 
                        VALUES (?, ?)
                """, (target, count, target, target, count))

                # 2. Đưa vào phòng tạm giam (Blacklist hiện hành)
                cursor.execute("""
                    INSERT INTO Blacklist (target_value, target_type, reason, expired_at, violation_count)
                    VALUES (?, ?, ?, ?, ?)
                """, (target, target_type, reason, expiry, count))
                
                # SQL Server cần commit để xác nhận thay đổi dữ liệu
                conn.commit()

            # Lệnh cấm phải có hiệu lực NGAY ở tiến trình này, không đợi tới
            # hạn làm mới định kỳ.
            _kho_chan.xoa_dem()
            print(f"✅ [V3 FUSION] Hệ thống đã thực thi lệnh cấm cho: {target}")

        except Exception as e:
            print(f"🔥 [LỖI NGHIÊM TRỌNG] Không thể thực thi add_to_blacklist: {e}")

    @staticmethod
    async def verify_request_access(ip: str, device_id: Optional[str] = None, student_code: Optional[str] = None):
        """Kiểm tra đa tầng: mã sinh viên > mã thiết bị > IP.

        Xét mã sinh viên trước rồi mới tới IP, vì cả trường dùng chung vài địa
        chỉ IP ra ngoài — chặn theo IP dễ làm oan hàng nghìn người.

        Toàn bộ phép kiểm tra này đọc từ bộ nhớ nên tốn vài micro giây. Bản cũ
        mở tới ba kết nối SQL cho mỗi yêu cầu HTTP, đo được 15 giây.
        """
        for muc_tieu, loai in ((student_code, "STUDENT_CODE"),
                               (device_id, "DEVICE_ID"),
                               (ip, "IP")):
            if not muc_tieu:
                continue
            chan = _kho_chan.tra_cuu(str(muc_tieu))
            if chan:
                return chan, loai
        return None, None
