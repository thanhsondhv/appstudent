"""
Kiểm thử phần logic khó nhất của hệ thống thông báo, không cần Redis thật.

Ba cơ chế được kiểm ở đây là ba chỗ dễ sai nhất và hậu quả nặng nhất nếu sai:

  1. CHIA NHỎ CÔNG VIỆC — một thông báo tới nhiều nghìn thiết bị phải được cắt
     thành nhiều công việc để các worker cùng gửi. Cắt sai thì hoặc bỏ sót
     người nhận, hoặc gửi trùng.

  2. ĐẾM PHẦN HOÀN THÀNH — chỉ khi phần CUỐI CÙNG gửi xong mới được đánh dấu
     thông báo là đã gửi. Sai ở đây thì phần đầu tiên xong sẽ đóng cả thông báo
     lại trong khi các phần khác còn đang chạy, và những người ở phần sau
     không bao giờ nhận được tin.

  3. HÀNG ĐỢI TIN CẬY — worker chết giữa chừng thì công việc phải quay lại
     hàng đợi, không được biến mất.

Dùng Redis giả trong bộ nhớ nên chạy được ở bất kỳ đâu, kể cả trong CI, mà
không cần cài Redis hay Firebase.

Chạy:  python tests/test_hang_doi_thong_bao.py
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


# ===========================================================================
# Redis giả — chỉ đủ các lệnh mà mã thật dùng
# ===========================================================================


class RedisGia:
    def __init__(self) -> None:
        self.danh_sach: dict[str, list[str]] = {}
        self.chuoi: dict[str, int] = {}

    # -- danh sách --
    def rpush(self, khoa, *gia_tri):
        self.danh_sach.setdefault(khoa, []).extend(gia_tri)
        return len(self.danh_sach[khoa])

    def lrange(self, khoa, dau, cuoi):
        ds = self.danh_sach.get(khoa, [])
        return ds[dau:] if cuoi == -1 else ds[dau:cuoi + 1]

    def llen(self, khoa):
        return len(self.danh_sach.get(khoa, []))

    def lrem(self, khoa, so_luong, gia_tri):
        ds = self.danh_sach.get(khoa, [])
        da_xoa = 0
        while gia_tri in ds and (so_luong == 0 or da_xoa < so_luong):
            ds.remove(gia_tri)
            da_xoa += 1
        return da_xoa

    def brpoplpush(self, nguon, dich, timeout=0):
        ds = self.danh_sach.get(nguon, [])
        if not ds:
            return None
        gia_tri = ds.pop()          # lấy từ cuối, giống RPOP
        self.rpush(dich, gia_tri)
        return gia_tri

    # -- chuỗi/số đếm --
    def set(self, khoa, gia_tri, ex=None):
        self.chuoi[khoa] = int(gia_tri)

    def get(self, khoa):
        return self.chuoi.get(khoa)

    def incrby(self, khoa, so):
        self.chuoi[khoa] = self.chuoi.get(khoa, 0) + int(so)
        return self.chuoi[khoa]

    def decr(self, khoa):
        self.chuoi[khoa] = self.chuoi.get(khoa, 0) - 1
        return self.chuoi[khoa]

    def delete(self, *khoa):
        for k in khoa:
            self.chuoi.pop(k, None)
            self.danh_sach.pop(k, None)


# ===========================================================================
# Bản sao logic cần kiểm
# ===========================================================================
# Không import producer_app/worker_windows vì chúng kéo theo fastapi, redis,
# firebase_admin, pyodbc. Ba hàm dưới đây phản chiếu đúng thuật toán trong mã
# thật; nếu mã thật đổi mà quên đổi ở đây thì phép thử vẫn đạt — nên mỗi khi
# sửa thuật toán chia lô hoặc đếm phần, phải cập nhật cả tệp này.

SO_THIET_BI_MOI_CONG_VIEC = 450


def chia_cong_viec(nid, tokens: list[str]) -> list[dict]:
    """Phản chiếu phần chia nhỏ trong producer_app._quet_va_nap()."""
    cac_lo = [
        tokens[i:i + SO_THIET_BI_MOI_CONG_VIEC]
        for i in range(0, len(tokens), SO_THIET_BI_MOI_CONG_VIEC)
    ]
    return [
        {
            "nid": nid,
            "tokens": lo,
            "phan": thu_tu,
            "tong_phan": len(cac_lo),
            "tong_thiet_bi": len(tokens),
        }
        for thu_tu, lo in enumerate(cac_lo, start=1)
    ]


def dat_bo_dem(r: RedisGia, nid, tong_phan) -> None:
    r.set(f"notif:{nid}:con_lai", tong_phan, ex=21600)
    r.set(f"notif:{nid}:thanh_cong", 0, ex=21600)


def ghi_ket_qua_neu_xong(r: RedisGia, nid, phan_thanh_cong, tong_thiet_bi, da_ghi: list):
    """Phản chiếu worker_windows._ghi_ket_qua_neu_xong().

    `da_ghi` thay cho việc ghi cơ sở dữ liệu — mỗi lần ghi thêm một phần tử.
    """
    r.incrby(f"notif:{nid}:thanh_cong", phan_thanh_cong)
    con_lai = r.decr(f"notif:{nid}:con_lai")
    if con_lai > 0:
        return
    tong = int(r.get(f"notif:{nid}:thanh_cong") or phan_thanh_cong)
    da_ghi.append({"nid": nid, "thanh_cong": tong, "tong": tong_thiet_bi})
    r.delete(f"notif:{nid}:con_lai", f"notif:{nid}:thanh_cong")


# ===========================================================================
# Phép thử
# ===========================================================================


def test_chia_nho_dung_so_luong():
    """15.000 thiết bị phải chia đủ, không sót không thừa."""
    tokens = [f"tk{i}" for i in range(15000)]
    viec = chia_cong_viec(nid=1, tokens=tokens)

    assert len(viec) == 34, f"Phải có 34 công việc, đang có {len(viec)}"
    gom = [t for v in viec for t in v["tokens"]]
    assert gom == tokens, "Ghép lại các phần phải ra đúng danh sách ban đầu"
    assert len(set(gom)) == 15000, "Không được có thiết bị nào lặp lại"
    assert all(len(v["tokens"]) <= 450 for v in viec), "Không lô nào được quá 450"
    assert all(v["tong_phan"] == 34 for v in viec), "Mọi phần phải biết tổng số phần"


def test_khong_chia_khi_it_thiet_bi():
    """245 thiết bị như hiện nay thì chỉ tạo đúng một công việc."""
    viec = chia_cong_viec(nid=2, tokens=[f"tk{i}" for i in range(245)])
    assert len(viec) == 1
    assert viec[0]["tong_phan"] == 1


def test_chi_phan_cuoi_cung_ghi_ket_qua():
    """Đây là chỗ dễ sai nhất: phần đầu xong KHÔNG được đóng cả thông báo."""
    r = RedisGia()
    da_ghi: list = []
    tokens = [f"tk{i}" for i in range(1000)]      # → 3 phần
    viec = chia_cong_viec(nid=7, tokens=tokens)
    dat_bo_dem(r, 7, len(viec))

    for i, v in enumerate(viec, start=1):
        ghi_ket_qua_neu_xong(r, 7, len(v["tokens"]), v["tong_thiet_bi"], da_ghi)
        if i < len(viec):
            assert not da_ghi, f"Phần {i}/{len(viec)} xong mà đã ghi kết quả — SAI"

    assert len(da_ghi) == 1, "Chỉ được ghi đúng một lần"
    assert da_ghi[0]["thanh_cong"] == 1000, \
        f"Phải cộng dồn đủ 1000, đang là {da_ghi[0]['thanh_cong']}"


def test_dem_dung_khi_cac_phan_xong_khong_theo_thu_tu():
    """Nhiều worker chạy song song nên thứ tự hoàn thành là ngẫu nhiên."""
    r = RedisGia()
    da_ghi: list = []
    viec = chia_cong_viec(nid=9, tokens=[f"tk{i}" for i in range(1350)])  # 3 phần
    dat_bo_dem(r, 9, len(viec))

    for v in [viec[2], viec[0], viec[1]]:          # xong theo thứ tự đảo lộn
        ghi_ket_qua_neu_xong(r, 9, len(v["tokens"]), v["tong_thiet_bi"], da_ghi)

    assert len(da_ghi) == 1
    assert da_ghi[0]["thanh_cong"] == 1350


def test_mot_phan_that_bai_van_ghi_so_that():
    """Phần lỗi trả về 0 thiết bị — tổng phải phản ánh đúng, không làm tròn lên."""
    r = RedisGia()
    da_ghi: list = []
    viec = chia_cong_viec(nid=11, tokens=[f"tk{i}" for i in range(900)])  # 2 phần
    dat_bo_dem(r, 11, len(viec))

    ghi_ket_qua_neu_xong(r, 11, 450, 900, da_ghi)   # phần 1 thành công
    ghi_ket_qua_neu_xong(r, 11, 0, 900, da_ghi)     # phần 2 thất bại

    assert len(da_ghi) == 1
    assert da_ghi[0]["thanh_cong"] == 450, "Phải ghi 450/900, không được ghi 900"


def test_hang_doi_giu_viec_cho_den_khi_xong():
    """BRPOPLPUSH: việc phải nằm ở hàng 'đang xử lý' cho tới khi gửi xong."""
    r = RedisGia()
    r.rpush("q_default", "viec_1")

    chuoi = r.brpoplpush("q_default", "q_default:dang_xu_ly", timeout=1)
    assert chuoi == "viec_1"
    assert r.llen("q_default") == 0, "Đã lấy ra khỏi hàng chính"
    assert r.llen("q_default:dang_xu_ly") == 1, \
        "Phải còn ở hàng đang xử lý — nếu worker chết lúc này thì mới lấy lại được"

    r.lrem("q_default:dang_xu_ly", 1, chuoi)        # gửi xong
    assert r.llen("q_default:dang_xu_ly") == 0


def test_lay_lai_viec_khi_worker_chet():
    """Việc treo quá lâu ở hàng 'đang xử lý' phải được đưa về hàng chính."""
    import json

    r = RedisGia()
    GIAY_COI_NHU_CHET = 300

    cu = json.dumps({"nid": 5, "_bat_dau_luc": time.time() - 400})   # treo 400 giây
    moi = json.dumps({"nid": 6, "_bat_dau_luc": time.time() - 10})   # mới 10 giây
    r.rpush("q_default:dang_xu_ly", cu, moi)

    moc = time.time() - GIAY_COI_NHU_CHET
    for chuoi in r.lrange("q_default:dang_xu_ly", 0, -1):
        d = json.loads(chuoi)
        if d.get("_bat_dau_luc", 0) > moc:
            continue                                  # còn mới, để yên
        r.lrem("q_default:dang_xu_ly", 1, chuoi)
        d["_lan_thu"] = d.get("_lan_thu", 0) + 1
        d.pop("_bat_dau_luc", None)
        r.rpush("q_default", json.dumps(d))

    assert r.llen("q_default") == 1, "Việc treo phải quay lại hàng chính"
    assert r.llen("q_default:dang_xu_ly") == 1, "Việc mới phải được để yên"
    assert json.loads(r.lrange("q_default", 0, -1)[0])["nid"] == 5


def test_bo_cuoc_sau_so_lan_thu_lai():
    """Tin hỏng không được quay vòng vô tận — phải sang hàng đợi lỗi."""
    import json

    r = RedisGia()
    SO_LAN_THU_LAI = 3
    d = {"nid": 8, "_lan_thu": 3, "_bat_dau_luc": time.time() - 400}
    r.rpush("q_default:dang_xu_ly", json.dumps(d))

    for chuoi in r.lrange("q_default:dang_xu_ly", 0, -1):
        data = json.loads(chuoi)
        r.lrem("q_default:dang_xu_ly", 1, chuoi)
        if data.get("_lan_thu", 0) >= SO_LAN_THU_LAI:
            r.rpush("q_default:that_bai", chuoi)
        else:
            r.rpush("q_default", chuoi)

    assert r.llen("q_default") == 0, "Không được đưa lại vào hàng chính"
    assert r.llen("q_default:that_bai") == 1, "Phải nằm ở hàng đợi lỗi để người vận hành xem"


if __name__ == "__main__":
    phep_thu = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    loi = 0
    for fn in phep_thu:
        try:
            fn()
            print(f"  ✅ {fn.__name__}")
        except AssertionError as exc:
            loi += 1
            print(f"  ❌ {fn.__name__}\n     {exc}")
        except Exception as exc:  # noqa: BLE001
            loi += 1
            print(f"  ❌ {fn.__name__} — lỗi bất ngờ: {exc}")

    tong = len(phep_thu)
    print(f"\n{'✅ TẤT CẢ ĐẠT' if loi == 0 else f'❌ {loi}/{tong} KHÔNG ĐẠT'}  ({tong} phép thử)")
    sys.exit(1 if loi else 0)
