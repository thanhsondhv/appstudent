"""
Phát hành và kiểm tra token truy cập.

SỬA NGÀY 18/08/2026 — hai lỗi bảo mật nghiêm trọng ở bản cũ:

  1. Khoá ký viết cứng trong mã: SECRET_KEY = "<chuỗi đoán được, đã gỡ bỏ>".
     Chuỗi này đoán được. Bất kỳ ai biết nó đều tự tạo được token hợp lệ cho
     tài khoản bất kỳ, kể cả quản trị viên. Nay đọc từ JWT_SECRET_KEY trong .env.

  2. Hạn dùng lưu ở trường tự đặt tên `expires` thay vì trường chuẩn `exp`.
     Thư viện jose chỉ kiểm tra `exp`, nên trên thực tế KHÔNG có token nào hết
     hạn — một token bị lộ sẽ dùng được mãi mãi. Nay dùng đúng `exp`, và
     `jwt.decode` tự từ chối token quá hạn.

Bổ sung thêm:
  - `get_current_user` — dependency lấy danh tính từ token, dùng cho MỌI
    endpoint cần biết người gọi là ai. Đây là cách duy nhất đúng để xác định
    người dùng; đọc mã người dùng từ nội dung máy khách gửi lên là lỗ hổng.
  - `require_staff` / `require_admin` — chặn theo vai trò ngay ở tầng đường dẫn.
"""

from __future__ import annotations

import time
import uuid
from dataclasses import dataclass

from fastapi import Depends, HTTPException, Security, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt

from core.settings import settings

SECRET_KEY = settings.security.jwt_secret
ALGORITHM = settings.security.jwt_algorithm

reusable_oauth2 = HTTPBearer()

# Các vai trò được coi là cán bộ, giảng viên trở lên.
# Giữ khớp với lib/core/auth/user_role.dart ở phía ứng dụng.
STAFF_ROLES = {"CANBO", "CB", "GIANGVIEN", "GV", "COVAN", "CV", "ADMIN", "AD"}
ADMIN_ROLES = {"ADMIN", "AD"}


# ---------------------------------------------------------------------------
# Danh tính người gọi
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Identity:
    """Danh tính đã được xác thực, suy ra TỪ TOKEN — không phải từ nội dung
    máy khách gửi lên."""

    user_code: str
    role: str
    method: str = "N/A"
    token_id: str = ""

    @property
    def is_staff(self) -> bool:
        return self.role.upper() in STAFF_ROLES

    @property
    def is_admin(self) -> bool:
        return self.role.upper() in ADMIN_ROLES


# ---------------------------------------------------------------------------
# Phát hành token
# ---------------------------------------------------------------------------


def create_access_token(user_id: str, role: str, method: str = "N/A") -> str:
    """Phát hành token truy cập ngắn hạn."""
    now = int(time.time())
    payload = {
        "sub": str(user_id),           # chuẩn JWT: chủ thể của token
        "user_id": str(user_id),       # giữ lại cho mã cũ đang đọc trường này
        "role": role,
        "method": method,
        "iat": now,
        # Trường CHUẨN — jose tự kiểm tra và từ chối khi quá hạn
        "exp": now + settings.security.jwt_ttl_minutes * 60,
        "jti": uuid.uuid4().hex,       # định danh token, dùng khi cần thu hồi
        "typ": "access",
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def create_refresh_token(user_id: str, role: str) -> str:
    """Token làm mới, hạn dài hơn. Chỉ dùng để xin token truy cập mới,
    không dùng để gọi API nghiệp vụ."""
    now = int(time.time())
    payload = {
        "sub": str(user_id),
        "role": role,
        "iat": now,
        "exp": now + settings.security.refresh_ttl_days * 86400,
        "jti": uuid.uuid4().hex,
        "typ": "refresh",
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


# ---------------------------------------------------------------------------
# Kiểm tra token
# ---------------------------------------------------------------------------


def _decode(token: str, *, expect_type: str = "access") -> dict:
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    except JWTError as exc:
        # jose gộp cả hết hạn lẫn sai chữ ký vào JWTError. Phân biệt để thông
        # điệp trả về đúng việc: hết hạn thì ứng dụng làm mới token, sai chữ ký
        # thì phải đăng nhập lại.
        detail = "Phiên đăng nhập đã hết hạn" if "expire" in str(exc).lower() \
            else "Token không hợp lệ"
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=detail) from exc

    if payload.get("typ", "access") != expect_type:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Loại token không đúng cho thao tác này",
        )
    return payload


async def verify_token(
    http_auth: HTTPAuthorizationCredentials = Security(reusable_oauth2),
) -> dict:
    """Giữ nguyên tên và kiểu trả về của bản cũ để mã đang gọi không phải sửa."""
    return _decode(http_auth.credentials)


async def get_current_user(
    http_auth: HTTPAuthorizationCredentials = Security(reusable_oauth2),
) -> Identity:
    """Dependency chuẩn để biết ai đang gọi.

    Dùng cho MỌI endpoint có đụng đến dữ liệu cá nhân:

        @router.post("/chat")
        async def chat(body: dict, me: Identity = Depends(get_current_user)):
            # Dùng me.user_code, KHÔNG dùng body["studentId"]
    """
    payload = _decode(http_auth.credentials)
    user_code = str(payload.get("sub") or payload.get("user_id") or "").strip()
    if not user_code:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token thiếu thông tin người dùng",
        )
    return Identity(
        user_code=user_code.upper(),
        role=str(payload.get("role") or "SinhVien").upper(),
        method=str(payload.get("method") or "N/A"),
        token_id=str(payload.get("jti") or ""),
    )


async def require_staff(me: Identity = Depends(get_current_user)) -> Identity:
    """Chỉ cho cán bộ, giảng viên, cố vấn, quản trị viên đi qua."""
    if not me.is_staff:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Chức năng này chỉ dành cho cán bộ, giảng viên",
        )
    return me


async def require_admin(me: Identity = Depends(get_current_user)) -> Identity:
    """Chỉ cho quản trị viên đi qua."""
    if not me.is_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Chức năng này chỉ dành cho quản trị hệ thống",
        )
    return me


def refresh_access_token(refresh_token: str) -> str:
    """Đổi token làm mới lấy token truy cập mới."""
    payload = _decode(refresh_token, expect_type="refresh")
    return create_access_token(
        user_id=str(payload.get("sub")),
        role=str(payload.get("role") or "SinhVien"),
        method="refresh",
    )
