import 'package:flutter/material.dart';
import '../core/auth/user_role.dart';
import '../core/api/api.dart';

class NotificationSettingsScreen extends StatefulWidget {
  final String userId;
  final String userRole;
  const NotificationSettingsScreen({super.key, required this.userId, required this.userRole});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  bool _isLoading = true;
  // Lưu trữ cấu hình từ server: { "LICH_THI": {"enabled": true, "time": 60} }
  Map<String, Map<String, dynamic>> _settingsMap = {};

  // Danh sách mẫu giao diện
  late final List<Map<String, dynamic>> categories;

  @override
  void initState() {
    super.initState();
    _initCategoryDefinition();
    _loadSettingsFromServer();
  }

  // 🔥 Định nghĩa các mục hiển thị (Sửa lỗi khớp Group Name)
  void _initCategoryDefinition() {
    // Kiểm tra vai trò để hiện menu tương ứng
    final bool isStaff = UserRole.parse(widget.userRole).isStaff;
    
    if (isStaff) {
      categories = [
        {"id": "GENERAL", "name": "Thông báo VinhUni", "icon": Icons.info_outline, "group": "HỆ THỐNG"},
        {"id": "VAN_BAN", "name": "Văn bản & Công văn mới", "icon": Icons.description_outlined, "group": "HỆ THỐNG"},
        {"id": "LICH_TUAN", "name": "Lịch công tác tuần", "icon": Icons.event_note_rounded, "group": "LỊCH TRÌNH", "hasTime": true},
        {"id": "LICH_DAY", "name": "Nhắc lịch dạy giảng viên", "icon": Icons.calendar_month_rounded, "group": "LỊCH TRÌNH", "hasTime": true},
      ];
    } else {
      categories = [
        {"id": "GENERAL", "name": "Thông báo chung", "icon": Icons.notifications_none_rounded, "group": "HỆ THỐNG"},
        {"id": "LICH_THI", "name": "Nhắc lịch thi & Phòng thi", "icon": Icons.assignment_outlined, "group": "HỌC TẬP", "hasTime": true},
        {"id": "DIEM", "name": "Công bố điểm số mới", "icon": Icons.auto_graph_rounded, "group": "HỌC TẬP"},
        {"id": "LICH_HOC", "name": "Nhắc lịch học buổi sáng", "icon": Icons.alarm_on_rounded, "group": "LỊCH TRÌNH", "hasTime": true},
        {"id": "CANH_BAO", "name": "Cảnh báo học vụ (GPA)", "icon": Icons.warning_amber_rounded, "group": "HỌC TẬP"},
      ];
    }
  }

  Future<void> _loadSettingsFromServer() async {
    try {
      final res = await Api.get('/api/notifications/settings/${widget.userId}');

      if (res.thanhCong) {
        final List data = res.data is List ? res.data as List : const [];

        Map<String, Map<String, dynamic>> temp = {};
        for (var item in data) {
          temp[item['category']] = {
            "enabled": item['is_enabled'], 
            "time": item['lead_time']
          };
        }
        setState(() {
          _settingsMap = temp;
          _isLoading = false;
        });
      } else {
        debugPrint("❌ API Error: ${res.statusCode}");
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("🔥 Exception: $e");
      setState(() => _isLoading = false);
    }
  }

  /// Bật/tắt một loại thông báo, hoặc đổi giờ nhắc trước.
  ///
  /// ⚠️ SỬA 19/08/2026: bản cũ đổi giao diện rồi gọi máy chủ mà KHÔNG hề xem
  /// kết quả. Máy chủ từ chối — mất mạng, hết phiên, lỗi máy chủ — thì công tắc
  /// vẫn hiện là đã bật, người dùng yên tâm bỏ đi. Mở lại ứng dụng thì nó về
  /// như cũ, và không ai hiểu vì sao.
  ///
  /// Nay vẫn đổi giao diện trước cho nhanh, nhưng máy chủ từ chối thì TRẢ LẠI
  /// trạng thái cũ và nói rõ. Thà thấy nó bật lại còn hơn tưởng đã lưu.
  Future<void> _update(String cid, bool val, int time) async {
    final truocDo = _settingsMap[cid];

    // Đổi giao diện ngay để người dùng không phải chờ mạng
    setState(() => _settingsMap[cid] = {"enabled": val, "time": time});

    try {
      final res = await Api.post(
        "/api/notifications/update",
        duLieu: {
          "user_id": widget.userId,
          "category": cid,
          "is_enabled": val,
          "lead_time": time
        },
      );
      if (res.thanhCong) return;

      debugPrint("❌ Máy chủ từ chối lưu cài đặt: ${res.statusCode}");
      _traLaiTrangThaiCu(cid, truocDo, res.thongDiepLoi);
    } catch (e) {
      debugPrint("❌ Không lưu được cài đặt: $e");
      _traLaiTrangThaiCu(cid, truocDo, "Không kết nối được máy chủ.");
    }
  }

  void _traLaiTrangThaiCu(String cid, dynamic truocDo, String liDo) {
    if (!mounted) return;
    setState(() {
      if (truocDo == null) {
        _settingsMap.remove(cid);
      } else {
        _settingsMap[cid] = truocDo;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Chưa lưu được cài đặt. ${liDo.isEmpty ? "Vui lòng thử lại." : liDo}"),
        backgroundColor: const Color(0xFFB3261E),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _pickTime(String cid) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Thông báo trước thời điểm diễn ra", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(height: 20),
            _timeBtn(cid, "15 phút", 15),
            _timeBtn(cid, "30 phút", 30),
            _timeBtn(cid, "1 tiếng", 60),
            _timeBtn(cid, "1 ngày", 1440),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _timeBtn(String cid, String label, int mins) {
    bool isSelected = _settingsMap[cid]?['time'] == mins;
    return ListTile(
      title: Text(label),
      trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.blue) : null,
      onTap: () {
        _update(cid, true, mins);
        Navigator.pop(context);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("Tùy chọn thông báo", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        centerTitle: true, 
        elevation: 0.5, 
        backgroundColor: Colors.white, 
        foregroundColor: Colors.black
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF0054A6)))
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _section("HỆ THỐNG"),
              _section("LỊCH TRÌNH"),
              _section("HỌC TẬP"),
            ],
          ),
    );
  }

  Widget _section(String groupName) {
    // Lọc các category thuộc group này
    var items = categories.where((c) => c['group'] == groupName).toList();
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 10, top: 10),
          child: Text(groupName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white, 
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]
          ),
          child: Column(
            children: items.map((cat) {
              // Lấy giá trị từ Map dữ liệu server, nếu chưa có thì mặc định là true/30
              bool isOn = _settingsMap[cat['id']]?['enabled'] ?? true;
              int t = _settingsMap[cat['id']]?['time'] ?? 30;

              return Column(
                children: [
                  SwitchListTile(
                    activeColor: const Color(0xFF0054A6),
                    secondary: Icon(cat['icon'], color: const Color(0xFF0054A6)),
                    title: Text(cat['name'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: cat['hasTime'] == true && isOn 
                      ? InkWell(
                          onTap: () => _pickTime(cat['id']),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text("🔔 Nhắc trước: ${t < 60 ? '$t phút' : (t >= 1440 ? '1 ngày' : '${t~/60} tiếng')} >", 
                              style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        )
                      : null,
                    value: isOn,
                    onChanged: (v) => _update(cat['id'], v, t),
                  ),
                  if (items.last != cat) const Divider(height: 1, indent: 70),
                ],
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 15),
      ],
    );
  }
}