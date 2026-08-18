"""
API ký số văn bản và hồ sơ dịch vụ công.

Mọi endpoint ký đều yêu cầu vai trò cán bộ trở lên — kiểm tra ở tầng đường dẫn
bằng `Depends(require_staff)`, không dựa vào việc ứng dụng có ẩn nút hay không.

Endpoint kiểm tra chữ ký thì mở cho mọi người đã đăng nhập, kể cả sinh viên:
người nhận văn bản cần tự xác minh được văn bản mình cầm là thật.

Thêm ngày 18/08/2026.
"""

from __future__ import annotations

import logging
import shutil
import tempfile
from pathlib import Path

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from fastapi.responses import FileResponse, JSONResponse

from auth.jwt_handler import Identity, get_current_user, require_admin, require_staff
from services.signing_service import (
    LoiKySo,
    MucPAdES,
    YeuCauKy,
    signing_service,
)

logger = logging.getLogger("vinhuni.signature_api")

router = APIRouter(prefix="/api/chu-ky-so", tags=["Ký số"])

# Chỉ nhận PDF. Ảnh và tệp Word phải chuyển sang PDF trước — ký trực tiếp lên
# định dạng khác thì phần mềm đọc phổ thông không kiểm tra được chữ ký.
KIEU_TEP_CHO_PHEP = {"application/pdf"}
DUNG_LUONG_TOI_DA = 25 * 1024 * 1024  # 25 MB


# ---------------------------------------------------------------------------
# Trạng thái hệ thống ký số
# ---------------------------------------------------------------------------


@router.get("/trang-thai")
async def trang_thai_ky_so(me: Identity = Depends(require_staff)):
    """Tình trạng sẵn sàng của hệ thống ký số.

    Hiển thị trên cổng quản trị để biết ngay có ký được không, và nếu chưa thì
    thiếu gì — thay vì phải thử ký rồi mới biết lỗi.
    """
    return signing_service.trang_thai()


# ---------------------------------------------------------------------------
# Ký văn bản
# ---------------------------------------------------------------------------


@router.post("/ky")
async def ky_van_ban(
    tep: UploadFile = File(..., description="Tệp PDF cần ký"),
    ly_do: str = Form("Phê duyệt văn bản"),
    chuc_danh: str = Form(""),
    muc: str = Form(MucPAdES.LT.value),
    hien_thi_chu_ky: bool = Form(True),
    me: Identity = Depends(require_staff),
):
    """Ký số một văn bản PDF.

    Người ký được xác định TỪ TOKEN — không nhận tên người ký từ máy khách gửi
    lên. Cho phép máy khách tự khai người ký thì bất kỳ ai cũng ký thay được
    lãnh đạo.
    """
    if tep.content_type not in KIEU_TEP_CHO_PHEP:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Chỉ ký được tệp PDF. Vui lòng chuyển văn bản sang PDF trước khi ký.",
        )

    try:
        muc_pades = MucPAdES(muc)
    except ValueError:
        muc_pades = MucPAdES.LT

    thu_muc_tam = Path(tempfile.mkdtemp(prefix="vinhuni_ky_"))
    try:
        duong_dan_vao = thu_muc_tam / (tep.filename or "van_ban.pdf")
        kich_thuoc = 0
        with duong_dan_vao.open("wb") as fh:
            while khoi := await tep.read(1024 * 1024):
                kich_thuoc += len(khoi)
                if kich_thuoc > DUNG_LUONG_TOI_DA:
                    raise HTTPException(
                        status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                        detail=f"Tệp vượt quá {DUNG_LUONG_TOI_DA // (1024 * 1024)} MB",
                    )
                fh.write(khoi)

        ket_qua = signing_service.ky_van_ban(
            YeuCauKy(
                duong_dan_pdf=duong_dan_vao,
                nguoi_ky_ma=me.user_code,
                # Tên hiển thị lấy từ chứng thư số khi ký, đây chỉ là nhãn phụ
                nguoi_ky_ten=me.user_code,
                chuc_danh=chuc_danh,
                ly_do=ly_do,
                muc=muc_pades,
                hien_thi=hien_thi_chu_ky,
            )
        )

        if not ket_qua.thanh_cong:
            return JSONResponse(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                content={
                    "thanh_cong": False,
                    "loi": ket_qua.loi,
                    "canh_bao": ket_qua.canh_bao,
                },
            )

        logger.info(
            "Cán bộ %s đã ký văn bản %s, mức %s",
            me.user_code, ket_qua.ma_van_ban, ket_qua.muc_dat_duoc,
        )

        return {
            "thanh_cong": True,
            "ma_van_ban": ket_qua.ma_van_ban,
            "muc_dat_duoc": ket_qua.muc_dat_duoc,
            "thoi_diem_ky": ket_qua.thoi_diem_ky,
            "ma_bam_goc": ket_qua.ma_bam_goc,
            "ma_bam_da_ky": ket_qua.ma_bam_da_ky,
            "canh_bao": ket_qua.canh_bao,
            "duong_dan_tai": f"/api/chu-ky-so/tai/{ket_qua.ma_van_ban}",
        }

    except LoiKySo as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)) from exc
    finally:
        shutil.rmtree(thu_muc_tam, ignore_errors=True)


# ---------------------------------------------------------------------------
# Tải văn bản đã ký
# ---------------------------------------------------------------------------


@router.get("/tai/{ma_van_ban}")
async def tai_van_ban_da_ky(ma_van_ban: str, me: Identity = Depends(get_current_user)):
    """Tải tệp đã ký.

    Mã văn bản được lọc chặt để không thể dùng làm đường dẫn đi ra ngoài thư mục
    lưu trữ — đây là lỗ hổng kinh điển khi ghép tên tệp từ dữ liệu người dùng.
    """
    if not ma_van_ban.isalnum() or len(ma_van_ban) > 32:
        raise HTTPException(status_code=400, detail="Mã văn bản không hợp lệ")

    thu_muc = signing_service.thu_muc_luu.resolve()
    ung_vien = list(thu_muc.glob(f"*_dhv_{ma_van_ban}.pdf"))
    if not ung_vien:
        raise HTTPException(status_code=404, detail="Không tìm thấy văn bản đã ký")

    tep = ung_vien[0].resolve()
    # Chốt chặn thứ hai: tệp phải thực sự nằm trong thư mục lưu trữ
    if thu_muc not in tep.parents:
        raise HTTPException(status_code=400, detail="Đường dẫn không hợp lệ")

    return FileResponse(tep, media_type="application/pdf", filename=tep.name)


# ---------------------------------------------------------------------------
# Kiểm tra chữ ký
# ---------------------------------------------------------------------------


@router.post("/kiem-tra")
async def kiem_tra_chu_ky(
    tep: UploadFile = File(..., description="Tệp PDF cần kiểm tra"),
    me: Identity = Depends(get_current_user),
):
    """Kiểm tra chữ ký số của một văn bản.

    Mở cho mọi người đã đăng nhập, kể cả sinh viên: người nhận giấy xác nhận cần
    tự kiểm tra được văn bản mình cầm là thật và chưa bị sửa.
    """
    if tep.content_type not in KIEU_TEP_CHO_PHEP:
        raise HTTPException(status_code=415, detail="Chỉ kiểm tra được tệp PDF")

    thu_muc_tam = Path(tempfile.mkdtemp(prefix="vinhuni_ktra_"))
    try:
        duong_dan = thu_muc_tam / "kiem_tra.pdf"
        kich_thuoc = 0
        with duong_dan.open("wb") as fh:
            while khoi := await tep.read(1024 * 1024):
                kich_thuoc += len(khoi)
                if kich_thuoc > DUNG_LUONG_TOI_DA:
                    raise HTTPException(status_code=413, detail="Tệp quá lớn")
                fh.write(khoi)

        ket_qua = signing_service.kiem_tra(duong_dan)

        if not ket_qua:
            return {
                "co_chu_ky": False,
                "ket_luan": "Văn bản này chưa được ký số.",
                "chu_ky": [],
            }

        tat_ca_hop_le = all(k.hop_le for k in ket_qua)
        return {
            "co_chu_ky": True,
            "tat_ca_hop_le": tat_ca_hop_le,
            "ket_luan": (
                "Văn bản hợp lệ, nội dung nguyên vẹn kể từ khi ký."
                if tat_ca_hop_le
                else "Chữ ký có vấn đề — xem chi tiết bên dưới."
            ),
            "chu_ky": [
                {
                    "hop_le": k.hop_le,
                    "nguyen_ven": k.nguyen_ven,
                    "chung_thu_tin_cay": k.chung_thu_tin_cay,
                    "nguoi_ky": k.nguoi_ky,
                    "to_chuc_cap": k.to_chuc_cap,
                    "thoi_diem_ky": k.thoi_diem_ky,
                    "co_dau_thoi_gian": k.co_dau_thoi_gian,
                    "muc_dat_duoc": k.muc_dat_duoc,
                    "canh_bao": k.canh_bao,
                    "loi": k.loi,
                }
                for k in ket_qua
            ],
        }

    except LoiKySo as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    finally:
        shutil.rmtree(thu_muc_tam, ignore_errors=True)


# ---------------------------------------------------------------------------
# Ký số từ xa
# ---------------------------------------------------------------------------


@router.post("/tu-xa/chuan-bi")
async def chuan_bi_ky_tu_xa(
    ma_van_ban: str = Form(...),
    me: Identity = Depends(require_staff),
):
    """Bước 1 của luồng ký số từ xa: tính giá trị băm để gửi sang nhà cung cấp
    dịch vụ chứng thực. Người ký sẽ xác nhận trên điện thoại của mình.

    Ưu điểm so với giữ chứng thư trên máy chủ: khoá riêng không bao giờ rời khỏi
    nhà cung cấp, máy chủ của trường bị xâm nhập cũng không ký giả được.
    """
    if not ma_van_ban.isalnum() or len(ma_van_ban) > 32:
        raise HTTPException(status_code=400, detail="Mã văn bản không hợp lệ")

    ung_vien = list(signing_service.thu_muc_luu.glob(f"*_dhv_{ma_van_ban}.pdf"))
    if not ung_vien:
        raise HTTPException(status_code=404, detail="Không tìm thấy văn bản")

    return signing_service.chuan_bi_ky_tu_xa(ung_vien[0])


# ---------------------------------------------------------------------------
# Nhật ký ký số (quản trị)
# ---------------------------------------------------------------------------


@router.get("/nhat-ky")
async def nhat_ky_ky_so(gioi_han: int = 100, me: Identity = Depends(require_admin)):
    """Danh sách văn bản đã ký gần đây — phục vụ đối soát và thanh tra."""
    gioi_han = max(1, min(gioi_han, 1000))
    tep_list = sorted(
        signing_service.thu_muc_luu.glob("*_dhv_*.pdf"),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )[:gioi_han]

    return {
        "tong_so": len(tep_list),
        "danh_sach": [
            {
                "ma_van_ban": p.stem.rsplit("_dhv_", 1)[-1],
                "ten_tep": p.name,
                "kich_thuoc": p.stat().st_size,
                "thoi_diem": p.stat().st_mtime,
            }
            for p in tep_list
        ],
    }
