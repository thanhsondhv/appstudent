import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class BangDiemTongHopScreen extends StatefulWidget {
  const BangDiemTongHopScreen({super.key});

  @override
  State<BangDiemTongHopScreen> createState() => _BangDiemTongHopScreenState();
}

class _BangDiemTongHopScreenState extends State<BangDiemTongHopScreen> {
  final Color vinhUniBlue = const Color(0xFF0054A6);
  final Color backgroundLight = const Color(0xFFF8FAFF);

  bool isLoading = true;
  String? errorMessage;
  
  String currentUserId = "";
  String selectedProgramId = "ALL";
  List<Map<String, dynamic>> programList = [
    {"program_id": "ALL", "program_name": "Tất cả ngành học"}
  ];
  List<dynamic> transcriptData = [];

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    setState(() { isLoading = true; errorMessage = null; });
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? userId = prefs.getString('user_code') ?? prefs.getString('user_id'); 

      if (userId == null || userId.isEmpty) {
        setState(() { errorMessage = "Vui lòng đăng nhập!"; isLoading = false; });
        return;
      }
      currentUserId = userId;

      // 1. Tải danh sách ngành học cho Combobox
      await _fetchPrograms(currentUserId);
      
      // 2. Tải bảng điểm tổng hợp
      await _fetchTranscriptSummary(selectedProgramId);

    } catch (e) {
      setState(() { errorMessage = "Lỗi khởi tạo dữ liệu!"; isLoading = false; });
    }
  }

  Future<void> _fetchPrograms(String userId) async {
    try {
      // 🔥 ĐỔI IP Ở ĐÂY
      final url = 'https://mobi.vinhuni.edu.vn/api/student-programs/$userId'; 
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          programList = [
            {"program_id": "ALL", "program_name": "Tất cả ngành học"},
            ...data.map((e) => {
                  "program_id": e["program_id"].toString(),
                  "program_name": e["program_name"].toString()
                }).toList()
          ];
        });
      }
    } catch (e) { debugPrint("Lỗi tải DS ngành: $e"); }
  }

  Future<void> _fetchTranscriptSummary(String programId) async {
    setState(() => isLoading = true);
    try {
      // 🔥 ĐỔI IP Ở ĐÂY
      final url = 'https://mobi.vinhuni.edu.vn/api/transcript-summary/$currentUserId?program_id=$programId';
      
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          transcriptData = data;
          isLoading = false;
        });
      } else {
        setState(() { transcriptData = []; isLoading = false; });
      }
    } catch (e) {
      setState(() { errorMessage = "Lỗi tải bảng điểm!"; isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundLight,
      appBar: AppBar(
        title: const Text("BẢNG ĐIỂM TỔNG HỢP", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
        backgroundColor: vinhUniBlue,
        centerTitle: true,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: isLoading
                ? Center(child: CircularProgressIndicator(color: vinhUniBlue))
                : errorMessage != null
                ? _buildErrorView()
                : _buildDataTable(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
        boxShadow: [BoxShadow(color: vinhUniBlue.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Lọc theo chương trình đào tạo", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: vinhUniBlue.withOpacity(0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: vinhUniBlue.withOpacity(0.1)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: selectedProgramId,
                icon: Icon(Icons.school_rounded, color: vinhUniBlue),
                items: programList.map((program) {
                  return DropdownMenuItem<String>(
                    value: program["program_id"],
                    child: Text(
                      program["program_name"],
                      style: TextStyle(
                          fontSize: 14, 
                          fontWeight: program["program_id"] == "ALL" ? FontWeight.bold : FontWeight.w600,
                          color: program["program_id"] == "ALL" ? vinhUniBlue : Colors.black87
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null && newValue != selectedProgramId) {
                    setState(() { selectedProgramId = newValue; });
                    _fetchTranscriptSummary(newValue);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 🌟 GIAO DIỆN BẢNG THEO HƯỚNG CUỘN NGANG GIỐNG WEB
  Widget _buildDataTable() {
    if (transcriptData.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.insert_chart_outlined_rounded, size: 60, color: vinhUniBlue.withOpacity(0.2)),
        const SizedBox(height: 10),
        const Text("Chưa có dữ liệu điểm tổng hợp", style: TextStyle(color: Colors.grey))
      ]));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: DataTable(
              headingRowColor: WidgetStateProperty.resolveWith((states) => vinhUniBlue.withOpacity(0.05)),
              dataRowMinHeight: 45,
              dataRowMaxHeight: 45,
              horizontalMargin: 16,
              columnSpacing: 25,
              border: TableBorder.all(color: Colors.grey.shade200, width: 1),
              columns: const [
                DataColumn(label: Text('STT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                DataColumn(label: Text('Học Kỳ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                DataColumn(label: Text('TBC (Hệ 4)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue))),
                DataColumn(label: Text('TBC (Hệ 10)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue))),
                DataColumn(label: Text('TBC Học kỳ (Hệ 4)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green))),
                DataColumn(label: Text('TBC Học kỳ (Hệ 10)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green))),
                DataColumn(label: Text('TC Tích lũy', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                DataColumn(label: Text('TC Nợ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red))),
                DataColumn(label: Text('TC Đăng ký', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                DataColumn(label: Text('CTĐT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
              ],
              rows: transcriptData.map((item) {
                return DataRow(cells: [
                  DataCell(Text(item['stt'].toString())),
                  DataCell(Text(item['hoc_ky'], style: const TextStyle(fontWeight: FontWeight.w600))),
                  DataCell(Text(item['tbc_he4'].toString(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
                  DataCell(Text(item['tbc_he10'].toString(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
                  DataCell(Text(item['tbc_hk_he4'].toString(), style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.green))),
                  DataCell(Text(item['tbc_hk_he10'].toString(), style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.green))),
                  DataCell(Text(item['tc_tich_luy'].toString(), style: const TextStyle(fontWeight: FontWeight.bold))),
                  DataCell(Text(item['tc_no'].toString(), style: TextStyle(color: item['tc_no'] > 0 ? Colors.red : Colors.black))),
                  DataCell(Text(item['tc_dang_ky'].toString())),
                  DataCell(Text(item['ctdt'], style: const TextStyle(color: Colors.grey, fontSize: 12))),
                ]);
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorView() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Icon(Icons.error_outline_rounded, size: 50, color: Colors.redAccent),
    const SizedBox(height: 12),
    Text(errorMessage ?? "Lỗi", style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
    const SizedBox(height: 16),
    ElevatedButton(onPressed: _initData, child: const Text("Thử lại"))
  ]));
}