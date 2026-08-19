/* ===========================================================================
   Bảng người nhận thông báo — thay cho việc quét chuỗi IdNguoiHocs

   VÌ SAO CẦN

   Cả tbl_ThongBao lẫn tbl_Notification_Queue lưu danh sách người nhận dưới
   dạng MỘT CHUỖI mã ngăn bởi dấu phẩy, kiểu NVARCHAR(MAX). Muốn biết một người
   có nhận thông báo nào thì phải quét cả chuỗi bằng LIKE '%mã%'.

   Đo ngày 19/08/2026 trên dữ liệu thật:
     • tbl_ThongBao chỉ 491 dòng, nhưng IdNguoiHocs trung bình 263.948 ký tự,
       dòng lớn nhất 1.078.605 ký tự — tổng cộng ~240 MB.
     • Mỗi lần mở danh sách thông báo, máy chủ quét lại trọn 240 MB đó: 5,41
       giây cho MỘT người dùng. Với 15 nghìn sinh viên thì không thể chịu nổi.
     • tbl_ThongBao là HEAP, không có một chỉ mục nào.

   VÀ MỘT LỖI SAI DỮ LIỆU NGHIÊM TRỌNG HƠN

   LIKE '%1679%' khớp cả những mã DÀI HƠN có chứa "1679" ở giữa. Kiểm trên dữ
   liệu thật: tài khoản 1679 khớp 22 thông báo, trong khi so khớp đúng theo dấu
   phân cách khớp 0. Tức người dùng đang đọc được 22 thông báo KHÔNG PHẢI CỦA
   MÌNH — và ngược lại, người khác cũng đọc được thông báo của họ.

   CÁCH LÀM

   Tách chuỗi thành từng dòng trong một bảng riêng, có chỉ mục theo mã người
   nhận. Tra cứu chuyển từ "quét 240 MB" thành "tìm theo chỉ mục".

   AN TOÀN

   Chỉ TẠO MỚI, không sửa và không xoá gì của bảng cũ. Cột IdNguoiHocs giữ
   nguyên, nên quay lui chỉ cần bỏ dùng bảng này. Chạy lại nhiều lần không sao.

   YÊU CẦU: SQL Server 2016 trở lên (dùng STRING_SPLIT).
   =========================================================================== */

SET NOCOUNT ON;

/* --- 1. Bảng người nhận ------------------------------------------------- */
IF OBJECT_ID('dbo.tbl_ThongBao_NguoiNhan', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.tbl_ThongBao_NguoiNhan (
        Nguon        VARCHAR(16)   NOT NULL,   -- 'THONGBAO' hoặc 'QUEUE'
        ThongBaoId   INT           NOT NULL,
        MaNguoiNhan  VARCHAR(32)   NOT NULL,   -- đã chuẩn hoá, bỏ tiền tố SV/CB
        CONSTRAINT PK_ThongBao_NguoiNhan PRIMARY KEY (Nguon, ThongBaoId, MaNguoiNhan)
    );
    PRINT '  + Đã tạo bảng tbl_ThongBao_NguoiNhan';
END
ELSE
    PRINT '  = Bảng tbl_ThongBao_NguoiNhan đã có';
GO

/* Chỉ mục cho câu hỏi hay dùng nhất: "người này nhận những thông báo nào" */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_NguoiNhan_Ma' AND object_id = OBJECT_ID('dbo.tbl_ThongBao_NguoiNhan'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_NguoiNhan_Ma
        ON dbo.tbl_ThongBao_NguoiNhan (MaNguoiNhan, Nguon) INCLUDE (ThongBaoId);
    PRINT '  + Đã tạo chỉ mục IX_NguoiNhan_Ma';
END
GO

/* --- 2. Nạp dữ liệu từ tbl_ThongBao ------------------------------------- */
PRINT '  … đang tách danh sách người nhận của tbl_ThongBao';

INSERT INTO dbo.tbl_ThongBao_NguoiNhan (Nguon, ThongBaoId, MaNguoiNhan)
SELECT DISTINCT 'THONGBAO', t.Id, x.ma
FROM dbo.tbl_ThongBao t
CROSS APPLY (
    SELECT UPPER(LTRIM(RTRIM(value))) AS ma
    FROM STRING_SPLIT(CAST(t.IdNguoiHocs AS NVARCHAR(MAX)), ',')
    WHERE LTRIM(RTRIM(value)) <> ''
) s
CROSS APPLY (
    /* Bỏ tiền tố SV/CB để khớp với cách mã được chuẩn hoá ở nơi khác */
    SELECT CASE
             WHEN s.ma LIKE 'SV%' THEN STUFF(s.ma, 1, 2, '')
             WHEN s.ma LIKE 'CB%' THEN STUFF(s.ma, 1, 2, '')
             ELSE s.ma
           END AS ma
) x
WHERE t.IdNguoiHocs IS NOT NULL
  AND LEN(x.ma) BETWEEN 1 AND 32
  AND NOT EXISTS (
        SELECT 1 FROM dbo.tbl_ThongBao_NguoiNhan n
        WHERE n.Nguon = 'THONGBAO' AND n.ThongBaoId = t.Id AND n.MaNguoiNhan = x.ma
  );
PRINT '  + tbl_ThongBao: đã nạp ' + CAST(@@ROWCOUNT AS VARCHAR(20)) + ' dòng người nhận';
GO

/* --- 3. Nạp dữ liệu từ tbl_Notification_Queue --------------------------- */
PRINT '  … đang tách danh sách người nhận của tbl_Notification_Queue';

INSERT INTO dbo.tbl_ThongBao_NguoiNhan (Nguon, ThongBaoId, MaNguoiNhan)
SELECT DISTINCT 'QUEUE', q.ID, x.ma
FROM dbo.tbl_Notification_Queue q
CROSS APPLY (
    SELECT UPPER(LTRIM(RTRIM(value))) AS ma
    FROM STRING_SPLIT(CAST(q.IdNguoiHocs AS NVARCHAR(MAX)), ',')
    WHERE LTRIM(RTRIM(value)) <> ''
) s
CROSS APPLY (
    SELECT CASE
             WHEN s.ma LIKE 'SV%' THEN STUFF(s.ma, 1, 2, '')
             WHEN s.ma LIKE 'CB%' THEN STUFF(s.ma, 1, 2, '')
             ELSE s.ma
           END AS ma
) x
WHERE q.IdNguoiHocs IS NOT NULL
  AND LEN(x.ma) BETWEEN 1 AND 32
  AND NOT EXISTS (
        SELECT 1 FROM dbo.tbl_ThongBao_NguoiNhan n
        WHERE n.Nguon = 'QUEUE' AND n.ThongBaoId = q.ID AND n.MaNguoiNhan = x.ma
  );
PRINT '  + tbl_Notification_Queue: đã nạp ' + CAST(@@ROWCOUNT AS VARCHAR(20)) + ' dòng người nhận';
GO

/* --- 4. Chỉ mục cho các bảng đang thiếu --------------------------------- */

/* tbl_ThongBao là HEAP, không có chỉ mục nào. Danh sách luôn lọc IsDeleted và
   sắp theo NgayPhatHanh, nên đánh chỉ mục đúng hai cột đó. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_ThongBao_Ngay' AND object_id = OBJECT_ID('dbo.tbl_ThongBao'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_ThongBao_Ngay
        ON dbo.tbl_ThongBao (IsDeleted, NgayPhatHanh DESC) INCLUDE (Id, IdLoaiThongBao);
    PRINT '  + Đã tạo chỉ mục IX_ThongBao_Ngay';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_ReadStatus_Student' AND object_id = OBJECT_ID('dbo.tbl_Notification_Read_Status'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_ReadStatus_Student
        ON dbo.tbl_Notification_Read_Status (StudentId) INCLUDE (NotifID);
    PRINT '  + Đã tạo chỉ mục IX_ReadStatus_Student';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_Queue_Sent_Ngay' AND object_id = OBJECT_ID('dbo.tbl_Notification_Queue'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_Queue_Sent_Ngay
        ON dbo.tbl_Notification_Queue (IsSent, CreatedAt DESC) INCLUDE (ID, StudentId, Category, Scope);
    PRINT '  + Đã tạo chỉ mục IX_Queue_Sent_Ngay';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_Hides_Student' AND object_id = OBJECT_ID('dbo.tbl_Notification_Hides'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_Hides_Student
        ON dbo.tbl_Notification_Hides (StudentId) INCLUDE (NotifID);
    PRINT '  + Đã tạo chỉ mục IX_Hides_Student';
END
GO

PRINT '';
PRINT '✅ Xong. Kiểm tra lại bằng:';
PRINT '   SELECT Nguon, COUNT(*) FROM tbl_ThongBao_NguoiNhan GROUP BY Nguon;';
