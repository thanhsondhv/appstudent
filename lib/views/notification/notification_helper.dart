import 'package:flutter/material.dart';

// ✅ ĐỊNH NGHĨA MODEL DÙNG CHUNG
class UserSearchModel {
  final String id, name, info;
  UserSearchModel({required this.id, required this.name, required this.info});
  
  factory UserSearchModel.fromJson(Map<String, dynamic> json) => UserSearchModel(
    id: json['id']?.toString() ?? json['ma_sv']?.toString() ?? '', 
    name: json['name']?.toString() ?? json['ho_ten']?.toString() ?? 'Không tên', 
    info: json['info']?.toString() ?? ''
  );
}

class NotificationHelper {
  static const Color vinhUniBlue = Color(0xFF0054A6);

  // --- WIDGET GIAO DIỆN CHUNG ---

  static Widget buildLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 10),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey)),
  );

  static InputDecoration inputDecor(String hint, IconData icon, {Color? color}) => InputDecoration(
    hintText: hint,
    prefixIcon: Icon(icon, color: color ?? vinhUniBlue, size: 20),
    filled: true,
    fillColor: const Color(0xFFF1F5F9),
    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 15),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: vinhUniBlue)),
  );

  static Widget buildDropdown({
    required String hint,
    required List<String> items,
    required String? value,
    required Function(String?) onChanged,
    String Function(String)? displayFunc,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true, 
          hint: Text(hint, style: const TextStyle(fontSize: 13)),
          value: items.contains(value) ? value : null,
          items: items.map((e) => DropdownMenuItem(
            value: e, 
            child: Text(
              displayFunc != null ? displayFunc(e) : e, 
              style: const TextStyle(fontSize: 13), 
              maxLines: 1, 
              overflow: TextOverflow.ellipsis
            )
          )).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  // 🔥 HÀM THÔNG BÁO SNACKBAR (Sơn cần thêm cái này để hết lỗi ở các file Screen)
  static void showSnack(BuildContext context, String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 13)), 
        backgroundColor: color, 
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}