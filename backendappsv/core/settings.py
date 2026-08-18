"""
Cấu hình tập trung cho toàn bộ backend VinhUni.

Đây là NƠI DUY NHẤT được phép đọc biến môi trường. Mọi module khác import từ đây:

    from core.settings import settings
    conn = pyodbc.connect(settings.db.local_conn_str)

Nguyên tắc:
  1. Không viết cứng khoá bí mật trong mã nguồn. Tất cả đọc từ tệp .env.
  2. Ứng dụng từ chối khởi động nếu thiếu khoá bắt buộc — thà chết sớm lúc
     triển khai còn hơn chạy được rồi lộ dữ liệu.
  3. Tệp .env không bao giờ được commit (đã chặn trong .gitignore).
     Mẫu tham khảo nằm ở .env.example.

Thêm ngày 18/08/2026 — Pha 0, thay thế cấu hình rải rác ở Main.py, config.py,
notification_worker.py, master_worker.py, appsettings.json và ~20 tệp khác.
"""

from __future__ import annotations

import os
import sys
from dataclasses import dataclass, field
from pathlib import Path

# ---------------------------------------------------------------------------
# Nạp tệp .env (không phụ thuộc thư viện ngoài để tránh vỡ khi thiếu gói)
# ---------------------------------------------------------------------------

BASE_DIR = Path(__file__).resolve().parent.parent


def _load_dotenv(path: Path) -> None:
    """Đọc tệp .env đơn giản: mỗi dòng KEY=VALUE, bỏ qua dòng trống và chú thích.

    Biến môi trường thật của hệ điều hành luôn thắng giá trị trong .env,
    để môi trường triển khai (systemd, Docker, IIS) ghi đè được mà không sửa tệp.
    """
    if not path.exists():
        return
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        os.environ.setdefault(key, value)


_load_dotenv(BASE_DIR / ".env")


# ---------------------------------------------------------------------------
# Tiện ích đọc biến
# ---------------------------------------------------------------------------

_MISSING: list[str] = []


def _req(key: str) -> str:
    """Khoá bắt buộc — ghi nhận nếu thiếu, báo lỗi gộp một lần ở cuối."""
    value = os.getenv(key, "").strip()
    if not value:
        _MISSING.append(key)
    return value


def _opt(key: str, default: str = "") -> str:
    return os.getenv(key, default).strip()


def _int(key: str, default: int) -> int:
    try:
        return int(os.getenv(key, "").strip() or default)
    except ValueError:
        return default


def _bool(key: str, default: bool = False) -> bool:
    return os.getenv(key, str(default)).strip().lower() in ("1", "true", "yes", "on")


def _may_chu(key: str, default: str = "") -> str:
    r"""Tên máy chủ SQL, đã chuẩn hoá dấu gạch ngược.

    Tên thực thể SQL Server viết dạng `MÁY\THỰC_THỂ`, chỉ MỘT dấu gạch ngược.
    Nhưng khi chép giá trị từ mã Python (nơi phải viết `\\` để thoát) sang tệp
    `.env` (nơi không có cơ chế thoát), rất dễ mang theo cả hai dấu.

    Đã xảy ra thật: `.env` ghi `STAFF_DB_SERVER=172.16.0.26\\VINHUNI`, chuỗi
    kết nối sinh ra sai, đăng nhập cán bộ hỏng — mà thông báo lỗi ODBC chỉ nói
    "Login timeout expired", không hề nhắc tới dấu gạch ngược.

    Gộp mọi dãy gạch ngược liên tiếp thành một. Tên máy chủ SQL không bao giờ
    có hai dấu liền nhau nên phép gộp này không làm hỏng giá trị đúng.
    """
    gia_tri = _opt(key, default)
    while "\\\\" in gia_tri:
        gia_tri = gia_tri.replace("\\\\", "\\")
    return gia_tri


# ---------------------------------------------------------------------------
# Các nhóm cấu hình
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class DatabaseSettings:
    driver: str = field(default_factory=lambda: _opt("DB_DRIVER", "ODBC Driver 17 for SQL Server"))
    server: str = field(default_factory=lambda: _may_chu("DB_SERVER") or _req("DB_SERVER"))
    name: str = field(default_factory=lambda: _opt("DB_NAME", "VinhUni_Local"))
    user: str = field(default_factory=lambda: _req("DB_USER"))
    password: str = field(default_factory=lambda: _req("DB_PASSWORD"))
    trust_cert: bool = field(default_factory=lambda: _bool("DB_TRUST_SERVER_CERT", True))

    @property
    def local_conn_str(self) -> str:
        """Chuỗi kết nối chuẩn — thay cho ~5 biến thể đang rải khắp mã nguồn."""
        parts = [
            f"DRIVER={{{self.driver}}}",
            f"SERVER={self.server}",
            f"DATABASE={self.name}",
            f"UID={self.user}",
            f"PWD={self.password}",
        ]
        if self.trust_cert:
            parts.append("TrustServerCertificate=yes")
        return ";".join(parts) + ";"

    @property
    def safe_repr(self) -> str:
        """Dạng ghi nhật ký được — không lộ mật khẩu."""
        return f"{self.server}/{self.name} (user={self.user})"


@dataclass(frozen=True)
class StaffDatabaseSettings:
    """CSDL hồ sơ cán bộ — máy chủ riêng, tài khoản riêng với CSDL chính."""

    driver: str = field(default_factory=lambda: _opt("DB_DRIVER", "ODBC Driver 17 for SQL Server"))
    server: str = field(default_factory=lambda: _may_chu("STAFF_DB_SERVER"))
    name: str = field(default_factory=lambda: _opt("STAFF_DB_NAME", "DBHoSoCanBo"))
    user: str = field(default_factory=lambda: _opt("STAFF_DB_USER"))
    password: str = field(default_factory=lambda: _opt("STAFF_DB_PASSWORD"))

    @property
    def conn_str(self) -> str:
        if not self.server:
            return ""
        return (
            f"DRIVER={{{self.driver}}};SERVER={self.server};DATABASE={self.name};"
            f"UID={self.user};PWD={self.password};TrustServerCertificate=yes;"
        )


@dataclass(frozen=True)
class MicrosoftSettings:
    """Đăng nhập một lần bằng tài khoản Office 365 của trường."""

    client_id: str = field(default_factory=lambda: _req("MS_CLIENT_ID"))
    client_secret: str = field(default_factory=lambda: _req("MS_CLIENT_SECRET"))
    tenant_id: str = field(default_factory=lambda: _req("MS_TENANT_ID"))
    redirect_uri: str = field(
        default_factory=lambda: _opt("MS_REDIRECT_URI", "https://mobi.vinhuni.edu.vn/office365_login")
    )

    @property
    def conf_url(self) -> str:
        return f"https://login.microsoftonline.com/{self.tenant_id}/v2.0/.well-known/openid-configuration"


@dataclass(frozen=True)
class AISettings:
    openai_api_key: str = field(default_factory=lambda: _opt("OPENAI_API_KEY"))
    chat_model: str = field(default_factory=lambda: _opt("AI_CHAT_MODEL", "gpt-4o-mini"))
    embedding_model: str = field(default_factory=lambda: _opt("AI_EMBEDDING_MODEL", "text-embedding-3-small"))

    # Ngưỡng an toàn — xem core/ai_guard.py
    max_prompt_chars: int = field(default_factory=lambda: _int("AI_MAX_PROMPT_CHARS", 4000))
    max_requests_per_hour: int = field(default_factory=lambda: _int("AI_MAX_REQUESTS_PER_HOUR", 60))
    require_citation: bool = field(default_factory=lambda: _bool("AI_REQUIRE_CITATION", True))
    log_prompts: bool = field(default_factory=lambda: _bool("AI_LOG_PROMPTS", False))


@dataclass(frozen=True)
class SigningSettings:
    """Ký số văn bản hành chính và hồ sơ dịch vụ công."""

    # HSM / chứng thư số của trường (dùng cho ký số tổ chức)
    pkcs11_lib: str = field(default_factory=lambda: _opt("SIGN_PKCS11_LIB"))
    pkcs11_pin: str = field(default_factory=lambda: _opt("SIGN_PKCS11_PIN"))
    pkcs11_token_label: str = field(default_factory=lambda: _opt("SIGN_PKCS11_TOKEN_LABEL"))

    # Chứng thư dạng tệp (chỉ dùng cho môi trường thử nghiệm)
    pfx_path: str = field(default_factory=lambda: _opt("SIGN_PFX_PATH"))
    pfx_password: str = field(default_factory=lambda: _opt("SIGN_PFX_PASSWORD"))

    # Dịch vụ cấp dấu thời gian và kiểm tra thu hồi (bắt buộc cho PAdES-LTV)
    tsa_url: str = field(default_factory=lambda: _opt("SIGN_TSA_URL"))
    tsa_username: str = field(default_factory=lambda: _opt("SIGN_TSA_USERNAME"))
    tsa_password: str = field(default_factory=lambda: _opt("SIGN_TSA_PASSWORD"))

    # Ký số từ xa của nhà cung cấp dịch vụ chứng thực (VNPT-CA, Viettel-CA, MISA...)
    remote_signing_url: str = field(default_factory=lambda: _opt("SIGN_REMOTE_URL"))
    remote_signing_key: str = field(default_factory=lambda: _opt("SIGN_REMOTE_API_KEY"))

    storage_dir: str = field(default_factory=lambda: _opt("SIGN_STORAGE_DIR", str(BASE_DIR / "signed_documents")))

    @property
    def is_configured(self) -> bool:
        return bool(self.pkcs11_lib or self.pfx_path or self.remote_signing_url)


@dataclass(frozen=True)
class SecuritySettings:
    session_secret: str = field(default_factory=lambda: _req("SESSION_SECRET_KEY"))
    jwt_secret: str = field(default_factory=lambda: _req("JWT_SECRET_KEY"))
    jwt_algorithm: str = field(default_factory=lambda: _opt("JWT_ALGORITHM", "HS256"))
    jwt_ttl_minutes: int = field(default_factory=lambda: _int("JWT_TTL_MINUTES", 120))
    refresh_ttl_days: int = field(default_factory=lambda: _int("JWT_REFRESH_TTL_DAYS", 30))

    firebase_credentials: str = field(
        default_factory=lambda: _opt("FIREBASE_CREDENTIALS_PATH", "vinhuni-portal-firebase-adminsdk.json")
    )

    # Công tắc siết xác thực cho nhóm endpoint thông báo.
    #
    # Các endpoint /get-notifs, /count-unread, /mark-read, /hide-notif nhận mã
    # người dùng từ đường dẫn mà không đối chiếu với ai đang gọi — tức là biết
    # mã số của người khác là đọc được thông báo của họ. Phải bịt.
    #
    # Nhưng bản ứng dụng đang cài trên máy sinh viên KHÔNG gửi token cho những
    # endpoint này. Bật bắt buộc ngay là toàn bộ máy chưa cập nhật mất thông báo.
    #
    # Vì vậy chia hai bước:
    #   • Để FALSE khi vừa triển khai: có token thì kiểm tra chặt, không có thì
    #     vẫn phục vụ nhưng ghi nhật ký để đếm còn bao nhiêu máy dùng bản cũ.
    #   • Đổi thành TRUE sau khi bản ứng dụng mới đã phủ hết — lúc đó không có
    #     token là bị từ chối.
    require_auth_notifs: bool = field(
        default_factory=lambda: _bool("REQUIRE_AUTH_NOTIFS", False)
    )

    @property
    def allowed_origins(self) -> list[str]:
        raw = _opt("CORS_ALLOWED_ORIGINS", "https://mobi.vinhuni.edu.vn")
        return [o.strip() for o in raw.split(",") if o.strip()]


@dataclass(frozen=True)
class Settings:
    env: str = field(default_factory=lambda: _opt("APP_ENV", "production"))
    base_url: str = field(default_factory=lambda: _opt("APP_BASE_URL", "https://mobi.vinhuni.edu.vn"))
    internal_student_ai: str = field(
        default_factory=lambda: _opt("INTERNAL_STUDENT_AI", "http://127.0.0.1:8011/internal/verify_student")
    )
    image_folder: str = field(default_factory=lambda: _opt("IMAGE_FOLDER", str(BASE_DIR / "vneid_images")))

    db: DatabaseSettings = field(default_factory=DatabaseSettings)
    staff_db: StaffDatabaseSettings = field(default_factory=StaffDatabaseSettings)
    microsoft: MicrosoftSettings = field(default_factory=MicrosoftSettings)
    ai: AISettings = field(default_factory=AISettings)
    signing: SigningSettings = field(default_factory=SigningSettings)
    security: SecuritySettings = field(default_factory=SecuritySettings)

    @property
    def is_production(self) -> bool:
        return self.env.lower() in ("production", "prod")


# ---------------------------------------------------------------------------
# Khởi tạo — chết sớm nếu thiếu khoá bắt buộc
# ---------------------------------------------------------------------------

settings = Settings()

if _MISSING:
    missing = ", ".join(sorted(set(_MISSING)))
    sys.stderr.write(
        "\n"
        "==========================================================\n"
        " KHÔNG THỂ KHỞI ĐỘNG: thiếu cấu hình bắt buộc\n"
        "==========================================================\n"
        f" Thiếu các biến: {missing}\n\n"
        f" Cách khắc phục:\n"
        f"   1. Sao chép {BASE_DIR / '.env.example'} thành {BASE_DIR / '.env'}\n"
        "   2. Điền giá trị thật cho từng biến\n"
        "   3. Khởi động lại dịch vụ\n\n"
        " Lưu ý: tệp .env đã được .gitignore chặn, không bao giờ commit nó.\n"
        "==========================================================\n\n"
    )
    raise SystemExit(1)
