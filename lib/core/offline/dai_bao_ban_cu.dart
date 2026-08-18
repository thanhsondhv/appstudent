import 'package:flutter/material.dart';

/// Dải báo mỏng hiện ở đầu danh sách khi màn hình đang hiển thị dữ liệu đã lưu
/// trên máy vì không gọi được máy chủ.
///
/// Vì sao cần: các màn tra cứu vẫn hiện dữ liệu cũ khi mất mạng — đúng, vì có
/// còn hơn không. Nhưng nếu không nói gì, người dùng tưởng đó là số liệu mới
/// nhất. Với lịch thi hay lịch dạy thì hiểu nhầm đó dẫn tới đi nhầm phòng,
/// nhầm giờ.
///
/// Cố ý làm mỏng và không chặn thao tác: đây là thông tin phụ, không phải lỗi.
///
/// Thêm ngày 18/08/2026 (Pha 1).
class DaiBaoBanCu extends StatelessWidget {
  const DaiBaoBanCu({
    super.key,
    required this.hienThi,
    this.khiBamTaiLai,
  });

  final bool hienThi;

  /// Bỏ trống thì dải báo không có nút tải lại.
  final VoidCallback? khiBamTaiLai;

  @override
  Widget build(BuildContext context) {
    if (!hienThi) return const SizedBox.shrink();

    const Color mauCanhBao = Color(0xFF96631A);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      color: const Color(0xFFFBF2E1),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 17, color: mauCanhBao),
          const SizedBox(width: 9),
          const Expanded(
            child: Text(
              'Đang xem dữ liệu đã lưu trên máy. Có thể chưa phải bản mới nhất.',
              style: TextStyle(fontSize: 12.5, color: mauCanhBao, height: 1.3),
            ),
          ),
          if (khiBamTaiLai != null)
            TextButton(
              onPressed: khiBamTaiLai,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Tải lại',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: mauCanhBao,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
