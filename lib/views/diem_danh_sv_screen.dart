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
  final int pinLength = 6;
  final List<TextEditingController> _controllers = List.generate(6, (i) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (i) => FocusNode());
  bool _isLoading = false;
  final Color vinhUniBlue = const Color(0xFF0054A6);

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    for (var n in _focusNodes) {
      n.dispose();
    }
    super.dispose();
  }

  // --- 1. XỬ LÝ NHẬP LIỆU TỪNG Ô ---
  void _onPinChanged(String value, int index) {
    if (value.length == 1 && index < pinLength - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }

    String currentPin = _controllers.map((e) => e.text).join();
    if (currentPin.length == pinLength) {
      _handleAttendanceSubmit(currentPin);
    }
  }

  // --- 2. XÁC THỰC SINH TRẮC HỌC & GỬI ĐIỂM DANH ---
  Future<void> _handleAttendanceSubmit(String pin) async {
    setState(() => _isLoading = true);
    final LocalAuthentication auth = LocalAuthentication();

    try {
      // A. Lấy tọa độ GPS thực tế
      Position position = await _determinePosition();

      // B. Xác thực vân tay/khuôn mặt tại máy local (Tránh nghẽn server)
      bool didAuthenticate = await auth.authenticate(
        localizedReason: 'Vui lòng xác thực chính chủ để điểm danh',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );

      if (!didAuthenticate) {
        _showSnackBar("Xác thực sinh trắc học thất bại!", Colors.red);
        return;
      }

      // C. Gửi dữ liệu lên Server (attendance_router.py)
      final response = await http.post(
        Uri.parse("https://mobi.vinhuni.edu.vn/api/attendance/submit"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "student_id": widget.studentId,
          "code": pin,
          "lat": position.latitude,
          "lon": position.longitude,
          "is_biometric_valid": true // Đã xác thực thành công tại máy local
        }),
      );

      final resData = jsonDecode(response.body);
      if (resData['status'] == 'success') {
        _showSuccessDialog(resData['message']);
      } else {
        _showSnackBar(resData['message'], Colors.red);
        _clearPin();
      }
    } catch (e) {
      _showSnackBar("Lỗi: ${e.toString()}", Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- 3. HÀM LẤY TỌA ĐỘ GPS ---
  Future<Position> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return Future.error('Vui lòng bật GPS trên thiết bị!');

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return Future.error('Quyền truy cập vị trí bị từ chối!');
    }
    return await Geolocator.getCurrentPosition();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("ĐIỂM DANH MÃ PIN", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: vinhUniBlue,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          children: [
            const SizedBox(height: 20),
            const Icon(Icons.fingerprint_rounded, size: 80, color: Color(0xFF0054A6)),
            const SizedBox(height: 20),
            const Text("Nhập mã PIN điểm danh", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text("Mã PIN gồm 6 chữ số được giảng viên cung cấp", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 50),

            // --- HÀNG 6 Ô NHẬP PIN ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(6, (index) => _buildPinBox(index)),
            ),

            const SizedBox(height: 60),
            if (_isLoading) 
              const CircularProgressIndicator()
            else
              const Text("Hệ thống sẽ tự động xác thực sau khi nhập đủ 6 số", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.blueGrey, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildPinBox(int index) {
    return SizedBox(
      width: 45,
      child: TextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        autofocus: index == 0,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: vinhUniBlue),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          counterText: "",
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: vinhUniBlue, width: 2)),
        ),
        onChanged: (v) => _onPinChanged(v, index),
      ),
    );
  }

  void _clearPin() {
    for (var c in _controllers) {
      c.clear();
    }
    _focusNodes[0].requestFocus();
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  void _showSuccessDialog(String msg) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Icon(Icons.check_circle, color: Colors.green, size: 60),
        content: Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text("HOÀN TẤT", style: TextStyle(color: Colors.white)),
            ),
          )
        ],
      ),
    );
  }
}