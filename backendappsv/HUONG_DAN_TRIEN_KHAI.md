# Hướng dẫn đưa backend lên server mobi

Cập nhật 18/08/2026.

Toàn bộ thay đổi hiện chỉ nằm trên máy lập trình. Tài liệu này là các bước để
đưa lên server, xếp theo đúng thứ tự phải làm.

---

## Trước khi bắt đầu — hai điều dễ làm hỏng nhất

**1. Tệp `.env` KHÔNG đi theo git.** Nó nằm trong `.gitignore` (cố ý — để khoá
bí mật không lọt lên GitHub). Kéo mã về server xong mà quên tạo `.env` thì
backend **không khởi động được**, báo lỗi rõ ràng ở màn hình đen chứ không chạy
nửa vời. Đây là lỗi số một khi triển khai lần đầu.

**2. Ba tiến trình mới thay cho các tiến trình cũ.** Chạy song song hai bên là
mỗi thông báo gửi hai lần cho ~15 nghìn sinh viên. Phải dừng hẳn bản cũ trước.

---

## Bước 1 — Sao lưu

```
xcopy C:\đường\dẫn\backendappsv C:\backup\backendappsv_18082026 /E /I /H
```

Sao lưu cả cơ sở dữ liệu nếu tiện. Bước sau có ghi vào
`tbl_Notification_Read_Status`.

---

## Bước 2 — Lấy mã mới về

```
cd C:\đường\dẫn\backendappsv
git fetch origin
git checkout nang-cap/pha-0-1-bao-mat-va-nen-tang
git pull
```

---

## Bước 3 — Tạo tệp `.env` (bắt buộc)

```
copy .env.example .env
notepad .env
```

Tám khoá **bắt buộc**, thiếu một khoá là không khởi động:

| Khoá | Điền gì |
|---|---|
| `DB_SERVER` | tên/địa chỉ máy chủ SQL, ví dụ `AI2025\SQLEXPRESS02` |
| `DB_USER` | tài khoản SQL |
| `DB_PASSWORD` | mật khẩu SQL |
| `MS_CLIENT_ID` | ứng dụng Microsoft (đăng nhập bằng tài khoản trường) |
| `MS_CLIENT_SECRET` | khoá bí mật của ứng dụng đó |
| `MS_TENANT_ID` | mã tổ chức Microsoft |
| `SESSION_SECRET_KEY` | chuỗi ngẫu nhiên dài |
| `JWT_SECRET_KEY` | chuỗi ngẫu nhiên dài |

Sinh chuỗi ngẫu nhiên:

```
python -c "import secrets; print(secrets.token_urlsafe(48))"
```

> **Lưu ý về `JWT_SECRET_KEY`:** đổi khoá này là **mọi người đang đăng nhập bị
> đăng xuất** và phải đăng nhập lại. Chọn đúng một lần rồi giữ nguyên. Nếu muốn
> người dùng không bị văng ra, giữ nguyên khoá đang dùng ở bản cũ.

---

## Bước 4 — Cài Redis (bắt buộc, chưa có thì thông báo không gửi được)

Hàng đợi thông báo chạy trên Redis. Trên Windows chọn một trong hai:

* **Memurai** — bản Redis cho Windows, chạy như dịch vụ: https://www.memurai.com
* **WSL** — `wsl --install` rồi `sudo apt install redis-server`

Kiểm tra:

```
redis-cli ping
```

Phải trả về `PONG`.

---

## Bước 5a — Chép thư mục `models/` từ máy chủ về kho mã (BẮT BUỘC)

Năm tệp import `models.chat_model` — `ChatMessage`, `ChatGroup`, `User`,
`ChatMember`, `MessageAction`, `GroupKnowledge`:

* `routers/api_chatgroupv1.py`
* `core/socket_manager.py`
* `services/ai_service.py`
* `services/chatgroup/message_service.py`
* `services/chatgroup/member_service.py`

Nhưng thư mục `models/` **chưa bao giờ được commit** — nó chỉ tồn tại trên máy
chủ đang chạy. Kho mã hiện thiếu nó, nên cài mới ở bất kỳ máy nào khác là
`Main.py` không nạp được và **cả backend không khởi động**.

Việc cần làm, một lần:

```
xcopy C:\đường\dẫn\hiện\tại\models  C:\kho-ma\backendappsv\models /E /I
cd C:\kho-ma\backendappsv
git add models
git commit -m "Bo sung thu muc models con thieu trong kho ma"
```

Kiểm tra lại bằng:

```
python tests/kiem_tra_module_thieu.py
```

---

## Bước 5 — Cài thư viện Python

```
pip install -r requirements.txt
```

---

## Bước 6 — Chạy kiểm tra trước khi khởi động

```
python kiem_tra_truoc_khi_chay.py
```

Kịch bản này kiểm 7 nhóm: tệp `.env`, trình điều khiển ODBC, kết nối cơ sở dữ
liệu và các bảng cần có, Redis, khoá Firebase, cổng mạng, và nhắc về tiến trình
cũ. Mỗi mục hỏng đều kèm cách khắc phục cụ thể.

**Chỉ sang bước 7 khi nó in `✅ SẴN SÀNG CHẠY`.**

---

## Bước 7 — Dừng hẳn các tiến trình đời cũ

Mở Task Manager, kết thúc mọi tiến trình `python.exe` đang chạy:

* `master_worker.py`
* `sync_and_notify_worker.py`  *(bản không có đuôi `_new`)*
* `notification_worker.py`

Nếu chúng đang chạy dưới dạng dịch vụ Windows hay Task Scheduler thì **tắt cả
lịch chạy tự động**, không chỉ tắt tiến trình — nếu không nó tự bật lại.

---

## Bước 8 — Khởi động ba tiến trình mới

Ba cửa sổ dòng lệnh riêng, hoặc ba dịch vụ:

```
python -m uvicorn Main:app --host 0.0.0.0 --port 8000
```

```
python notification_system/producer_app.py
```

```
python notification_system/worker_windows.py
```

Và tiến trình đồng bộ nền:

```
python sync_and_notify_worker_new.py
```

Chi tiết vai trò từng tiến trình xem `HE_THONG_THONG_BAO.md`.

---

## Bước 9 — Kiểm tra sau khi chạy

```
curl https://mobi.vinhuni.edu.vn/api/count-unread/1679
curl http://localhost:8082/health
curl http://localhost:8082/trang-thai-hang-doi
```

Thử gửi một thông báo cho **đúng một người** (mã của chính mình) trước khi gửi
diện rộng.

---

## Bước 10 — Siết xác thực (làm SAU, không làm ngay)

Năm endpoint thông báo trước đây nhận mã người dùng từ máy khách mà không đối
chiếu — biết mã số người khác là đọc được thông báo của họ. Đã bịt, nhưng theo
hai bước, vì **bản ứng dụng đang cài trên máy sinh viên không gửi token** cho
các endpoint này. Siết ngay là mọi máy chưa cập nhật mất thông báo.

**Lúc này (`REQUIRE_AUTH_NOTIFS=false`, mặc định):**
có token thì kiểm chặt, không có token thì vẫn phục vụ và ghi nhật ký:

```
⚠️  [get-notifs] lượt gọi thứ 500 không kèm token — máy khách bản cũ.
```

**Khi nào siết được:** sau khi bản ứng dụng mới đã phủ hết máy người dùng, và
dòng nhật ký trên không còn xuất hiện nữa. Khi đó:

```
REQUIRE_AUTH_NOTIFS=true
```

rồi khởi động lại. Từ lúc đó, gọi không kèm token là bị từ chối.

> Chừng nào còn `false` thì lỗ hổng vẫn còn — kẻ tấn công chỉ cần không gửi
> token. Đây là bước chuyển tiếp để không làm hỏng máy người dùng, không phải
> bản vá hoàn chỉnh. Nên đẩy bản ứng dụng mới càng sớm càng tốt.

---

## Nếu phải quay lui

```
git checkout main
```

rồi khởi động lại các tiến trình cũ. Dữ liệu đã ghi vào
`tbl_Notification_Read_Status` không gây hại cho bản cũ — bảng đó vốn đã có.
