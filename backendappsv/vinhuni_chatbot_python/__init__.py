import json
import os

# Đọc file appsettings.json từ thư mục gốc của dự án
config_path = os.path.join(os.getcwd(), 'appsettings.json')
with open(config_path, 'r', encoding='utf-8') as f:
    CONFIG = json.load(f)