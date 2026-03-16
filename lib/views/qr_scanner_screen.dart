import 'dart:io';
import 'package:flutter/material.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});
  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;

  @override
  void reassemble() {
    super.reassemble();
    if (Platform.isAndroid) controller?.pauseCamera();
    controller?.resumeCamera();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("QUÉT MÃ ĐIỂM DANH", style: TextStyle(color: Colors.white, fontSize: 16)),
        backgroundColor: const Color(0xFF0054A6),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white), onPressed: () => Navigator.pop(context)),
      ),
      body: Stack(
        children: [
          QRView(
            key: qrKey,
            onQRViewCreated: _onQRViewCreated,
            overlay: QrScannerOverlayShape(
              borderColor: Colors.orange, borderRadius: 10, borderLength: 30, borderWidth: 10, cutOutSize: 300,
            ),
          ),
          const Positioned(
            bottom: 100, left: 0, right: 0,
            child: Text("Đưa mã QR của giảng viên vào khung để điểm danh", textAlign: TextAlign.center, style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  void _onQRViewCreated(QRViewController controller) {
    this.controller = controller;
    controller.scannedDataStream.listen((scanData) {
      if (scanData.code != null) {
        controller.pauseCamera(); // Dừng cam ngay khi quét được
        Navigator.pop(context, scanData.code); // Trả mã về màn hình Home
      }
    });
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }
}