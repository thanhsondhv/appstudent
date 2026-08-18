from google import genai

# Thay bằng Key của bạn
client = genai.Client(api_key="AIzaSyDUB0ELQXnjIw6mvZB8GoybI4OqWLo6iQ8") 

print("--- DANH SÁCH MODEL HỖ TRỢ EMBEDDING ---")
try:
    for m in client.models.list():
        # Trong bản SDK mới, chúng ta kiểm tra trong 'supported_actions'
        if 'embed_content' in m.supported_actions or 'embedContent' in m.supported_actions:
            print(f"✅ Model: {m.name}")
            print(f"   Mô tả: {m.display_name}")
            print("-" * 30)
except Exception as e:
    print(f"❌ Lỗi khi lấy danh sách: {e}")