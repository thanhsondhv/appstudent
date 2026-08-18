"""
Worker gửi thông báo — lấy việc từ Redis và gọi Firebase.

Chạy nhiều bản song song, mỗi bản một tiến trình:
    python worker_windows.py q_high
    python worker_windows.py q_default

═══════════════════════════════════════════════════════════════════════════
VIẾT LẠI NGÀY 18/08/2026 — vấn đề mất tin của bản cũ
═══════════════════════════════════════════════════════════════════════════

Bản cũ dùng BLPOP: lệnh này lấy công việc RA KHỎI hàng đợi ngay lập tức. Nếu
worker chết giữa chừng — mất điện, hết bộ nhớ, Redis khởi động lại, người vận
hành đóng nhầm cửa sổ — thì công việc biến mất khỏi Redis, trong khi bản ghi
trong cơ sở dữ liệu đã bị đánh dấu "đang xử lý". Tin đó không bao giờ được gửi
và cũng không ai biết.

Nay dùng BRPOPLPUSH: công việc được chuyển sang một hàng đợi "đang xử lý" một
cách nguyên tử, chỉ bị xoá khỏi đó khi đã gửi xong. Việc nào nằm quá lâu ở
hàng đợi đó nghĩa là worker phụ trách đã chết — worker khác sẽ nhặt lại.
"""

from __future__ import annotations

import json
import os
import signal
import sys
import time

from redis import Redis

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tasks import LoiGuiThongBao, send_fcm_task  # noqa: E402

REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))

# Công việc nằm ở hàng đợi "đang xử lý" quá ngần này giây thì coi như worker
# phụ trách đã chết, cho phép worker khác nhặt lại.
GIAY_COI_NHU_CHET = int(os.getenv("NOTIF_STALE_SECONDS", "300"))

# Số lần thử lại trước khi bỏ cuộc — tránh một tin hỏng quay vòng vô tận
SO_LAN_THU_LAI = int(os.getenv("NOTIF_MAX_RETRY", "3"))

_dang_chay = True


def _dung_lai(signum, frame):  # noqa: ARG001
    """Dừng êm khi nhận tín hiệu tắt, để không bỏ dở công việc đang làm."""
    global _dang_chay
    print("\n🛑 Nhận tín hiệu dừng, hoàn tất công việc hiện tại rồi thoát…")
    _dang_chay = False


def _ghi_ket_qua_neu_xong(r: Redis, nid, phan_thanh_cong: int, tong_thiet_bi: int) -> None:
    """Đếm ngược số phần còn lại; phần cuối cùng xong thì ghi kết quả vào CSDL.

    Một thông báo lớn được chia cho nhiều worker cùng gửi. Phần nào xong cũng
    giảm bộ đếm đi một. Chỉ khi bộ đếm về 0 — tức là phần cuối cùng — mới đánh
    dấu thông báo là đã gửi. Nếu để mỗi phần tự đánh dấu thì phần đầu tiên xong
    sẽ đóng cả thông báo lại trong khi các phần khác còn đang chạy.

    DECR của Redis là thao tác nguyên tử nên không sợ hai worker cùng lúc.
    """
    try:
        r.incrby(f"notif:{nid}:thanh_cong", phan_thanh_cong)
        con_lai = r.decr(f"notif:{nid}:con_lai")

        if con_lai is not None and con_lai > 0:
            return  # còn phần khác đang chạy

        tong_thanh_cong = int(r.get(f"notif:{nid}:thanh_cong") or phan_thanh_cong)

        from database import get_db_conn
        with get_db_conn() as conn:
            cursor = conn.cursor()
            cursor.execute(
                "UPDATE tbl_Notification_Queue "
                "SET IsSent = ?, SentAt = GETDATE(), Summary = ? WHERE Id = ?",
                (
                    1 if tong_thanh_cong > 0 else 0,   # 1 = đã gửi, 0 = để thử lại
                    f"Gửi {tong_thanh_cong}/{tong_thiet_bi} thiết bị",
                    nid,
                ),
            )
            conn.commit()

        r.delete(f"notif:{nid}:con_lai", f"notif:{nid}:thanh_cong")
        print(f"✅ Tin #{nid} hoàn tất: {tong_thanh_cong}/{tong_thiet_bi} thiết bị")

    except Exception as exc:  # noqa: BLE001
        print(f"⚠️  Không ghi được kết quả tin #{nid}: {exc}")


def _nhat_lai_viec_bo_do(r: Redis, hang_doi: str, hang_dang_lam: str) -> None:
    """Đưa lại những công việc bị bỏ dở về hàng đợi chính.

    Chỉ nhặt việc đã nằm quá lâu — việc mới vào có thể đang được worker khác xử lý.
    """
    try:
        cho_doi = r.lrange(hang_dang_lam, 0, -1)
        moc = time.time() - GIAY_COI_NHU_CHET
        so_nhat = 0

        for chuoi in cho_doi:
            try:
                du_lieu = json.loads(chuoi)
            except json.JSONDecodeError:
                r.lrem(hang_dang_lam, 1, chuoi)
                continue

            bat_dau = du_lieu.get("_bat_dau_luc", 0)
            if bat_dau and bat_dau > moc:
                continue  # còn mới, để yên

            r.lrem(hang_dang_lam, 1, chuoi)
            lan_thu = du_lieu.get("_lan_thu", 0)
            if lan_thu >= SO_LAN_THU_LAI:
                r.rpush(f"{hang_doi}:that_bai", chuoi)
                print(f"⚠️  Tin #{du_lieu.get('nid')} thất bại {lan_thu} lần "
                      f"→ chuyển sang hàng đợi lỗi")
            else:
                du_lieu["_lan_thu"] = lan_thu + 1
                du_lieu.pop("_bat_dau_luc", None)
                r.rpush(hang_doi, json.dumps(du_lieu, default=str))
                so_nhat += 1

        if so_nhat:
            print(f"♻️  Nhặt lại {so_nhat} công việc bị bỏ dở")

    except Exception as exc:  # noqa: BLE001
        print(f"⚠️  Lỗi khi nhặt việc bỏ dở: {exc}")


def start_worker(hang_doi: str) -> None:
    r = Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)
    hang_dang_lam = f"{hang_doi}:dang_xu_ly"

    print(f"👷 Worker trực làn: {hang_doi}  (pid {os.getpid()})")
    print(f"   Redis {REDIS_HOST}:{REDIS_PORT} · nhặt lại việc bỏ dở sau {GIAY_COI_NHU_CHET}s")

    _nhat_lai_viec_bo_do(r, hang_doi, hang_dang_lam)
    lan_don_gan_nhat = time.time()

    while _dang_chay:
        try:
            # Định kỳ nhặt lại việc mà worker khác bỏ dở
            if time.time() - lan_don_gan_nhat > GIAY_COI_NHU_CHET:
                _nhat_lai_viec_bo_do(r, hang_doi, hang_dang_lam)
                lan_don_gan_nhat = time.time()

            # BRPOPLPUSH: chuyển việc sang hàng "đang xử lý" một cách nguyên tử.
            # timeout=5 để vòng lặp còn cơ hội chạy phần dọn dẹp ở trên.
            chuoi = r.brpoplpush(hang_doi, hang_dang_lam, timeout=5)
            if chuoi is None:
                continue

            try:
                du_lieu = json.loads(chuoi)
            except json.JSONDecodeError:
                print("❌ Bỏ qua một công việc không đọc được")
                r.lrem(hang_dang_lam, 1, chuoi)
                continue

            # Ghi thời điểm bắt đầu để biết việc nào bị treo
            danh_dau = dict(du_lieu, _bat_dau_luc=time.time())
            r.lrem(hang_dang_lam, 1, chuoi)
            chuoi_danh_dau = json.dumps(danh_dau, default=str)
            r.rpush(hang_dang_lam, chuoi_danh_dau)

            try:
                ket_qua = send_fcm_task(
                    du_lieu["nid"],
                    du_lieu["title"],
                    du_lieu["body"],
                    du_lieu["cat"],
                    du_lieu["tokens"],
                    du_lieu["priority"],
                    du_lieu.get("group_id", ""),
                )
                # Gửi xong mới xoá khỏi hàng "đang xử lý"
                r.lrem(hang_dang_lam, 1, chuoi_danh_dau)

                phan = du_lieu.get("phan", 1)
                tong_phan = du_lieu.get("tong_phan", 1)
                if tong_phan > 1:
                    print(f"   phần {phan}/{tong_phan} của tin #{du_lieu['nid']}: "
                          f"{ket_qua['thanh_cong']}/{ket_qua['tong']} thiết bị")

                _ghi_ket_qua_neu_xong(
                    r,
                    du_lieu["nid"],
                    ket_qua["thanh_cong"],
                    du_lieu.get("tong_thiet_bi", ket_qua["tong"]),
                )

            except LoiGuiThongBao as exc:
                r.lrem(hang_dang_lam, 1, chuoi_danh_dau)
                lan_thu = du_lieu.get("_lan_thu", 0) + 1
                if lan_thu >= SO_LAN_THU_LAI:
                    r.rpush(f"{hang_doi}:that_bai", json.dumps(du_lieu, default=str))
                    print(f"⚠️  Tin #{du_lieu.get('nid')} bỏ cuộc sau {lan_thu} lần: {exc}")
                else:
                    du_lieu["_lan_thu"] = lan_thu
                    r.rpush(hang_doi, json.dumps(du_lieu, default=str))
                    print(f"🔁 Tin #{du_lieu.get('nid')} sẽ thử lại (lần {lan_thu})")

            except Exception as exc:  # noqa: BLE001
                # Lỗi lạ: để nguyên ở hàng "đang xử lý", cơ chế nhặt lại sẽ lo
                print(f"❌ Lỗi ngoài dự kiến với tin #{du_lieu.get('nid')}: {exc}")

        except KeyboardInterrupt:
            break
        except Exception as exc:  # noqa: BLE001
            print(f"❌ Lỗi vòng lặp worker: {exc}")
            time.sleep(2)

    print("👋 Worker đã dừng")


if __name__ == "__main__":
    signal.signal(signal.SIGINT, _dung_lai)
    signal.signal(signal.SIGTERM, _dung_lai)
    start_worker(sys.argv[1] if len(sys.argv) > 1 else "q_default")
