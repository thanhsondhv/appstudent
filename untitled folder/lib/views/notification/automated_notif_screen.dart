import 'package:flutter/material.dart';
import 'notification_helper.dart';

class AutomatedNotifScreen extends StatefulWidget {
  // 💡 Xóa 'const' ở đây để tránh lỗi hằng số khi gọi từ Portal
  AutomatedNotifScreen({super.key});

  @override
  State<AutomatedNotifScreen> createState() => _AutomatedNotifScreenState();
}

class _AutomatedNotifScreenState extends State<AutomatedNotifScreen> {
  bool _autoBirthday = true;
  bool _autoHoliday = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text("TỰ ĐỘNG & SỰ KIỆN", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: NotificationHelper.vinhUniBlue,
        centerTitle: true,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context)
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle("Cài đặt tự động"),
            _buildAutoCard("Chúc mừng Sinh nhật", "Gửi tin nhắn cá nhân hóa vào đúng ngày sinh của SV/GV.", Icons.cake_rounded, Colors.pink, _autoBirthday, (v) => setState(() => _autoBirthday = v)),
            _buildAutoCard("Ngày lễ trong năm", "Tự động gửi lời chúc vào 20/11, Tết, 8/3...", Icons.celebration_rounded, Colors.orange, _autoHoliday, (v) => setState(() => _autoHoliday = v)),
            
            const SizedBox(height: 25),
            _buildSectionTitle("Thư viện mẫu chuyên nghiệp"),
            
            // ✅ Đã thay các Icon lỗi bằng Icon chuẩn hoặc String
            _buildTemplateItem("Mẫu 20/11 (Cán bộ)", "Tri ân người lái đò thầm lặng...", Icons.auto_awesome),
            _buildTemplateItem("Mẫu Tết Nguyên Đán", "Cung chúc tân xuân, vạn sự như ý...", "🧧"), // Truyền String "🧧" thì OK
            _buildTemplateItem("Mẫu Nhắc đóng học phí", "Thông báo gia hạn đóng học phí kỳ 2.1...", Icons.account_balance_wallet),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoCard(String title, String sub, IconData icon, Color color, bool value, Function(bool) onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text(sub, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged, activeColor: NotificationHelper.vinhUniBlue)
        ],
      ),
    );
  }

  Widget _buildTemplateItem(String title, String desc, dynamic iconData) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: iconData is IconData 
          ? Icon(iconData, color: Colors.blueGrey) 
          : Text(iconData.toString(), style: const TextStyle(fontSize: 20)),
        title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text(desc, style: const TextStyle(fontSize: 11)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
        onTap: () {},
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 5),
      child: Text(title.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1.2)),
    );
  }
}