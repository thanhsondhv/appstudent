import sys
import os

# Ép Python phải nhìn vào thư mục dự án hiện tại
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

# Sau đó mới thực hiện import
from services.ai_corrector_service import router as ocr_router