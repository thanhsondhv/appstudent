import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_helper.dart'; // File helper Sơn gửi mình
import '../../core/api/api.dart';

class SendAllSchoolScreen extends StatefulWidget {
  const SendAllSchoolScreen({super.key});

  @override
  State<SendAllSchoolScreen> createState() => _SendAllSchoolScreenState();
}

class _SendAllSchoolScreenState extends State<SendAllSchoolScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  
  String _targetType = "ALL"; // Mặc định: Tất cả
  bool _isLoading = false;

  // Hàm xử lý gửi thông báo
  Future<void> _handleSend() async {
    if (_titleController.text.isEmpty || _contentController.text.isEmpty) {
      NotificationHelper.showSnack(context, "Vui lòng điền đủ tiêu đề và nội dung!", Colors.orange);
      return;
    }

    // --- HIỆN DIALOG XÁC NHẬN (Cực kỳ quan trọng cho Admin) ---
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Xác nhận gửi"),
        content: Text("Bạn có chắc chắn muốn gửi thông báo này tới TOÀN TRƯỜNG (${_targetType == 'ALL' ? 'Tất cả' : _targetType == 'STUDENT' ? 'Sinh viên' : 'Cán bộ'}) không?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Hủy")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text("Gửi ngay")
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final senderId = prefs.getString('user_id') ?? "Admin";

      final response = await Api.post(
        "/api/admin/send-notification-all",
        duLieu: {
          "title": _titleController.text,
          "content": _contentController.text,
          "sender_id": senderId,
          "target_type": _targetType,
        },
      );

      if (!response.thanhCong) {
        // Sửa 18/08/2026: bản cũ đọc thẳng resData['status'] nên khi máy chủ
        // trả 500 kèm nội dung không phải JSON thì ném ngoại lệ, người gửi
        // không biết thông báo đã đi hay chưa.
        if (context.mounted) {
          NotificationHelper.showSnack(context, response.thongDiepLoi, Colors.red);
        }
        return;
      }

      final resData = response.data is Map ? response.data as Map : const {};
      if (resData['status'] == 'success') {
        NotificationHelper.showSnack(context, "Đã đưa thông báo vào hàng đợi gửi!", Colors.green);
        _titleController.clear();
        _contentController.clear();
      } else {
        NotificationHelper.showSnack(context, "Lỗi: ${resData['message']}", Colors.red);
      }
    } catch (e) {
      NotificationHelper.showSnack(context, "Lỗi kết nối Server!", Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: NotificationHelper.vinhUniBlue,
        title: const Text("GỬI TOÀN TRƯỜNG", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white), onPressed: () => Navigator.pop(context)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NotificationHelper.buildLabel("Đối tượng nhận tin"),
            _buildTargetSelector(),
            
            const SizedBox(height: 20),
            NotificationHelper.buildLabel("Tiêu đề thông báo"),
            TextField(
              controller: _titleController,
              decoration: NotificationHelper.inputDecor("Nhập tiêu đề ngắn gọn...", Icons.title),
            ),
            
            const SizedBox(height: 20),
            NotificationHelper.buildLabel("Nội dung chi tiết"),
            TextField(
              controller: _contentController,
              maxLines: 6,
              decoration: NotificationHelper.inputDecor("Nhập nội dung thông báo...", Icons.message_outlined),
            ),
            
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _handleSend,
                icon: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.send_rounded, color: Colors.white),
                label: Text(_isLoading ? "ĐANG XỬ LÝ..." : "GỬI TOÀN TRƯỜNG", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: NotificationHelper.vinhUniBlue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 5
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Widget chọn đối tượng (ALL / STUDENT / STAFF)
  Widget _buildTargetSelector() {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(15)),
      child: Row(
        children: [
          _targetChip("Tất cả", "ALL"),
          _targetChip("Sinh viên", "STUDENT"),
          _targetChip("Cán bộ", "STAFF"),
        ],
      ),
    );
  }

  Widget _targetChip(String label, String value) {
    bool isSelected = _targetType == value;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _targetType = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? NotificationHelper.vinhUniBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.black54,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13
              ),
            ),
          ),
        ),
      ),
    );
  }
}