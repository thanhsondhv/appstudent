import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';

class TaiChinhScreen extends StatefulWidget {
  const TaiChinhScreen({super.key});

  @override
  State<TaiChinhScreen> createState() => _TaiChinhScreenState();
}

class _TaiChinhScreenState extends State<TaiChinhScreen> with SingleTickerProviderStateMixin {
  final Color vinhUniBlue = const Color(0xFF0054A6);
  final Color backgroundLight = const Color(0xFFF8FAFF);

  bool isLoading = true;
  String? errorMessage;
  Map<String, dynamic> financeData = {};
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchFinanceData();
  }

  Future<void> _fetchFinanceData() async {
    setState(() { isLoading = true; errorMessage = null; });
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? userId = prefs.getString('user_code') ?? prefs.getString('user_id');

      if (userId == null || userId.isEmpty) {
        setState(() { errorMessage = "Vui lòng đăng nhập!"; isLoading = false; });
        return;
      }

      final url = 'https://mobi.vinhuni.edu.vn/api/finance/$userId';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        setState(() {
          financeData = json.decode(response.body);
          isLoading = false;
        });
      } else {
        setState(() { errorMessage = "Không thể tải dữ liệu"; isLoading = false; });
      }
    } catch (e) {
      setState(() { errorMessage = "Lỗi kết nối máy chủ"; isLoading = false; });
    }
  }

  String formatCurrency(double amount) {
    final formatCurrency = NumberFormat.currency(locale: "vi_VN", symbol: "đ");
    return formatCurrency.format(amount);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundLight,
      appBar: AppBar(
        title: const Text("THÔNG TIN TÀI CHÍNH", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
        backgroundColor: vinhUniBlue,
        centerTitle: true,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator(color: vinhUniBlue))
          : errorMessage != null
              ? _buildErrorView()
              : Column(
                  children: [
                    _buildBalanceCard(),
                    _buildTabBar(),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildTuitionDetails(),
                          _buildTransactionHistory(),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  // 💳 THẺ THÔNG TIN TÀI KHOẢN (SỐ DƯ VÍ & CÔNG NỢ)
  Widget _buildBalanceCard() {
    double soDuVi = (financeData['so_du_vi'] ?? 0).toDouble();
    double conNo = (financeData['tong_con_no'] ?? 0).toDouble();
    double daNop = (financeData['tong_da_nop'] ?? 0).toDouble();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [vinhUniBlue, const Color(0xFF0078D4)], 
          begin: Alignment.topLeft, 
          end: Alignment.bottomRight
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: vinhUniBlue.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("SỐ DƯ TÀI KHOẢN", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
              Icon(Icons.account_balance_wallet_rounded, color: Colors.white.withOpacity(0.8), size: 24),
            ],
          ),
          const SizedBox(height: 8),
          
          Text(
            formatCurrency(soDuVi),
            style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
          
          const SizedBox(height: 24),
          Container(height: 1, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 16),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Đã thanh toán phí", style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(formatCurrency(daNop), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: conNo > 0 ? Colors.redAccent.withOpacity(0.8) : Colors.white.withOpacity(0.2), 
                  borderRadius: BorderRadius.circular(12)
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(conNo > 0 ? "Cần nộp" : "Đã hoàn thành", style: const TextStyle(color: Colors.white, fontSize: 11)),
                    const SizedBox(height: 2),
                    Text(
                      conNo > 0 ? formatCurrency(conNo) : "0 đ", 
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)
                    ),
                  ],
                ),
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: TabBar(
        controller: _tabController,
        labelColor: vinhUniBlue,
        unselectedLabelColor: Colors.blueGrey,
        indicatorColor: vinhUniBlue,
        indicatorWeight: 3,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        tabs: const [
          Tab(text: "Chi tiết khoản thu"),
          Tab(text: "Lịch sử nạp/rút"),
        ],
      ),
    );
  }

  // 📝 TAB 1: CHI TIẾT CÁC KHOẢN THU
  Widget _buildTuitionDetails() {
    List details = financeData['chi_tiet_hoc_phi'] ?? [];
    if (details.isEmpty) return _buildEmptyState("Không có dữ liệu công nợ");

    return ListView.builder(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 40),
      itemCount: details.length,
      itemBuilder: (context, index) {
        var item = details[index];
        double conNo = (item['con_no'] ?? 0).toDouble();
        
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: conNo > 0 ? Colors.red.shade50 : Colors.green.shade50,
              child: Icon(conNo > 0 ? Icons.receipt_long : Icons.check_circle, color: conNo > 0 ? Colors.redAccent : Colors.green),
            ),
            title: Text(item['ma_hoc_phan'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text("Năm học: ${item['nam_hoc']}", style: const TextStyle(fontSize: 12)),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatCurrency((item['hoc_phi'] ?? 0).toDouble()), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                  conNo > 0 ? "Cần nộp: ${formatCurrency(conNo)}" : "Đã hoàn thành", 
                  style: TextStyle(fontSize: 11, color: conNo > 0 ? Colors.red : Colors.green, fontWeight: FontWeight.bold)
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 💳 TAB 2: LỊCH SỬ GIAO DỊCH
  Widget _buildTransactionHistory() {
    List transactions = financeData['lich_su_giao_dich'] ?? [];
    if (transactions.isEmpty) return _buildEmptyState("Chưa có giao dịch nào");

    return ListView.builder(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 40),
      itemCount: transactions.length,
      itemBuilder: (context, index) {
        var tx = transactions[index];
        bool isSuccess = tx['trang_thai'] == "Thành công";

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: isSuccess ? Colors.green.shade50 : Colors.orange.shade50,
              child: Icon(isSuccess ? Icons.account_balance_wallet : Icons.schedule, color: isSuccess ? Colors.green : Colors.orange),
            ),
            title: Text(tx['noi_dung'], maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(tx['ngay_giao_dich'], style: const TextStyle(fontSize: 11)),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text("+${formatCurrency((tx['so_tien'] ?? 0).toDouble())}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 14)),
                const SizedBox(height: 4),
                Text(tx['trang_thai'], style: TextStyle(fontSize: 11, color: isSuccess ? Colors.green : Colors.orange, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(String msg) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(Icons.account_balance_wallet_outlined, size: 60, color: Colors.grey.shade300),
    const SizedBox(height: 12),
    Text(msg, style: TextStyle(color: Colors.grey.shade500))
  ]));

  Widget _buildErrorView() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Icon(Icons.error_outline, size: 50, color: Colors.redAccent),
    const SizedBox(height: 12),
    Text(errorMessage ?? "Lỗi", style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
    ElevatedButton(onPressed: _fetchFinanceData, child: const Text("Thử lại"))
  ]));
}