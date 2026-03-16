import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'api_service_lichcanbo.dart';
import 'schedule_canbo.dart';

class StaffScheduleScreen extends StatefulWidget {
  const StaffScheduleScreen({super.key});

  @override
  _StaffScheduleScreenState createState() => _StaffScheduleScreenState();
}

class _StaffScheduleScreenState extends State<StaffScheduleScreen> {
  final ApiServiceLichCanbo api = ApiServiceLichCanbo();
  
  List<WeeklySchedule> _allSchedules = [];
  List<WeeklySchedule> _filteredSchedules = [];
  bool _isLoading = true;
  DateTime? _selectedDate;
  int _weekOffset = 0; // 🔥 0: Tuần này, 1: Tuần sau, -1: Tuần trước
  final Color vinhUniBlue = const Color(0xFF0054A6);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // --- LOGIC XỬ LÝ DỮ LIỆU ---

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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Lỗi: $e")));
      }
    }
  }

  String _getVietDay(String dateStr) {
    try {
      DateTime date = DateTime.parse(dateStr);
      switch (date.weekday) {
        case 1: return "Thứ 2";
        case 2: return "Thứ 3";
        case 3: return "Thứ 4";
        case 4: return "Thứ 5";
        case 5: return "Thứ 6";
        case 6: return "Thứ 7";
        case 7: return "CN";
        default: return "";
      }
    } catch (e) { return ""; }
  }

  void _applyFilter() {
    if (_selectedDate == null) {
      // Tính toán ngày dựa trên Offset tuần
      DateTime now = DateTime.now().add(Duration(days: _weekOffset * 7));
      DateTime startOfWeek = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
      DateTime endOfWeek = startOfWeek.add(const Duration(days: 6, hours: 23, minutes: 59));

      _filteredSchedules = _allSchedules.where((s) {
        try {
          DateTime d = DateTime.parse(s.date);
          return d.isAfter(startOfWeek.subtract(const Duration(seconds: 1))) && 
                 d.isBefore(endOfWeek.add(const Duration(seconds: 1)));
        } catch (e) { return false; }
      }).toList();
      
      _filteredSchedules.sort((a, b) => a.date.compareTo(b.date));
    } else {
      String dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      _filteredSchedules = _allSchedules.where((s) => s.date.contains(dateStr)).toList();
    }
  }

  // --- GIAO DIỆN THANH ĐIỀU HƯỚNG TUẦN ---

  Widget _buildFilterBanner() {
    String label = "";
    DateTime now = DateTime.now().add(Duration(days: _weekOffset * 7));
    DateTime start = now.subtract(Duration(days: now.weekday - 1));
    DateTime end = start.add(const Duration(days: 6));

    if (_selectedDate == null) {
      if (_weekOffset == 0) label = "Tuần này";
      else if (_weekOffset == 1) label = "Tuần sau";
      else if (_weekOffset == -1) label = "Tuần trước";
      else label = "Tuần từ ${DateFormat('dd/MM').format(start)}";
    } else {
      label = "Ngày: ${DateFormat('dd/MM/yyyy').format(_selectedDate!)}";
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 0.5))
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Nút lùi tuần
          if (_selectedDate == null)
            IconButton(
              icon: Icon(Icons.chevron_left, color: vinhUniBlue),
              onPressed: () => setState(() { _weekOffset--; _applyFilter(); }),
            )
          else const SizedBox(width: 48),

          // Hiển thị dải ngày
          Column(
            children: [
              Text(label, style: TextStyle(fontSize: 14, color: vinhUniBlue, fontWeight: FontWeight.bold)),
              Text("${DateFormat('dd/MM').format(start)} - ${DateFormat('dd/MM').format(end)}", 
                   style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ],
          ),

          // Nút tiến tuần
          if (_selectedDate == null)
            IconButton(
              icon: Icon(Icons.chevron_right, color: vinhUniBlue),
              onPressed: () => setState(() { _weekOffset++; _applyFilter(); }),
            )
          else 
            IconButton(
              icon: const Icon(Icons.close, color: Colors.red, size: 20),
              onPressed: () => setState(() { _selectedDate = null; _weekOffset = 0; _applyFilter(); }),
            ),
        ],
      ),
    );
  }

  // --- CÁC HÀM UI KHÁC (GIỮ NGUYÊN BẢN ĐẸP CŨ) ---

  void _showScheduleDetail(WeeklySchedule item) {
    bool isMorning = item.session.contains("Sáng");
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
        child: Column(
          children: [
            Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(25),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: isMorning ? Colors.orange[50] : Colors.blue[50], borderRadius: BorderRadius.circular(20)),
                          child: Text(item.session, style: TextStyle(color: isMorning ? Colors.orange[800] : Colors.blue[800], fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                        const Spacer(),
                        Text(DateFormat('dd/MM/yyyy').format(DateTime.parse(item.date)), style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text("NỘI DUNG CÔNG VIỆC", style: TextStyle(fontSize: 11, color: Colors.grey, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Text(item.content, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, height: 1.5)),
                    const SizedBox(height: 25),
                    _buildDetailRow(Icons.access_time_outlined, "Thời gian", item.time),
                    _buildDetailRow(Icons.location_on_outlined, "Địa điểm", item.location),
                    _buildDetailRow(Icons.person_outline, "Chủ trì", item.chair),
                    _buildDetailRow(Icons.groups_outlined, "Thành phần", item.participants),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    if (value.isEmpty || value == "null") return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: vinhUniBlue, size: 20),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(), style: TextStyle(color: Colors.grey[400], fontSize: 10, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Color(0xFF2D3436))),
              ],
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        toolbarHeight: 70,
        backgroundColor: vinhUniBlue,
        elevation: 0,
        centerTitle: true,
        title: const Text("Lịch Công Tác", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(icon: Icon(_selectedDate == null ? Icons.calendar_month : Icons.filter_alt), onPressed: _pickDate),
          PopupMenuButton<String>(
            onSelected: _handleSync,
            icon: const Icon(Icons.sync),
            itemBuilder: (context) => [
              const PopupMenuItem(value: "current", child: Text("Đồng bộ tuần này")),
              const PopupMenuItem(value: "next", child: Text("Đồng bộ tuần sau")),
            ],
          ),
        ],
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildFilterBanner(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadData,
                    child: _filteredSchedules.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            itemCount: _filteredSchedules.length,
                            itemBuilder: (context, index) => _buildScheduleCard(_filteredSchedules[index]),
                          ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildScheduleCard(WeeklySchedule item) {
    bool isMorning = item.session.contains("Sáng");
    String shortDate = "";
    String thu = _getVietDay(item.date);
    try {
      shortDate = DateFormat('dd/MM').format(DateTime.parse(item.date));
    } catch (e) { shortDate = ""; }
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: InkWell(
        onTap: () => _showScheduleDetail(item),
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 4, color: isMorning ? Colors.orange[300] : Colors.blue[300]),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                width: 90, 
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(thu, style: TextStyle(fontSize: 10, color: vinhUniBlue, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(shortDate, style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                    const SizedBox(height: 4),
                    Text(item.time, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: vinhUniBlue, letterSpacing: -0.5)),
                  ],
                ),
              ),
              VerticalDivider(width: 1, thickness: 0.5, color: Colors.grey[100], indent: 15, endIndent: 15),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.content, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, height: 1.3)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined, size: 12, color: Colors.grey[400]),
                          const SizedBox(width: 4),
                          Expanded(child: Text(item.location, style: TextStyle(color: Colors.grey[500], fontSize: 12), overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Icon(Icons.keyboard_arrow_right_rounded, color: Colors.grey[200], size: 22),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.2),
        Icon(Icons.event_busy_outlined, size: 70, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        const Center(child: Text("Không có lịch trình.", style: TextStyle(color: Colors.grey))),
      ],
    );
  }

  Future<void> _pickDate() async {
    DateTime? picked = await showDatePicker(context: context, initialDate: _selectedDate ?? DateTime.now(), firstDate: DateTime(2025), lastDate: DateTime(2030));
    if (picked != null) { setState(() { _selectedDate = picked; _weekOffset = 0; _applyFilter(); }); }
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