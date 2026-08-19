import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chatgroup/chat_room_page.dart';
import 'chatgroup/chat_group_list_page.dart';
import 'thongbao_chitiet_screen.dart';
import '../services/notification_service.dart';
import '../services/database_helper.dart';
import '../core/auth/user_role.dart';
import '../core/repositories/notification_repository.dart';
import '../core/utils/rut_gon_html.dart';


class ThongBaoScreen extends StatefulWidget {
  const ThongBaoScreen({super.key});

  @override
  State<ThongBaoScreen> createState() => _ThongBaoScreenState();
}

class _ThongBaoScreenState extends State<ThongBaoScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Color vinhUniBlue = const Color(0xFF0054A6);
  
  // Danh sách tin cho từng Tab
  List<dynamic> generalNotifs = [];   
  List<dynamic> workNotifs = [];      
  List<dynamic> reminderNotifs = [];  
  List<dynamic> personalNotifs = [];  
  
  bool isLoading = true;
  String userRole = "SinhVien";

  /// Đúng khi tải xong mà không có tin nào — để phân biệt với lúc đang tải,
  /// và để hiện nút thử lại thay vì một màn hình trống không giải thích gì.
  bool khongTaiDuoc = false;

  /// Đã tự chuyển sang tab có tin lần nào chưa. Chỉ làm MỘT lần lúc mới mở,
  /// để không cướp quyền điều khiển khi người dùng đã tự chọn tab khác.
  bool _daTuChonTab = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    // Người dùng tự chọn tab thì tôn trọng lựa chọn đó, không tự đổi nữa
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) _daTuChonTab = true;
    });
    _initRoleAndFetch();
    // 🔥 KHỞI ĐỘNG NHỊP TIM KHI VÀO APP
 
  }

  // --- 1. KHỞI TẠO VÀ LẤY DỮ LIỆU ---
  Future<void> _initRoleAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        userRole = prefs.getString('user_role') ?? "SinhVien";
      });
      // Gọi hàm tải dữ liệu chính
      fetchNotifications();
    }
  }

  /// 🔥 HÀM TẢI DỮ LIỆU (TỐI ƯU TỐC ĐỘ: HIỆN OFFLINE TRƯỚC)
  Future<void> fetchNotifications() async {
    if (!mounted) return;
    
    final prefs = await SharedPreferences.getInstance();
    final String? currentUserId = prefs.getString('user_code');
    if (currentUserId == null) return;

    // ⚡ BƯỚC A: Lấy dữ liệu từ SQLite (Instant - hiện ngay trong 0.1s)
    final localData = await DatabaseHelper.instance.getOfflineNotifs(currentUserId);
    if (mounted && localData.isNotEmpty) {
      _updateGroups(localData); // Chia tin vào các tab
      setState(() => isLoading = false); // Tắt loading ngay vì đã có tin cũ để xem
    }

    // 🌐 BƯỚC B: Chạy ngầm việc tải từ Server (Không bắt người dùng đợi)
    NotificationService.fetchAndSyncNotifs(currentUserId).then((newData) {
      if (!mounted) return;

      // ⚠️ SỬA 18/08/2026: bản cũ chỉ tắt vòng xoay khi `newData.isNotEmpty`.
      // Máy chủ trả về danh sách rỗng — hoặc lỗi mạng làm trả về rỗng — thì
      // vòng xoay quay MÃI MÃI, người dùng tưởng ứng dụng treo. Nay luôn tắt,
      // và phân biệt rõ "thật sự không có tin" với "không tải được".
      _updateGroups(newData);
      setState(() {
        isLoading = false;
        khongTaiDuoc = newData.isEmpty;
      });
      NotificationService.refreshAppIconBadge();
    }).catchError((e) {
      debugPrint("⚠️ Lỗi đồng bộ thông báo: $e");
      if (mounted) {
        setState(() {
          isLoading = false;
          khongTaiDuoc = true;
        });
      }
    });
  }

  // --- 2. QUY HOẠCH TIN NHẮN VÀO TAB (LOGIC CHÍNH) ---
  void _updateGroups(List<dynamic> data) {
    final bool isStaff = UserRole.parse(userRole).isStaff;

    setState(() {
      // 🛡️ Lọc bỏ tin nhắn rác hoặc tin chỉ dùng cho Push
      final cleanData = data.where((n) {
        String loai = n['LoaiTin']?.toString().toUpperCase() ?? "";
        if (loai == 'CHAT_GROUP') return false;
        if (n['Scope']?.toString().toUpperCase() == 'CHAT_PUSH_ONLY') return false;
        return true;
      }).toList();

      // Chia nhóm vào 4 Tab dựa trên TabGroup
      generalNotifs = cleanData.where((n) {
        String loai = n['LoaiTin']?.toString().toUpperCase() ?? "";
        if (isStaff && (loai == 'THONG_BAO' || loai.contains('VAN_BAN'))) return false;
        return _safeGetTabGroup(n) == 'GENERAL';
      }).toList();

      workNotifs = cleanData.where((n) => _safeGetTabGroup(n) == 'WORK').toList();
      reminderNotifs = cleanData.where((n) => _safeGetTabGroup(n) == 'REMINDER').toList();
      personalNotifs = cleanData.where((n) => _safeGetTabGroup(n) == 'PERSONAL').toList();

      // Tính toán Badge trong App
      _calculateAndApplyBadges();
    });

    // Sau khi đã chia tin vào các tab mới biết tab nào có gì
    _moTabCoTin();
  }

  /// Đoạn xem trước của một thông báo.
  ///
  /// Máy chủ dựng trường TomTat bằng cách cắt cứng nội dung HTML theo số ký tự,
  /// nên nhiều tin có TomTat chỉ gồm đúng một thẻ mở bị cắt dở — bỏ thẻ đi thì
  /// còn chuỗi rỗng. Khi đó lấy tạm từ NoiDung đầy đủ để danh sách không bị
  /// trống trơn.
  String _tomTat(dynamic notif) {
    final tomTat = rutGonHtml(notif['TomTat']?.toString(), gioiHan: 160);
    if (tomTat.isNotEmpty) return tomTat;
    return rutGonHtml(notif['NoiDung']?.toString(), gioiHan: 160);
  }

  /// Mở sẵn tab đang có tin chưa đọc.
  ///
  /// Sửa 18/08/2026: ứng dụng luôn mở ở tab đầu tiên (VINHUNI). Với tài khoản
  /// cán bộ thì tin thường nằm ở tab CÔNG TÁC, nên mở mục Thông báo chỉ thấy
  /// màn hình trắng "Không có tin mới từ VinhUni" — người dùng tưởng ứng dụng
  /// không tải được, trong khi 12 tin đang nằm ở tab bên cạnh.
  ///
  /// Ưu tiên tab có tin CHƯA ĐỌC; không có thì lấy tab đầu tiên có tin.
  void _moTabCoTin() {
    if (_daTuChonTab || !mounted) return;

    final cacTab = [generalNotifs, workNotifs, reminderNotifs, personalNotifs];

    // Tab hiện tại đã có tin thì để nguyên
    if (cacTab[_tabController.index].isNotEmpty) {
      _daTuChonTab = true;
      return;
    }

    // Ưu tiên tab CÓ TIN CHƯA ĐỌC, theo số của máy chủ (số này tính trên toàn
    // bộ dữ liệu, không chỉ 20 tin đã tải về).
    int dich = -1;
    for (var i = 0; i < cacTab.length; i++) {
      if (_soChuaDocCuaTab(i, cacTab[i]) > 0) { dich = i; break; }
    }
    if (dich < 0) dich = cacTab.indexWhere((ds) => ds.isNotEmpty);
    if (dich < 0) return;   // không tab nào có tin — để yên, hiện trạng thái rỗng

    _daTuChonTab = true;
    _tabController.animateTo(dich);
  }

  /// Tin này thuộc tab nào.
  ///
  /// Máy chủ đã tính sẵn `TabGroup`; bảng dưới đây chỉ là đường lui cho những
  /// tin cũ trong bộ nhớ máy chưa có trường đó.
  ///
  /// ⚠️ SỬA 19/08/2026, hai điểm:
  ///
  ///   • Thiếu nhóm 'THI' — nhóm ĐÔNG NHẤT (336/471 tin trong hàng đợi, tức
  ///     72%). Nay xếp cùng 'LICH_THI' vào NHẮC LỊCH, khớp với máy chủ.
  ///   • Mặc định cũ là PERSONAL, nghĩa là mọi nhóm tin LẠ đều bị dồn vào tab
  ///     CÁ NHÂN — nơi lẽ ra chỉ chứa tin gửi đích danh. Máy chủ mặc định
  ///     GENERAL; hai bên phải giống nhau, nếu không cùng một tin sẽ nằm ở hai
  ///     tab khác nhau tuỳ lúc đó lấy từ mạng hay từ bộ nhớ máy.
  String _safeGetTabGroup(dynamic n) {
    if (n['TabGroup'] != null && n['TabGroup'].toString().isNotEmpty) {
      return n['TabGroup'].toString().toUpperCase();
    }
    final loai = n['LoaiTin']?.toString().toUpperCase() ?? "";

    const nhacLich = [
      'CANH_BAO', 'LICH_THI', 'THI', 'LICH_HOP', 'NHAC_HEN',
      'HUY_LICH', 'HUY_LOP_LT', 'KHAN_CAP', 'REMINDER',
    ];
    const hocTap = [
      'LICH_TUAN', 'DIEM', 'LICH_DAY', 'LICH_CONGTAC', 'LICH_HOC',
      'LOP_HP', 'LOP_HC', 'WORK',
    ];
    const caNhan = ['PHAN_HOI', 'DUYET_DON', 'CA_NHAN', 'PERSONAL'];

    if (nhacLich.contains(loai)) return 'REMINDER';
    if (hocTap.contains(loai)) return 'WORK';
    if (caNhan.contains(loai)) return 'PERSONAL';
    return 'GENERAL';
  }

  // --- 3. QUẢN LÝ BADGE TRONG APP ---
  Future<void> _calculateAndApplyBadges() async {
    int total = _getTotalUnread();
    
    // Cập nhật Badge ngoài Icon App (Nếu cần đồng bộ ngay)
    NotificationService.refreshAppIconBadge();

    // Hỏi máy chủ số của từng tab. Không hỏi được thì giữ nguyên bản cũ và
    // huy hiệu tự lùi về đếm trong danh sách đã tải.
    try {
      final theoTab = await NotificationRepository.instance.soChuaDocTheoTab();
      if (theoTab.isNotEmpty && mounted) {
        setState(() => _soTheoTabTuMayChu = theoTab);
      }
    } catch (e) {
      debugPrint("⚠️ [ThôngBáo] Chưa lấy được số chưa đọc theo tab: $e");
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('unread_notif_count', total);
    
    if (NotificationService.onRefreshBadge != null) {
      NotificationService.onRefreshBadge!();
    }
  }

  int _getTotalUnread() {
    return _countUnreadInList(generalNotifs) +
           _countUnreadInList(workNotifs) +
           _countUnreadInList(reminderNotifs) +
           _countUnreadInList(personalNotifs);
  }

  /// Số chưa đọc mỗi tab, do máy chủ tính trên TOÀN BỘ dữ liệu.
  ///
  /// Rỗng khi chưa hỏi được máy chủ — lúc đó [_soChuaDocCuaTab] tự lùi về đếm
  /// trong danh sách đã tải.
  Map<String, int> _soTheoTabTuMayChu = const {};

  static const _nhomCuaTab = ['GENERAL', 'WORK', 'REMINDER', 'PERSONAL'];

  /// Số hiện trên huy hiệu của tab thứ [viTri].
  int _soChuaDocCuaTab(int viTri, List<dynamic> danhSachDaTai) {
    final tuMayChu = _soTheoTabTuMayChu[_nhomCuaTab[viTri]];
    if (tuMayChu != null) return tuMayChu;
    return _countUnreadInList(danhSachDaTai);
  }

  int _countUnreadInList(List<dynamic> list) {
    return list.where((n) {
      var isRead = n['IsRead'].toString(); 
      return isRead == 'false' || isRead == '0' || isRead == 'null';
    }).length;
  }

  // --- 4. GIAO DIỆN (UI COMPONENTS) ---
  List<String> _getTabLabels() {
    final bool isStaff = UserRole.parse(userRole).isStaff;
    return [
      "VINHUNI", 
      isStaff ? "CÔNG TÁC" : "HỌC TẬP", 
      "NHẮC LỊCH", 
      "CÁ NHÂN"
    ];
  }

  @override
  Widget build(BuildContext context) {
    final labels = _getTabLabels();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        // 🔥 Ẩn nút Back tự động
        automaticallyImplyLeading: false, 
        title: const Text(
          "Thông báo", 
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87)
        ),
        backgroundColor: Colors.white,
        centerTitle: false,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: Icon(Icons.done_all_rounded, color: vinhUniBlue, size: 22),
            onPressed: _showMarkAllReadConfirm,
            tooltip: "Đánh dấu tất cả đã đọc",
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: vinhUniBlue,
          unselectedLabelColor: Colors.grey.shade500,
          indicatorColor: vinhUniBlue,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
          tabs: [
            _buildTabWithBadge(labels[0], _soChuaDocCuaTab(0, generalNotifs)),
            _buildTabWithBadge(labels[1], _soChuaDocCuaTab(1, workNotifs)),
            _buildTabWithBadge(labels[2], _soChuaDocCuaTab(2, reminderNotifs)),
            _buildTabWithBadge(labels[3], _soChuaDocCuaTab(3, personalNotifs)),
          ],
        ),
      ),
      body: isLoading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: vinhUniBlue),
                  const SizedBox(height: 14),
                  const Text("Đang tải thông báo…",
                      style: TextStyle(fontSize: 13, color: Colors.grey)),
                ],
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildList(generalNotifs, "Không có tin mới từ VinhUni"),
                _buildList(workNotifs, UserRole.parse(userRole).isStudent ? "Chưa có lịch học mới" : "Chưa có lịch công tác"),
                _buildList(reminderNotifs, "Không có nhắc nhở lịch trình"),
                _buildList(personalNotifs, "Hộp thư cá nhân trống"),
              ],
            ),
    );
  }

  Widget _buildTabWithBadge(String label, int unreadCount) {
    return Tab(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Text(label),
          if (unreadCount > 0)
            Positioned(
              right: -16, top: -8,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.red, shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5)
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Center(
                  // '99' trơn khiến 386 tin trông như đúng 99. Dấu cộng cho
                  // biết đây là con số đã chặn trần.
                  child: Text(unreadCount > 99 ? '99+' : '$unreadCount', 
                    style: const TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildList(List<dynamic> list, String emptyMsg) {
    if (list.isEmpty) return _buildEmptyState(emptyMsg);
    return RefreshIndicator(
      onRefresh: fetchNotifications,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        itemCount: list.length,
        itemBuilder: (context, index) => _buildNotificationCard(list[index]),
      ),
    );
  }

  Widget _buildNotificationCard(dynamic notif) {
    bool isRead = (notif['IsRead'] == true || notif['IsRead'] == 1);
    String loai = notif['LoaiTin']?.toString().toUpperCase() ?? "PERSONAL";
    
    IconData icon;
    Color color;
    switch (loai) {
      case 'VAN_BAN': icon = Icons.description_outlined; color = Colors.indigo; break;
      case 'LICH_TUAN': icon = Icons.event_note_outlined; color = Colors.blue; break;
      case 'LICH_THI': icon = Icons.assignment_outlined; color = Colors.red; break;
      case 'CANH_BAO': icon = Icons.report_problem_outlined; color = Colors.orange; break;
      case 'LOP_HP': icon = Icons.school_outlined; color = Colors.green; break;
      default: icon = Icons.notifications_none_outlined; color = Colors.blueGrey;
    }

    return GestureDetector(
      // thongbao_screen.dart

// lib/views/thongbao_screen.dart

onTap: () async {
        String loai = notif['LoaiTin']?.toString().toUpperCase() ?? "";
        
        // ========================================================
        // 1. XỬ LÝ NẾU LÀ THÔNG BÁO TỪ NHÓM CHAT
        // ========================================================
        if (loai == 'CHAT' || loai == 'CHAT_GROUP') {
          final prefs = await SharedPreferences.getInstance();
          String uCode = prefs.getString('user_code') ?? "";

          if (mounted && uCode.isNotEmpty) {
            String specificGid = notif['Scope']?.toString() ?? 
                                 notif['GroupId']?.toString() ?? 
                                 notif['RoomID']?.toString() ?? "";

            if (specificGid.isEmpty && notif['Summary'] != null) {
              String summary = notif['Summary'].toString();
              if (summary.contains('private_')) specificGid = summary;
            }

            if (specificGid.isNotEmpty) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ChatRoomPage(groupId: specificGid, userCode: uCode)),
              ).then((_) => fetchNotifications());
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ChatGroupListPage(userCode: uCode)),
              ).then((_) => fetchNotifications());
            }
            return; // KẾT THÚC LUỒNG CHAT
          }
        }
        
        // ========================================================
        // 2. XỬ LÝ CÁC THÔNG BÁO THƯỜNG (Lịch tuần, Văn bản, Cảnh báo...)
        // ========================================================
        try {
          int notifId = int.parse(notif['ID']?.toString() ?? notif['id']?.toString() ?? '0');

          // A. Đánh dấu đã đọc: ghi vào máy ngay, báo máy chủ ở nền.
          // Trước 18/08/2026 chỉ ghi vào máy, phần báo máy chủ bị chú thích
          // nên đổi điện thoại là mất sạch trạng thái đã đọc.
          NotificationRepository.instance.danhDauDaDoc(notifId);

          // Trước đó trong hàm này có các lệnh chờ; màn hình có thể đã bị đóng
          // trong lúc đó, mở màn hình mới khi ấy sẽ gây lỗi.
          if (!context.mounted) return;

          // B. MỞ MÀN HÌNH CHI TIẾT NGAY LẬP TỨC (Không dùng await để tránh đơ)
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChiTietThongBaoScreen(notification: notif),
            ),
          ).then((_) {
            // Khi từ màn hình chi tiết quay lại, refresh list để mất dấu chấm đỏ
            fetchNotifications(); 
          });

        } catch (e) {
          debugPrint("❌ Lỗi click thông báo thường: $e");
        }
      },
      onLongPress: () => _showDeleteMenu(notif),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: isRead ? Colors.white : vinhUniBlue.withOpacity(0.04),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isRead ? Colors.transparent : vinhUniBlue.withOpacity(0.1)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(loai.replaceAll('_', ' '), style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color, letterSpacing: 0.5)),
                    Text(notif['NgayPhatHanh'] ?? "", style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                  ]),
                  const SizedBox(height: 6),
                  Text(notif['TieuDe'] ?? "", 
                    style: TextStyle(fontWeight: isRead ? FontWeight.w500 : FontWeight.bold, fontSize: 14, color: Colors.black87),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  // Bỏ thẻ HTML trước khi hiển thị — nội dung do cán bộ dán
                  // từ Word nên mang theo <p class="MsoNormal" style="...">
                  Text(
                    _tomTat(notif),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.3),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (!isRead) Container(margin: const EdgeInsets.only(top: 25, left: 5), width: 8, height: 8, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String msg) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_off_outlined, size: 60, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(msg, style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
        ],
      ),
    );
  }

  void _showMarkAllReadConfirm() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("Xác nhận", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: const Text("Bạn muốn đánh dấu tất cả thông báo là đã đọc?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Hủy", style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _danhDauTatCaDaDoc();
            },
            child: Text("Đồng ý", style: TextStyle(color: vinhUniBlue, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  

  /// Đánh dấu toàn bộ thông báo đã đọc và báo kết quả thật cho người dùng.
  ///
  /// Phân biệt rõ hai trường hợp: máy chủ đã ghi nhận, và chỉ đổi được trên máy
  /// này. Báo "thành công" khi máy chủ chưa nhận là nói dối người dùng — họ sẽ
  /// thấy các tin đó chưa đọc trở lại ở thiết bị khác.
  Future<void> _danhDauTatCaDaDoc() async {
    final mayChuDaNhan = await NotificationRepository.instance.danhDauTatCaDaDoc();
    if (!mounted) return;

    await fetchNotifications();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mayChuDaNhan
            ? "Đã đánh dấu tất cả là đã đọc"
            : "Đã đánh dấu trên máy này. Chưa đồng bộ được lên máy chủ, "
              "sẽ thử lại khi có mạng."),
        backgroundColor: mayChuDaNhan ? const Color(0xFF1D6A4C) : const Color(0xFF96631A),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showDeleteMenu(dynamic notif) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                title: const Text("Xóa thông báo này", style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500)),
                onTap: () { 
                  Navigator.pop(context); 
                  // 🔥 Ép kiểu an toàn và quét cả 'ID' lẫn 'id'
                  int notifId = int.parse((notif['ID'] ?? notif['id'] ?? 0).toString());
                  _handleHideNotif(notifId); 
                },
              ),
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: const Text("Hủy bỏ"),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Xoá một thông báo khỏi danh sách của người này.
  ///
  /// ⚠️ SỬA 19/08/2026: bản cũ CHỈ ghi vào SQLite, không hề báo máy chủ. Tin
  /// biến mất ngay nhưng lần tải sau lại quay về — và người dùng phải xoá lại,
  /// mãi không hết. Đổi điện thoại hay cài lại ứng dụng là tất cả trở lại.
  ///
  /// Đây đúng là lỗi đã gặp ở "đánh dấu đã đọc": hàm
  /// [NotificationRepository.an] vốn làm đúng cả hai việc, nhưng màn hình này
  /// không gọi nó mà tự ghi thẳng xuống SQLite.
  Future<void> _handleHideNotif(int id) async {
    // 1. Bỏ khỏi giao diện NGAY, không bắt người dùng chờ mạng
    setState(() {
      generalNotifs.removeWhere((item) => (item['ID'] ?? item['id']) == id);
      workNotifs.removeWhere((item) => (item['ID'] ?? item['id']) == id);
      reminderNotifs.removeWhere((item) => (item['ID'] ?? item['id']) == id);
      personalNotifs.removeWhere((item) => (item['ID'] ?? item['id']) == id);
    });
    _calculateAndApplyBadges();

    // 2. Ghi vào máy rồi báo máy chủ — cả hai do kho dữ liệu lo
    final mayChuDaNhan = await NotificationRepository.instance.an(id);
    if (!mounted) return;

    if (!mayChuDaNhan) {
      // Nói thật: đã xoá trên máy này, nhưng thiết bị khác vẫn còn thấy
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Đã xoá trên máy này. Chưa đồng bộ được lên máy chủ, "
              "tin có thể xuất hiện lại ở thiết bị khác."),
          backgroundColor: Color(0xFF96631A),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }
}