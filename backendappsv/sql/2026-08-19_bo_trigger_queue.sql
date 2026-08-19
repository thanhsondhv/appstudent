/* ===========================================================================
   Gỡ trigger khỏi tbl_Notification_Queue

   VÌ SAO PHẢI GỠ

   SQL Server không cho phép `OUTPUT INSERTED.<cột>` (dạng không có INTO) trên
   một bảng đang có trigger đang bật:

     "The target table ... of the DML statement cannot have any enabled
      triggers if the statement contains an OUTPUT clause without INTO clause."

   Ba chỗ trong mã ứng dụng ghi vào tbl_Notification_Queue theo đúng cách đó —
   toàn bộ là các API GỬI THÔNG BÁO. Để trigger lại là gửi thông báo hỏng ngay.
   Phép thử tests/kiem_tra_bang_nguoi_nhan.py đã bắt được điều này trước khi nó
   kịp lên máy chủ.

   VÀ VÌ SAO KHÔNG CẦN

   Đo ngày 19/08/2026: tra cứu người nhận trên tbl_Notification_Queue chỉ mất
   0,01 giây — cột IdNguoiHocs ở bảng này nhỏ. Chậm 5,41 giây là ở tbl_ThongBao
   (~240 MB). Nên chỉ tbl_ThongBao cần tới bảng người nhận.

   Riêng lỗi khớp nhầm chuỗi con thì vẫn phải sửa cho cả hai — với Queue thì
   sửa bằng cách so khớp có dấu phân cách ngay trong câu truy vấn, không cần
   thêm bảng và không cần trigger.
   =========================================================================== */

SET NOCOUNT ON;
GO

IF OBJECT_ID('dbo.TR_Queue_DongBoNguoiNhan', 'TR') IS NOT NULL
BEGIN
    DROP TRIGGER dbo.TR_Queue_DongBoNguoiNhan;
    PRINT '  - Đã gỡ trigger TR_Queue_DongBoNguoiNhan';
END
GO

IF OBJECT_ID('dbo.TR_Queue_XoaNguoiNhan', 'TR') IS NOT NULL
BEGIN
    DROP TRIGGER dbo.TR_Queue_XoaNguoiNhan;
    PRINT '  - Đã gỡ trigger TR_Queue_XoaNguoiNhan';
END
GO

/* Dọn các dòng nguồn QUEUE: không còn ai cập nhật chúng nên để lại chỉ gây
   nhầm lẫn — dữ liệu cũ dần mà nhìn vẫn như thật. */
DELETE FROM dbo.tbl_ThongBao_NguoiNhan WHERE Nguon = 'QUEUE';
PRINT '  - Đã dọn ' + CAST(@@ROWCOUNT AS VARCHAR(20)) + ' dòng nguồn QUEUE';
GO

PRINT '';
PRINT '✅ tbl_Notification_Queue trở lại không trigger — các API gửi thông báo chạy bình thường.';
PRINT '   tbl_ThongBao vẫn giữ trigger và bảng người nhận (đó mới là chỗ chậm).';
