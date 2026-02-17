import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import '../widgets/face_scanner_overlay.dart';

enum ScanState { initial, far, near, hold, processing }

class FaceScanProScreen extends StatefulWidget {
  const FaceScanProScreen({super.key});
  @override
  State<FaceScanProScreen> createState() => _FaceScanProScreenState();
}

class _FaceScanProScreenState extends State<FaceScanProScreen> with SingleTickerProviderStateMixin {
  CameraController? _controller;
  late AnimationController _animController;
  
  ScanState _currentState = ScanState.initial;
  String _guideText = "ĐANG KHỞI TẠO...";
  Color _statusColor = Colors.white;
  
  File? _farFile;
  File? _nearFile;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _animController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    // iPhone 7 sử dụng Camera trước (index 1)
    _controller = CameraController(cameras[1], ResolutionPreset.high, enableAudio: false);
    await _controller!.initialize();
    if (mounted) {
      setState(() {
        _currentState = ScanState.far;
        _guideText = "XÁC ĐỊNH VÙNG MẶT (XA)";
      });
      _runAutoAuth();
    }
  }

  // Luồng tự động: Xa -> Gần -> Giữ nguyên -> Chụp
  void _runAutoAuth() async {
    // Bước 1: Chụp ảnh XA (đảm bảo mặt nằm trong khung)
    await Future.delayed(const Duration(seconds: 3)); // Tăng thời gian hướng dẫn
    if (!mounted) return;
    
    await HapticFeedback.lightImpact();
    final farImg = await _controller!.takePicture();
    
    setState(() {
      _farFile = File(farImg.path);
      _currentState = ScanState.near;
      _guideText = "VUI LÒNG TIẾN LẠI GẦN...";
      _statusColor = Colors.blueAccent;
    });

    // Bước 2: Chờ người dùng tiến lại gần (Cần sự thay đổi kích thước mặt > 12%)
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    setState(() {
      _currentState = ScanState.hold;
      _guideText = "GIỮ NGUYÊN VỊ TRÍ...";
      _statusColor = Colors.greenAccent; // Chuyển xanh khi vùng mặt đạt yêu cầu
    });

    // Bước 3: Chụp ảnh GẦN sau khi giữ nguyên để tránh nhòe
    await Future.delayed(const Duration(seconds: 1));
    await HapticFeedback.mediumImpact();
    final nearImg = await _controller!.takePicture();

    setState(() {
      _nearFile = File(nearImg.path);
      _currentState = ScanState.processing;
      _guideText = "ĐANG ĐỐI KHỚP VECTOR...";
    });

    // Trả kết quả về LoginScreen để gửi lên FastAPI
    if (mounted) {
      Navigator.pop(context, {'front': _farFile, 'pose': _nearFile});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) return const Scaffold(backgroundColor: Colors.black);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          CameraPreview(_controller!),
          // Overlay vòng tròn lớn hơn để tránh lỗi "mặt nhỏ"
          AnimatedBuilder(
            animation: _animController,
            builder: (context, child) => CustomPaint(
              size: MediaQuery.of(context).size,
              painter: FaceScannerOverlay(
                progress: _animController.value, 
                borderColor: _statusColor,
                radius: 160.0, // Tăng bán kính khung quét
              ),
            ),
          ),
          Positioned(
            bottom: 120, left: 0, right: 0,
            child: Column(
              children: [
                Text(_guideText, textAlign: TextAlign.center, 
                  style: TextStyle(color: _statusColor, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                if (_currentState == ScanState.near)
                  const Icon(Icons.arrow_upward, color: Colors.blueAccent, size: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _animController.dispose();
    super.dispose();
  }
}