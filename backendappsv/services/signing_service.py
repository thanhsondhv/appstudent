"""
Dịch vụ ký số văn bản điện tử — VinhUni.

Dùng cho hồ sơ dịch vụ công và văn bản hành chính của trường: giấy xác nhận sinh
viên, bảng điểm, quyết định, thông báo, đơn từ đã duyệt.

CHUẨN ÁP DỤNG
-------------
Ký theo PAdES (PDF Advanced Electronic Signature) — chuẩn chữ ký số cho tệp PDF
được công nhận rộng rãi, và là dạng mà các phần mềm đọc PDF phổ biến kiểm tra được.

Bốn mức, chọn mức nào tuỳ giá trị pháp lý cần đạt:

  B-B    Ký cơ bản. Chữ ký mất hiệu lực khi chứng thư hết hạn.
  B-T    Ký + dấu thời gian từ tổ chức cấp dấu thời gian (TSA).
         Chứng minh được văn bản đã tồn tại tại thời điểm ký.
  B-LT   Ký + dấu thời gian + nhúng sẵn thông tin kiểm tra thu hồi chứng thư.
         Kiểm tra được cả khi máy chủ của tổ chức chứng thực ngừng hoạt động.
  B-LTA  Như B-LT, thêm dấu thời gian lưu trữ, gia hạn được nhiều thập kỷ.

→ Với hồ sơ dịch vụ công, tối thiểu phải đạt B-LT. Đây là lý do biến
  SIGN_TSA_URL trong .env là bắt buộc chứ không tuỳ chọn: thiếu dấu thời gian
  thì sau khi chứng thư hết hạn, không ai chứng minh được văn bản ký lúc nào.

BA PHƯƠNG THỨC KÝ
-----------------
  (A) PKCS#11 — thiết bị ký số USB hoặc HSM cắm tại máy chủ.
      Khoá riêng không bao giờ rời khỏi thiết bị. Dùng cho con dấu tổ chức.

  (B) Tệp PFX — CHỈ dùng khi thử nghiệm. Khoá riêng nằm trên đĩa, ai đọc được
      tệp là ký được thay. Không dùng cho văn bản có giá trị pháp lý.

  (C) Ký số từ xa — khoá riêng do tổ chức cung cấp dịch vụ chứng thực chữ ký số
      giữ (VNPT-CA, Viettel-CA, MISA eSign, FPT-CA...). Máy chủ gửi giá trị băm,
      người ký xác nhận trên điện thoại, nhà cung cấp trả về chữ ký.
      Đây là phương thức phù hợp nhất cho cán bộ ký trên ứng dụng di động.

LƯU Ý PHÁP LÝ
-------------
Giá trị pháp lý của chữ ký số ở Việt Nam do Luật Giao dịch điện tử và các nghị
định hướng dẫn quy định, và các văn bản này có thay đổi theo thời gian. Trước
khi đưa vào sử dụng cho hồ sơ dịch vụ công, cần:
  1. Xác nhận với đơn vị pháp chế của trường về quy định đang hiệu lực.
  2. Dùng chứng thư số do tổ chức cung cấp dịch vụ chứng thực chữ ký số công
     cộng đã được cấp phép phát hành — không dùng chứng thư tự tạo.
  3. Với văn bản của trường với tư cách tổ chức, dùng chứng thư của tổ chức
     (con dấu số), không dùng chứng thư cá nhân của người thao tác.

Module này lo phần kỹ thuật. Phần tuân thủ pháp lý là việc của con người.

Thêm ngày 18/08/2026.
"""

from __future__ import annotations

import hashlib
import logging
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
from typing import Any, BinaryIO

from core.settings import settings

logger = logging.getLogger("vinhuni.signing")


# ---------------------------------------------------------------------------
# Nạp thư viện có kiểm soát
# ---------------------------------------------------------------------------
# pyHanko kéo theo khá nhiều gói phụ. Nếu chưa cài, phần còn lại của backend
# vẫn phải chạy bình thường — chỉ riêng chức năng ký số báo lỗi rõ ràng.

PYHANKO_SAN_SANG = False
_LOI_NAP = ""

try:
    from pyhanko.pdf_utils.incremental_writer import IncrementalPdfFileWriter
    from pyhanko.sign import signers, timestamps
    from pyhanko.sign.fields import SigFieldSpec, append_signature_field
    from pyhanko.sign.validation import validate_pdf_signature
    from pyhanko_certvalidator import ValidationContext

    PYHANKO_SAN_SANG = True
except ImportError as exc:  # pragma: no cover - phụ thuộc môi trường
    _LOI_NAP = str(exc)
    logger.warning(
        "Chưa cài pyHanko nên chức năng ký số không dùng được: %s. "
        "Cài bằng: pip install 'pyHanko[pkcs11,image-support]'",
        exc,
    )


class LoiKySo(Exception):
    """Lỗi trong quá trình ký hoặc kiểm tra chữ ký."""


def _bao_dam_san_sang() -> None:
    if not PYHANKO_SAN_SANG:
        raise LoiKySo(
            "Chưa cài thư viện ký số pyHanko. "
            "Chạy: pip install 'pyHanko[pkcs11,image-support]'"
            + (f" (lỗi gốc: {_LOI_NAP})" if _LOI_NAP else "")
        )


# ---------------------------------------------------------------------------
# Kiểu dữ liệu
# ---------------------------------------------------------------------------


class PhuongThucKy(str, Enum):
    THIET_BI = "pkcs11"      # USB token / HSM
    TEP_PFX = "pfx"          # chỉ thử nghiệm
    TU_XA = "remote"         # nhà cung cấp dịch vụ chứng thực


class MucPAdES(str, Enum):
    B = "PAdES-B-B"
    T = "PAdES-B-T"
    LT = "PAdES-B-LT"
    LTA = "PAdES-B-LTA"


@dataclass
class YeuCauKy:
    """Một yêu cầu ký số."""

    duong_dan_pdf: Path
    nguoi_ky_ma: str                    # mã cán bộ, lấy từ token
    nguoi_ky_ten: str
    chuc_danh: str = ""
    ly_do: str = "Phê duyệt văn bản"
    dia_diem: str = "Trường Đại học Vinh"
    lien_he: str = ""
    muc: MucPAdES = MucPAdES.LT
    # Vị trí ô chữ ký hiển thị trên trang, đơn vị point (72 point = 1 inch)
    trang: int = -1                     # -1 = trang cuối
    o_chu_ky: tuple[int, int, int, int] = (380, 60, 560, 150)
    hien_thi: bool = True


@dataclass
class KetQuaKy:
    thanh_cong: bool
    duong_dan_da_ky: Path | None = None
    ma_van_ban: str = ""
    ma_bam_goc: str = ""                # SHA-256 của tệp trước khi ký
    ma_bam_da_ky: str = ""              # SHA-256 của tệp sau khi ký
    thoi_diem_ky: str = ""
    muc_dat_duoc: str = ""
    canh_bao: list[str] = field(default_factory=list)
    loi: str = ""


@dataclass
class KetQuaKiemTra:
    hop_le: bool
    nguyen_ven: bool                    # nội dung có bị sửa sau khi ký không
    chung_thu_tin_cay: bool             # chứng thư có thuộc chuỗi tin cậy không
    nguoi_ky: str = ""
    to_chuc_cap: str = ""
    thoi_diem_ky: str = ""
    co_dau_thoi_gian: bool = False
    muc_dat_duoc: str = ""
    canh_bao: list[str] = field(default_factory=list)
    loi: str = ""


# ---------------------------------------------------------------------------
# Dịch vụ
# ---------------------------------------------------------------------------


class SigningService:
    def __init__(self) -> None:
        self.thu_muc_luu = Path(settings.signing.storage_dir)
        self.thu_muc_luu.mkdir(parents=True, exist_ok=True)

    # -- Thông tin cấu hình -------------------------------------------------

    def trang_thai(self) -> dict[str, Any]:
        """Báo cáo tình trạng sẵn sàng — dùng cho trang giám sát của quản trị viên."""
        s = settings.signing
        return {
            "thu_vien_san_sang": PYHANKO_SAN_SANG,
            "phuong_thuc": self._phuong_thuc().value if s.is_configured else None,
            "da_cau_hinh": s.is_configured,
            "co_dau_thoi_gian": bool(s.tsa_url),
            "muc_toi_da": (
                MucPAdES.LT.value if s.tsa_url else MucPAdES.B.value
            ),
            "canh_bao": self._canh_bao_cau_hinh(),
        }

    def _canh_bao_cau_hinh(self) -> list[str]:
        s = settings.signing
        cb: list[str] = []
        if not s.is_configured:
            cb.append("Chưa cấu hình phương thức ký nào trong .env")
        if not s.tsa_url:
            cb.append(
                "Chưa có dịch vụ cấp dấu thời gian (SIGN_TSA_URL). "
                "Chữ ký sẽ mất hiệu lực khi chứng thư hết hạn — "
                "không đủ điều kiện cho hồ sơ dịch vụ công."
            )
        if s.pfx_path and not s.pkcs11_lib:
            cb.append(
                "Đang dùng chứng thư dạng tệp .pfx. Khoá riêng nằm trên đĩa máy chủ, "
                "chỉ phù hợp môi trường thử nghiệm."
            )
        if settings.is_production and s.pfx_path:
            cb.append(
                "CẢNH BÁO: môi trường production nhưng vẫn dùng tệp .pfx. "
                "Chuyển sang thiết bị ký số hoặc ký số từ xa."
            )
        return cb

    def _phuong_thuc(self) -> PhuongThucKy:
        s = settings.signing
        if s.pkcs11_lib:
            return PhuongThucKy.THIET_BI
        if s.remote_signing_url:
            return PhuongThucKy.TU_XA
        return PhuongThucKy.TEP_PFX

    # -- Ký ------------------------------------------------------------------

    def ky_van_ban(self, yc: YeuCauKy) -> KetQuaKy:
        """Ký một tệp PDF và trả về đường dẫn tệp đã ký."""
        _bao_dam_san_sang()

        if not yc.duong_dan_pdf.exists():
            return KetQuaKy(thanh_cong=False, loi="Không tìm thấy tệp cần ký")

        ma_bam_goc = self._bam_tep(yc.duong_dan_pdf)
        ma_van_ban = uuid.uuid4().hex[:16].upper()
        canh_bao = self._canh_bao_cau_hinh()

        try:
            nguoi_ky = self._tao_nguoi_ky()
            may_dau_thoi_gian = self._tao_may_dau_thoi_gian()

            if may_dau_thoi_gian is None and yc.muc != MucPAdES.B:
                canh_bao.append(
                    f"Không có dịch vụ dấu thời gian, chỉ đạt được {MucPAdES.B.value} "
                    f"thay vì {yc.muc.value}"
                )

            duong_dan_ra = self.thu_muc_luu / f"{yc.duong_dan_pdf.stem}_dhv_{ma_van_ban}.pdf"

            with yc.duong_dan_pdf.open("rb") as f_in:
                writer = IncrementalPdfFileWriter(f_in)

                ten_o = f"ChuKy_{ma_van_ban}"
                if yc.hien_thi:
                    append_signature_field(
                        writer,
                        SigFieldSpec(sig_field_name=ten_o, on_page=yc.trang, box=yc.o_chu_ky),
                    )

                sig_meta = signers.PdfSignatureMetadata(
                    field_name=ten_o if yc.hien_thi else None,
                    reason=yc.ly_do,
                    location=yc.dia_diem,
                    contact_info=yc.lien_he or f"{yc.nguoi_ky_ma}@vinhuni.edu.vn",
                    name=yc.nguoi_ky_ten,
                    # Nhúng thông tin kiểm tra thu hồi chứng thư — điều kiện của mức LT
                    embed_validation_info=yc.muc in (MucPAdES.LT, MucPAdES.LTA),
                    use_pades_lta=yc.muc == MucPAdES.LTA,
                    validation_context=self._ngu_canh_kiem_tra(),
                    subfilter=signers.SigSeedSubFilter.PADES,
                )

                pdf_signer = signers.PdfSigner(
                    sig_meta,
                    signer=nguoi_ky,
                    timestamper=may_dau_thoi_gian,
                    stamp_style=self._kieu_dau(yc) if yc.hien_thi else None,
                )

                with duong_dan_ra.open("wb") as f_out:
                    pdf_signer.sign_pdf(writer, output=f_out)

            logger.info(
                "Đã ký văn bản %s cho %s (%s)", ma_van_ban, yc.nguoi_ky_ma, yc.muc.value
            )

            return KetQuaKy(
                thanh_cong=True,
                duong_dan_da_ky=duong_dan_ra,
                ma_van_ban=ma_van_ban,
                ma_bam_goc=ma_bam_goc,
                ma_bam_da_ky=self._bam_tep(duong_dan_ra),
                thoi_diem_ky=datetime.now(timezone.utc).isoformat(),
                muc_dat_duoc=(
                    yc.muc.value if may_dau_thoi_gian else MucPAdES.B.value
                ),
                canh_bao=canh_bao,
            )

        except Exception as exc:  # noqa: BLE001 - báo lại nguyên nhân cho người dùng
            logger.exception("Ký văn bản thất bại")
            return KetQuaKy(
                thanh_cong=False,
                ma_bam_goc=ma_bam_goc,
                loi=f"Không ký được: {exc}",
                canh_bao=canh_bao,
            )

    # -- Kiểm tra ------------------------------------------------------------

    def kiem_tra(self, duong_dan_pdf: Path | BinaryIO) -> list[KetQuaKiemTra]:
        """Kiểm tra mọi chữ ký có trong một tệp PDF.

        Trả về một kết quả cho mỗi chữ ký. Danh sách rỗng nghĩa là tệp chưa ký.
        """
        _bao_dam_san_sang()

        from pyhanko.pdf_utils.reader import PdfFileReader

        ket_qua: list[KetQuaKiemTra] = []
        try:
            fh = (
                duong_dan_pdf.open("rb")
                if isinstance(duong_dan_pdf, Path)
                else duong_dan_pdf
            )
            try:
                reader = PdfFileReader(fh)
                ngu_canh = self._ngu_canh_kiem_tra()

                for sig in reader.embedded_signatures:
                    trang_thai = validate_pdf_signature(sig, ngu_canh)
                    cb: list[str] = []

                    if not trang_thai.intact:
                        cb.append("Nội dung văn bản đã bị sửa sau khi ký")
                    if not trang_thai.trusted:
                        cb.append(
                            "Chứng thư không thuộc chuỗi tin cậy đã cấu hình — "
                            "cần bổ sung chứng thư gốc của tổ chức chứng thực"
                        )
                    if not trang_thai.timestamp_validity:
                        cb.append("Chữ ký không có dấu thời gian hợp lệ")

                    ket_qua.append(
                        KetQuaKiemTra(
                            hop_le=bool(trang_thai.bottom_line),
                            nguyen_ven=bool(trang_thai.intact),
                            chung_thu_tin_cay=bool(trang_thai.trusted),
                            nguoi_ky=str(getattr(trang_thai, "signer_reported_dt", "") or sig.signer_cert.subject.human_friendly),
                            to_chuc_cap=sig.signer_cert.issuer.human_friendly,
                            thoi_diem_ky=str(sig.self_reported_timestamp or ""),
                            co_dau_thoi_gian=trang_thai.timestamp_validity is not None,
                            muc_dat_duoc=(
                                MucPAdES.LT.value
                                if trang_thai.timestamp_validity
                                else MucPAdES.B.value
                            ),
                            canh_bao=cb,
                        )
                    )
            finally:
                if isinstance(duong_dan_pdf, Path):
                    fh.close()
        except Exception as exc:  # noqa: BLE001
            logger.exception("Kiểm tra chữ ký thất bại")
            return [
                KetQuaKiemTra(
                    hop_le=False, nguyen_ven=False, chung_thu_tin_cay=False,
                    loi=f"Không đọc được chữ ký: {exc}",
                )
            ]

        return ket_qua

    # -- Ký số từ xa (luồng băm rồi ký) --------------------------------------

    def chuan_bi_ky_tu_xa(self, duong_dan_pdf: Path) -> dict[str, str]:
        """Chuẩn bị dữ liệu cho luồng ký số từ xa.

        Luồng đầy đủ:
          1. Máy chủ tính giá trị băm của phần cần ký  ← hàm này
          2. Gửi giá trị băm sang nhà cung cấp dịch vụ chứng thực
          3. Người ký nhận thông báo trên điện thoại và bấm xác nhận
          4. Nhà cung cấp trả về chữ ký số của giá trị băm
          5. Máy chủ nhúng chữ ký vào PDF        ← hoan_tat_ky_tu_xa()

        Khoá riêng không bao giờ đi qua máy chủ của trường. Đây là điểm mạnh
        chính của phương thức này so với việc giữ tệp .pfx trên đĩa.
        """
        ma_giao_dich = uuid.uuid4().hex
        return {
            "ma_giao_dich": ma_giao_dich,
            "ma_bam": self._bam_tep(duong_dan_pdf),
            "thuat_toan_bam": "SHA-256",
            "ghi_chu": (
                "Gửi ma_bam sang API của nhà cung cấp dịch vụ chứng thực. "
                "Chi tiết giao thức khác nhau giữa VNPT-CA, Viettel-CA, MISA — "
                "xem tài liệu tích hợp của nhà cung cấp mà trường ký hợp đồng."
            ),
        }

    # -- Hàm phụ trợ ---------------------------------------------------------

    @staticmethod
    def _bam_tep(duong_dan: Path) -> str:
        h = hashlib.sha256()
        with duong_dan.open("rb") as fh:
            for khoi in iter(lambda: fh.read(65536), b""):
                h.update(khoi)
        return h.hexdigest()

    def _tao_nguoi_ky(self):
        """Tạo đối tượng ký theo phương thức đã cấu hình."""
        s = settings.signing
        pt = self._phuong_thuc()

        if pt == PhuongThucKy.THIET_BI:
            from pyhanko.sign import pkcs11 as ph_pkcs11

            return ph_pkcs11.PKCS11Signer(
                ph_pkcs11.open_pkcs11_session(
                    s.pkcs11_lib,
                    token_label=s.pkcs11_token_label or None,
                    user_pin=s.pkcs11_pin or None,
                ),
                cert_label=None,
            )

        if pt == PhuongThucKy.TEP_PFX:
            if not s.pfx_path:
                raise LoiKySo(
                    "Chưa cấu hình phương thức ký. Đặt SIGN_PKCS11_LIB (thiết bị ký số) "
                    "hoặc SIGN_PFX_PATH (chỉ thử nghiệm) trong .env"
                )
            if settings.is_production:
                logger.error(
                    "Đang ký bằng tệp .pfx trong môi trường production — "
                    "khoá riêng nằm trên đĩa, rủi ro cao"
                )
            return signers.SimpleSigner.load_pkcs12(
                pfx_file=s.pfx_path,
                passphrase=s.pfx_password.encode() if s.pfx_password else None,
            )

        raise LoiKySo(
            "Ký số từ xa cần triển khai theo giao thức của nhà cung cấp cụ thể. "
            "Dùng chuan_bi_ky_tu_xa() làm điểm bắt đầu."
        )

    def _tao_may_dau_thoi_gian(self):
        s = settings.signing
        if not s.tsa_url:
            return None
        kwargs: dict[str, Any] = {"url": s.tsa_url}
        if s.tsa_username:
            kwargs["auth"] = (s.tsa_username, s.tsa_password)
        return timestamps.HTTPTimeStamper(**kwargs)

    def _ngu_canh_kiem_tra(self):
        """Chuỗi chứng thư tin cậy.

        Mặc định dùng kho chứng thư của hệ điều hành. Với chứng thư do tổ chức
        chứng thực trong nước cấp, cần nạp thêm chứng thư gốc của tổ chức đó —
        nếu không, chữ ký hợp lệ vẫn bị báo là không tin cậy.
        """
        return ValidationContext(allow_fetching=True)


# Thể hiện dùng chung
signing_service = SigningService()
