import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert'; 
import 'package:vinhuni_app/views/secretary/secretary_service.dart'; 
import 'package:vinhuni_app/services/onedrive_service.dart'; 

class MeetingRecorderScreen extends StatefulWidget {
  const MeetingRecorderScreen({super.key});
  @override
  State<MeetingRecorderScreen> createState() => _MeetingRecorderScreenState();
}

class _MeetingRecorderScreenState extends State<MeetingRecorderScreen> {
  final _service = SecretaryService(); 
  final _driveService = OneDriveService(); 
  
  bool _isRecording = false;
  bool _isProcessing = false;

  String _liveRawText = ""; 
  String _resultText = "Sẵn sàng ghi âm cuộc họp"; 
  String _summary = "";
  List<dynamic> _tasks = [];

  @override
  void initState() {
    super.initState();
    _service.initLiveSTT(); 
  }

  // 🔥 1. XUẤT FILE VÀ CHIA SẺ (Zalo/Mail)
  Future<void> _exportToDocx() async {
    try {
      setState(() => _isProcessing = true);
      final directory = await getApplicationDocumentsDirectory();
      final fileName = "Bien_ban_A3_${DateTime.now().millisecondsSinceEpoch}.txt";
      final file = File('${directory.path}/$fileName');

      // 🔥 FIX: Đổi tên hàm thành formatForStaff theo Service mới
      String content = _service.formatForStaff({
        'clean_text': _resultText,
        'summary': _summary,
        'tasks': _tasks,
      });

      await file.writeAsString(content);
      final box = context.findRenderObject() as RenderBox?;
      
      await Share.shareXFiles(
        [XFile(file.path)], 
        text: 'Biên bản họp từ Thư ký AI VinhUni (Team A3)',
        sharePositionOrigin: box!.localToGlobal(Offset.zero) & box.size
      );
      
      setState(() => _isProcessing = false);
    } catch (e) {
      setState(() => _isProcessing = false);
      _showSnackBar("Lỗi xuất file: $e", Colors.red);
    }
  }

  // 🔥 2. LƯU VÀO ONEDRIVE
  Future<void> _saveToOneDrive() async {
    if (_resultText.isEmpty && _liveRawText.isEmpty) {
      _showSnackBar("Không có nội dung để lưu!", Colors.orange);
      return;
    }
    
    setState(() => _isProcessing = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('ms_access_token');
      
      if (token == null || token.isEmpty) {
        _showSnackBar("Vui lòng kết nối OneDrive!", Colors.red);
        return;
      }

      List<dynamic> rootItems = await _driveService.fetchItems(token, folderId: "root");
      String targetFolderId = "root"; 

      for (var item in rootItems) {
        if (item['name'] == 'Nhat_Ky_AI' && item['folder'] != null) {
          targetFolderId = item['id'];
          break;
        }
      }

      // 🔥 FIX: Đổi tên hàm thành formatForStaff
      String content = _service.formatForStaff({
        'clean_text': _resultText.isNotEmpty ? _resultText : _liveRawText,
        'summary': _summary.isNotEmpty ? _summary : "Ghi chép nhanh (Chưa có tóm tắt)",
        'tasks': _tasks,
      });

      String fileName = "Bien_Ban_A3_${DateTime.now().millisecondsSinceEpoch}.txt";
      List<int> bytes = utf8.encode(content);

      bool success = await _driveService.uploadFileBytes(token, fileName, bytes, targetFolderId);

      if (success) {
        _showSnackBar("✅ Đã lưu vào OneDrive thành công!", Colors.green);
      } else {
        throw Exception("Upload thất bại");
      }
    } catch (e) {
      _showSnackBar("Lỗi lưu Cloud: $e", Colors.red);
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text("THƯ KÝ AI [CAN BO]", 
          style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0054A6),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            if (_isRecording) 
              const Text("🔴 Đang xử lý Live Transcript...", 
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
            
            const SizedBox(height: 30),

            GestureDetector(
              onTap: _isProcessing ? null : () async {
                if (!_isRecording) {
                  setState(() { 
                    _isRecording = true; 
                    _liveRawText = "";
                    _resultText = "Đang lắng nghe..."; 
                    _summary = "";
                  });
                  await _service.start(onLiveResult: (text) {
                    setState(() => _liveRawText = text);
                  });
                } else {
                  setState(() { _isRecording = false; _isProcessing = true; });

                  // 🔥 FIX QUAN TRỌNG: Truyền rawText và role chuẩn
                  final result = await _service.stopAndUpload(
                    rawText: _liveRawText, 
                    role: 'CanBo'
                  ); 

                  setState(() {
                    _isProcessing = false;
                    if (result != null && result['status'] == 'success') {
                      final data = result['data']; 
                      _resultText = data['clean_text'] ?? "";
                      _summary = data['summary'] ?? "";
                      _tasks = data['tasks'] ?? [];
                    } else {
                      _resultText = "Không nhận được phản hồi từ AI A3.";
                    }
                  });
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(25),
                decoration: BoxDecoration(
                  color: _isRecording ? Colors.red.withOpacity(0.1) : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: _isRecording ? Colors.red : const Color(0xFF0054A6), width: 3),
                ),
                child: Icon(_isRecording ? Icons.stop : Icons.mic, 
                  size: 55, color: _isRecording ? Colors.red : const Color(0xFF0054A6)),
              ),
            ),

            const SizedBox(height: 30),

            if (_isRecording)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.shade100)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("⚡ NHẬN DIỆN TRỰC TIẾP:", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue)),
                    const SizedBox(height: 8),
                    Text(_liveRawText.isEmpty ? "Đang bắt tín hiệu..." : _liveRawText),
                  ],
                ),
              ),

            if (!_isProcessing && _summary.isNotEmpty) ...[
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildTool(Icons.cloud_upload, "Lưu Cloud", _saveToOneDrive),
                  _buildTool(Icons.share, "Gửi Zalo", _exportToDocx),
                  _buildTool(Icons.copy, "Chép", () {
                    Clipboard.setData(ClipboardData(text: _resultText));
                    _showSnackBar("Đã chép", Colors.blue);
                  }),
                ],
              ),
            ],

            const SizedBox(height: 20),
            _buildResultCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isProcessing) 
            const Center(child: Column(children: [CircularProgressIndicator(), SizedBox(height: 10), Text("Team A3 đang xử lý..."),],)),
          
          if (!_isProcessing && _summary.isNotEmpty) ...[
            const Text("📌 TÓM TẮT BIÊN BẢN", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            const SizedBox(height: 8),
            Text(_summary, style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic, height: 1.5)),
            const Divider(height: 30),
          ],
          
          if (!_isProcessing) ...[
            const Text("📝 VĂN BẢN ĐÃ CHỈNH SỬA", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
            const SizedBox(height: 10),
            Text(_resultText, style: const TextStyle(fontSize: 15, height: 1.6)),
          ],

          if (!_isProcessing && _tasks.isNotEmpty) ...[
            const Divider(height: 30),
            const Text("✅ VIỆC CẦN LÀM", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
            const SizedBox(height: 10),
            ..._tasks.map((t) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text("• $t"))).toList(),
          ],
        ],
      ),
    );
  }

  Widget _buildTool(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(children: [Icon(icon, color: const Color(0xFF0054A6)), const SizedBox(height: 4), Text(label, style: const TextStyle(fontSize: 11))]),
    );
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }
}