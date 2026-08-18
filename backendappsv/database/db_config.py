from core.settings import settings  # cấu hình tập trung
# database/db_config.py

class DBConfig:

    @staticmethod
    def get_connection_string():
        return (
            "DRIVER={ODBC Driver 17 for SQL Server};"
            f"SERVER={settings.db.server};"
            "DATABASE=VinhUni_Local;"
            "UID=ChatbotUser;"
            "PWD=VinhUni@2026;"
            "TrustServerCertificate=yes;"
        )