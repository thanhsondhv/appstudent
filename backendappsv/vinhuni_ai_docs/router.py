import io
import time
import fitz
import docx  # Thêm thư viện đọc file Word (.docx)
from fastapi import APIRouter, HTTPException, UploadFile, File, Query, BackgroundTasks
from .service import AIService
from .repository import DocRepository
from core.settings import settings  # cấu hình tập trung (Pha 0)

# =====================================================================
# 1. CẤU HÌNH KẾT NỐI SQL SERVER LOCAL (.253)
# =====================================================================
DB_SERVER = settings.db.server
DB_USER = settings.db.user
DB_PASSWORD = settings.db.password
DB_NAME = settings.db.name
REMOTE_CONN_STR = settings.db.local_conn_str

repo = DocRepository(REMOTE_CONN_STR)
router = APIRouter(prefix="/api/ai-docs", tags=["AI Knowledge Management"])


# =====================================================================
# 2. HÀM CHẠY NGẦM: XỬ LÝ VĂN BẢN (BATCHING)
# =====================================================================
def process_document_background(filename: str, content: str):
    try:
        chunks = AIService.split_text(content)
        total_chunks = len(chunks)
        print(f"🚀 Bắt đầu tiến trình ngầm: Xử lý {total_chunks} khối cho file {filename}...")

        batch_size = 20
        
        for i in range(0, total_chunks, batch_size):
            batch_chunks = chunks[i:i + batch_size]
            
            for j, chunk_text in enumerate(batch_chunks):
                actual_index = i + j
                try:
                    vector = AIService.get_embedding(chunk_text)
                    repo.save_chunk(filename, actual_index, chunk_text, vector)
                except Exception as e:
                    print(f"⚠️ Lỗi ở khối {actual_index} file {filename}: {e}")
            
            print(f"✅ Đã lưu thành công {min(i + batch_size, total_chunks)} / {total_chunks} khối...")
            time.sleep(1)
            
        print(f"🎉 HOÀN THÀNH xử lý file: {filename}!")
        
    except Exception as e:
        print(f"🔥 Lỗi nghiêm trọng trong tiến trình ngầm: {e}")


# =====================================================================
# 3. ENDPOINT: UPLOAD FILE WORD (.DOCX) - GIỐNG HỆT DOCXSERVICE.CS
# =====================================================================
@router.post("/upload-docx")
async def upload_docx(background_tasks: BackgroundTasks, file: UploadFile = File(...)):
    if not file.filename.lower().endswith(".docx"):
        raise HTTPException(status_code=400, detail="Vui lòng upload file định dạng .docx (Word)")

    try:
        # Đọc luồng dữ liệu của file tải lên
        file_bytes = await file.read()
        
        # Dùng thư viện python-docx để đọc nội dung (Giống hệt OpenXML)
        doc = docx.Document(io.BytesIO(file_bytes))
        full_text = []
        for para in doc.paragraphs:
            if para.text.strip():
                full_text.append(para.text)
                
        document_content = "\n".join(full_text)

        if not document_content.strip():
            raise HTTPException(status_code=400, detail="Không tìm thấy văn bản trong file Word này.")

        # Ném vào tiến trình chạy ngầm
        background_tasks.add_task(process_document_background, file.filename, document_content)

        return {
            "status": "PROCESSING", 
            "message": f"File Word {file.filename} đang được AI xử lý ngầm. Đã trích xuất thành công {len(document_content)} ký tự tiếng Việt chuẩn!",
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Lỗi đọc file Word: {str(e)}")


# =====================================================================
# 4. ENDPOINT: UPLOAD FILE PDF (DÀNH CHO PDF CHUẨN)
# =====================================================================
@router.post("/upload-pdf")
async def upload_pdf(background_tasks: BackgroundTasks, file: UploadFile = File(...)):
    if not file.filename.lower().endswith(".pdf"):
        raise HTTPException(status_code=400, detail="Chỉ hỗ trợ định dạng file .pdf")

    try:
        pdf_content = ""
        file_bytes = await file.read()
        pdf_document = fitz.open(stream=file_bytes, filetype="pdf")
        
        for page_num in range(len(pdf_document)):
            page = pdf_document.load_page(page_num)
            page_text = page.get_text("text")
            if page_text:
                pdf_content += page_text + "\n"
                
        pdf_document.close()

        if not pdf_content.strip():
            raise HTTPException(status_code=400, detail="Không thể trích xuất văn bản từ file PDF này.")

        background_tasks.add_task(process_document_background, file.filename, pdf_content)

        return {
            "status": "PROCESSING", 
            "message": f"File {file.filename} đang được AI đọc ngầm.",
            "approximate_length": len(pdf_content)
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Lỗi xử lý PDF: {str(e)}")


# =====================================================================
# 5. ENDPOINT: HỎI ĐÁP QUY CHẾ VỚI AI (RAG)
# =====================================================================
@router.get("/ask")
async def ask_ai(question: str = Query(..., description="Câu hỏi của sinh viên")):
    try:
        q_vector = AIService.get_embedding(question)
        context = repo.search_similar(q_vector, top_k=3)
        
        if not context.strip():
            context = "Không có tài liệu cụ thể trong hệ thống. Hãy trả lời dựa trên hiểu biết chung hoặc hướng dẫn liên hệ nhà trường."

        answer = AIService.get_answer(question, context)
        
        return {
            "question": question,
            "answer": answer,
            "has_context": True if context != "Không có tài liệu cụ thể trong hệ thống. Hãy trả lời dựa trên hiểu biết chung hoặc hướng dẫn liên hệ nhà trường." else False
        }
    except Exception as e:
        print(f"🔥 Lỗi Chatbot AI: {e}")
        return {"answer": "Hệ thống AI đang bận, bạn vui lòng thử lại sau giây lát!"}


# =====================================================================
# 6. ENDPOINT: XÓA SẠCH DỮ LIỆU TÀI LIỆU
# =====================================================================
@router.delete("/clear-documents")
async def clear_documents(doc_name: str = None):
    try:
        conn = repo.get_cursor()
        cursor = conn.cursor()
        
        if doc_name:
            cursor.execute("DELETE FROM DocumentChunks WHERE DocumentName = ?", (doc_name,))
        else:
            cursor.execute("TRUNCATE TABLE DocumentChunks")
            
        conn.commit()
        conn.close()
        return {"message": "Đã xóa dữ liệu tài liệu thành công"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))