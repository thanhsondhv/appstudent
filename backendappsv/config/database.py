#C:\vinhuni_project\config\database.py
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from config.settings import settings

# 1. Khởi tạo Engine kết nối SQL Server
# fast_executemany=True giúp tăng tốc độ chèn dữ liệu hàng loạt (bulk insert)
engine = create_engine(
    settings.SQLALCHEMY_DATABASE_URL, 
    fast_executemany=True,
    pool_size=10, 
    max_overflow=20
)

# 2. Tạo SessionLocal - nơi quản lý các phiên làm việc với DB
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# 3. Base class để các Models (như ChatMessage) kế thừa
Base = declarative_base()

# 4. Dependency: Hàm này sẽ được FastAPI gọi để cấp "vé" truy cập DB cho mỗi Request
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close() # Đảm bảo đóng kết nối sau khi dùng xong để tránh tràn bộ nhớ