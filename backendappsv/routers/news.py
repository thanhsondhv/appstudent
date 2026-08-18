from fastapi import APIRouter, Request, HTTPException
import pyodbc
from datetime import datetime
from core.settings import settings  # cấu hình tập trung (Pha 0)


router = APIRouter(prefix="/api", tags=["News"])

DB_SERVER = settings.db.server
DB_USER = settings.db.user
DB_PASSWORD = settings.db.password
DB_NAME = settings.db.name
REMOTE_CONN_STR = settings.db.local_conn_str

# --- HÀM HELPER ĐỂ FORMAT DỮ LIỆU ---
def format_row(row, columns):
    row_dict = dict(zip(columns, row))
    for key, value in row_dict.items():
        if isinstance(value, (datetime)):
            row_dict[key] = value.strftime("%d/%m/%Y %H:%M")
    return row_dict

@router.post("/news")
async def get_news(request: Request):
    try:
        data = await request.json()
        page      = int(data.get('page', 1))
        page_size = 8
        offset    = (page - 1) * page_size

        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()

            # ── Đếm tổng số bài ─────────────────────
            cursor.execute("""
                SELECT COUNT(*)
                FROM dbo.BaiViet_VinhUni
            """)
            total = cursor.fetchone()[0]

            # ── Lấy trang hiện tại ───────────────────
            cursor.execute("""
                SELECT
                    bv.TieuDe, bv.TrichDan, bv.HinhAnh, bv.NoiDung,
                    cb.HS_TenGoiKhac AS TacGia,
                    bv.NguoiDang, bv.NgayDang
                FROM dbo.BaiViet_VinhUni bv
                LEFT JOIN tbl_CANBO_HoSo_Temp cb ON bv.NguoiDang = cb.HS_ID
                ORDER BY bv.NgayDang DESC
                OFFSET ? ROWS FETCH NEXT ? ROWS ONLY
            """, (offset, page_size))

            rows    = cursor.fetchall()
            columns = [col[0] for col in cursor.description]
            result  = [format_row(row, columns) for row in rows]

        return {
            "status":    "success",
            "page":      page,
            "page_size": page_size,
            "total":     total,          # ← Flutter dùng để tính tổng số trang
            "data":      result,
        }

    except Exception as e:
        print(f"🔥 Lỗi News: {e}")
        return {"status": "error", "message": str(e)}

# ═══════════════════════════════════════════════════════
#  2. TÌM KIẾM TIN TỨC (cũng có total)
# ═══════════════════════════════════════════════════════
@router.post("/news_search")
async def search_news(request: Request):
    try:
        data    = await request.json()
        keyword = str(data.get('keyword', '')).strip()
        page    = int(data.get('page', 1))
        page_size = 6
        offset  = (page - 1) * page_size
        kw      = f"%{keyword}%"

        with pyodbc.connect(REMOTE_CONN_STR) as conn:
            cursor = conn.cursor()

            # ── Đếm tổng kết quả tìm kiếm ───────────
            cursor.execute("""
                SELECT COUNT(*)
                FROM dbo.BaiViet_VinhUni bv
                WHERE bv.TieuDe LIKE ? OR bv.TrichDan LIKE ?
            """, (kw, kw))
            total = cursor.fetchone()[0]

            # ── Lấy trang hiện tại ───────────────────
            cursor.execute("""
                SELECT
                    bv.TieuDe, bv.TrichDan, bv.HinhAnh, bv.NoiDung,
                    cb.HS_TenGoiKhac AS TacGia,
                    bv.NguoiDang, bv.NgayDang
                FROM dbo.BaiViet_VinhUni bv
                LEFT JOIN tbl_CANBO_HoSo_Temp cb ON bv.NguoiDang = cb.HS_ID
                WHERE bv.TieuDe LIKE ? OR bv.TrichDan LIKE ?
                ORDER BY bv.NgayDang DESC
                OFFSET ? ROWS FETCH NEXT ? ROWS ONLY
            """, (kw, kw, offset, page_size))

            rows    = cursor.fetchall()
            columns = [col[0] for col in cursor.description]
            result  = [format_row(row, columns) for row in rows]

        return {
            "status":    "success",
            "page":      page,
            "page_size": page_size,
            "total":     total,          # ← Flutter dùng để tính tổng số trang
            "data":      result,
        }

    except Exception as e:
        return {"status": "error", "message": str(e)}