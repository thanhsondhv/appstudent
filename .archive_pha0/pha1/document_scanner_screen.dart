import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinhuni_app/services/onedrive_service.dart';
import 'package:vinhuni_app/services/vinhuni_api_client.dart';
import 'package:dio/dio.dart' as dio;

class DocumentScannerScreen extends StatefulWidget {
  const DocumentScannerScreen({super.key});
  @override
  State<DocumentScannerScreen> createState() => _DocumentScannerScreenState();
}

class _DocumentScannerScreenState extends State<DocumentScannerScreen> {
  final _driveService = OneDriveService();
  
  // 🔥 KHỞI TẠO CONTROLLER CỐ ĐỊNH ĐỂ FIX LỖI TRẮNG MÀN HÌNH
  late TextEditingController _textController;
  
  bool _isProcessing = false;
  String _extractedText = "";
  List<dynamic> _keyPoints = [];

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
  }

  @override
  void dispose() {
    _textController.dispose(); // Dọn dẹp bộ nhớ
    super.dispose();
  }

  // --- 1. LOGIC QUÉT VÀ NHẬN DIỆN CHỮ (OCR A3) ---
  Future<void> _scanDocument() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (image == null) return;

    if (!mounted) return;
    setState(() {
      _isProcessing = true;
      _extractedText = ""; // Reset dữ liệu cũ
      _textController.clear();
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      String userId = prefs.getString('user_id') ?? "SV_ANONYMOUS";

      final formData = dio.FormData.fromMap({
        'file': await dio.MultipartFile.fromFile(image.path),
        'user_id': userId,
        'role': 'sinhvien', 
      });
      
      // Gọi API Backend
      final res = await VinhUniClient.instance.post('/api/ocr/extract-text', data: formData);
      
      // 🕵️ Debug để Sơn xem server trả về cái gì
      debugPrint("📡 [OCR DATA]: ${res.data}");

      if (mounted && res.data['status'] == 'success') {
        setState(() {
          // Bóc tách đúng tầng dữ liệu từ Backend Python
          final data = res.data['data'];
          _extractedText = data['refined_text'] ?? "";
          _keyPoints = data['key_points'] ?? [];
          
          // 🔥 CẬP NHẬT CHỮ VÀO CONTROLLER ĐỂ HIỂN THỊ LÊN UI
          _textController.text = _extractedText;
          _isProcessing = false;
        });
      } else {
        throw Exception("Server trả về lỗi hoặc format không đúng");
      }
    } catch (e) {
      debugPrint("🔥 Lỗi OCR thực tế: $e");
      if (mounted) {
        setState(() => _isProcessing = false);
        _showSnackBar("Không thể trích xuất chữ. Sơn kiểm tra lại Server nhé!", Colors.red);
      }
    }
  }

  // --- 2. LOGIC LƯU VÀO MICROSOFT ONEDRIVE (A3 MS FUSION) ---
  Future<void> _saveToOneDrive() async {
    if (_extractedText.isEmpty) return;

    if (!mounted) return;
    setState(() => _isProcessing = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('ms_access_token');
      
      if (token == null || token.isEmpty) {
        _showSnackBar("Sơn ơi, hãy kết nối OneDrive trước nhé!", Colors.orange);
        return;
      }

      List<dynamic> items = await _driveService.fetchItems(token, folderId: "root");
      String targetFolderId = "root";
      for (var item in items) {
        if (item['name'] == 'Tai_Lieu_Hoc_Tap' && item['folder'] != null) {
          targetFolderId = item['id'];
          break;
        }
      }

      String fullContent = "📌 KẾT QUẢ QUÉT TÀI LIỆU VINHUNI\n\n"
          "💡 Ý CHÍNH:\n${_keyPoints.map((e) => "- $e").join('\n')}\n\n"
          "📝 NỘI DUNG CHI TIẾT:\n$_extractedText";

      String fileName = "OCR_VinhUni_${DateTime.now().millisecondsSinceEpoch}.txt";
      List<int> bytes = utf8.encode(fullContent);

      bool success = await _driveService.uploadFileBytes(token, fileName, bytes, targetFolderId);

      if (mounted) {
        if (success) {
          _showSnackBar("✅ Đã cất tài liệu vào OneDrive thành công!", Colors.green);
        } else {
          _showSnackBar("Lưu thất bại, thử lại sau nhé!", Colors.red);
        }
      }
    } catch (e) {
      _showSnackBar("Lỗi Cloud: $e", Colors.red);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // --- 3. GIAO DIỆN ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("QUÉT TÀI LIỆU HỌC TẬP (AI)", 
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.green[800],
        centerTitle: true,
        elevation: 0,
      ),
      body: _isProcessing 
        ? Center(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.green), 
              const SizedBox(height: 15), 
              Text("AI A3 đang số hóa tài liệu cho Sơn...", style: const TextStyle(fontSize: 12, color: Colors.grey))
            ]
          ))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                if (_extractedText.isEmpty) _buildWelcomeUI(),
                if (_extractedText.isNotEmpty) ...[
                  _buildResultUI(),
                  const SizedBox(height: 30),
                  _buildActionButtons(),
                ],
              ],
            ),
          ),
    );
  }

  Widget _buildWelcomeUI() {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 80),
          Icon(Icons.camera_enhance_outlined, size: 100, color: Colors.green[100]),
          const SizedBox(height: 24),
          const Text("CHỤP GIÁO TRÌNH / TÀI LIỆU PDF",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          const SizedBox(height: 8),
          const Text("AI sẽ tự động chuyển ảnh thành văn bản sạch\nvà trích xuất ý chính cho bạn.",
            textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 48),
          ElevatedButton.icon(
            onPressed: _scanDocument,
            icon: const Icon(Icons.photo_camera, color: Colors.white),
            label: const Text("BẮT ĐẦU QUÉT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultUI() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.green, size: 18),
            SizedBox(width: 8),
            Text("Ý CHÍNH TỪ TÀI LIỆU:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _keyPoints.map((e) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.green.shade100)),
            child: Text(e.toString(), style: const TextStyle(fontSize: 11, color: Colors.green)),
          )).toList(),
        ),
        const SizedBox(height: 24),
        const Text("📝 NỘI DUNG VĂN BẢN SẠCH:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 13)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white, 
            borderRadius: BorderRadius.circular(15), 
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
            border: Border.all(color: Colors.grey.shade200)
          ),
          child: TextField(
            maxLines: 15,
            controller: _textController, // 🔥 Dùng Controller cố định
            style: const TextStyle(fontSize: 13, height: 1.5),
            decoration: const InputDecoration.collapsed(hintText: "Đang chờ dữ liệu..."),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _scanDocument,
            icon: const Icon(Icons.refresh),
            label: const Text("QUÉT LẠI"),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: BorderSide(color: Colors.grey.shade400),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _saveToOneDrive,
            icon: const Icon(Icons.cloud_upload, color: Colors.white),
            label: const Text("LƯU ONEDRIVE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: const TextStyle(fontSize: 12)), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }
}