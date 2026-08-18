# services/embedding_service.py
from openai import OpenAI
from config.settings import OPENAI_API_KEY, EMBEDDING_MODEL
from core.settings import settings  # cấu hình tập trung (Pha 0)

class EmbeddingService:

    def __init__(self):
        self.client = OpenAI(api_key=settings.ai.openai_api_key)

    def get_embedding(self, text: str):
        response = self.client.embeddings.create(
            model=EMBEDDING_MODEL,
            input=text
        )

        return response.data[0].embedding