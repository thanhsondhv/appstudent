import time
import requests
import os
import subprocess

API_URL = "http://127.0.0.1:8080/api/health" 

def restart_service():
    print("\n" + "="*30)
    print("🔥 Đang khởi động lại VinhUni API...")
    
    # Giết tiến trình đang chiếm cổng 8080
    os.system("for /f \"tokens=5\" %a in ('netstat -aon ^| findstr :8080') do taskkill /f /pid %a")
    time.sleep(1)
    
    # Khởi động Main.py
    subprocess.Popen(["start", "cmd", "/k", "python", "Main.py"], shell=True)
    
    # 🔥 QUAN TRỌNG: Đợi 15 giây để App khởi động xong rồi mới bắt đầu giám sát
    print("⏳ Đang đợi App khởi động (15 giây)...")
    time.sleep(15)
    print("🚀 Bắt đầu giám sát...")
    print("="*30 + "\n")

print("🛡️ Watchdog đang chạy...")
restart_service()

while True:
    try:
        response = requests.get(API_URL, timeout=5)
        if response.status_code == 200:
            # Hệ thống ổn, in ra log để theo dõi (tùy chọn)
            # print(f"✅ [{time.strftime('%H:%M:%S')}] API Hoạt động tốt.")
            pass
        else:
            restart_service()
    except Exception:
        restart_service()
        
    time.sleep(30) # Kiểm tra mỗi 30 giây