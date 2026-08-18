from sentence_transformers import SentenceTransformer
import os

# Tên model bạn đang dùng
model_name = 'paraphrase-multilingual-MiniLM-L12-v2'

# Đường dẫn thư mục để cất model ngay trong dự án của Sơn
save_path = './models/notification_model'

print(f"⏳ Đang tải model {model_name}...")
model = SentenceTransformer(model_name)

# Lưu model xuống ổ cứng
model.save(save_path)
print(f"✅ Đã lưu model thành công vào: {os.path.abspath(save_path)}")