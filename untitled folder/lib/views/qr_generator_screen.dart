import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart'; // Thư viện vừa thêm

class QRGeneratorScreen extends StatelessWidget {
  final String attendanceCode; // Mã PIN 6 số mà giảng viên vừa tạo
  final String className;

  const QRGeneratorScreen({
    super.key, 
    required this.attendanceCode, 
    required this.className
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("MÃ QR ĐIỂM DANH", style: TextStyle(color: Colors.white, fontSize: 16)),
        backgroundColor: const Color(0xFF0054A6),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              className.toUpperCase(),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0054A6)),
            ),
            const SizedBox(height: 10),
            const Text("Mời sinh viên quét mã để điểm danh"),
            const SizedBox(height: 30),
            
            // 🔥 ĐÂY LÀ NƠI VẼ MÃ QR
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15)],
              ),
              child: QrImageView(
                data: attendanceCode, // Dữ liệu chứa trong QR chính là mã PIN
                version: QrVersions.auto,
                size: 280.0,
                gapless: false,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF0054A6)),
                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
              ),
            ),
            
            const SizedBox(height: 30),
            Text(
              "MÃ PIN: $attendanceCode",
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 5),
            ),
            const SizedBox(height: 40),
            
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
              label: const Text("ĐÓNG MÀN HÌNH"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            )
          ],
        ),
      ),
    );
  }
}