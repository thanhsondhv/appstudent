import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';

// Import các màn hình tách riêng
import 'admin_notification_page.dart';
import 'chat_screen.dart'; 

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (kIsWeb) {
      // Cấu hình Firebase cho Web
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: "AIzaSy...", 
          appId: "1:...",
          messagingSenderId: "...",
          projectId: "...",
          authDomain: "vinhuni-portal.firebaseapp.com",
          storageBucket: "vinhuni-portal.appspot.com",
        ),
      );
    } else {
      // Cấu hình Firebase cho Android/iOS
      await Firebase.initializeApp();
    }
    print("✅ Firebase initialized successfully");
  } catch (e) {
    print("❌ Firebase init error: $e");
  }

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      primaryColor: const Color(0xFF0056b3),
      useMaterial3: true,
      fontFamily: 'Inter',
    ),
    home: const HomeScreen(),
  ));
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  String? studentId; 
  bool _isAuthChecked = false;
  bool _isLoading = false;

  List<dynamic> allFilters = []; 
  List<String> displayYears = [];
  List<String> displaySemesters = [];
  List<String> displayWeeks = []; 
  
  String? selectedYear;
  String? selectedSemester;
  String? selectedWeek;

  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final String domain = "https://mobi.vinhuni.edu.vn/api";

  final List<String> _titles = ["Thông báo", "Lịch học", "Lịch thi", "Bảng điểm", "Hỏi đáp"];
  final List<String> _endpoints = ["get-notifs", "get-schedule", "get-exams", "get-grades"];

  @override
  void initState() {
    super.initState();
    _initializeAuth(); 
  }

  // --- HỆ THỐNG XÁC THỰC & FIREBASE ---
  Future<void> _initializeAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString('user_id'); 
    if (savedId != null && savedId.isNotEmpty) {
      if (!kIsWeb) {
        await FirebaseMessaging.instance.subscribeToTopic("vinhuni_all_students");
        print("🚀 Đã đăng ký nhóm trên Mobile");
      }
      if (mounted) {
        setState(() { studentId = savedId; _isAuthChecked = true; });
        _loadFilters(); 
      }
    } else {
      if (mounted) setState(() => _isAuthChecked = true);
    }
  }

  Future<void> _handleLogin() async {
    if (_userController.text.isEmpty || _passController.text.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse("https://mobi.vinhuni.edu.vn/login"),
        body: {'username': _userController.text, 'password': _passController.text},
      );
      if (response.statusCode == 200 || response.request?.url.path.contains('mobile') == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_id', _userController.text);
        if (!kIsWeb) {
          await FirebaseMessaging.instance.subscribeToTopic("vinhuni_all_students");
        }
        if (mounted) {
          setState(() { studentId = _userController.text; _isLoading = false; });
          _loadFilters();
        }
      } else {
        _showError("Thông tin đăng nhập không chính xác");
      }
    } catch (e) { _showError("Lỗi kết nối máy chủ"); }
    finally { if (mounted) setState(() => _isLoading = false); }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  // --- HỆ THỐNG CẬP NHẬT BỘ LỌC 3 CẤP ---
  Future<void> _loadFilters() async {
    if (studentId == null) return;
    try {
      final response = await http.get(Uri.parse('$domain/get-filters/$studentId'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (mounted) {
          setState(() {
            allFilters = data;
            displayYears = allFilters.map((e) => e['nam'].toString()).toSet().toList();
            if (displayYears.isNotEmpty) {
              selectedYear = displayYears[0];
              _updateSemesterList(selectedYear!); 
            }
          });
        }
      }
    } catch (e) { debugPrint("Lỗi Filter: $e"); }
  }

  void _updateSemesterList(String year) {
    setState(() {
      displaySemesters = allFilters
          .where((e) => e['nam'].toString() == year)
          .map((e) => e['ky'].toString())
          .toSet().toList();
      if (displaySemesters.isNotEmpty) {
        selectedSemester = displaySemesters[0];
        _updateWeekList(year, selectedSemester!); 
      }
    });
  }

  void _updateWeekList(String year, String semester) {
    setState(() {
      displayWeeks = allFilters
          .where((e) => e['nam'].toString() == year && e['ky'].toString() == semester)
          .map((e) => e['tuan'].toString())
          .toSet().toList();
      displayWeeks.sort((a, b) => int.parse(a).compareTo(int.parse(b)));
      selectedWeek = displayWeeks.isNotEmpty ? displayWeeks[0] : null;
    });
  }

  // --- TRUY VẤN DỮ LIỆU ---
  Future<List<dynamic>> fetchData() async {
    if (studentId == null) return [];
    try {
      String url = '$domain/${_endpoints[_currentIndex]}/$studentId';
      if (_currentIndex > 0) {
        url += "?nam_hoc=${Uri.encodeComponent(selectedYear ?? '')}&hoc_ky=${Uri.encodeComponent(selectedSemester ?? '')}";
        if (_currentIndex == 1 && selectedWeek != null) url += "&tuan=$selectedWeek";
      }
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) return json.decode(response.body) as List<dynamic>;
      return [];
    } catch (e) { return []; }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthChecked) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (studentId == null) return _buildLoginUI();

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Text(_titles[_currentIndex], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0056b3),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_alert, color: Colors.white),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => AdminNotificationPage())),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              setState(() { studentId = null; allFilters = []; });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Chỉ hiện FilterBar cho Lịch học (1), Lịch thi (2), Điểm (3)
          if (_currentIndex > 0 && _currentIndex < 4) _buildFilterBar(), 
          Expanded(
            child: _currentIndex == 4 
              ? ChatScreen(studentId: studentId!) // Tab Hỏi đáp
              : FutureBuilder<List<dynamic>>(
                  key: ValueKey("$_currentIndex$selectedYear$selectedSemester$selectedWeek"),
                  future: fetchData(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                    if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("Không có dữ liệu"));
                    return ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: snapshot.data!.length,
                      itemBuilder: (context, index) => _buildDataCard(snapshot.data![index]),
                    );
                  },
                ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: const Color(0xFF0056b3),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.notifications), label: "Thông báo"),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: "Lịch học"),
          BottomNavigationBarItem(icon: Icon(Icons.edit_note), label: "Lịch thi"),
          BottomNavigationBarItem(icon: Icon(Icons.grade), label: "Điểm"),
          BottomNavigationBarItem(icon: Icon(Icons.psychology), label: "Hỏi đáp"),
        ],
      ),
    );
  }

  // --- GIAO DIỆN COMPONENT ---
  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Row(
        children: [
          Expanded(child: _buildDropdown(selectedYear, displayYears, (v) { selectedYear = v; _updateSemesterList(v!); }, "Năm")),
          const SizedBox(width: 8),
          Expanded(child: _buildDropdown(selectedSemester, displaySemesters, (v) { selectedSemester = v; _updateWeekList(selectedYear!, v!); }, "Kỳ")),
          const SizedBox(width: 8),
          if (_currentIndex == 1)
            Expanded(child: _buildDropdown(selectedWeek, displayWeeks, (v) { setState(() => selectedWeek = v); }, "Tuần")),
        ],
      ),
    );
  }

  Widget _buildDropdown(String? value, List<String> items, Function(String?) onChanged, String label) {
    return DropdownButtonFormField<String>(
      value: (items.contains(value)) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
      ),
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis))).toList(),
      onChanged: (v) => onChanged(v),
    );
  }

  Widget _buildDataCard(var item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE2E8F0))),
      child: ListTile(
        title: Text(item['TieuDe'] ?? item['TenHocPhan'] ?? "", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(item['NgayThi'] ?? item['NgayPhatHanh'] ?? "", style: TextStyle(color: Colors.blue[800], fontSize: 13)),
        ),
        trailing: const Icon(Icons.arrow_circle_right_outlined, color: Color(0xFF0056b3), size: 28),
        onTap: () => _showDetailBottomSheet(item),
      ),
    );
  }

  void _showDetailBottomSheet(var item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(item['TenHocPhan'] ?? "Chi tiết", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF0056b3)), textAlign: TextAlign.center),
            ),
            const Divider(height: 30),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: HtmlWidget(item['NoiDung'] ?? "Không có nội dung", textStyle: const TextStyle(fontSize: 16, height: 1.5)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0056b3), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                  child: const Text("ĐÓNG", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginUI() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.school_rounded, size: 100, color: Color(0xFF0056b3)),
              const SizedBox(height: 24),
              const Text("Vinh Uni Portal", style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
              const SizedBox(height: 40),
              TextField(controller: _userController, decoration: InputDecoration(labelText: "Mã sinh viên", prefixIcon: const Icon(Icons.person), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
              const SizedBox(height: 20),
              TextField(controller: _passController, obscureText: true, decoration: InputDecoration(labelText: "Mật khẩu", prefixIcon: const Icon(Icons.lock), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleLogin,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0056b3), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("ĐĂNG NHẬP", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}