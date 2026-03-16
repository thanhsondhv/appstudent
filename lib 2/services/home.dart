import 'package:flutter/material.dart';

class StudentService {
  List<Map<String, dynamic>> getFullMenu() {
    return [
      {'title': 'Lịch học', 'icon': Icons.calendar_today_rounded, 'color': 0xFF0054A6},
      {'title': 'Lịch thi', 'icon': Icons.assignment_rounded, 'color': 0xFFFF9800},
      {'title': 'Điểm danh', 'icon': Icons.how_to_reg_rounded, 'color': 0xFF4CAF50},
      {'title': 'Xem điểm', 'icon': Icons.analytics_rounded, 'color': 0xFF2196F3},
    ];
  }
}
