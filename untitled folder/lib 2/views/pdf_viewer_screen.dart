import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

class PdfViewerScreen extends StatelessWidget {
  final String url;
  final String title;

  const PdfViewerScreen({super.key, required this.url, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          title, 
          style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold)
        ),
        backgroundColor: const Color(0xFF0054A6),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SfPdfViewer.network(
        url,
        // Xử lý khi load file thất bại (ví dụ link lỗi hoặc server chết)
        onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Không thể tải văn bản: ${details.description}")),
          );
        },
      ),
    );
  }
}