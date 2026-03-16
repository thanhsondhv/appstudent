import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:local_auth/local_auth.dart';

class DiemDanhSvScreen extends StatefulWidget {
  final String studentId;
  const DiemDanhSvScreen({super.key, required this.studentId});

  @override
  State<DiemDanhSvScreen> createState() => _DiemDanhSvScreenState();
}

class _DiemDanhSvScreenState extends State<DiemDanhSvScreen> {
  // 🔥 CHỐT: 4 SỐ CHO NHANH
  final int pinLength = 4;
  final List<TextEditingController> _controllers = List.generate(4, (i) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(4, (i) => FocusNode());
  
  bool _isLoading = false;
  final Color vinhUniBlue = const Color(0xFF0054A6);

  @override
  void dispose() {
    for (var c in _controllers) c.dispose();
    for (var n in _focusNodes) n.dispose();
    super.dispose();
  }

  // --- 1. XỬ LÝ NHẬP LIỆU TỰ ĐỘNG ---
  void _onPinChanged(String value, int index) {
    // Tự động sang ô tiếp theo
    if (value.length == 1 && index < pinLength - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    // Tự động quay lại khi xóa (Backspace)
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }

    // Kiểm tra nếu đã nhập đủ 4 số thì tự động gửi
    String currentPin = _controllers.map((e) => e.text).join();
    if (currentPin.length == pinLength) {
      _handleAttendanceSubmit(currentPin);
    }
  }

  // --- 2. XÁC THỰC & GỬI DỮ LIỆU ---
  Future<void> _handleAttendanceSubmit(String pin) async {
    setState(() => _isLoading = true);
    final LocalAuthentication auth = LocalAuthentication();

    try {
      // A. Lấy tọa độ GPS (Đảm bảo SV đang ở gần lớp)
      Position position = await _determinePosition();

      // B. Xác thực Sinh trắc học (FaceID/Vân tay)
      bool didAuthenticate = await auth.authenticate(
        localizedReason: 'Xác thực chính chủ để hoàn tất điểm danh',
        options: const AuthenticationOptions(
          biometricOnly: true, 
          stickyAuth: true
        ),
      );

      if (!didAuthenticate) {
        _showSnackBar("Xác thực thất bại! Vui lòng thử lại.", Colors.orange);
        _clearPin();
        return;
      }

      // C. Gọi API Backend (Sơn nhớ đổi URL nếu chạy thật nhé)
      final response = await http.post(
        Uri.parse("https://mobi.vinhuni.edu.vn/api/attendance/submit"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "student_id": widget.studentId,
          "code": pin,
          "lat": position.latitude,
          "lon": position.longitude,
          "is_biometric_valid": true 
        }),
      );

      final resData = jsonDecode(response.body);
      
      if (resData['status'] == 'success') {
        _showSuccessDialog("Hệ thống đã ghi nhận bạn có mặt!");
      } else {
        _showSnackBar(resData['message'] ?? "Mã PIN không đúng", Colors.red);
        _clearPin();
      }
    } catch (e) {
      _showSnackBar("Lỗi kết nối: ${e.toString()}", Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- 3. HÀM KIỂM TRA GPS ---
  Future<Position> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return Future.error('Vui lòng bật định vị GPS!');

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return Future.error('Quyền vị trí bị từ chối!');
    }
    // Lấy vị trí với độ chính xác cao
    return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  }

  // --- 4. GIAO DIỆN CHÍNH ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("ĐIỂM DANH SINH VIÊN", 
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: vinhUniBlue,
        centerTitle: true,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30.0),
          child: Column(
            children: [
              const SizedBox(height: 40),
              // Icon minh họa
              const Icon(Icons.security_update_good_rounded, size: 100, color: Color(0xFF0054A6)),
              const SizedBox(height: 20),
              const Text("Xác nhận có mặt", 
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87)),
              const SizedBox(height: 10),
              const Text(
                "Nhập mã PIN 4 số từ giảng viên để xác thực vị trí và sinh trắc học của bạn.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 50),

              // --- HÀNG 4 Ô NHẬP PIN ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(4, (index) => _buildPinBox(index)),
              ),

              const SizedBox(height: 60),
              if (_isLoading)
                Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 15),
                    Text("Đang xử lý dữ liệu...", style: TextStyle(color: vinhUniBlue, fontSize: 13)),
                  ],
                )
              else
                const Text(
                  "Tự động xác thực sau khi nhập đủ 4 số",
                  style: TextStyle(fontStyle: FontStyle.italic, color: Colors.blueGrey, fontSize: 12),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGET Ô NHẬP PIN LẺ ---
  Widget _buildPinBox(int index) {
    return SizedBox(
      width: 60, // Ô PIN 4 số sẽ to hơn ô 6 số cho dễ bấm
      height: 70,
      child: TextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        autofocus: index == 0,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: vinhUniBlue),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly, // Chỉ cho nhập số
        ],
        decoration: InputDecoration(
          counterText: "",
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: Colors.grey.shade300, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: vinhUniBlue, width: 2.5),
          ),
          fillColor: Colors.grey.shade50,
          filled: true,
        ),
        onChanged: (v) => _onPinChanged(v, index),
      ),
    );
  }

  // --- CÁC HÀM TIỆN ÍCH ---
  void _clearPin() {
    for (var c in _controllers) c.clear();
    _focusNodes[0].requestFocus();
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  void _showSuccessDialog(String msg) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Column(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 80),
            SizedBox(height: 15),
            Text("Thành công!", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(msg, textAlign: TextAlign.center),
        actions: [
          Center(
            child: TextButton(
              onPressed: () {
                Navigator.pop(ctx); // Đóng Dialog
                Navigator.pop(context); // Quay về Home
              },
              child: const Text("XÁC NHẬN", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }
}