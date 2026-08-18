import os
import requests
import pyodbc
import json
from core.settings import settings  # cấu hình tập trung (Pha 0)

# --- LAYER 0: CẤU HÌNH ---
DOWNLOAD_DIR = r"C:\vinhuni_project\uploads\docs"
LOCAL_CONN_STR = settings.db.local_conn_str
BASE_URL = "https://qlvb.vinhuni.edu.vn"

if not os.path.exists(DOWNLOAD_DIR):
    os.makedirs(DOWNLOAD_DIR)

# 🔥 DÁN COOKIE MỚI NHẤT CỦA SƠN VÀO ĐÂY
FULL_COOKIE = '_ga=GA1.1.181989031.1769428040; _ga_MFE3C1YNEC=GS2.1.s1772725732$o16$g0$t1772725732$j60$l0$h0; session_id=a369eff10e788ebb0acaf1feba3da3064367d36f; cids=1'

HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36 Edg/144.0.0.0',
    'Cookie': FULL_COOKIE
}

# --- LAYER 1: HÀM TÌM KIẾM ---
def get_attachment_id_vinhuni(doc_id, model_name, so_ky_hieu):
    url = f"{BASE_URL}/web/dataset/call_kw"
    try:
        payload = {
            "jsonrpc": "2.0", "method": "call",
            "params": {
                "model": "ir.attachment",
                "method": "search_read",
                "args": [["|", ["res_id", "=", int(doc_id)], ["name", "ilike", so_ky_hieu]]],
                "kwargs": {"fields": ["id", "name"], "order": "id desc"}
            }, "id": 1
        }
        res = requests.post(url, json=payload, headers=HEADERS, timeout=15).json()
        attachments = res.get('result', [])
        if attachments:
            for att in attachments:
                if att['name'].lower().endswith('.pdf'): return att['id']
            return attachments[0]['id']
    except: return None

# --- LAYER 2: LOGIC TẢI ---
def download_now():
    conn = pyodbc.connect(LOCAL_CONN_STR, autocommit=True)
    cursor = conn.cursor()
    
    # 🔥 ĐÃ SỬA: Lấy thêm cột AttachmentId từ SQL của Sơn
    cursor.execute("""
        SELECT DocId, SoKyHieu, ISNULL(ModelName, 'van_ban_noi_bo'), AttachmentId
        FROM tbl_Document_Library 
        WHERE (FileName IS NULL OR FileName = '') AND IsActive = 1
    """)
    rows = cursor.fetchall()

    for doc_id, so_ky_hieu, model_name, sql_att_id in rows:
        print(f"\n🚀 Đang xử lý: {so_ky_hieu}")
        
        # BƯỚC QUAN TRỌNG: Kiểm tra xem Sơn đã nhập ID thủ công chưa
        if sql_att_id:
            print(f"✅ Dùng ID từ SQL Sơn đã nhập: {sql_att_id}")
            att_id = sql_att_id
        else:
            print(f"🔎 SQL chưa có ID, đang lùng trên Odoo...")
            att_id = get_attachment_id_vinhuni(doc_id, model_name, so_ky_hieu)
        
        if att_id:
            url_dl = f"{BASE_URL}/web/content/{att_id}?download=true"
            try:
                res = requests.get(url_dl, headers=HEADERS, timeout=30)
                size = len(res.content)
                
                if res.status_code == 200 and size > 2000:
                    fn = f"VinhUni_{doc_id}.pdf"
                    with open(os.path.join(DOWNLOAD_DIR, fn), "wb") as f:
                        f.write(res.content)
                    
                    # Cập nhật lại SQL lần cuối
                    cursor.execute("UPDATE tbl_Document_Library SET FileName = ?, AttachmentId = ? WHERE DocId = ?", (fn, att_id, doc_id))
                    print(f"✅ THÀNH CÔNG! Đã lưu file: {fn} ({size} bytes)")
                else:
                    print(f"❌ LỖI: File rỗng ({size} bytes). Kiểm tra lại Cookie/ID!")
            except Exception as e:
                print(f"🔥 Lỗi tải: {e}")
        else:
            print("❌ Không tìm thấy ID file.")
    conn.close()

if __name__ == "__main__":
    download_now()