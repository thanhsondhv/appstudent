/* ===========================================================================
   Giữ bảng người nhận luôn khớp với dữ liệu gốc

   Bảng tbl_ThongBao_NguoiNhan được nạp một lần từ dữ liệu đang có. Nếu không
   có gì cập nhật nó thì mọi thông báo TẠO MỚI SAU ĐÓ sẽ không tới được ai —
   một lỗi im lặng và rất khó truy, vì bảng gốc vẫn đúng.

   Dùng trigger thay vì sửa mã ứng dụng, vì có nhiều nơi cùng ghi vào hai bảng
   này: API gửi thông báo, các tiến trình đồng bộ nền, và cả những công cụ chạy
   tay. Trigger bắt được tất cả.

   Chi phí: mỗi lần THÊM một thông báo phải tách chuỗi người nhận. Việc này xảy
   ra vài lần mỗi ngày, trong khi việc ĐỌC xảy ra liên tục — đổi một chút chậm
   lúc ghi lấy nhanh lúc đọc là đúng hướng.

   AN TOÀN: chỉ thêm trigger, không đụng gì tới cấu trúc hay dữ liệu bảng gốc.
   Gỡ bằng DROP TRIGGER là quay lại nguyên trạng.
   =========================================================================== */

SET NOCOUNT ON;
GO

/* --- tbl_ThongBao ------------------------------------------------------- */
IF OBJECT_ID('dbo.TR_ThongBao_DongBoNguoiNhan', 'TR') IS NOT NULL
    DROP TRIGGER dbo.TR_ThongBao_DongBoNguoiNhan;
GO

CREATE TRIGGER dbo.TR_ThongBao_DongBoNguoiNhan
ON dbo.tbl_ThongBao
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    /* Chỉ làm việc khi danh sách người nhận thực sự đổi — UPDATE tiêu đề hay
       nội dung thì không cần tách lại 260 nghìn ký tự. */
    IF UPDATE(IdNguoiHocs) OR NOT EXISTS (SELECT 1 FROM deleted)
    BEGIN
        DELETE n
        FROM dbo.tbl_ThongBao_NguoiNhan n
        WHERE n.Nguon = 'THONGBAO'
          AND n.ThongBaoId IN (SELECT Id FROM inserted);

        INSERT INTO dbo.tbl_ThongBao_NguoiNhan (Nguon, ThongBaoId, MaNguoiNhan)
        SELECT DISTINCT 'THONGBAO', i.Id, x.ma
        FROM inserted i
        CROSS APPLY (
            SELECT UPPER(LTRIM(RTRIM(value))) AS ma
            FROM STRING_SPLIT(CAST(i.IdNguoiHocs AS NVARCHAR(MAX)), ',')
            WHERE LTRIM(RTRIM(value)) <> ''
        ) s
        CROSS APPLY (
            SELECT CASE
                     WHEN s.ma LIKE 'SV%' THEN STUFF(s.ma, 1, 2, '')
                     WHEN s.ma LIKE 'CB%' THEN STUFF(s.ma, 1, 2, '')
                     ELSE s.ma
                   END AS ma
        ) x
        WHERE i.IdNguoiHocs IS NOT NULL
          AND LEN(x.ma) BETWEEN 1 AND 32;
    END
END
GO
PRINT '  + Đã tạo trigger TR_ThongBao_DongBoNguoiNhan';
GO

/* --- tbl_Notification_Queue --------------------------------------------- */
IF OBJECT_ID('dbo.TR_Queue_DongBoNguoiNhan', 'TR') IS NOT NULL
    DROP TRIGGER dbo.TR_Queue_DongBoNguoiNhan;
GO

CREATE TRIGGER dbo.TR_Queue_DongBoNguoiNhan
ON dbo.tbl_Notification_Queue
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF UPDATE(IdNguoiHocs) OR NOT EXISTS (SELECT 1 FROM deleted)
    BEGIN
        DELETE n
        FROM dbo.tbl_ThongBao_NguoiNhan n
        WHERE n.Nguon = 'QUEUE'
          AND n.ThongBaoId IN (SELECT ID FROM inserted);

        INSERT INTO dbo.tbl_ThongBao_NguoiNhan (Nguon, ThongBaoId, MaNguoiNhan)
        SELECT DISTINCT 'QUEUE', i.ID, x.ma
        FROM inserted i
        CROSS APPLY (
            SELECT UPPER(LTRIM(RTRIM(value))) AS ma
            FROM STRING_SPLIT(CAST(i.IdNguoiHocs AS NVARCHAR(MAX)), ',')
            WHERE LTRIM(RTRIM(value)) <> ''
        ) s
        CROSS APPLY (
            SELECT CASE
                     WHEN s.ma LIKE 'SV%' THEN STUFF(s.ma, 1, 2, '')
                     WHEN s.ma LIKE 'CB%' THEN STUFF(s.ma, 1, 2, '')
                     ELSE s.ma
                   END AS ma
        ) x
        WHERE i.IdNguoiHocs IS NOT NULL
          AND LEN(x.ma) BETWEEN 1 AND 32;
    END
END
GO
PRINT '  + Đã tạo trigger TR_Queue_DongBoNguoiNhan';
GO

/* --- Dọn dòng mồ côi khi thông báo bị xoá ------------------------------- */
IF OBJECT_ID('dbo.TR_ThongBao_XoaNguoiNhan', 'TR') IS NOT NULL
    DROP TRIGGER dbo.TR_ThongBao_XoaNguoiNhan;
GO

CREATE TRIGGER dbo.TR_ThongBao_XoaNguoiNhan
ON dbo.tbl_ThongBao
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DELETE n FROM dbo.tbl_ThongBao_NguoiNhan n
    WHERE n.Nguon = 'THONGBAO' AND n.ThongBaoId IN (SELECT Id FROM deleted);
END
GO
PRINT '  + Đã tạo trigger TR_ThongBao_XoaNguoiNhan';
GO

IF OBJECT_ID('dbo.TR_Queue_XoaNguoiNhan', 'TR') IS NOT NULL
    DROP TRIGGER dbo.TR_Queue_XoaNguoiNhan;
GO

CREATE TRIGGER dbo.TR_Queue_XoaNguoiNhan
ON dbo.tbl_Notification_Queue
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DELETE n FROM dbo.tbl_ThongBao_NguoiNhan n
    WHERE n.Nguon = 'QUEUE' AND n.ThongBaoId IN (SELECT ID FROM deleted);
END
GO
PRINT '  + Đã tạo trigger TR_Queue_XoaNguoiNhan';
PRINT '';
PRINT '✅ Bảng người nhận nay tự cập nhật theo mọi thay đổi của hai bảng gốc.';
