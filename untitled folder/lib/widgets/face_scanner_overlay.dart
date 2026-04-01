import 'package:flutter/material.dart';
import 'dart:math' as math;

class FaceScannerOverlay extends CustomPainter {
  final double progress;
  final Color borderColor;
  final double radius; // Thêm tham số radius

  FaceScannerOverlay({required this.progress, this.borderColor = Colors.white, this.radius = 140});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withOpacity(0.7)..style = PaintingStyle.fill;

    // Đục lỗ tròn với bán kính linh hoạt
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(Rect.fromCircle(center: Offset(size.width / 2, size.height / 2 - 50), radius: radius))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);

    final borderPaint = Paint()
      ..color = borderColor // Sử dụng màu trạng thái (Trắng -> Xanh)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;

    canvas.drawCircle(Offset(size.width / 2, size.height / 2 - 50), radius, borderPaint);
  }
  
  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}