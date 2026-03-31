Widget _buildFeatureGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- PHẦN 1: CHỨC NĂNG CHÍNH ---
          _buildSectionTitle("Chức năng chính"),
          if (widget.appMenu.isNotEmpty)
            _buildGridSystem([
              ...widget.appMenu.map((m) {
                Color c = Color(int.parse(m['color']));
                return _buildItemWidget(m, c);
              }).toList(),
            ]),

          const SizedBox(height: 20), // Khoảng cách giữa 2 phần

          // --- PHẦN 2: CỔNG CÁN BỘ (Chỉ hiện khi là CanBo) ---
          if (widget.userRole == 'CanBo') ...[
            const SizedBox(height: 10),
            _buildSectionTitle("Cổng cán bộ"),
            _buildGridSystem([
              _buildItemWidget({
                'title': 'Xếp loại',
                'icon': 'leaderboard', // Biểu tượng cột xếp hạng
                'color': '0xFF1976D2',
                'route': '/xep_loai',
              }, const Color(0xFF1976D2)),

              _buildItemWidget({
                'title': 'Hồ sơ cá nhân',
                'icon': 'account_box', // Biểu tượng thẻ hồ sơ
                'color': '0xFF388E3C', // Màu xanh lá cho hồ sơ
                'route': '/ho_so',
              }, const Color(0xFF388E3C)),
              _buildItemWidget({
                'title': 'Danh bạ cán bộ',
                'icon': 'contact_phone', // Biểu tượng danh bạ điện thoại
                'color': '0xFF7B1FA2', // Màu tím
                'route': '/danh_ba',
              }, const Color(0xFF7B1FA2)),
            ]),
          ],
        ],
      ),
    );
  }

// Widget bổ trợ để vẽ tiêu đề phần cho đỡ lặp code
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 5, bottom: 15),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

// Widget bổ trợ để cấu hình GridView dùng chung
  Widget _buildGridSystem(List<Widget> children) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.9,
      children: children,
    );
  }

// Tách hàm này ra để dùng chung cho cả map và thêm cứng, tránh lặp code switch-case
  Widget _buildItemWidget(Map<String, dynamic> m, Color c) {
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
          case '/ket_qua_chung_nhan': Navigator.push(context, MaterialPageRoute(builder: (context) => ChungChiTraCuuScreen(userMaSV: widget.studentId))); break;
          //Cổng cán bộ
          case '/xep_loai':
            Navigator.push(context, MaterialPageRoute(builder: (context) => XepLoaiScreen(hsid: widget.studentId,chucNang: 'XepLoai_ThangTheoCaNhan',title: 'Xếp loại cá nhân')));
            break;
          case '/ho_so':
            Navigator.push(context, MaterialPageRoute(builder: (context) => XepLoaiScreen(hsid: widget.studentId,chucNang: 'profile_about',title: 'Hồ sơ cá nhân')));
            break;
          case '/danh_ba':
            Navigator.push(context, MaterialPageRoute(builder: (context) => XepLoaiScreen(hsid: widget.studentId,chucNang: 'LUI_DanhBaCanBo',title: 'Danh bạ cán bộ')));
            break;
           //Mặc định
          default: try { Navigator.pushNamed(context, route); } catch (e) {} break;
        }
      },
      child: Column(children: [
        Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
            child: Icon(_getIcon(m['icon']), size: 30, color: c)
        ),
        const SizedBox(height: 8),
        Text(m['title'], textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis)
      ]),
    );
  }          