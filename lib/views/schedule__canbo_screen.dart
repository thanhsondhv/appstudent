import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'api_service_lichcanbo.dart';
import 'schedule_canbo.dart';

class StaffScheduleScreen extends StatefulWidget {
  @override
  _StaffScheduleScreenState createState() => _StaffScheduleScreenState();
}

class _StaffScheduleScreenState extends State<StaffScheduleScreen> {
  final ApiServiceLichCanbo api = ApiServiceLichCanbo();
  
  List<WeeklySchedule> _allSchedules = [];
  List<WeeklySchedule> _filteredSchedules = [];
  bool _isLoading = true;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final data = await api.fetchSchedules();
      setState(() {
        _allSchedules = data;
        _applyFilter();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Lỗi: $e")),
        );
      }
    }
  }

  void _applyFilter() {
    if (_selectedDate == null) {
      _filteredSchedules = List.from(_allSchedules);
    } else {
      String dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      _filteredSchedules = _allSchedules.where((s) => s.date.contains(dateStr)).toList();
    }
  }

  // --- UI CHÍNH ---
  @override
  Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      // Tăng chiều cao lên 70-80 để có không gian đẩy nút xuống
      toolbarHeight: 80, 
      backgroundColor: Colors.blue[900],
      elevation: 0,
      centerTitle: true,
      // Đảm bảo icon có màu trắng nổi bật
      iconTheme: const IconThemeData(color: Colors.white, size: 26), 
      title: const Padding(
        padding: EdgeInsets.only(top: 20), // Đẩy chữ "Lịch Công Tác" xuống
        child: Text("Lịch Công Tác", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(top: 20, right: 10), // Đẩy nút Lọc xuống
          child: IconButton(
            icon: Icon(_selectedDate == null ? Icons.calendar_month : Icons.filter_alt),
            onPressed: _pickDate,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 20, right: 10), // Đẩy nút Sync xuống
          child: PopupMenuButton<String>(
            onSelected: _handleSync,
            icon: const Icon(Icons.sync, color: Colors.white),
            itemBuilder: (context) => [
              const PopupMenuItem(value: "current", child: Text("Đồng bộ tuần này")),
              const PopupMenuItem(value: "next", child: Text("Đồng bộ tuần sau")),
            ],
          ),
        )
      ],
    ),
      body: SafeArea( // 🛡️ BẢO VỆ GIAO DIỆN KHÔNG BỊ CHE KHUẤT
        child: _isLoading 
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Thanh hiển thị bộ lọc hiện tại
                  if (_selectedDate != null) _buildFilterBanner(),
                  
                  // Danh sách lịch
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _loadData,
                      child: _filteredSchedules.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              padding: const EdgeInsets.only(top: 10, bottom: 20),
                              itemCount: _filteredSchedules.length,
                              itemBuilder: (context, index) => _buildScheduleCard(_filteredSchedules[index]),
                            ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // Widget hiển thị khi không có dữ liệu để tránh lỗi Null
  Widget _buildEmptyState() {
    return ListView( // Dùng ListView để RefreshIndicator vẫn hoạt động
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.3),
        const Center(child: Text("Không có lịch trình nào cho ngày này.")),
        if (_selectedDate != null)
          TextButton(
            onPressed: () => setState(() { _selectedDate = null; _applyFilter(); }),
            child: const Text("Xóa bộ lọc"),
          )
      ],
    );
  }

  // Widget hiển thị banner ngày đang chọn
  Widget _buildFilterBanner() {
    return Container(
      color: Colors.orange[50],
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "Ngày: ${DateFormat('dd/MM/yyyy').format(_selectedDate!)}",
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
          ),
          InkWell(
            onTap: () => setState(() { _selectedDate = null; _applyFilter(); }),
            child: const Icon(Icons.close, size: 18, color: Colors.red),
          )
        ],
      ),
    );
  }

  Widget _buildScheduleCard(WeeklySchedule item) {
    bool isMorning = item.session.contains("Sáng");
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isMorning ? Colors.orange[100] : Colors.blue[100],
          child: Icon(isMorning ? Icons.wb_sunny : Icons.nightlight_round, 
                      color: isMorning ? Colors.orange : Colors.blue, size: 20),
        ),
        title: Text(item.content, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("📍 ${item.location}\n👤 ${item.chair}"),
        trailing: Text(item.time, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  // Các hàm phụ trợ
  Future<void> _pickDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2025),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() { _selectedDate = picked; _applyFilter(); });
    }
  }

  void _handleSync(String week) async {
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      String msg = await api.syncSchedule(week);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      _loadData();
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Lỗi đồng bộ")));
    }
  }
}