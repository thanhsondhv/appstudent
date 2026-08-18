/// Chuyển một đoạn HTML thành văn bản thuần để hiển thị ở phần tóm tắt.
///
/// Vì sao cần: nội dung thông báo do cán bộ soạn trên trình soạn thảo web, và
/// phần lớn được dán từ Microsoft Word nên mang theo cả rừng thẻ
/// `<p class="MsoNormal" style="...">`. Danh sách thông báo trong ứng dụng lại
/// hiển thị trường tóm tắt bằng widget `Text` thuần — nên người dùng nhìn thấy
/// nguyên mã HTML thay vì nội dung:
///
///     <p class="MsoNormal" style="text-align: justify; line-height: 18.0pt…
///     <p>Mời c&aacute;c th&iacute; sinh dự thi Đ&aacute;nh gi&aacute; NLNN…
///
/// Hàm này chỉ dùng cho phần XEM TRƯỚC. Màn hình chi tiết vẫn dựng HTML đầy đủ
/// bằng widget chuyên dụng để giữ định dạng, bảng biểu, đường dẫn.
///
/// Thêm ngày 18/08/2026.
library;

/// Các thực thể HTML hay gặp trong văn bản tiếng Việt soạn từ Word.
const Map<String, String> _thucThe = {
  '&nbsp;': ' ',
  '&amp;': '&',
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&apos;': "'",
  '&#39;': "'",
  '&ldquo;': '"',
  '&rdquo;': '"',
  '&lsquo;': "'",
  '&rsquo;': '’',
  '&hellip;': '…',
  '&ndash;': '–',
  '&mdash;': '—',
  // Nguyên âm có dấu — Word hay xuất ra dạng thực thể thay vì ký tự Unicode
  '&aacute;': 'á', '&agrave;': 'à', '&acirc;': 'â', '&atilde;': 'ã',
  '&eacute;': 'é', '&egrave;': 'è', '&ecirc;': 'ê',
  '&iacute;': 'í', '&igrave;': 'ì',
  '&oacute;': 'ó', '&ograve;': 'ò', '&ocirc;': 'ô', '&otilde;': 'õ',
  '&uacute;': 'ú', '&ugrave;': 'ù', '&yacute;': 'ý',
  '&Aacute;': 'Á', '&Agrave;': 'À', '&Acirc;': 'Â',
  '&Eacute;': 'É', '&Ecirc;': 'Ê',
  '&Oacute;': 'Ó', '&Ocirc;': 'Ô',
  '&Uacute;': 'Ú',
  '&dstrok;': 'đ', '&Dstrok;': 'Đ',
};

final RegExp _theHtml = RegExp(r'<[^>]*>');
final RegExp _khoiBoDi = RegExp(
  r'<(script|style)[^>]*>.*?</\1>',
  caseSensitive: false,
  dotAll: true,
);
final RegExp _soThapPhan = RegExp(r'&#(\d+);');
final RegExp _soThapLucPhan = RegExp(r'&#[xX]([0-9a-fA-F]+);');
final RegExp _nhieuKhoangTrang = RegExp(r'\s+');
/// Thẻ mở bị cắt cụt ở cuối chuỗi: `<span style="...` không có dấu '>'.
final RegExp _theBiCatDo = RegExp(r'<[^>]*$');
/// Phần đuôi của một thẻ đã mất dấu '<' mở, nằm ở đầu chuỗi:
/// `font-family: 'Times New Roman';">Nội dung` → chỉ giữ `Nội dung`.
final RegExp _duoiTheODau = RegExp(r'^[^<>]*\"\s*>');

/// Trả về văn bản thuần từ [html], đã bỏ thẻ và giải mã thực thể.
///
/// [gioiHan] cắt bớt nếu quá dài — mặc định 0 nghĩa là không cắt.
String rutGonHtml(String? html, {int gioiHan = 0}) {
  if (html == null || html.isEmpty) return '';

  var vanBan = html;

  // 1. Bỏ hẳn phần script và style kèm nội dung bên trong
  vanBan = vanBan.replaceAll(_khoiBoDi, ' ');

  // 2. Đổi các thẻ ngắt dòng thành khoảng trắng, tránh dính chữ hai đoạn
  vanBan = vanBan.replaceAll(
    RegExp(r'</?(br|p|div|tr|li|h[1-6])[^>]*>', caseSensitive: false),
    ' ',
  );

  // 3. Bỏ mọi thẻ còn lại
  vanBan = vanBan.replaceAll(_theHtml, '');

  // 3b. Bỏ thẻ bị cắt dở ở cuối chuỗi.
  //
  // Máy chủ dựng trường tóm tắt bằng cách cắt cứng nội dung HTML theo số ký tự,
  // nên hay cắt ngay giữa một thẻ:
  //     <span style="font-size: 12pt; font-family: 'Times New Roman'
  // Thẻ này không có dấu '>' đóng nên biểu thức ở bước 3 không khớp, và người
  // dùng nhìn thấy nguyên đoạn mã trong danh sách thông báo.
  vanBan = vanBan.replaceAll(_theBiCatDo, '');

  // 3c. Tương tự cho phần đầu: nếu chuỗi bắt đầu bằng phần đuôi của một thẻ
  // đã bị cắt mất dấu '<' mở.
  vanBan = vanBan.replaceFirst(_duoiTheODau, '');

  // 4. Giải mã thực thể
  _thucThe.forEach((ma, ky_tu) {
    vanBan = vanBan.replaceAll(ma, ky_tu);
  });
  vanBan = vanBan.replaceAllMapped(_soThapPhan, (m) {
    final ma = int.tryParse(m.group(1)!);
    return ma != null ? String.fromCharCode(ma) : m.group(0)!;
  });
  vanBan = vanBan.replaceAllMapped(_soThapLucPhan, (m) {
    final ma = int.tryParse(m.group(1)!, radix: 16);
    return ma != null ? String.fromCharCode(ma) : m.group(0)!;
  });

  // 5. Gom khoảng trắng thừa
  vanBan = vanBan.replaceAll(_nhieuKhoangTrang, ' ').trim();

  if (gioiHan > 0 && vanBan.length > gioiHan) {
    return '${vanBan.substring(0, gioiHan).trimRight()}…';
  }
  return vanBan;
}
