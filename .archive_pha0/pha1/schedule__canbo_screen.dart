import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/vinhuni_api_client.dart'; // Bộ điều hướng an ninh Pro
import '../views/schedule_canbo.dart';
import '../services/database_helper.dart';

class StaffScheduleScreen extends StatefulWidget {
  const StaffScheduleScreen({super.key});

  @override
  _StaffScheduleScreenState createState() => _StaffScheduleScreenState();
}

class _StaffScheduleScreenState extends State<StaffScheduleScreen> {
  // --- Khai báo biến ---
  List<WeeklySchedule> _allSchedules = [];
  List<WeeklySchedule> _filteredSchedules = [];
  bool _isLoading = true;
  DateTime? _selectedDate;
  int _weekOffset = 0; 
  final Color vinhUniBlue = const Color(0xFF0054A6);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // --- 1. LOGIC TẢI DỮ LIỆU (OFFLINE-FIRST + AUTO TOKEN) ---
  Future<void> _loadData() async {
    if (mounted) setState(() => _isLoading = true);
    
    try {
      // BƯỚC A: Đọc dữ liệu từ SQLite để hiện ngay lập tức
      final cachedData = await DatabaseHelper.instance.getAllStaffSchedules();
      if (cachedData.isNotEmpty) {
        setState(() {
          _allSchedules = cachedData.map((i) => WeeklySchedule.fromMap(i)).toList();
          _applyFilter();
          _isLoading = false; 
        });
      }

      // BƯỚC B: Tải bản mới từ API qua VinhUniClient (Tự động kèm Token)
      // Endpoint này khớp với cấu trúc FastAPI chúng ta đã làm
      final response = await VinhUniClient.instance.get('/api/admin/schedule/view-data');

      if (response.statusCode == 200) {
        List<dynamic> data = response.data['data'];
        final List<WeeklySchedule> freshData = data.map((json) => WeeklySchedule.fromJson(json)).toList();

        // BƯỚC C: Đồng bộ SQLite cho lần xem sau
        await DatabaseHelper.instance.syncFullWeeklySchedule(
          freshData.map((e) => e.toMap()).toList()
        );

        if (mounted) {
          setState(() {
            _allSchedules = freshData;
            _applyFilter();
            _isLoading = false;
          });
          debugPrint("✅ [MATRIX] Đã cập nhật lịch mới nhất từ Server");
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint("❌ [AUTH ERROR] Lỗi tải lịch hoặc Token hết hạn: $e");
      if (_allSchedules.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Phiên làm việc hết hạn hoặc lỗi kết nối."), behavior: SnackBarBehavior.floating)
        );
      }
    }
  }

  // --- 2. LOGIC BỘ LỌC THỜI GIAN ---
  void _applyFilter() {
  if (_selectedDate == null) {
    // 1. Lọc theo tuần dựa trên weekOffset
    DateTime now = DateTime.now().add(Duration(days: _weekOffset * 7));
    // Xác định ngày đầu tuần (Thứ 2) và cuối tuần (Chủ nhật)
    DateTime startOfWeek = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    DateTime endOfWeek = startOfWeek.add(const Duration(days: 6, hours: 23, minutes: 59));

    _filteredSchedules = _allSchedules.where((s) {
      try {
        DateTime d = DateTime.parse(s.date);
        return d.isAfter(startOfWeek.subtract(const Duration(seconds: 1))) && 
               d.isBefore(endOfWeek.add(const Duration(seconds: 1)));
      } catch (e) { return false; }
    }).toList();
  } else {
    // 2. Lọc theo đích danh ngày đã chọn từ Calendar
    String dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
    _filteredSchedules = _allSchedules.where((s) => s.date.contains(dateStr)).toList();
  }
  
  // 🔥 3. LOGIC SẮP XẾP ĐA TẦNG: NGÀY -> GIỜ
  _filteredSchedules.sort((a, b) {
    // Bước A: So sánh ngày (EventDate)
    int dateCompare = a.date.compareTo(b.date);
    
    // Nếu ngày khác nhau, trả về kết quả so sánh ngày luôn
    if (dateCompare != 0) return dateCompare;

    // Bước B: Nếu cùng ngày, tiến hành so sánh Giờ (TimeValue)
    // Chuẩn hóa giờ về dạng 5 ký tự (08:00 thay vì 8:00) để so sánh chuỗi chính xác
    String timeA = a.time.length == 4 ? "0${a.time}" : a.time;
    String timeB = b.time.length == 4 ? "0${b.time}" : b.time;
    
    return timeA.compareTo(timeB);
  });
}

  String _getVietDay(String dateStr) {
    try {
      DateTime date = DateTime.parse(dateStr);
      List<String> days = ["", "Thứ 2", "Thứ 3", "Thứ 4", "Thứ 5", "Thứ 6", "Thứ 7", "CN"];
      return days[date.weekday];
    } catch (e) { return ""; }
  }

  // --- 3. GIAO DIỆN CHÍNH (UI) ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        toolbarHeight: 70,
        backgroundColor: vinhUniBlue,
        elevation: 0,
        centerTitle: true,
        title: const Text("LỊCH CÔNG TÁC", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(_selectedDate == null ? Icons.calendar_month : Icons.filter_alt, color: Colors.white), 
            onPressed: _pickDate
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBanner(),
          Expanded(
            child: _isLoading && _allSchedules.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
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

  // Banner điều hướng tuần
  Widget _buildFilterBanner() {
    String label = "";
    DateTime now = DateTime.now().add(Duration(days: _weekOffset * 7));
    DateTime start = now.subtract(Duration(days: now.weekday - 1));
    DateTime end = start.add(const Duration(days: 6));

    if (_selectedDate == null) {
      if (_weekOffset == 0) label = "Tuần này";
      else if (_weekOffset == 1) label = "Tuần sau";
      else if (_weekOffset == -1) label = "Tuần trước";
      else label = "Từ ${DateFormat('dd/MM').format(start)}";
    } else {
      label = "Ngày: ${DateFormat('dd/MM/yyyy').format(_selectedDate!)}";
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 0.5))),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _selectedDate == null 
            ? IconButton(icon: Icon(Icons.chevron_left, color: vinhUniBlue), onPressed: () => setState(() { _weekOffset--; _applyFilter(); }))
            : const SizedBox(width: 48),
          Column(
            children: [
              Text(label, style: TextStyle(fontSize: 15, color: vinhUniBlue, fontWeight: FontWeight.bold)),
              Text("${DateFormat('dd/MM').format(start)} - ${DateFormat('dd/MM').format(end)}", style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ],
          ),
          _selectedDate == null
            ? IconButton(icon: Icon(Icons.chevron_right, color: vinhUniBlue), onPressed: () => setState(() { _weekOffset++; _applyFilter(); }))
            : IconButton(icon: const Icon(Icons.close, color: Colors.red, size: 22), onPressed: () => setState(() { _selectedDate = null; _weekOffset = 0; _applyFilter(); })),
        ],
      ),
    );
  }

  // Card lịch chi tiết (Zalo Style)
  Widget _buildScheduleCard(WeeklySchedule item) {
    bool isMorning = item.session.contains("Sáng");
    String shortDate = "";
    try { shortDate = DateFormat('dd/MM').format(DateTime.parse(item.date)); } catch (e) { }
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: InkWell(
        onTap: () => _showScheduleDetail(item),
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 5, decoration: BoxDecoration(color: isMorning ? Colors.orange[300] : Colors.blue[400], borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12)))),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                width: 85, 
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_getVietDay(item.date), style: TextStyle(fontSize: 11, color: vinhUniBlue, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(shortDate, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    const SizedBox(height: 6),
                    Text(item.time, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: vinhUniBlue)),
                  ],
                ),
              ),
              VerticalDivider(width: 1, thickness: 0.6, color: Colors.grey[100], indent: 15, endIndent: 15),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.content, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, height: 1.3, color: Color(0xFF2D3436))),
                      if (item.chair.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text("Chủ trì: ${item.chair}", style: TextStyle(color: Colors.grey[700], fontSize: 13), overflow: TextOverflow.ellipsis),
                      ],
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined, size: 14, color: Colors.grey[400]),
                          const SizedBox(width: 4),
                          Expanded(child: Text(item.location, style: TextStyle(color: Colors.grey[500], fontSize: 13), overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Chi tiết lịch (Modal Bottom Sheet)
  void _showScheduleDetail(WeeklySchedule item) {
    bool isMorning = item.session.contains("Sáng");
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
        child: Column(
          children: [
            Container(margin: const EdgeInsets.only(top: 12), width: 45, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(25),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(color: isMorning ? Colors.orange[50] : Colors.blue[50], borderRadius: BorderRadius.circular(20)),
                          child: Text(item.session, style: TextStyle(color: isMorning ? Colors.orange[800] : Colors.blue[800], fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                        const Spacer(),
                        Text(DateFormat('dd/MM/yyyy').format(DateTime.parse(item.date)), style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 25),
                    const Text("NỘI DUNG CHI TIẾT", style: TextStyle(fontSize: 12, color: Color(0xFF0054A6), letterSpacing: 1.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Text(item.content, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, height: 1.5, color: Color(0xFF2D3436))),
                    const Divider(height: 40, thickness: 0.5),
                    _buildDetailRow(Icons.access_time_filled_rounded, "Giờ bắt đầu", item.time),
                    _buildDetailRow(Icons.location_on_rounded, "Địa điểm tổ chức", item.location),
                    _buildDetailRow(Icons.stars_rounded, "Chủ trì cuộc họp", item.chair),
                    _buildDetailRow(Icons.people_alt_rounded, "Thành phần tham gia", item.participants),
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
    if (value.isEmpty || value == "null" || value == "") return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 25),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: vinhUniBlue.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: vinhUniBlue, size: 20)),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(), style: TextStyle(color: Colors.grey[500], fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                const SizedBox(height: 5),
                Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF2D3436), height: 1.4)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_note_rounded, size: 80, color: Colors.grey[200]),
          const SizedBox(height: 16),
          Text("Không có lịch trình trong thời gian này", style: TextStyle(color: Colors.grey[400], fontSize: 14)),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    DateTime? picked = await showDatePicker(
      context: context, 
      initialDate: _selectedDate ?? DateTime.now(), 
      firstDate: DateTime(2024), 
      lastDate: DateTime(2030),
      builder: (context, child) => Theme(data: Theme.of(context).copyWith(colorScheme: ColorScheme.light(primary: vinhUniBlue)), child: child!),
    );
    if (picked != null) { setState(() { _selectedDate = picked; _weekOffset = 0; _applyFilter(); }); }
  }
}