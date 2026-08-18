import 'dart:io';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/onedrive_service.dart';

class ShareHandler {
  static final OneDriveService _driveService = OneDriveService();

  // Khởi tạo lắng nghe chia sẻ (Gọi hàm này trong initState của Home)
  static void init(BuildContext context) {
    // 1. Lắng nghe khi App đang chạy ngầm rồi nhận file
    ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
      _processSharedFiles(context, value);
    });

    // 2. Lắng nghe khi App bị đóng hoàn toàn rồi được mở bằng lệnh Share
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      _processSharedFiles(context, value);
    });
  }

  static void _processSharedFiles(BuildContext context, List<SharedMediaFile> files) async {
    if (files.isEmpty) return;

    // Hiện hộp thoại chờ xử lý
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text("Đang chuẩn bị tải lên..."),
          ],
        ),
      ),
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('ms_access_token');

      if (token == null) throw "Vui lòng kết nối OneDrive trước";

      for (var file in files) {
        // Lấy tên file từ đường dẫn
        String fileName = file.path.split('/').last;
        // Đọc bytes
        List<int> bytes = await File(file.path).readAsBytes();
        
        // Tạm thời upload vào thư mục Gốc (Root)
        // Sơn có thể cải tiến bằng cách hiện Dialog chọn thư mục tại đây
        await _driveService.uploadFileBytes(token, fileName, bytes, "root");
      }

      Navigator.pop(context); // Đóng dialog chờ
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Đã lưu ${files.length} file vào OneDrive"), backgroundColor: Colors.green)
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Lỗi chia sẻ: $e"), backgroundColor: Colors.red)
      );
    }
  }
}