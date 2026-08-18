"""
Bộ nạp hàng đợi thông báo (Producer).

Quét bảng tbl_Notification_Queue, tìm người nhận, rồi đẩy công việc vào Redis
cho các worker gửi đi. Chia hai làn theo mức ưu tiên: q_high cho tin cần đến
ngay (chat, nhắc lịch thi), q_default cho tin thường.

═══════════════════════════════════════════════════════════════════════════
VIẾT LẠI NGÀY 18/08/2026 — sáu vấn đề của bản cũ
═══════════════════════════════════════════════════════════════════════════

1. GỬI NHẦM NGƯỜI (nghiêm trọng nhất)
   Bản cũ:  WHERE StudentId LIKE '%2057%'
   Mã 2057 khớp luôn 12057, 20570, 120579 — thông báo cá nhân về điểm, học
   phí, tin nhắn riêng bị gửi cho người khác. Nay so khớp CHÍNH XÁC sau khi
   chuẩn hoá mã.

2. TRUY VẤN N+1
   Bản cũ chạy một truy vấn cho MỖI người nhận. Gửi toàn trường 5.000 sinh
   viên = 5.000 lượt truy vấn cho một thông báo. Nay gom thành một truy vấn
   theo lô.

3. BỎ QUA CÀI ĐẶT NGƯỜI DÙNG
   Màn "Cấu hình nhận thông báo" ghi vào tbl_Notification_User_Settings nhưng
   bản cũ không đọc — người dùng tắt nhận tin vẫn bị gửi. Nay lọc theo IsEnabled.

4. BỎ RƠI TIN CŨ HƠN 24 GIỜ
   Bản cũ:  AND CreatedAt >= DATEADD(hour, -24, GETDATE())
   Hệ thống nghỉ một ngày là toàn bộ tin trong khoảng đó không bao giờ được
   gửi, mà vẫn nằm IsSent = 0 tích tụ mãi. Nay xử lý hết tin tồn, chỉ đánh dấu
   bỏ qua khi đã quá hạn thực sự (mặc định 7 ngày) và ghi rõ lý do.

5. MẤT TIN KHI WORKER CHẾT
   Xem worker_windows.py — nay dùng hàng đợi "đang xử lý" để lấy lại tin.

6. KHÔNG CÓ GIỚI HẠN LÔ GỬI
   Xem tasks.py — Firebase giới hạn cứng 500 token mỗi lượt.
"""

from __future__ import annotations

import asyncio
import json
import os
import sys
from datetime import datetime

import pyodbc
import redis.asyncio as redis
from fastapi import FastAPI
from contextlib import asynccontextmanager

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from core.settings import settings  # noqa: E402

# ---------------------------------------------------------------------------
# Cấu hình
# ---------------------------------------------------------------------------

REMOTE_CONN_STR = settings.db.local_conn_str

REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))

CHU_KY_GIAY = int(os.getenv("NOTIF_SCAN_INTERVAL", "5"))
SO_TIN_MOI_LUOT = int(os.getenv("NOTIF_BATCH_SIZE", "100"))

# Tin cũ hơn ngần này thì không gửi nữa — gửi muộn cả tuần còn phiền hơn không gửi
SO_NGAY_QUA_HAN = int(os.getenv("NOTIF_MAX_AGE_DAYS", "7"))

# SQL Server giới hạn 2100 tham số mỗi câu lệnh; chia lô cho an toàn
SO_MA_MOI_TRUY_VAN = 1000

# Số thiết bị mỗi công việc trong hàng đợi.
#
# Đây là con số quyết định tốc độ ở quy mô lớn. Một thông báo toàn trường tới
# ~15.000 thiết bị, nếu để nguyên MỘT công việc thì chỉ MỘT worker gánh, bốn
# worker còn lại đứng nhìn, và tin nhắn chat xếp hàng phía sau hàng chục phút.
# Chia thành nhiều công việc nhỏ để cả năm worker cùng làm.
#
# 450 khớp với giới hạn cứng 500 token mỗi lượt gửi của Firebase, chừa dư an toàn.
SO_THIET_BI_MOI_CONG_VIEC = int(os.getenv("NOTIF_DEVICES_PER_JOB", "450"))

# Chế độ chạy thử: tìm người nhận và in ra kết quả, KHÔNG ghi gì vào cơ sở dữ
# liệu và KHÔNG đẩy việc vào Redis. Dùng để kiểm tra xem truy vấn có tìm đúng
# người không, trước khi cho gửi thật.
#     NOTIF_DRY_RUN=1 python producer_app.py
CHAY_THU = os.getenv("NOTIF_DRY_RUN", "").strip() in ("1", "true", "yes")

# Trạng thái trong tbl_Notification_Queue
CHUA_GUI, DA_GUI, DANG_XU_LY, BO_QUA = 0, 1, 2, 3

r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)


def _lam_sach(ma) -> str:
    """Chuẩn hoá mã người dùng: bỏ tiền tố SV/CB, viết hoa, cắt khoảng trắng."""
    return str(ma or "").strip().upper().replace("SV", "").replace("CB", "")


# ---------------------------------------------------------------------------
# Tìm người nhận
# ---------------------------------------------------------------------------


def _lay_token_theo_ma(cursor, ma_list: list[str], category: str) -> list[str]:
    """Lấy token của những người ĐƯỢC PHÉP nhận loại tin này.

    Gộp ba việc vào một truy vấn thay vì lặp từng người:
      • so khớp mã chính xác (không dùng LIKE)
      • chỉ lấy token đang hoạt động
      • loại người đã tắt nhận loại tin này trong cài đặt

    Không có bản ghi cài đặt thì mặc định là BẬT — người chưa từng vào màn cấu
    hình vẫn nhận tin bình thường.
    """
    if not ma_list:
        return []

    tokens: list[str] = []
    for i in range(0, len(ma_list), SO_MA_MOI_TRUY_VAN):
        lo = ma_list[i:i + SO_MA_MOI_TRUY_VAN]
        cho_trong = ",".join("?" * len(lo))
        sql = f"""
            SELECT DISTINCT t.FCMToken
            FROM tbl_FCM_Tokens t
            LEFT JOIN tbl_Notification_User_Settings s
                   ON s.UserId = REPLACE(REPLACE(UPPER(RTRIM(t.StudentId)), 'SV', ''), 'CB', '')
                  AND s.Category = ?
            WHERE t.IsActive = 1
              AND t.FCMToken IS NOT NULL AND LEN(t.FCMToken) > 0
              AND REPLACE(REPLACE(UPPER(RTRIM(t.StudentId)), 'SV', ''), 'CB', '') IN ({cho_trong})
              AND ISNULL(s.IsEnabled, 1) = 1
        """
        cursor.execute(sql, (category, *lo))
        tokens.extend(row[0] for row in cursor.fetchall() if row[0])

    return list(dict.fromkeys(tokens))  # bỏ trùng, giữ thứ tự


def _lay_token_toan_truong(cursor, category: str) -> list[str]:
    """Người nhận là 'ALL' — lấy mọi token đang hoạt động, trừ người đã tắt.

    Không liệt kê từng mã rồi mới tra: với vài nghìn người thì cách đó vừa chậm
    vừa vượt giới hạn tham số của SQL Server.
    """
    cursor.execute("""
        SELECT DISTINCT t.FCMToken
        FROM tbl_FCM_Tokens t
        LEFT JOIN tbl_Notification_User_Settings s
               ON s.UserId = REPLACE(REPLACE(UPPER(RTRIM(t.StudentId)), 'SV', ''), 'CB', '')
              AND s.Category = ?
        WHERE t.IsActive = 1
          AND t.FCMToken IS NOT NULL AND LEN(t.FCMToken) > 0
          AND ISNULL(s.IsEnabled, 1) = 1
    """, (category,))
    return [row[0] for row in cursor.fetchall() if row[0]]


# ---------------------------------------------------------------------------
# Vòng quét
# ---------------------------------------------------------------------------


def _quet_va_nap() -> list[tuple[str, dict]]:
    """Đọc tin chưa gửi, tìm người nhận, trả về danh sách (tên hàng đợi, công việc).

    Chạy đồng bộ trong executor vì pyodbc không hỗ trợ async.
    """
    cong_viec: list[tuple[str, dict]] = []

    with pyodbc.connect(REMOTE_CONN_STR) as conn:
        cursor = conn.cursor()

        # 1. Đánh dấu bỏ qua những tin đã quá hạn — để chúng không nằm mãi
        #    trong bảng và không bị gửi muộn cả tuần.
        # Truyền thẳng số ÂM chứ không viết DATEADD(day, -?, ...):
        # SQL Server không cho đặt dấu trừ trước tham số, sẽ báo
        # "Operand data type nvarchar is invalid for minus operator".
        if not CHAY_THU:
            cursor.execute("""
                UPDATE tbl_Notification_Queue
                SET IsSent = ?, Summary = N'Bỏ qua: quá hạn gửi'
                WHERE IsSent = ? AND CreatedAt < DATEADD(day, ?, GETDATE())
            """, (BO_QUA, CHUA_GUI, -SO_NGAY_QUA_HAN))
            so_bo_qua = cursor.rowcount
            if so_bo_qua > 0:
                print(f"⏭️  Bỏ qua {so_bo_qua} tin quá hạn (> {SO_NGAY_QUA_HAN} ngày)")

        # 2. Lấy tin cần gửi. Ưu tiên cao trước, cùng mức thì cũ trước.
        cursor.execute(f"""
            SELECT TOP {SO_TIN_MOI_LUOT}
                   Id, StudentId, Title, Body, Category,
                   ISNULL(Priority, 0), IdNguoiHocs, Scope
            FROM tbl_Notification_Queue
            WHERE IsSent = ?
            ORDER BY Priority DESC, Id ASC
        """, (CHUA_GUI,))
        rows = cursor.fetchall()

        for row in rows:
            nid, sid, title, body, cat, prio, id_list, scope = row
            category = str(cat or "GENERAL").upper()

            # 3. Xác định người nhận
            if str(sid or "").strip().upper() == "ALL":
                tokens = _lay_token_toan_truong(cursor, category)
            else:
                ma_list = []
                if sid:
                    ma_list.append(_lam_sach(sid))
                if id_list:
                    ma_list.extend(_lam_sach(x) for x in str(id_list).split(","))
                ma_list = [m for m in dict.fromkeys(ma_list) if m]
                tokens = _lay_token_theo_ma(cursor, ma_list, category)

            # 4. Không có ai nhận thì đóng tin lại, ghi rõ lý do
            if not tokens:
                if CHAY_THU:
                    print(f"   [thử] tin #{nid} ({category}): KHÔNG có người nhận đủ điều kiện")
                else:
                    cursor.execute("""
                        UPDATE tbl_Notification_Queue
                        SET IsSent = ?, SentAt = GETDATE(),
                            Summary = N'Không có người nhận đủ điều kiện'
                        WHERE Id = ?
                    """, (DA_GUI, nid))
                continue

            is_chat = category in ("CHAT", "CHAT_GROUP")
            hang_doi = "q_high" if prio >= 5 else "q_default"

            # Chia danh sách thiết bị thành nhiều công việc nhỏ để các worker
            # cùng xử lý song song. Mỗi phần mang theo số thứ tự và tổng số
            # phần; worker dùng bộ đếm trong Redis để biết khi nào xong hết.
            cac_lo = [
                tokens[i:i + SO_THIET_BI_MOI_CONG_VIEC]
                for i in range(0, len(tokens), SO_THIET_BI_MOI_CONG_VIEC)
            ]
            tong_phan = len(cac_lo)

            for thu_tu, lo in enumerate(cac_lo, start=1):
                cong_viec.append((
                    hang_doi,
                    {
                        "nid": nid,
                        "title": title,
                        "body": body,
                        "cat": cat,
                        "tokens": lo,
                        "priority": prio,
                        "group_id": scope if is_chat else "",
                        "phan": thu_tu,
                        "tong_phan": tong_phan,
                        "tong_thiet_bi": len(tokens),
                        "nap_luc": datetime.now().isoformat(),
                    },
                ))

            # 5. Đánh dấu ĐANG XỬ LÝ để lượt quét sau không lấy lại
            if CHAY_THU:
                print(f"   [thử] tin #{nid} ({category}) → {len(tokens)} thiết bị, "
                      f"{tong_phan} công việc, làn {hang_doi}")
            else:
                cursor.execute(
                    "UPDATE tbl_Notification_Queue SET IsSent = ? WHERE Id = ?",
                    (DANG_XU_LY, nid),
                )

        if CHAY_THU:
            conn.rollback()   # chắc chắn không để lại dấu vết nào
        else:
            conn.commit()

    return cong_viec


async def producer_loop() -> None:
    if CHAY_THU:
        print("🧪 CHẠY THỬ — không ghi cơ sở dữ liệu, không đẩy vào Redis")
    print(f"🚀 Bộ nạp hàng đợi đã khởi động — quét mỗi {CHU_KY_GIAY} giây")
    print(f"   CSDL: {settings.db.safe_repr}")
    print(f"   Redis: {REDIS_HOST}:{REDIS_PORT}")

    while True:
        try:
            loop = asyncio.get_event_loop()
            cong_viec = await loop.run_in_executor(None, _quet_va_nap)

            # Đặt bộ đếm số phần còn lại cho từng thông báo TRƯỚC khi đẩy việc
            # đi. Nếu đặt sau, worker nhanh tay có thể xử lý xong một phần khi
            # bộ đếm chưa tồn tại và tưởng nhầm là đã hoàn tất.
            so_phan: dict = {}
            for _, du_lieu in cong_viec:
                so_phan[du_lieu["nid"]] = du_lieu["tong_phan"]
            if not CHAY_THU:
                for nid, tong in so_phan.items():
                    khoa = f"notif:{nid}:con_lai"
                    await r.set(khoa, tong, ex=6 * 3600)      # tự dọn sau 6 giờ
                    await r.set(f"notif:{nid}:thanh_cong", 0, ex=6 * 3600)

            if not CHAY_THU:
                for hang_doi, du_lieu in cong_viec:
                    await r.rpush(hang_doi, json.dumps(du_lieu, default=str))

            if cong_viec:
                cao = sum(1 for q, _ in cong_viec if q == "q_high")
                tong_token = sum(len(d["tokens"]) for _, d in cong_viec)
                print(f"📤 Nạp {len(so_phan)} tin → {len(cong_viec)} công việc "
                      f"({cao} ưu tiên cao) → {tong_token} thiết bị")

        except pyodbc.Error as exc:
            print(f"⚠️  Lỗi cơ sở dữ liệu: {exc}")
        except Exception as exc:  # noqa: BLE001
            print(f"⚠️  Lỗi vòng quét: {exc}")

        await asyncio.sleep(CHU_KY_GIAY)


# ---------------------------------------------------------------------------
# Ứng dụng
# ---------------------------------------------------------------------------


@asynccontextmanager
async def lifespan(app: FastAPI):
    task = asyncio.create_task(producer_loop())
    yield
    task.cancel()


app = FastAPI(title="VinhUni Notification Producer", lifespan=lifespan)


@app.get("/health")
async def health():
    """Cho công cụ giám sát biết bộ nạp còn sống và Redis còn kết nối."""
    try:
        await r.ping()
        redis_ok = True
    except Exception:  # noqa: BLE001
        redis_ok = False
    return {"trang_thai": "ok" if redis_ok else "loi_redis", "redis": redis_ok}


@app.get("/trang-thai-hang-doi")
async def trang_thai_hang_doi():
    """Độ dài các hàng đợi — tăng liên tục nghĩa là worker không kịp xử lý."""
    return {
        "q_high": await r.llen("q_high"),
        "q_default": await r.llen("q_default"),
        "q_high:dang_xu_ly": await r.llen("q_high:dang_xu_ly"),
        "q_default:dang_xu_ly": await r.llen("q_default:dang_xu_ly"),
    }


if __name__ == "__main__":
    import uvicorn

    # Cổng 8082 — bản cũ dùng 8081, trùng với notification_worker.py ở thư mục
    # gốc nên hai bên không chạy cùng lúc được.
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PRODUCER_PORT", "8082")))
