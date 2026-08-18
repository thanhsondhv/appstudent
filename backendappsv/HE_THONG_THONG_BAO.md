# Hệ thống thông báo VinhUni

Tài liệu này mô tả **đúng những tiến trình cần chạy** và những tiến trình đã bị
thay thế. Viết ngày 18/08/2026 sau đợt hợp nhất.

Trước đợt này có **bốn worker chạy song song** làm trùng việc nhau, hai bộ gửi
thông báo đẩy tranh nhau cổng 8081, và không tài liệu nào nói cái nào là chính.
Hệ quả là gửi trùng, gửi sót, và không ai dám tắt cái gì.

---

## Cần chạy những gì

Đúng **ba** tiến trình, mỗi tiến trình một vai trò rõ ràng:

### 1. Bộ đồng bộ — `sync_and_notify_worker_new.py`

Kéo dữ liệu về và **sinh ra** thông báo trong `tbl_Notification_Queue`.

```bash
python sync_and_notify_worker_new.py
```

| Việc | Nhịp |
|---|---|
| Bóc tách lịch tuần + tài liệu Odoo + đồng bộ delta qua stored procedure | 30 phút |
| Nhắc sự kiện sắp diễn ra (`sp_AI_Remind_Upcoming_Events`) | 5 phút |
| Biến lịch tuần thành thông báo (`sp_AI_Process_Weekly_Notification`) | 15 phút |
| Bản tin sáng / chiều (kèm thời tiết, âm lịch) | 6:30 và 13:00 |
| Đồng bộ hồ sơ cán bộ từ máy chủ `.26` | 48 giờ |
| Dọn hàng đợi cũ | 2:00 sáng |

### 2. Hệ thống gửi — `notification_system/`

**Lấy** thông báo từ hàng đợi và **đẩy** đến thiết bị người dùng.

```bash
cd notification_system
run_system.bat          # Windows: khởi động cả bộ nạp lẫn worker
```

Gồm một bộ nạp (`producer_app.py`, cổng **8082**) và năm worker:
hai worker cho làn ưu tiên cao `q_high` (chat, nhắc lịch thi), ba worker cho
làn thường `q_default` (lịch học, tin tức, văn bản).

Theo dõi:
- `http://localhost:8082/health` — bộ nạp và Redis còn sống không
- `http://localhost:8082/trang-thai-hang-doi` — độ dài hàng đợi; **tăng liên
  tục nghĩa là worker không kịp xử lý**, cần thêm worker

**Chia nhỏ công việc để chạy song song.** Một thông báo toàn trường tới ~15.000
thiết bị được cắt thành ~34 công việc, mỗi công việc 450 thiết bị, để cả năm
worker cùng gửi. Nếu để nguyên một công việc thì chỉ một worker gánh — mất
khoảng 10 phút và làm nghẽn cả tin nhắn chat phía sau. Chia nhỏ rút xuống còn
khoảng 2 phút.

Số phần còn lại của mỗi thông báo được đếm bằng khoá `notif:{id}:con_lai` trong
Redis. Chỉ khi phần cuối cùng gửi xong, thông báo mới được đánh dấu `IsSent = 1`.
Dùng `DECR` của Redis nên nhiều worker cùng lúc vẫn đếm đúng.

**Bắt buộc có Redis** chạy ở `localhost:6379`. Thiếu Redis thì `run_system.bat`
dừng ngay với thông báo rõ ràng thay vì chạy rồi lỗi âm thầm.

### 3. Bộ quét nhắc lịch — `notification_worker.py`

```bash
python notification_worker.py          # cổng 8083
```

Chỉ **sinh** nhắc lịch thi vào hàng đợi, **không gửi** — phần gửi đã gỡ ngày
18/08/2026 để không trùng với `notification_system/`.

Vì sao vẫn giữ: nó nhắc lịch theo **thời gian báo trước riêng của từng người**
(`tbl_Notification_User_Settings.LeadTimeMinutes`). Bản `_new` cũng nhắc lịch
nhưng qua `sp_AI_Remind_Upcoming_Events @MinutesBefore = 30` — cố định 30 phút
cho tất cả, bỏ qua thiết lập cá nhân mà màn "Cấu hình nhận thông báo" ghi vào.

Khi nào sửa được stored procedure để đọc `LeadTimeMinutes` từng người thì có
thể dừng hẳn tệp này.

---

## Luồng dữ liệu

```
Nguồn dữ liệu (.200, .26, Odoo, trang lịch tuần)
        │
        ▼
sync_and_notify_worker_new.py          ← sinh thông báo
        │
        ▼
tbl_Notification_Queue  (IsSent = 0)
        │
        ▼
notification_system/producer_app.py    ← tìm người nhận, lọc theo cài đặt
        │                                 (IsSent → 2 "đang xử lý")
        ▼
Redis:  q_high  /  q_default
        │
        ▼
worker_windows.py ×5                   ← gửi FCM, chia lô 450 token
        │                                 (IsSent → 1 "đã gửi")
        ▼
Thiết bị người dùng
```

### Ý nghĩa cột `IsSent`

| Giá trị | Nghĩa |
|---|---|
| 0 | Chưa gửi — bộ nạp sẽ lấy ở lượt quét sau |
| 1 | Đã gửi xong |
| 2 | Đang xử lý — đã nạp vào Redis, worker đang gửi |
| 3 | Bỏ qua — quá hạn (mặc định 7 ngày) |

---

## Đã bị thay thế — KHÔNG chạy nữa

Nằm ở `_luu_tru/worker_da_thay_the/`, giữ lại để đối chiếu:

| Tệp | Vì sao dừng |
|---|---|
| `master_worker.py` | Trùng phần lớn với bản `_new`. Hai việc riêng của nó — xử lý thông báo lịch tuần và đồng bộ hồ sơ cán bộ — **đã chuyển sang** `sync_and_notify_worker_new.py` |
| `sync_and_notify_worker.py` | Bản cũ hơn của `_new`, dùng vòng lặp `while True` thay vì bộ lập lịch |
| `services/scraper_service.py` | `class WeeklyScraper` trùng hệt bản đã nhúng trong `_new`, và không tệp nào import |

**Chạy lại chúng cùng lúc với bản `_new` sẽ gây gửi trùng thông báo.**

---

## Những lỗi đã sửa trong đợt này

Ghi lại để không ai vô tình khôi phục:

1. **Gửi nhầm người.** Truy vấn cũ dùng `WHERE StudentId LIKE '%mã%'`.

   Đo trên cơ sở dữ liệu thật ngày 18/08/2026: `tbl_users` có **~62.000 tài
   khoản**, trong đó **48.234 mã sinh viên dài 15 ký tự** và **~2.600 mã cán bộ
   chỉ dài 4–5 ký tự**. Thử 20 mã cán bộ ngắn nhất thì **cả 20 đều nằm lọt bên
   trong mã của người khác**:

   | Mã cán bộ | Truy vấn cũ gửi nhầm sang |
   |---|---|
   | `1011` | **5.486 người** |
   | `1010` | 2.844 người |
   | `1008` | 976 người |

   Nghĩa là gửi một thông báo riêng cho cán bộ mã `1011` thì **5.486 người khác
   cũng nhận được**. Với thông báo về lương, kỷ luật, hay tin nhắn cá nhân thì
   đây là lộ dữ liệu nghiêm trọng.

   **Chưa gây hậu quả** vì hiện mới có 103 người đăng ký nhận thông báo đẩy
   (245 thiết bị) — chưa có mã nào va chạm. Nhưng sẽ xảy ra ngay khi triển khai
   rộng. Nay so khớp chính xác thay vì `LIKE`.

2. **Vỡ khi gửi toàn trường.** Firebase giới hạn cứng **500 token** mỗi
   `MulticastMessage`. Bản cũ đưa cả nghìn token vào một lần → ném lỗi, rơi vào
   khối `except` chỉ có một dòng `print`, tin mất luôn. Nay chia lô 450.

3. **Mất tin khi worker chết.** `BLPOP` lấy việc ra khỏi hàng đợi ngay lập tức;
   worker chết giữa chừng là việc biến mất. Nay dùng `BRPOPLPUSH` sang hàng đợi
   "đang xử lý", chỉ xoá khi gửi xong, và tự nhặt lại việc treo quá 5 phút.

4. **Bỏ qua cài đặt người dùng.** Màn "Cấu hình nhận thông báo" ghi vào
   `tbl_Notification_User_Settings` nhưng đường ống không đọc. Nay lọc theo
   `IsEnabled` ngay trong truy vấn lấy token.

5. **Bỏ rơi tin cũ hơn 24 giờ.** Hệ thống nghỉ một ngày là toàn bộ tin trong
   khoảng đó không bao giờ được gửi, mà vẫn nằm `IsSent = 0` tích tụ mãi trong
   bảng. Nay xử lý hết tin tồn, chỉ đánh dấu bỏ qua khi quá 7 ngày.

6. **Truy vấn N+1.** Một truy vấn cho mỗi người nhận — gửi 5.000 sinh viên là
   5.000 lượt truy vấn cho một thông báo. Nay gom theo lô 1.000 mã.

7. **Không dọn token chết.** Người gỡ ứng dụng thì token vô hiệu vĩnh viễn
   nhưng vẫn được gửi mỗi lần. Nay đọc phản hồi Firebase và tắt token tương ứng.

---

## Cấu hình

Toàn bộ nằm trong `.env` ở thư mục gốc backend, không còn viết cứng trong mã.

| Biến | Mặc định | Ý nghĩa |
|---|---|---|
| `REDIS_HOST` / `REDIS_PORT` | `localhost` / `6379` | Nơi đặt hàng đợi |
| `PRODUCER_PORT` | `8082` | Cổng bộ nạp (tránh trùng 8081) |
| `NOTIF_SCAN_INTERVAL` | `5` | Giây giữa hai lượt quét |
| `NOTIF_BATCH_SIZE` | `100` | Số tin lấy mỗi lượt |
| `NOTIF_MAX_AGE_DAYS` | `7` | Quá ngần này ngày thì bỏ qua |
| `NOTIF_STALE_SECONDS` | `300` | Việc treo quá lâu thì nhặt lại |
| `NOTIF_MAX_RETRY` | `3` | Số lần thử lại trước khi bỏ cuộc |
| `NOTIF_DEVICES_PER_JOB` | `450` | Số thiết bị mỗi công việc — quyết định mức song song |
| `SCANNER_PORT` | `8083` | Cổng bộ quét nhắc lịch |
| `WEATHER_API_KEY` | — | Cho bản tin sáng/chiều |
| `STAFF_LINKED_SERVER` | `172.16.0.26\vinhuni` | Máy chủ hồ sơ cán bộ |
