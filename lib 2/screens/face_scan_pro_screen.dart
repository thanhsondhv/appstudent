//face_scan_pro_screen.dart
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
  bool _isCameraInitialized = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _animController = AnimationController(
      vsync: this, 
      duration: const Duration(seconds: 2)
    )..repeat();
  }

  // --- HÀM KHỞI TẠO CAMERA AN TOÀN ---
  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception("Không tìm thấy Camera");

      // Khởi tạo Camera trước (index 1 trên iPhone)
      _controller = CameraController(
        cameras[1], 
        ResolutionPreset.high, 
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg, // Tối ưu cho iOS để tránh lỗi ảnh
      );

      await _controller!.initialize();

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
          _currentState = ScanState.far;
          _guideText = "XÁC ĐỊNH VÙNG MẶT (XA)";
        });
        _runAutoAuth();
      }
    } catch (e) {
      // 🔥 XỬ LÝ LỖI: Nếu từ chối quyền hoặc lỗi phần cứng, thoát ngay lập tức
      debugPrint("❌ Lỗi khởi tạo Camera: $e");
      if (mounted) {
        // Trả về null để Login Screen biết là không có ảnh
        Navigator.pop(context); 
        
        // Thông báo cho người dùng biết lý do thoát
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("VinhUni cần quyền Camera để nhận diện. Vui lòng bật trong Cài đặt."),
            backgroundColor: Colors.redAccent,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _runAutoAuth() async {
    try {
      // Bước 1: Chụp ảnh XA
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted || _controller == null || !_controller!.value.isInitialized) return;
      
      await HapticFeedback.lightImpact();
      final farImg = await _controller!.takePicture();
      
      if (mounted) {
        setState(() {
          _farFile = File(farImg.path);
          _currentState = ScanState.near;
          _guideText = "VUI LÒNG TIẾN LẠI GẦN...";
          _statusColor = Colors.blueAccent;
        });
      }

      // Bước 2: Chờ người dùng tiến lại gần
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;

      setState(() {
        _currentState = ScanState.hold;
        _guideText = "GIỮ NGUYÊN VỊ TRÍ...";
        _statusColor = Colors.greenAccent;
      });

      // Bước 3: Chụp ảnh GẦN
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || _controller == null || !_controller!.value.isInitialized) return;

      await HapticFeedback.mediumImpact();
      final nearImg = await _controller!.takePicture();

      if (mounted) {
        setState(() {
          _nearFile = File(nearImg.path);
          _currentState = ScanState.processing;
          _guideText = "ĐANG ĐỐI KHỚP VECTOR...";
        });
        
        // Trả kết quả về LoginScreen
        Navigator.pop(context, {'front': _farFile, 'pose': _nearFile});
      }
    } catch (e) {
      debugPrint("❌ Lỗi trong quá trình quét: $e");
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Nếu chưa khởi tạo xong, hiện Loading thay vì màn hình đen
    if (!_isCameraInitialized || _controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 20),
              Text("Đang mở Camera...", style: TextStyle(color: Colors.white))
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Preview Camera
          SizedBox.expand(child: CameraPreview(_controller!)),
          
          // Overlay vòng tròn quét mặt
          AnimatedBuilder(
            animation: _animController,
            builder: (context, child) => CustomPaint(
              size: MediaQuery.of(context).size,
              painter: FaceScannerOverlay(
                progress: _animController.value, 
                borderColor: _statusColor,
                radius: 160.0,
              ),
            ),
          ),

          // Nút Hủy để thoát nếu không muốn quét nữa
          Positioned(
            top: 50,
            right: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // Chỉ dẫn phía dưới
          Positioned(
            bottom: 100, left: 0, right: 0,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20)
                  ),
                  child: Text(_guideText, textAlign: TextAlign.center, 
                    style: TextStyle(color: _statusColor, fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 20),
                if (_currentState == ScanState.near)
                  const Icon(Icons.expand_more, color: Colors.blueAccent, size: 50),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // 🔥 GIẢI PHÓNG CAMERA NGAY ĐỂ TRÁNH ĐEN MÀN HÌNH LẦN SAU
    _controller?.dispose();
    _animController.dispose();
    super.dispose();
  }
}