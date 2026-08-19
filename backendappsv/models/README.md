# Thư mục `models/`

Có hai loại thứ khác hẳn nhau trong đây.

## Mã nguồn — CÓ trong git

* `chat_model.py` — định nghĩa bảng cho phần trò chuyện nhóm (SQLAlchemy).
  Năm tệp khác import `models.chat_model`; thiếu nó là backend không khởi động.
* `secretary_model.py`

## Mô hình tải về — KHÔNG trong git

`notification_model/` là mô hình `paraphrase-multilingual-MiniLM-L12-v2` tải từ
HuggingFace, dùng để so khớp thông báo theo ngữ nghĩa.

Nó **nặng 449 MB**. GitHub chặn cứng ở 100 MB mỗi tệp nên không đẩy lên được,
và để trong git thì kho mã phình từ vài MB lên 453 MB — ai sao chép về cũng
phải tải trọn 453 MB đó.

Nó cũng **không cần** nằm trong git: tái tạo được bằng đúng một lệnh.

### Cách tạo lại trên máy mới

```
cd backendappsv
python tv.py
```

Lệnh này tải mô hình rồi lưu vào `./models/notification_model`. Cần mạng và gói
`sentence-transformers` (đã có trong requirements.txt).

### Nơi dùng

* `vinhuni_notifications/router.py` — tìm kiếm thông báo theo ngữ nghĩa
* `tv.py` — chính tệp tải nó về
