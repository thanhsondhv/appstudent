"""
API cho cổng quản trị trên máy tính.

Các endpoint ở đây phục vụ những việc mà màn hình điện thoại làm không tiện:
theo dõi tiến trình đồng bộ, xem nhật ký trợ lý AI, kiểm tra hệ thống ký số,
đối soát số liệu.

Mọi endpoint đều yêu cầu vai trò quản trị — kiểm tra ở tầng đường dẫn bằng
`Depends(require_admin)`. Việc cổng quản trị có ẩn menu hay không không phải là
biện pháp bảo mật.

Thêm ngày 18/08/2026 — Pha 6 lộ trình nâng cấp.
"""

from __future__ import annotations

import json
import logging
import os
import time
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import pyodbc
from fastapi import APIRouter, Depends, HTTPException, Query

from auth.jwt_handler import Identity, require_admin, require_staff
from core.settings import settings
from services.signing_service import signing_service

logger = logging.getLogger("vinhuni.admin_portal")

router = APIRouter(prefix="/api/admin", tags=["Cổng quản trị"])

_BASE = Path(__file__).resolve().parent.parent


# ---------------------------------------------------------------------------
# Tổng quan hệ thống
# ---------------------------------------------------------------------------


@router.get("/tong-quan")
async def tong_quan(me: Identity = Depends(require_admin)) -> dict[str, Any]:
    """Bảng tổng quan: mọi thứ quản trị viên cần liếc qua mỗi sáng.

    Trước đây muốn biết những con số này phải đăng nhập máy chủ đọc tệp nhật ký.
    """
    return {
        "moi_truong": settings.env,
        "csdl": _trang_thai_csdl(),
        "ky_so": signing_service.trang_thai(),
        "tro_ly_ai": _thong_ke_ai(),
        "dong_bo": _trang_thai_dong_bo(),
        "cau_hinh": _kiem_tra_cau_hinh(),
        "thoi_diem": datetime.now(timezone.utc).isoformat(),
    }


def _trang_thai_csdl() -> dict[str, Any]:
    """Thử kết nối cơ sở dữ liệu và đo thời gian phản hồi."""
    bat_dau = time.perf_counter()
    try:
        with pyodbc.connect(settings.db.local_conn_str, timeout=5) as conn:
            conn.cursor().execute("SELECT 1").fetchone()
        return {
            "ket_noi_duoc": True,
            "may_chu": settings.db.safe_repr,
            "thoi_gian_ms": round((time.perf_counter() - bat_dau) * 1000, 1),
        }
    except pyodbc.Error as exc:
        logger.error("Không kết nối được CSDL: %s", exc)
        return {
            "ket_noi_duoc": False,
            "may_chu": settings.db.safe_repr,
            "loi": str(exc)[:200],
        }


def _thong_ke_ai() -> dict[str, Any]:
    """Đọc nhật ký kiểm toán trợ lý AI, tổng hợp 24 giờ gần nhất.

    Con số đáng chú ý nhất là số lượt bị chặn vì chèn lệnh: tăng đột biến nghĩa
    là có người đang thử tấn công một cách có hệ thống.
    """
    duong_dan = _BASE / "logs" / "ai_audit.jsonl"
    if not duong_dan.exists():
        return {"co_nhat_ky": False}

    moc = datetime.now(timezone.utc) - timedelta(hours=24)
    su_kien: Counter[str] = Counter()
    nguoi_dung: set[str] = set()
    tong_thoi_gian = 0
    dem_tra_loi = 0

    try:
        # Chỉ đọc phần cuối tệp — nhật ký có thể rất dài
        with duong_dan.open("rb") as fh:
            fh.seek(0, os.SEEK_END)
            kich_thuoc = fh.tell()
            fh.seek(max(0, kich_thuoc - 2_000_000))
            noi_dung = fh.read().decode("utf-8", errors="ignore")

        for dong in noi_dung.splitlines()[1:]:  # bỏ dòng đầu có thể bị cắt dở
            try:
                ban_ghi = json.loads(dong)
                if datetime.fromisoformat(ban_ghi["thoi_diem"]) < moc:
                    continue
            except (json.JSONDecodeError, KeyError, ValueError):
                continue

            su_kien[ban_ghi.get("su_kien", "?")] += 1
            nguoi_dung.add(ban_ghi.get("nguoi_dung_hash", ""))
            if "thoi_gian_ms" in ban_ghi:
                tong_thoi_gian += ban_ghi["thoi_gian_ms"]
                dem_tra_loi += 1
    except OSError as exc:
        return {"co_nhat_ky": False, "loi": str(exc)}

    return {
        "co_nhat_ky": True,
        "trong_24_gio": {
            "tong_luot": sum(su_kien.values()),
            "so_nguoi_dung": len(nguoi_dung),
            "tra_loi_thanh_cong": su_kien.get("TRA_LOI", 0),
            "chan_chen_lenh": su_kien.get("CHAN_CHEN_LENH", 0),
            "chan_tan_suat": su_kien.get("CHAN_TAN_SUAT", 0),
            "thoi_gian_tb_ms": round(tong_thoi_gian / dem_tra_loi) if dem_tra_loi else 0,
        },
    }


def _trang_thai_dong_bo() -> dict[str, Any]:
    """Thời điểm chạy gần nhất của các tiến trình đồng bộ.

    Suy ra từ thời gian sửa đổi tệp nhật ký. Cách này thô nhưng dùng được ngay
    mà không cần sửa các worker. Khi Pha 2 hợp nhất các worker thì thay bằng
    bảng trạng thái trong cơ sở dữ liệu.
    """
    ung_vien = {
        "dong_bo_du_lieu": _BASE / "logs" / "sync_worker.log",
        "gui_thong_bao": _BASE / "logs" / "notification_worker.log",
        "dong_bo_lms": _BASE / "logs" / "lms_sync.log",
    }
    ket_qua = {}
    for ten, duong_dan in ung_vien.items():
        if duong_dan.exists():
            sua_luc = datetime.fromtimestamp(duong_dan.stat().st_mtime, timezone.utc)
            tre_phut = (datetime.now(timezone.utc) - sua_luc).total_seconds() / 60
            ket_qua[ten] = {
                "chay_gan_nhat": sua_luc.isoformat(),
                "tre_phut": round(tre_phut, 1),
                # Đồng bộ chạy mỗi 30 phút; quá 90 phút coi như có sự cố
                "binh_thuong": tre_phut < 90,
            }
        else:
            ket_qua[ten] = {"chay_gan_nhat": None, "binh_thuong": False,
                            "ghi_chu": "Chưa có tệp nhật ký"}
    return ket_qua


def _kiem_tra_cau_hinh() -> list[dict[str, str]]:
    """Các vấn đề cấu hình cần người xử lý. Hiện ngay đầu trang thay vì chờ
    đến khi có sự cố mới phát hiện."""
    van_de: list[dict[str, str]] = []

    if not settings.is_production:
        van_de.append({
            "muc": "thong_tin",
            "noi_dung": f"Đang chạy ở môi trường '{settings.env}', không phải production",
        })
    if settings.ai.log_prompts:
        van_de.append({
            "muc": "canh_bao",
            "noi_dung": "AI_LOG_PROMPTS đang bật — nhật ký lưu nguyên văn câu hỏi "
                        "của người dùng. Chỉ dùng khi gỡ lỗi, nhớ tắt sau đó.",
        })
    if not settings.signing.tsa_url and settings.signing.is_configured:
        van_de.append({
            "muc": "canh_bao",
            "noi_dung": "Ký số chưa có dịch vụ cấp dấu thời gian — "
                        "chữ ký không đủ điều kiện cho hồ sơ dịch vụ công",
        })
    if settings.is_production and settings.signing.pfx_path:
        van_de.append({
            "muc": "nghiem_trong",
            "noi_dung": "Môi trường production nhưng ký bằng tệp .pfx trên đĩa. "
                        "Chuyển sang thiết bị ký số hoặc ký số từ xa.",
        })
    if "*" in settings.security.allowed_origins:
        van_de.append({
            "muc": "nghiem_trong",
            "noi_dung": "CORS đang cho phép mọi nguồn. Giới hạn lại danh sách tên miền.",
        })
    return van_de


# ---------------------------------------------------------------------------
# Nhật ký trợ lý AI
# ---------------------------------------------------------------------------


@router.get("/nhat-ky-ai")
async def nhat_ky_ai(
    gioi_han: int = Query(100, ge=1, le=1000),
    chi_su_kien: str | None = Query(None, description="Lọc theo loại sự kiện"),
    me: Identity = Depends(require_admin),
) -> dict[str, Any]:
    """Nhật ký kiểm toán trợ lý AI.

    Câu hỏi đã được che dữ liệu cá nhân và mã người dùng đã băm — đủ để điều tra
    sự cố mà không biến nhật ký thành kho dữ liệu cá nhân.
    """
    duong_dan = _BASE / "logs" / "ai_audit.jsonl"
    if not duong_dan.exists():
        return {"tong_so": 0, "danh_sach": []}

    ban_ghi: list[dict[str, Any]] = []
    try:
        with duong_dan.open("rb") as fh:
            fh.seek(0, os.SEEK_END)
            fh.seek(max(0, fh.tell() - 2_000_000))
            for dong in fh.read().decode("utf-8", errors="ignore").splitlines()[1:]:
                try:
                    r = json.loads(dong)
                except json.JSONDecodeError:
                    continue
                if chi_su_kien and r.get("su_kien") != chi_su_kien:
                    continue
                ban_ghi.append(r)
    except OSError as exc:
        raise HTTPException(status_code=500, detail=f"Không đọc được nhật ký: {exc}") from exc

    ban_ghi.reverse()
    return {"tong_so": len(ban_ghi), "danh_sach": ban_ghi[:gioi_han]}


# ---------------------------------------------------------------------------
# Thống kê nghiệp vụ
# ---------------------------------------------------------------------------


@router.get("/thong-ke")
def thong_ke(me: Identity = Depends(require_staff)) -> dict[str, Any]:
    """Vài con số nghiệp vụ cho trang chủ cổng quản trị.

    Mở cho cán bộ chứ không chỉ quản trị viên — trưởng khoa cũng cần nhìn số
    liệu mà không phải xin quyền admin.
    """
    truy_van = {
        "thong_bao_hom_nay": (
            "SELECT COUNT(*) FROM tbl_Notification_Queue "
            "WHERE CAST(CreatedAt AS DATE) = CAST(GETDATE() AS DATE)"
        ),
        "thong_bao_cho_gui": "SELECT COUNT(*) FROM tbl_Notification_Queue WHERE IsSent = 0",
        # Sửa 18/08/2026 sau khi đối chiếu CSDL thật: tbl_Users KHÔNG có cột
        # LastLogin. Hai chỉ số dưới đây đo được bằng dữ liệu đang có:
        #   • phiên đang mở  — SessionToken còn giá trị
        #   • đã cài ứng dụng — có FCMToken để nhận thông báo đẩy
        "phien_dang_mo": (
            "SELECT COUNT(DISTINCT UserCode) FROM tbl_Users "
            "WHERE SessionToken IS NOT NULL AND LEN(SessionToken) > 0"
        ),
        "da_cai_ung_dung": (
            "SELECT COUNT(DISTINCT UserCode) FROM tbl_Users "
            "WHERE FCMToken IS NOT NULL AND LEN(FCMToken) > 0"
        ),
        "tai_khoan_bi_khoa": (
            "SELECT COUNT(*) FROM tbl_Users WHERE LockoutUntil > GETDATE()"
        ),
    }

    ket_qua: dict[str, Any] = {}
    try:
        with pyodbc.connect(settings.db.local_conn_str, timeout=8) as conn:
            cursor = conn.cursor()
            for ten, sql in truy_van.items():
                try:
                    hang = cursor.execute(sql).fetchone()
                    ket_qua[ten] = hang[0] if hang else 0
                except pyodbc.Error as exc:
                    # Bảng có thể chưa tồn tại trên môi trường mới — không làm
                    # hỏng cả trang chỉ vì một con số
                    logger.warning("Truy vấn '%s' lỗi: %s", ten, exc)
                    ket_qua[ten] = None
    except pyodbc.Error as exc:
        raise HTTPException(
            status_code=503, detail=f"Không kết nối được cơ sở dữ liệu: {exc}"
        ) from exc

    return ket_qua


# ---------------------------------------------------------------------------
# Kiểm tra sức khoẻ (không cần đăng nhập)
# ---------------------------------------------------------------------------


health_router = APIRouter(tags=["Hệ thống"])


@health_router.get("/health")
async def kiem_tra_suc_khoe() -> dict[str, Any]:
    """Endpoint cho công cụ giám sát bên ngoài gọi định kỳ.

    Không yêu cầu đăng nhập, và cố tình không tiết lộ chi tiết hệ thống —
    chỉ trả lời sống hay chết.
    """
    try:
        with pyodbc.connect(settings.db.local_conn_str, timeout=3) as conn:
            conn.cursor().execute("SELECT 1").fetchone()
        return {"trang_thai": "ok"}
    except pyodbc.Error:
        raise HTTPException(status_code=503, detail={"trang_thai": "loi_csdl"})
