class _HomeContentState extends State<HomeContent> {
  // --- [KHAI BÁO BIẾN TRẠNG THÁI] ---
  int _selectedTabIndex = 0;
  final Color vinhUniBlue = const Color(0xFF0054A6); //
  final _voiceService = VoiceControlService(); 
  bool _isVoiceLoading = false;

  // --- [HÀM HỖ TRỢ] ---

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg), 
        backgroundColor: color, 
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      )
    );
  }

  // Xử lý điều hướng thông minh từ AI Intent
  void _handleVoiceNavigation(String route, String message) {
    if (route.isEmpty) {
      _showSnackBar("🤖 AI: $message", Colors.orange);
      return;
    }
    
    _showSnackBar("🚀 $message", Colors.green);

    final String role = widget.userRole.toLowerCase();
    bool isStaff = role == 'canbo' || role == 'admin' || role == 'covan' || role == 'ad' || role == 'cb';

    switch (route) {
      case '/ai_secretary': 
        Navigator.push(context, MaterialPageRoute(builder: (context) => const MeetingRecorderScreen())); 
        break;
      case '/vanban': 
        Navigator.push(context, MaterialPageRoute(builder: (context) => const VanBanScreen())); 
        break;
      case '/lichcongtac': 
        Navigator.push(context, MaterialPageRoute(builder: (context) => const StaffScheduleScreen())); 
        break;
      case '/mo_diem_danh': 
        if (isStaff) {
          Navigator.push(context, MaterialPageRoute(builder: (context) => MoDiemDanhScreen(lecturerId: widget.studentId))); 
        } else {
          _showSnackBar("Chức năng chỉ dành cho cán bộ", Colors.red);
        }
        break;
      case '/student_feedback':
        Navigator.push(context, MaterialPageRoute(builder: (context) => const StudentSendToStaffScreen()));
        break;
      case '/ket_qua_chung_nhan':
        Navigator.push(context, MaterialPageRoute(builder: (context) => ChungChiTraCuuScreen(userMaSV: widget.studentId)));
        break;
      default: 
        try { 
          Navigator.pushNamed(context, route); 
        } catch (e) {
          _showSnackBar("Không tìm thấy chức năng này", Colors.red);
        }
        break;
    }
  }

  IconData _getIcon(String code) {
    switch (code) {
      case 'edit_calendar_rounded': return Icons.edit_calendar_rounded;
      case 'fact_check_rounded': return Icons.fact_check_rounded;
      case 'calendar_today': return Icons.calendar_today;
      case 'verified': return Icons.verified_user_rounded;
      case 'description_rounded': return Icons.description_rounded;  
      case 'card_membership': return Icons.card_membership;
      case 'event_note': return Icons.event_note;
      case 'assignment': return Icons.assignment;
      case 'bar_chart': return Icons.bar_chart;
      case 'schema_rounded': return Icons.schema_rounded;
      case 'grading_rounded': return Icons.grading_rounded;
      case 'account_balance_wallet_rounded': return Icons.account_balance_wallet_rounded;
      case 'health_and_safety_rounded': return Icons.health_and_safety_rounded;
      case 'military_tech_rounded': return Icons.military_tech_rounded;
      case 'card_giftcard_rounded': return Icons.card_giftcard_rounded;
      case 'warning_amber_rounded': return Icons.warning_amber_rounded;
      case 'campaign_rounded': return Icons.campaign_rounded;
      case 'auto_awesome': return Icons.auto_awesome;
      case 'settings': return Icons.settings;
      case 'leaderboard': return Icons.leaderboard_rounded;
      case 'account_box': return Icons.account_box_rounded;
      case 'contact_phone': return Icons.contact_phone_rounded;
      case 'chat_groups': return Icons.chat_rounded;
      case 'history_edu_rounded': return Icons.history_edu_rounded;
      case 'mic_external_on': return Icons.mic_external_on;
      case 'support_agent_rounded': return Icons.support_agent_rounded;
      case 'settings_suggest_rounded': return Icons.settings_suggest_rounded;
      case 'cloud_done_rounded': 
        return Icons.cloud_done_rounded;
      case 'school_rounded':
      return Icons.school_rounded;
      case 'document_scanner_rounded':
      return Icons.document_scanner_rounded;  
      default: return Icons.widgets_rounded; 
    }
  }

  // --- [GIAO DIỆN CHÍNH] ---

  @override
  Widget build(BuildContext context) {
    final String role = widget.userRole.toLowerCase();
    bool isStaff = role == 'canbo' || role == 'admin' || role == 'covan' || role == 'ad' || role == 'cb';
    
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(), 
      padding: const EdgeInsets.only(bottom: 120),
      child: Column(children: [
        _buildHeader(),
        if (isStaff) _buildTeacherBanner() else _buildStatisticCard(),
        _buildSearchBar(), 
        const SizedBox(height: 15),
        _buildFeatureGrid(isStaff),
        const SizedBox(height: 25),
        _buildNewsSection(),
      ]),
    );
  }

  // --- [CÁC COMPONENT GIAO DIỆN] ---

  Widget _buildHeader() {
    return Stack(
      children: [
        Container(height: 140, decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF0054A6), Color(0xFF0078D4)]), borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 15),
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.menu, color: Colors.white, size: 28), onPressed: () => Scaffold.of(context).openDrawer()),
              const SizedBox(width: 5),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.studentName.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis), const SizedBox(height: 4), Text(widget.faculty.isNotEmpty ? widget.faculty : "Mã số: ${widget.studentId}", style: const TextStyle(color: Colors.white70, fontSize: 12))])),
              GestureDetector(
                onTap: widget.onAvatarTap, 
                child: Container(
                  width: 52, height: 52, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                  child: ClipOval(
                    child: (widget.studentId != "") 
                      ? CachedNetworkImage(imageUrl: widget.avatarUrl ?? "", cacheKey: widget.studentId, fit: BoxFit.cover, errorWidget: (context, url, error) => const Icon(Icons.person, color: Colors.white))
                      : const Icon(Icons.person, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Trong _HomeContentState của home_screen.dart

String _voiceInstruction = "Tìm kiếm dịch vụ..."; // Mặc định

// --- [Nâng cấp giao diện Search Bar và Mic] ---
 Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      child: GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SearchScreen())),
        child: Container(height: 50, padding: const EdgeInsets.symmetric(horizontal: 18), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), border: Border.all(color: Colors.blue.withOpacity(0.1)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)]), child: Row(children: [const Icon(Icons.search_rounded, color: Color(0xFF0054A6), size: 22), const SizedBox(width: 12), Expanded(child: Text("Tìm kiếm dịch vụ...", style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 13))), Icon(Icons.mic_none_rounded, color: Colors.blueGrey.shade300, size: 20)])),
      ),
    );
  }

  Widget _buildFeatureGrid(bool isStaff) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.only(left: 5, bottom: 15), child: Text("Chức năng chính", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
        if (widget.appMenu.isNotEmpty) GridView.count(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.9, 
          children: widget.appMenu.map((m) { 
            Color c = Color(int.parse(m['color'])); 
            return GestureDetector(
              onTap: () { 
                final String route = m['route'] ?? ''; 
                switch (route) { 
                  case '/diem_danh_sv': Navigator.push(context, MaterialPageRoute(builder: (context) => DiemDanhSvScreen(studentId: widget.studentId))); break; 
                  case '/mo_diem_danh': Navigator.push(context, MaterialPageRoute(builder: (context) => MoDiemDanhScreen(lecturerId: widget.studentId))); break; 
                  case '/quan_ly_nghi_hoc': Navigator.push(context, MaterialPageRoute(builder: (context) => QuanLyXinPhepScreen(studentId: widget.studentId))); break; 
                  case '/duyet_vang_hoc': Navigator.push(context, MaterialPageRoute(builder: (context) => DuyetVangHocScreen(lecturerId: widget.studentId))); break; 
                  case '/chatscreen': if (widget.onChatTap != null) widget.onChatTap!(); break; 
                  case '/profile': if (widget.onAvatarTap != null) widget.onAvatarTap!(); break; 
                  case '/vanban': Navigator.push(context, MaterialPageRoute(builder: (context) => const VanBanScreen())); break; 
                  case '/certificate_page': Navigator.push(context, MaterialPageRoute(builder: (context) => CertificatePage(studentId: widget.studentId))); break; 
                  case '/lichcongtac': Navigator.push(context, MaterialPageRoute(builder: (context) => StaffScheduleScreen())); break; 
                  case '/xep_loai': Navigator.push(context, MaterialPageRoute(builder: (context) => XepLoaiScreen(hsid: widget.studentId, chucNang: 'XepLoai_ThangTheoCaNhan', title: 'Xếp loại cán bộ'))); break; 
                  case '/ho_so': Navigator.push(context, MaterialPageRoute(builder: (context) => XepLoaiScreen(hsid: widget.studentId, chucNang: 'ho-so-ca-nhan', title: 'Hồ sơ cán bộ'))); break; 
                  case '/ket_qua_chung_nhan': Navigator.push(context, MaterialPageRoute(builder: (context) => ChungChiTraCuuScreen(userMaSV: widget.studentId))); break; 
                  case '/ai_secretary': Navigator.push(context, MaterialPageRoute(builder: (context) => const MeetingRecorderScreen())); break;     
                  case '/student_feedback': Navigator.push(context, MaterialPageRoute(builder: (context) => const StudentSendToStaffScreen())); break;
                  case '/student_secretary':
                    Navigator.push(
                      context, 
                      MaterialPageRoute(builder: (context) => const StudentSecretaryScreen())
                    );
                    break;

                  case '/document_scanner':
                    Navigator.push(
                      context, 
                      MaterialPageRoute(builder: (context) => const DocumentScannerScreen())
                    );
                    break;
                  case '/onedrive_manager': 
                    Navigator.push(
                      context, 
                      MaterialPageRoute(builder: (context) => const OneDriveManagerScreen())
                    ); 
                    break;
                  //case '/chat_group_list': 
                  //  if (isStaff) Navigator.push(context, MaterialPageRoute(builder: (context) => ChatGroupListPage(userCode: widget.studentId))); 
                  //  else _showSnackBar("Chức năng chỉ dành cho cán bộ", Colors.orange);
                  //  break;
                  case '/chat_group_list': 
                    if (isStaff) {
                      // 🔥 CHUYỂN ĐỔI: Thay thế ChatGroupListPage bằng TeamsChatListScreen chuyên nghiệp
                      Navigator.push(
                        context, 
                        MaterialPageRoute(builder: (context) => const TeamsChatListScreen())
                      );
                    } else {
                      _showSnackBar("Chức năng chỉ dành cho cán bộ", Colors.orange);
                    }
                    break; 
                  default: Navigator.pushNamed(context, route); break; 
                } 
              }, 
              child: Column(children: [Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(20)), child: Icon(_getIcon(m['icon']), size: 30, color: c)), const SizedBox(height: 8), Text(m['title'], textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis)]),
            ); 
          }).toList(),
        )
      ]),
    );
  }

  Widget _buildStatisticCard() {
    if (widget.studentProfilesList.isEmpty) return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    if (_selectedTabIndex >= widget.studentProfilesList.length) _selectedTabIndex = 0;
    final current = widget.studentProfilesList[_selectedTabIndex];
    String status = current['trang_thai'] ?? "---";
    Color statusColor = status.toLowerCase().contains("tốt nghiệp") ? Colors.green : status.toLowerCase().contains("bảo lưu") ? Colors.orange : Colors.blue;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20), transform: Matrix4.translationValues(0, -20, 0),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade200), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
      child: Column(children: [
        if (widget.studentProfilesList.length > 1) Container(height: 38, decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))), child: Row(children: List.generate(widget.studentProfilesList.length, (index) => Expanded(child: GestureDetector(onTap: () => setState(() => _selectedTabIndex = index), child: Container(alignment: Alignment.center, decoration: BoxDecoration(border: Border(bottom: BorderSide(color: index == _selectedTabIndex ? vinhUniBlue : Colors.transparent, width: 2.5))), child: Text(widget.studentProfilesList[index]['ten_nganh'] ?? 'Ngành', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: index == _selectedTabIndex ? FontWeight.bold : FontWeight.w500, color: index == _selectedTabIndex ? vinhUniBlue : Colors.grey.shade500)))))))),
        Padding(padding: const EdgeInsets.all(18), child: Column(children: [if (widget.studentProfilesList.length == 1) Padding(padding: const EdgeInsets.only(bottom: 15), child: Text(current['ten_nganh'] ?? "Ngành học", style: TextStyle(fontWeight: FontWeight.bold, color: vinhUniBlue, fontSize: 14))), Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_statBox("GPA", current['gpa'].toString(), vinhUniBlue), Container(width: 1, height: 30, color: Colors.grey.withOpacity(0.2)), _statBox("Tín chỉ", current['tin_chi'].toString(), vinhUniBlue), Container(width: 1, height: 30, color: Colors.grey.withOpacity(0.2)), _statBox("Xếp loại", current['rank'], const Color(0xFF1B5E20))]), const SizedBox(height: 18), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Trạng thái:", style: TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.w500)), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text(status.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor)))])]))
      ]),
    );
  }

  Widget _statBox(String label, String val, Color c) => Column(children: [Text(val, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c)), const SizedBox(height: 4), Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600))]);
  
 Widget _buildTeacherBanner() => Container(
  margin: const EdgeInsets.symmetric(horizontal: 20),
  transform: Matrix4.translationValues(0, -20, 0), // Giữ nguyên hiệu ứng đè lên header
  padding: const EdgeInsets.all(20),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: vinhUniBlue.withOpacity(0.2)),
    boxShadow: [
      BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20)
    ],
  ),
  child: Row(
    children: [
      // Icon bảo mật/quản trị
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.admin_panel_settings_rounded, 
          color: Colors.orange, 
          size: 32,
        ),
      ),
      const SizedBox(width: 16),
      // Chỉ giữ lại tiêu đề chính
      const Expanded(
        child: Text(
          "Cổng thông tin Cán bộ",
          style: TextStyle(
            fontSize: 16, 
            fontWeight: FontWeight.bold, 
            color: Color(0xFF003366),
          ),
        ),
      ),
    ],
  ),
); 
  Widget _buildNewsSection() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Padding(padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15), child: Text("Khám phá VinhUni", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))), SizedBox(height: 150, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.only(left: 20, right: 10), children: [_buildNewsCard("Thư viện số", "Tài liệu online", Icons.auto_stories, Colors.blue, "https://thuvien.vinhuni.edu.vn/"), _buildNewsCard("Tin tức", "Thông báo mới", Icons.newspaper, Colors.green, "https://vinhuni.edu.vn/"), _buildNewsCard("Hotline", "Hỗ trợ SV", Icons.headset_mic, Colors.orange, "tel:02383855452")]))]);
  
  Widget _buildNewsCard(String title, String desc, IconData icon, Color color, String url) => GestureDetector(onTap: () async { final uri = Uri.parse(url); if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication); }, child: Container(width: 220, margin: const EdgeInsets.only(right: 15), padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: LinearGradient(colors: [color, color.withOpacity(0.7)]), borderRadius: BorderRadius.circular(24)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Icon(icon, color: Colors.white, size: 28), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)), Text(desc, style: const TextStyle(color: Colors.white70, fontSize: 11))])])));
}