import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinhuni_app/views/secretary/secretary_service.dart';
import 'package:vinhuni_app/services/onedrive_service.dart';

class StudentSecretaryScreen extends StatefulWidget {
  const StudentSecretaryScreen({super.key});

  @override
  State<StudentSecretaryScreen> createState() => _StudentSecretaryScreenState();
}

class _StudentSecretaryScreenState extends State<StudentSecretaryScreen> {
  final _service = SecretaryService();
  final _driveService = OneDriveService();
  
  bool _isRecording = false;
  bool _isProcessing = false;
  String _studentName = "Sinh viên"; // Tên mặc định

  String _liveRawText = "";        
  String _preparedLecture = "";    // Đổi từ Summary thành Soạn bài
  List<dynamic> _keyConcepts = []; 

  @override
  void initState() {
    super.initState();
    _loadStudentInfo();
    _service.initLiveSTT(); 
  }

  // Lấy tên sinh viên thực tế từ máy
  Future<void> _loadStudentInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _studentName = prefs.getString('user_name') ?? "Sinh viên";
    });
  }

  @override
  void dispose() {
    if (_isRecording) {
      _service.stopAndUpload(
        rawText: _liveRawText, 
        role: 'sinhvien',
        userName: _studentName,
      ); 
    }
    super.dispose();
  }

  void _safeState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  // --- 1. LOGIC SOẠN BÀI GIẢNG AI (A3 FUSION) ---
  Future<void> _handleRecording() async {
    if (!_isRecording) {
      _safeState(() { 
        _isRecording = true; 
        _liveRawText = ""; 
        _preparedLecture = "";
      });

      try {
        await _service.start(onLiveResult: (text) {
          _safeState(() => _liveRawText = text);
        });
      } catch (e) {
        _showSnackBar("Lỗi mic: $e", Colors.red);
        _safeState(() => _isRecording = false);
      }
    } else {
      _safeState(() { 
        _isRecording = false; 
        _isProcessing = true; 
      });
      
      try {
        // Gửi lệnh soạn bài dựa trên vai trò sinh viên
        final res = await _service.stopAndUpload(
          rawText: _liveRawText, 
          role: 'sinhvien',
          userName: _studentName,
        ); 

        if (!mounted) return; 

        if (res != null && res['status'] == 'success') {
          final data = res['data'];
          _safeState(() {
            _preparedLecture = data['summary'] ?? "Hệ thống chưa đủ dữ liệu để soạn bài.";
            _keyConcepts = data['tasks'] ?? [];
            _isProcessing = false;
          });
        } else {
          _safeState(() => _isProcessing = false);
          _showSnackBar("AI đang bận, bạn vui lòng thử lại nhé!", Colors.orange);
        }
      } catch (e) {
        _safeState(() => _isProcessing = false);
        _showSnackBar("Lỗi kết nối Server A3", Colors.red);
      }
    }
  }

  // --- 2. LƯU TÀI LIỆU SOẠN THẢO VÀO ONEDRIVE ---
  Future<void> _saveToCloud() async {
    if (_preparedLecture.isEmpty) return;
    
    _safeState(() => _isProcessing = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('ms_access_token');
      
      if (token == null || token.isEmpty) {
        _showSnackBar("Vui lòng kết nối OneDrive trước khi lưu!", Colors.orange);
        return;
      }

      List<dynamic> rootItems = await _driveService.fetchItems(token, folderId: "root");
      String targetFolderId = "root"; 
      for (var item in rootItems) {
        if (item['name'] == 'Tai_Lieu_Hoc_Tap' && item['folder'] != null) {
          targetFolderId = item['id'];
          break;
        }
      }

      String content = _service.formatForStudent({
        'summary': _preparedLecture,
        'clean_text': _liveRawText,
        'tasks': _keyConcepts,
      });

      String fileName = "Soan_Bai_VinhUni_${DateTime.now().millisecondsSinceEpoch}.txt";
      List<int> bytes = utf8.encode(content);

      bool success = await _driveService.uploadFileBytes(token, fileName, bytes, targetFolderId);

      if (mounted) {
        if (success) {
          _showSnackBar("✅ Đã lưu tài liệu soạn thảo thành công!", Colors.green);
        } else {
          _showSnackBar("Lưu thất bại, bạn kiểm tra lại OneDrive nhé!", Colors.red);
        }
      }
    } catch (e) {
      _showSnackBar("Lỗi hệ thống: $e", Colors.red);
    } finally {
      _safeState(() => _isProcessing = false);
    }
  }

  // --- 3. GIAO DIỆN ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F0),
      appBar: AppBar(
        title: const Text("SOẠN BÀI GIẢNG THÔNG MINH", 
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.orange[800],
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text("Chào $_studentName, AI đang sẵn sàng hỗ trợ bạn soạn bài.", 
              style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold)),
            const SizedBox(height: 40),
            
            if (_isRecording) _buildLiveTranscriptBox(),
            
            const SizedBox(height: 30),
            _buildMicButton(),
            const SizedBox(height: 40),
            
            if (_isProcessing) _buildProcessingLoader(),
            
            if (_preparedLecture.isNotEmpty && !_isProcessing) ...[
              _buildSaveButton(),
              const SizedBox(height: 20),
              _buildLectureCard(),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildLiveTranscriptBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.orange.shade100)),
      child: Column(children: [
        const Text("🎤 ĐANG GHI NHẬN NỘI DUNG GIẢNG DẠY...", style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text(_liveRawText.isEmpty ? "Đang chờ tín hiệu..." : _liveRawText, 
          style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey, fontSize: 13), textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _buildMicButton() {
    return GestureDetector(
      onTap: _isProcessing ? null : _handleRecording,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: _isRecording ? Colors.red.withOpacity(0.1) : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: _isRecording ? Colors.red : Colors.orange.shade800, width: _isRecording ? 6 : 4),
          boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.1), blurRadius: 20)],
        ),
        child: Icon(_isRecording ? Icons.stop_rounded : Icons.mic_rounded, size: 50, color: _isRecording ? Colors.red : Colors.orange[800]),
      ),
    );
  }

  Widget _buildProcessingLoader() {
    return Center(child: Column(children: [
      const CircularProgressIndicator(color: Colors.orange), 
      const SizedBox(height: 15), 
      Text("AI A3 đang soạn bài cho $_studentName...", style: const TextStyle(fontSize: 12, color: Colors.grey))
    ]));
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 12)),
        onPressed: _saveToCloud, 
        icon: const Icon(Icons.cloud_upload_rounded, color: Colors.white), 
        label: const Text("LƯU BÀI SOẠN VÀO ONEDRIVE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
      ),
    );
  }

  Widget _buildLectureCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.orange.shade100)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [Icon(Icons.edit_note, color: Colors.orange, size: 24), SizedBox(width: 8), Text("NỘI DUNG SOẠN THẢO", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 13))]),
          const SizedBox(height: 15),
          Text(_preparedLecture, style: const TextStyle(height: 1.6, fontSize: 14)),
          const Divider(height: 40),
          const Row(children: [Icon(Icons.psychology_alt, color: Colors.blueAccent, size: 20), SizedBox(width: 8), Text("CÂU HỎI TỰ ÔN TẬP", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent, fontSize: 13))]),
          const SizedBox(height: 15),
          ..._keyConcepts.map((e) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("❓ ", style: TextStyle(color: Colors.orange)), Expanded(child: Text(e.toString(), style: const TextStyle(fontSize: 13)))]))).toList(),
        ],
      ),
    );
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)));
  }
}