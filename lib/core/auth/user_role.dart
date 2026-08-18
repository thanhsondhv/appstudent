/// Vai trò người dùng trong hệ thống VinhUni.
///
/// NƠI DUY NHẤT được phép diễn giải chuỗi vai trò do máy chủ trả về.
///
/// Trước ngày 18/08/2026, cùng một giá trị `user_role` được ba màn hình kiểm tra
/// theo ba cách khác nhau:
///   • home_screen            so sánh chữ thường với 5 chuỗi rời rạc
///   • thongbao_screen        so sánh nguyên văn kiểu PascalCase (không hạ chữ)
///   • notification_settings  dùng `.contains("canbo")`
/// Hậu quả: máy chủ trả `"canbo"` thì màn Thông báo hiểu nhầm là sinh viên và
/// hiển thị sai nhóm tin. Tệp này chấm dứt tình trạng đó.
///
/// ⚠️ Lưu ý quan trọng: đây chỉ là lớp **hiển thị**. Việc ẩn một nút bấm không
/// phải là biện pháp bảo mật — mọi endpoint dành cho cán bộ BẮT BUỘC phải tự
/// kiểm tra vai trò từ token ở phía máy chủ.
library;

enum UserRole {
  /// Người học — vai trò mặc định khi không xác định được.
  sinhVien,

  /// Cán bộ, giảng viên.
  canBo,

  /// Cố vấn học tập — quyền của cán bộ, cộng thêm quản lý lớp phụ trách.
  coVan,

  /// Quản trị hệ thống.
  admin;

  /// Diễn giải chuỗi vai trò từ máy chủ, chấp nhận mọi biến thể đang tồn tại.
  ///
  /// Chấp nhận: "CanBo", "canbo", "CB", "cb", "GiangVien", "giang_vien",
  /// "CoVan", "covan", "Admin", "ad", "SinhVien", "sv"...
  /// Không nhận ra thì trả về [sinhVien] — mặc định về quyền thấp nhất,
  /// tuyệt đối không mặc định thành cán bộ.
  static UserRole parse(String? raw) {
    if (raw == null) return UserRole.sinhVien;

    // Chuẩn hoá: hạ chữ thường, bỏ dấu cách, gạch dưới, gạch ngang
    final key = raw.toLowerCase().replaceAll(RegExp(r'[\s_\-]'), '');
    if (key.isEmpty) return UserRole.sinhVien;

    const adminKeys = {'admin', 'ad', 'quantri', 'quantrivien', 'superadmin'};
    const coVanKeys = {'covan', 'cv', 'covanhoctap', 'advisor'};
    const canBoKeys = {
      'canbo', 'cb', 'giangvien', 'gv', 'giaovien',
      'staff', 'lecturer', 'teacher', 'nhanvien',
    };
    const sinhVienKeys = {'sinhvien', 'sv', 'student', 'hocvien', 'nguoihoc'};

    if (adminKeys.contains(key)) return UserRole.admin;
    if (coVanKeys.contains(key)) return UserRole.coVan;
    if (canBoKeys.contains(key)) return UserRole.canBo;
    if (sinhVienKeys.contains(key)) return UserRole.sinhVien;

    // Dự phòng cho các biến thể chưa liệt kê, ví dụ "CanBo_Khoa_CNTT"
    if (key.contains('admin') || key.contains('quantri')) return UserRole.admin;
    if (key.contains('covan')) return UserRole.coVan;
    if (key.contains('canbo') || key.contains('giangvien') || key.contains('staff')) {
      return UserRole.canBo;
    }

    return UserRole.sinhVien;
  }

  /// Giá trị chuẩn để ghi xuống máy và gửi lên máy chủ.
  String get wireValue => switch (this) {
        UserRole.sinhVien => 'SinhVien',
        UserRole.canBo => 'CanBo',
        UserRole.coVan => 'CoVan',
        UserRole.admin => 'Admin',
      };

  /// Tên hiển thị cho người dùng.
  String get displayName => switch (this) {
        UserRole.sinhVien => 'Sinh viên',
        UserRole.canBo => 'Cán bộ, giảng viên',
        UserRole.coVan => 'Cố vấn học tập',
        UserRole.admin => 'Quản trị hệ thống',
      };

  /// Có phải cán bộ, giảng viên hoặc cấp cao hơn không.
  ///
  /// Thay cho toàn bộ các biến thể `isStaff` từng viết rải rác.
  bool get isStaff => this != UserRole.sinhVien;

  bool get isStudent => this == UserRole.sinhVien;
  bool get isAdmin => this == UserRole.admin;

  /// Được mở điểm danh cho lớp học phần.
  bool get canOpenAttendance => isStaff;

  /// Được gửi thông báo cho nhiều người cùng lúc.
  bool get canBroadcastNotification => isStaff;

  /// Được duyệt đơn xin nghỉ, xin vắng học.
  bool get canApproveLeave => this == UserRole.coVan || this == UserRole.admin;

  /// Được xem lịch công tác của đơn vị.
  bool get canViewStaffSchedule => isStaff;

  /// Được vào cổng quản trị trên máy tính.
  bool get canAccessAdminPortal => isStaff;

  /// Được quản lý người dùng và cấu hình hệ thống.
  bool get canManageSystem => this == UserRole.admin;

  /// Được ký số văn bản với tư cách cá nhân có thẩm quyền.
  bool get canSignDocument => isStaff;
}
