import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'notification_settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback? onAvatarUpdate;
  const ProfileScreen({super.key, this.onAvatarUpdate});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final Color vinhUniBlue = const Color(0xFF0054A6);
  String studentName = ""; // Để trống lúc đầu để không hiện "Đang tải"
  String studentId = "";
  String userRole = "";
  bool isNotifEnabled = true;
  bool _isUpdatingFace = false;
  
  // Biến lưu thông tin thêm (Sẽ ẩn hoàn toàn nếu lỗi hoặc rỗng)
  String? studentStatus;
  String? studentClass;

  int _imageVersion = DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Lấy user_code đã được AuthService làm sạch thành số (1679)
    String savedId = prefs.getString('user_code') ?? "";

    setState(() {
      studentName = prefs.getString('full_name') ?? "Người dùng";
      studentId = savedId; // Chắc chắn lúc này là "1679"
      userRole = prefs.getString('user_role') ?? "SinhVien";
    });

    if (studentId.isNotEmpty) {
      _fetchStudentExtraInfo(studentId);
    }
  }

  // 🔥 HÀM GỌI API LẤY LỚP & TRẠNG THÁI (Đã bỏ lỗi kết nối hiển thị ra ngoài)
  Future<void> _fetchStudentExtraInfo(String id) async {
    try {
      final response = await http.get(
        Uri.parse("https://mobi.vinhuni.edu.vn/api/student-info/$id"),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          setState(() {
            studentStatus = data['trang_thai'];
            studentClass = data['lop_hanh_chinh'];
          });
        }
      }
    } catch (e) {
      // Khi lỗi (mất mạng, api chết), ta im lặng để studentStatus/Class = null
      // Giao diện sẽ tự ẩn các Badge đi thay vì hiện "Lỗi kết nối"
      debugPrint("API Extra Info Error: $e");
    }
  }

  // 🔥 CHỨC NĂNG CẬP NHẬT FACE ID (Vector)
  Future<void> _updateFaceID() async {
    if (studentId.isEmpty) return;
    final picker = ImagePicker();
    final XFile? image = await showModalBottomSheet<XFile>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_front_rounded),
              title: const Text('Chụp ảnh khuôn mặt (Camera trước)'),
              onTap: () async => Navigator.pop(context, await picker.pickImage(source: ImageSource.camera, preferredCameraDevice: CameraDevice.front)),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Chọn từ thư viện'),
              onTap: () async => Navigator.pop(context, await picker.pickImage(source: ImageSource.gallery)),
            ),
          ],
        ),
      ),
    );

    if (image == null) return;
    setState(() => _isUpdatingFace = true);

    try {
      var request = http.MultipartRequest('POST', Uri.parse("https://mobi.vinhuni.edu.vn/api/update-face-vector"));
      request.fields['student_id'] = studentId;
      request.files.add(await http.MultipartFile.fromPath('photo', image.path));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        _showMessage("✅ Cập nhật dữ liệu khuôn mặt thành công!");
        setState(() => _imageVersion = DateTime.now().millisecondsSinceEpoch);
        widget.onAvatarUpdate?.call();
      } else {
        _showMessage("⚠️ Không thể tạo vector khuôn mặt. Thử lại sau.");
      }
    } catch (e) {
      _showMessage("❌ Lỗi kết nối Server AI");
    } finally {
      if (mounted) setState(() => _isUpdatingFace = false);
    }
  }

  // 🔥 CHỨC NĂNG ĐỔI MẬT KHẨU
  void _showChangePasswordDialog() {
    final oldPassCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Đổi mật khẩu"),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: oldPassCtrl, obscureText: true, decoration: const InputDecoration(labelText: "Mật khẩu cũ")),
            const SizedBox(height: 10),
            TextField(controller: newPassCtrl, obscureText: true, decoration: const InputDecoration(labelText: "Mật khẩu mới")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Hủy")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: vinhUniBlue, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(context);
              _performChangePassword(oldPassCtrl.text, newPassCtrl.text);
            },
            child: const Text("Lưu"),
          ),
        ],
      ),
    );
  }

  Future<void> _performChangePassword(String oldPass, String newPass) async {
    if (oldPass.isEmpty || newPass.isEmpty) return;
    _showMessage("Đang xử lý đổi mật khẩu...");
    // Gọi API đổi mật khẩu tại đây...
  }

  // 🔥 GIỚI THIỆU ỨNG DỤNG
  // --- KHÔI PHỤC HÀM GIỚI THIỆU APP NHƯ CŨ ---
  void _showAboutApp() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.55,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 45,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(25),
                child: Column(
                  children: [
                    const Icon(Icons.school_rounded, size: 70, color: Color(0xFF0054A6)),
                    const SizedBox(height: 15),
                    const Text("Vinh Uni Student",
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const Text("Phiên bản 1.0.0", style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 20),
                    const Text(
                        "Ứng dụng cung cấp các dịch vụ học tập trực tuyến, tra cứu điểm thi, thời khóa biểu và bảo mật FaceID.",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, height: 1.5, color: Colors.black87)),
                    const SizedBox(height: 25),
                    _buildAboutItem(Icons.security, "Bảo mật dữ liệu FaceID"),
                    _buildAboutItem(Icons.notifications_active, "Thông báo đẩy thời gian thực"),
                    _buildAboutItem(Icons.update, "Cập nhật dữ liệu đồng bộ"),
                    const SizedBox(height: 20),
                    const Divider(),
                    const Text("© 2026 Vinh University",
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: vinhUniBlue),
          const SizedBox(width: 15),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  Future<void> _logout() async {
  // 1. Hiện thông báo xác nhận để tránh bấm nhầm
  bool? confirm = await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text("Đăng xuất"),
      content: const Text("Bạn có muốn xóa luôn liên kết Face ID trên thiết bị này không?"),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false), 
          child: const Text("KHÔNG, CHỈ ĐĂNG XUẤT")
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true), 
          child: const Text("CÓ, XÓA TẤT CẢ", style: TextStyle(color: Colors.white))
        ),
      ],
    ),
  );

  if (confirm == null) return; // Người dùng bấm ra ngoài hoặc hủy

  setState(() => _isUpdatingFace = true); // Hiển thị loading nhẹ

  try {
    // 2. Xóa sạch SharedPreferences (Token, ID, Role...)
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    // 3. Nếu người dùng chọn "CÓ", xóa luôn mật khẩu trong két sắt bảo mật
    if (confirm == true) {
      const storage = FlutterSecureStorage();
      await storage.delete(key: 'bio_user');
      await storage.delete(key: 'bio_pwd');
    }

    // 4. Đưa người dùng về màn hình đăng nhập và xóa toàn bộ lịch sử các màn hình cũ
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  } catch (e) {
    _showMessage("Lỗi khi đăng xuất: $e");
  } finally {
    if (mounted) setState(() => _isUpdatingFace = false);
  }
}

  // Widget hiển thị Badge thông tin thêm
  Widget _buildInfoBadges() {
    List<Widget> badges = [];
    if (studentClass != null && studentClass!.isNotEmpty) {
      badges.add(_badge(studentClass!, Colors.blueGrey));
    }
    if (studentStatus != null && studentStatus!.isNotEmpty) {
      Color color = studentStatus!.contains("nghiệp") ? Colors.green : vinhUniBlue;
      badges.add(_badge(studentStatus!, color));
    }
    if (badges.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(top: 8.0), child: Wrap(spacing: 8, children: badges));
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.3))),
      child: Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Tài khoản", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87)),
        centerTitle: true, backgroundColor: Colors.white, elevation: 0.5, automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Bảng Thông tin User
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
              child: Row(
                children: [
                  // Avatar an toàn
                  Container(
                    width: 70, height: 70,
                    decoration: BoxDecoration(color: vinhUniBlue.withOpacity(0.1), shape: BoxShape.circle),
                    child: ClipOval(
                      child: Image.network(
                        "https://mobi.vinhuni.edu.vn/api/get-avatar/$studentId?v=$_imageVersion",
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) => Icon(Icons.person, size: 40, color: vinhUniBlue),
                      ),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(studentName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        const SizedBox(height: 4),
                        Text("${userRole == "GiangVien" ? "MCB" : "MSV"}: $studentId", style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w600)),
                        _buildInfoBadges(),
                      ],
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 25),
            const Align(alignment: Alignment.centerLeft, child: Text("  CÀI ĐẶT", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12))),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
              child: Column(
                children: [
                  _buildMenuTile(
                    Icons.notifications_active_outlined, 
                    "Cấu hình nhận thông báo", 
                    Colors.orange, 
                    onTap: () => Navigator.push(
                      context, 
                      MaterialPageRoute(builder: (context) => NotificationSettingsScreen(userId: studentId, userRole: userRole))
                    )
                  ),
                  const Divider(height: 1, indent: 50),
                  _buildMenuTile(Icons.lock_outline, "Đổi mật khẩu", Colors.blue, onTap: _showChangePasswordDialog),
                  const Divider(height: 1, indent: 50),
                  _buildMenuTile(
                    Icons.face_retouching_natural_rounded, "Cập nhật Face ID", Colors.purple, 
                    onTap: _isUpdatingFace ? null : _updateFaceID,
                    trailing: _isUpdatingFace ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
              child: Column(
                children: [
                  _buildMenuTile(Icons.info_outline, "Giới thiệu ứng dụng", Colors.teal, onTap: _showAboutApp),
                  const Divider(height: 1, indent: 50),
                  _buildMenuTile(Icons.logout, "Đăng xuất", Colors.red, onTap: _logout, showArrow: false),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuTile(IconData icon, String title, Color color, {VoidCallback? onTap, Widget? trailing, bool showArrow = true}) {
    return ListTile(
      leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 20)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
      trailing: trailing ?? (showArrow ? const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey) : null),
      onTap: onTap,
    );
  }
}