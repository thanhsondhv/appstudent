import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class BHYTScreen extends StatefulWidget {
  const BHYTScreen({super.key});

  @override
  State<BHYTScreen> createState() => _BHYTScreenState();
}

class _BHYTScreenState extends State<BHYTScreen> {
  bool isLoading = true;
  Map<String, dynamic>? data;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String userId = prefs.getString('user_code') ?? prefs.getString('user_id') ?? "";
      final response = await http.get(Uri.parse('https://mobi.vinhuni.edu.vn/api/bhyt/$userId'));
      if (response.statusCode == 200) {
        setState(() {
          data = json.decode(response.body);
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  String formatVND(double amount) => NumberFormat.currency(locale: 'vi_VN', symbol: 'đ').format(amount);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        title: const Text("BẢO HIỂM Y TẾ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
        backgroundColor: const Color(0xFF0054A6),
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
      ),
      body: isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF0054A6))) 
        : RefreshIndicator(
            onRefresh: _fetchData,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDigitalCard(),
                  const SizedBox(height: 24),
                  const Text("LỊCH SỬ ĐĂNG KÝ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0054A6))),
                  const SizedBox(height: 12),
                  _buildHistoryList(),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildDigitalCard() {
    var the = data?['the_bhyt'];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF009688), Color(0xFF00695C)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: const Color(0xFF009688).withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("THẺ BẢO HIỂM Y TẾ", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              const Icon(Icons.health_and_safety, color: Colors.white70),
            ],
          ),
          const SizedBox(height: 24),
          Text(the?['so_the'] ?? "---", style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 2)),
          const SizedBox(height: 24),
          Row(
            children: [
              _cardInfoItem("TỪ NGÀY", the?['tu_ngay']),
              const SizedBox(width: 40),
              _cardInfoItem("ĐẾN NGÀY", the?['den_ngay']),
            ],
          )
        ],
      ),
    );
  }

  Widget _cardInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(value ?? "---", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }

  Widget _buildHistoryList() {
    List history = data?['lich_su'] ?? [];
    if (history.isEmpty) return const Center(child: Padding(padding: EdgeInsets.only(top: 20), child: Text("Chưa có lịch sử đăng ký")));
    
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: history.length,
      itemBuilder: (context, index) {
        var item = history[index];
        bool isSuccess = item['trang_thai'] == "Đã cấp thẻ" || item['trang_thai'] == "Đã duyệt";
        
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade100)),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            title: Text(item['ten_dot'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text("Ngày ĐK: ${item['ngay_dk']}\nHạn dùng: ${item['han_dung']}", style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.5)),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatVND(item['so_tien']), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 14)),
                const SizedBox(height: 4),
                Text(item['trang_thai'], style: TextStyle(color: isSuccess ? Colors.green : Colors.orange, fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        );
      },
    );
  }
}