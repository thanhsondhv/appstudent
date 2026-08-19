import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';

import 'package:vinhuni_app/services/onedrive_service.dart'; 
import 'package:vinhuni_app/services/vinhuni_api_client.dart';
import 'package:vinhuni_app/views/ms_login_screen.dart'; // Đảm bảo import màn hình Login
import '../core/auth/session.dart';

class OneDriveManagerScreen extends StatefulWidget {
  const OneDriveManagerScreen({super.key});

  @override
  State<OneDriveManagerScreen> createState() => _OneDriveManagerScreenState();
}

class _OneDriveManagerScreenState extends State<OneDriveManagerScreen> {
  final OneDriveService _driveService = OneDriveService();
  bool _isLoading = true;
  List<dynamic> _items = [];
  
  final List<Map<String, String>> _navStack = [
    {"id": "root", "name": "OneDrive Của Tôi"}
  ];

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  // --- 1. LOGIC TẢI DỮ LIỆU ĐÃ ĐƯỢC ĐỒNG BỘ VỚI ONEDRIVE SERVICE ---
  Future<void> _initAndLoad() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    try {
      // 🔥 DÙNG CHUNG HÀM GÁC CỔNG: showLoginUI = false để không tự động popup nhảy ra
      String? token = await _driveService.getValidToken(context, showLoginUI: false); 
      
      if (token == null || token.isEmpty) {
        if (mounted) setState(() { _items = []; _isLoading = false; });
        return;
      }
      
      final prefs = await SharedPreferences.getInstance();
      bool isSetupDone = prefs.getBool('is_onedrive_setup_done') ?? false;
      if (_navStack.length == 1 && !isSetupDone) {
        try {
          await _driveService.initializeVinhUniStructure(token);
          await prefs.setBool('is_onedrive_setup_done', true); 
        } catch (e) {
          debugPrint("ℹ️ Folder setup: $e");
        }
      }

      final data = await _driveService.fetchItems(token, folderId: _navStack.last['id']!);
      
      if (mounted) {
        setState(() {
          _items = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("🔥 Lỗi OneDrive Manager: $e");
      if (e.toString().contains("503")) {
        _showSnackBar("Hệ thống Microsoft đang bận, thử lại sau 30s.", Colors.orange);
      }
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- 2. LOGIC ĐĂNG NHẬP (Lấy Session Token từ Server) ---
  Future<void> _startMicrosoftLogin() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => MSLoginScreen()), // Đã gỡ bỏ chữ const
    );

    if (result != null && result is Map && result.containsKey('session_token')) {
      final String sessionToken = result['session_token'];
      setState(() => _isLoading = true);
      
      try {
        // Gọi API xác thực Handshake để lấy Access Token thật
        final response = await VinhUniClient.instance.post(
          '/api/auth/verify-session',
          data: {"session_token": sessionToken},
        );

        if (response.statusCode == 200 && response.data['status'] == 'success') {
          final String msAccessToken = response.data['data']['ms_access_token'] ?? "";
          if (msAccessToken.isNotEmpty) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('ms_access_token', msAccessToken);
            
            // 🔥 CHÌA KHÓA FIX LỖI Ở ĐÂY: Lưu thêm thời gian hết hạn (1 tiếng = 3.600.000 ms)
            await prefs.setInt('ms_token_expiry', DateTime.now().millisecondsSinceEpoch + 3500000);
            
            _showSnackBar("Kết nối Microsoft 365 thành công!", Colors.green);
            _initAndLoad(); 
          }
        }
      } catch (e) {
        _showSnackBar("Lỗi xác thực phiên Office 365.", Colors.red);
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  // 🔥 HÀM GIA HẠN KẾT NỐI VĨNH VIỄN (Refresh Token)
  Future<void> _silentRefreshToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userCode = prefs.getString('user_code'); // Lấy mã SV/CB đã lưu khi Login app

      final response = await VinhUniClient.instance.post(
        '/api/auth/refresh-ms-token',
        data: {"user_code": userCode},
      );

      if (response.statusCode == 200 && response.data['status'] == 'success') {
        String newToken = response.data['access_token'];
        await prefs.setString('ms_access_token', newToken);
        
        // 🔥 BỔ SUNG LƯU EXPIRY KHI GIA HẠN THÀNH CÔNG ĐỂ KHÔNG BỊ LẶP LỖI
        await prefs.setInt('ms_token_expiry', DateTime.now().millisecondsSinceEpoch + 3500000);
        
        debugPrint("♻️ [O365] Đã làm mới kết nối thành công!");
        _initAndLoad(); // Thử tải lại dữ liệu với token mới
      } else {
        _showExpiredDialog(); // Refresh token hết hạn mới hiện dialog
      }
    } catch (e) {
      _showExpiredDialog();
    }
  }

  // 🔥 HÀM HIỂN THỊ DIALOG HẾT HẠN (Đã được khôi phục)
  void _showExpiredDialog() {
    showDialog(
      context: context, 
      barrierDismissible: false, 
      builder: (ctx) => AlertDialog(
        title: const Text("Hết hạn kết nối"),
        content: const Text("Phiên làm việc Office 365 đã hết hạn. Thầy/Cô vui lòng đăng nhập lại."),
        actions: [ 
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _startMicrosoftLogin();
            }, 
            child: const Text("ĐĂNG NHẬP")
          ) 
        ],
      )
    );
  }

  // --- 3. THAO TÁC FILE (Upload/Delete) ---
  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);

    if (photo != null) {
      setState(() => _isLoading = true);
      try {
        String? token = await _driveService.getValidToken(context, showLoginUI: true);
        if (token == null) return;

        final bytes = await File(photo.path).readAsBytes();
        bool success = await _driveService.uploadFileBytes(
          token, "IMG_${DateTime.now().millisecondsSinceEpoch}.jpg", bytes, _navStack.last['id']!
        );
        if (success) { _showSnackBar("Đã tải ảnh lên OneDrive", Colors.green); _initAndLoad(); }
      } catch (e) { _showSnackBar("Lỗi upload: $e", Colors.red); }
      finally { setState(() => _isLoading = false); }
    }
  }

  Future<void> _handleDeleteItem(String itemId, String itemName) async {
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Xác nhận xoá"),
        content: Text("Xoá vĩnh viễn '$itemName'?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("HỦY")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("XOÁ", style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;

    if (confirm) {
      setState(() => _isLoading = true);
      try {
        String? token = await _driveService.getValidToken(context, showLoginUI: true);
        if (token != null) {
            await _driveService.deleteItem(token, itemId);
            _initAndLoad(); 
        }
      } catch (e) { _showSnackBar("Lỗi: $e", Colors.red); setState(() => _isLoading = false); }
    }
  }

  // --- 4. GIAO DIỆN CHÍNH ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        title: Text(_navStack.last['name']!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF0078D4),
        centerTitle: true,
        leading: _navStack.length > 1 
          ? IconButton(icon: const Icon(Icons.arrow_back_ios, size: 20, color: Colors.white), onPressed: () { setState(() => _navStack.removeLast()); _initAndLoad(); })
          : null,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF0078D4)))
        : _items.isEmpty 
          // Session.msAccessToken tự trả null khi token đã hết hạn, nên ở
          // đây không cần tự đọc và so sánh ms_token_expiry nữa (Pha 1).
          ? FutureBuilder<String?>(
              future: Session.msAccessToken,
              builder: (context, snapshot) {
                // Trong lúc còn đang đọc kho mã hoá thì chưa kết luận vội,
                // nếu không màn hình sẽ nháy sang "cần đăng nhập" rồi đổi lại.
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF0078D4)),
                  );
                }
                final token = snapshot.data;
                if (token == null || token.isEmpty) return _buildLoginRequiredState();
                return _buildEmptyState();
              },
            )
          : RefreshIndicator(
              onRefresh: _initAndLoad,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 10),
                itemCount: _items.length,
                itemBuilder: (context, index) => _buildItemCard(_items[index]),
              ),
            ),
      floatingActionButton: SpeedDial(
        icon: Icons.add, backgroundColor: const Color(0xFF0078D4),
        children: [
          SpeedDialChild(child: const Icon(Icons.camera_alt), label: 'Chụp ảnh tải lên', onTap: _pickAndUploadImage),
          // ⚠️ 19/08/2026: bỏ nút 'Thư mục mới'. Nó có nhãn và biểu tượng đầy
          // đủ nhưng `onTap` rỗng — bấm vào không có gì xảy ra, và người dùng
          // không biết là do hỏng hay do mình bấm trượt. Chưa có phần tạo thư
          // mục ở dịch vụ OneDrive nên tạm ẩn; bày ra một nút chết còn tệ hơn
          // là không bày.
        ],
      ),
    );
  }

  Widget _buildItemCard(dynamic item) {
    bool isFolder = item['folder'] != null;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ListTile(
        leading: Icon(isFolder ? Icons.folder : Icons.insert_drive_file, color: isFolder ? Colors.orange : Colors.blue),
        title: Text(item['name'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        trailing: IconButton(icon: const Icon(Icons.more_vert), onPressed: () => _showItemActions(item)),
        onTap: () {
          if (isFolder) {
            setState(() => _navStack.add({"id": item['id'], "name": item['name']}));
            _initAndLoad();
          } else { _launchOffice(item['webUrl']); }
        },
      ),
    );
  }

  Widget _buildLoginRequiredState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 80, color: Colors.grey),
          const SizedBox(height: 20),
          const Text("Chưa kết nối Microsoft 365", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0078D4)),
            onPressed: _startMicrosoftLogin, 
            child: const Text("KẾT NỐI NGAY", style: TextStyle(color: Colors.white))
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() => const Center(child: Text("Thư mục trống", style: TextStyle(color: Colors.grey)));

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }

  Future<void> _launchOffice(String? url) async { if (url != null) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication); }

  void _showItemActions(dynamic item) {
    showModalBottomSheet(context: context, builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.delete, color: Colors.red), title: const Text("Xoá mục này"), onTap: () { Navigator.pop(ctx); _handleDeleteItem(item['id'], item['name']); }),
    ]));
  }
}