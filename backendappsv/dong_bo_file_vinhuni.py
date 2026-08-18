import os
import re
import requests
import pyodbc
import rookiepy
import unicodedata
from core.settings import settings  # cấu hình tập trung (Pha 0)

# --- [LAYER 0: CẤU HÌNH] ---
DOWNLOAD_DIR = r"E:\app_vinhuni\vanban\docs"
LOCAL_CONN_STR = settings.db.local_conn_str
BASE_URL = "https://qlvb.vinhuni.edu.vn"

if not os.path.exists(DOWNLOAD_DIR): 
    os.makedirs(DOWNLOAD_DIR)

def clean_filename(text):
    """Biến 'Báo cáo số 22/BC' thành 'Bao_cao_so_22-BC'"""
    if not text: return "document"
    text = unicodedata.normalize('NFKD', text).encode('ascii', 'ignore').decode('ascii')
    text = re.sub(r'[\\/*?:"<>|]', '-', text)
    text = re.sub(r'\s+', '_', text).strip()
    return text[:130]

def get_session_from_browser():
    try:
        cookies = rookiepy.edge(["qlvb.vinhuni.edu.vn"])
        if not cookies: cookies = rookiepy.chrome(["qlvb.vinhuni.edu.vn"])
        for cookie in cookies:
            if cookie['name'] == 'session_id':
                print(f"✅ Đã kết nối Session: {cookie['value']}")
                return cookie['value']
    except Exception as e:
        print(f"❌ Lỗi Cookie: {e}")
    return None

# --- [LAYER 2: HÀM ĐỒNG BỘ CHÍNH] ---
def sync_vinhuni_final_boss():
    sid = get_session_from_browser()
    if not sid: return
    
    headers = {
        'Cookie': f'session_id={sid}; cids=1',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0'
    }

    try:
        conn = pyodbc.connect(LOCAL_CONN_STR, autocommit=True)
        cursor = conn.cursor()
    except Exception as e:
        print(f"❌ Lỗi SQL: {e}"); return

    print("📡 Đang quét Odoo (Đánh thẳng vào tai_lieu_chung)...")
    url_call_kw = f"{BASE_URL}/web/dataset/call_kw"
    
    payload_list = {
        "jsonrpc": "2.0", "method": "call",
        "params": {
            "model": "van_ban_noi_bo",
            "method": "search_read",
            "args": [[["id", ">", 0]]],
            "kwargs": {
                "fields": ["id", "so_ky_hieu", "trich_yeu", "loai_van_ban_id", "ngay_van_ban", "tai_lieu_ids"],
                "limit": 70, "order": "id desc"
            }
        }, "id": 1
    }

    try:
        res_json = requests.post(url_call_kw, json=payload_list, headers=headers).json()
        documents = res_json.get('result', [])
        
        for doc in documents:
            o_id = doc['id']
            so_hieu = doc.get('so_ky_hieu') or f"SBN-{o_id}"
            trich_yeu = doc.get('trich_yeu') or ""
            t_ids = doc.get('tai_lieu_ids', []) # Đây là danh sách [3307, 3312...]

            # Kiểm tra trong SQL
            cursor.execute("SELECT DocId, FileName FROM tbl_Document_Library WHERE DocId = ?", (o_id,))
            row = cursor.fetchone()

            # 1. Đồng bộ Metadata
            if not row:
                print(f"🆕 Đồng bộ mới: {so_hieu}")
                cursor.execute("SET IDENTITY_INSERT tbl_Document_Library ON")
                cursor.execute("""
                    INSERT INTO tbl_Document_Library (DocId, SoKyHieu, TrichYeu, LoaiVanBan, NgayBanHanh, IsActive)
                    VALUES (?, ?, ?, ?, ?, 1)
                """, (o_id, so_hieu, trich_yeu, 
                      doc['loai_van_ban_id'][1] if doc.get('loai_van_ban_id') else '', 
                      doc.get('ngay_van_ban')))
                cursor.execute("SET IDENTITY_INSERT tbl_Document_Library OFF")

            # 2. Tải File PDF dựa trên "Công thức Vàng" Sơn vừa soi được
            if t_ids and (not row or not row.FileName):
                # Odoo cho phép nhiều tài liệu, mình sẽ lấy cái ID đầu tiên trong danh sách
                target_id = t_ids[0] 
                
                # 🎯 Tên file theo đúng Label Sơn muốn: [Số hiệu] - [Trích yếu].pdf
                clean_so = clean_filename(so_hieu)
                clean_ty = clean_filename(trich_yeu)[:100]
                fn = f"{clean_so}_-_{clean_ty}.pdf"
                
                print(f"   ∟ 🎯 Tải File từ tai_lieu_chung (ID: {target_id}) -> {fn}")
                
                # Dùng đúng link cấu trúc: model=tai_lieu_chung&field=tai_lieu_dinh_kem_viewer
                url_dl = f"{BASE_URL}/web/content?model=tai_lieu_chung&field=tai_lieu_dinh_kem_viewer&id={target_id}&download=true"
                res_f = requests.get(url_dl, headers=headers)
                
                if res_f.status_code == 200 and len(res_f.content) > 2000:
                    path = os.path.join(DOWNLOAD_DIR, fn)
                    with open(path, "wb") as f:
                        f.write(res_f.content)
                    
                    # Cập nhật SQL
                    cursor.execute("UPDATE tbl_Document_Library SET FileName = ?, AttachmentId = ? WHERE DocId = ?", (fn, target_id, o_id))
                    print(f"   ∟ ✅ Thành công!")
                else:
                    print(f"   ∟ ❌ Lỗi link tải hoặc file trống (ID: {target_id})")
            elif not t_ids:
                print(f"   ∟ ⚠️ {so_hieu}: Văn bản này thực sự không có file đính kèm.")

    except Exception as e:
        print(f"🔥 Lỗi hệ thống: {e}")
    finally:
        conn.close()

if __name__ == "__main__":
    sync_vinhuni_final_boss()