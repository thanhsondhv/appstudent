/* ===========================================================================
   Gửi thông báo tự động theo sự kiện — sinh nhật, ngày lễ

   VÌ SAO

   Ứng dụng đã có màn hình "TỰ ĐỘNG & SỰ KIỆN" với hai công tắc và ba mẫu tin,
   nhưng phía máy chủ KHÔNG có gì cả: không endpoint, không bảng cấu hình,
   không tác vụ nền. Cán bộ bật "Chúc mừng sinh nhật" rồi tin rằng hệ thống sẽ
   tự gửi, mà nó không bao giờ gửi.

   Dữ liệu thì đã sẵn: tbl_users có cột Birthday, 60.618/61.974 tài khoản có
   ngày sinh. Đo trên dữ liệu thật: trung bình 150–215 người sinh nhật mỗi
   ngày, ngày đông nhất khoảng 215. Tải rất nhẹ.

   AN TOÀN: chỉ tạo mới hai bảng, không đụng gì tới dữ liệu đang có. Chạy lại
   nhiều lần không sao.
   =========================================================================== */

SET NOCOUNT ON;
GO

/* --- 1. Cấu hình: bật/tắt và nội dung mẫu --------------------------------- */
IF OBJECT_ID('dbo.tbl_ThongBao_TuDong', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.tbl_ThongBao_TuDong (
        MaCauHinh   VARCHAR(32)    NOT NULL PRIMARY KEY,  -- 'SINH_NHAT', 'NGAY_LE'
        TenHienThi  NVARCHAR(200)  NOT NULL,
        BatTat      BIT            NOT NULL DEFAULT 0,
        TieuDe      NVARCHAR(300)  NOT NULL,
        NoiDung     NVARCHAR(MAX)  NOT NULL,
        /* Giờ trong ngày sẽ gửi, 0–23. Gửi lúc 7h sáng là hợp lý: người dùng
           đã dậy nhưng chưa vào giờ học. */
        GioGui      TINYINT        NOT NULL DEFAULT 7,
        NguoiSua    VARCHAR(32)    NULL,
        SuaLuc      DATETIME       NULL
    );
    PRINT '  + Đã tạo bảng tbl_ThongBao_TuDong';
END
GO

/* Nội dung mặc định. Dùng {ten} làm chỗ thay tên người nhận. */
IF NOT EXISTS (SELECT 1 FROM dbo.tbl_ThongBao_TuDong WHERE MaCauHinh = 'SINH_NHAT')
    INSERT INTO dbo.tbl_ThongBao_TuDong
        (MaCauHinh, TenHienThi, BatTat, TieuDe, NoiDung, GioGui)
    VALUES
        ('SINH_NHAT', N'Chúc mừng sinh nhật', 0,
         N'Chúc mừng sinh nhật {ten}!',
         N'Trường Đại học Vinh chúc {ten} một ngày sinh nhật thật vui và một '
         + N'năm mới nhiều sức khoẻ, học tập và công tác tốt.',
         7);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.tbl_ThongBao_TuDong WHERE MaCauHinh = 'NGAY_LE')
    INSERT INTO dbo.tbl_ThongBao_TuDong
        (MaCauHinh, TenHienThi, BatTat, TieuDe, NoiDung, GioGui)
    VALUES
        ('NGAY_LE', N'Lời chúc ngày lễ', 0,
         N'{ten_ngay_le}',
         N'Trường Đại học Vinh gửi lời chúc tốt đẹp nhất tới {ten}.',
         7);
GO

/* --- 2. Nhật ký đã gửi: chống gửi trùng ----------------------------------- */
/* Tác vụ nền chạy mỗi giờ, và có thể chạy lại sau khi khởi động lại máy chủ.
   Không có bảng này thì một người có thể nhận cùng lời chúc nhiều lần trong
   ngày — phiền hơn là không gửi. */
IF OBJECT_ID('dbo.tbl_ThongBao_TuDong_Log', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.tbl_ThongBao_TuDong_Log (
        MaCauHinh   VARCHAR(32)  NOT NULL,
        MaNguoiNhan VARCHAR(32)  NOT NULL,
        Nam         SMALLINT     NOT NULL,   -- mỗi năm gửi lại một lần
        GuiLuc      DATETIME     NOT NULL DEFAULT GETDATE(),
        MaThongBao  INT          NULL,       -- trỏ về tbl_Notification_Queue
        CONSTRAINT PK_ThongBao_TuDong_Log
            PRIMARY KEY (MaCauHinh, MaNguoiNhan, Nam)
    );
    PRINT '  + Đã tạo bảng tbl_ThongBao_TuDong_Log';
END
GO

/* --- 3. Ngày lễ trong năm ------------------------------------------------- */
IF OBJECT_ID('dbo.tbl_NgayLe', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.tbl_NgayLe (
        Id       INT IDENTITY(1,1) PRIMARY KEY,
        Ngay     TINYINT       NOT NULL,
        Thang    TINYINT       NOT NULL,
        TenNgay  NVARCHAR(200) NOT NULL,
        /* 'ALL' cho mọi người, 'CB' chỉ cán bộ, 'SV' chỉ sinh viên */
        DoiTuong VARCHAR(8)    NOT NULL DEFAULT 'ALL',
        BatTat   BIT           NOT NULL DEFAULT 1,
        CONSTRAINT UQ_NgayLe UNIQUE (Ngay, Thang, DoiTuong)
    );
    PRINT '  + Đã tạo bảng tbl_NgayLe';
END
GO

/* Ngày lễ theo dương lịch. Tết Nguyên đán theo âm lịch nên KHÔNG đưa vào đây —
   tác vụ nền đã có thư viện lunar-python để tự tính. */
IF NOT EXISTS (SELECT 1 FROM dbo.tbl_NgayLe)
BEGIN
    INSERT INTO dbo.tbl_NgayLe (Ngay, Thang, TenNgay, DoiTuong) VALUES
        (1,  1,  N'Chúc mừng năm mới',                    'ALL'),
        (8,  3,  N'Chúc mừng ngày Quốc tế Phụ nữ 8/3',    'ALL'),
        (30, 4,  N'Chúc mừng ngày Giải phóng miền Nam',   'ALL'),
        (1,  5,  N'Chúc mừng ngày Quốc tế Lao động',      'ALL'),
        (2,  9,  N'Chúc mừng ngày Quốc khánh',            'ALL'),
        (20, 10, N'Chúc mừng ngày Phụ nữ Việt Nam',       'ALL'),
        (20, 11, N'Chúc mừng ngày Nhà giáo Việt Nam',     'CB'),
        (22, 12, N'Chúc mừng ngày Quân đội nhân dân',     'ALL');
    PRINT '  + Đã nạp 8 ngày lễ dương lịch';
END
GO

/* --- 4. Chỉ mục cho truy vấn hằng ngày ------------------------------------ */
/* Tác vụ nền hỏi mỗi ngày: "ai sinh nhật hôm nay". Không có chỉ mục thì quét
   toàn bộ 62 nghìn dòng. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_Users_Birthday' AND object_id = OBJECT_ID('dbo.tbl_users'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_Users_Birthday
        ON dbo.tbl_users (Birthday) INCLUDE (UserCode, FullName, UserRole, IsActive);
    PRINT '  + Đã tạo chỉ mục IX_Users_Birthday';
END
GO

PRINT '';
PRINT '✅ Xong. Bật bằng cách đặt BatTat = 1, hoặc dùng màn hình trong ứng dụng.';
