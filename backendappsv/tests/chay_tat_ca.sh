#!/usr/bin/env bash
# Chạy toàn bộ kiểm tra của backend.
#
# Không cần Redis, Firebase, hay kết nối cơ sở dữ liệu — cố ý như vậy để chạy
# được ở bất kỳ đâu, kể cả trên máy chưa cài gì và trong CI.
#
# Dùng:  bash tests/chay_tat_ca.sh
# Trả về mã thoát khác 0 nếu có bất kỳ kiểm tra nào không đạt.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

LOI=0

muc() { printf "\n\033[1m%s\033[0m\n" "$1"; }

muc "1. Biên dịch toàn bộ mã nguồn"
if python3 -m compileall -q . -x '(__pycache__|_luu_tru|venv|node_modules)' 2>&1 | grep -q .; then
  echo "   ❌ có tệp không biên dịch được"; LOI=1
else
  echo "   ✅ tất cả biên dịch được"
fi

muc "2. Tên chưa định nghĩa ở cấp module"
# py_compile KHÔNG bắt được loại lỗi này: `fsettings.db.x` là cú pháp hợp lệ
# nhưng chạy là NameError ngay, và vì ở cấp module nên tiến trình không khởi
# động nổi. Đã từng xảy ra ở 10 tệp cùng lúc ngày 18/08/2026.
python3 tests/kiem_tra_ten_khong_xac_dinh.py || LOI=1

muc "3. Lớp an toàn cho trợ lý AI"
python3 tests/test_ai_guard.py || LOI=1

muc "4. Cấu hình kết nối cơ sở dữ liệu"
# Tên máy chủ viết cứng chỉ đúng trên đúng một máy; ở nơi khác pyodbc chờ hết
# 15 giây mặc định. Ngày 19/08/2026, database/database.py mắc đúng lỗi đó và vì
# middleware gọi nó trên MỌI yêu cầu nên cả hệ thống mất 15 giây mỗi lượt.
python3 tests/kiem_tra_cau_hinh_ket_noi.py || LOI=1

muc "5. Bảng người nhận thông báo (tự bỏ qua nếu không có CSDL)"
python3 tests/kiem_tra_bang_nguoi_nhan.py || LOI=1

muc "6. Thông báo tự động (sinh nhật, ngày lễ)"
python3 tests/kiem_tra_thong_bao_tu_dong.py || LOI=1

muc "7. Module nội bộ / thư viện bị thiếu"
# Bắt trường hợp mã nguồn import một module chưa được commit, hoặc một thư viện
# chưa khai trong requirements.txt. Cả hai đều chỉ vỡ khi CHẠY, không phải khi
# biên dịch — và vỡ đúng lúc cài mới lên máy chủ.
python3 tests/kiem_tra_module_thieu.py || LOI=1

muc "8. Đổi nhà cung cấp mô hình AI (OpenAI ⇄ Gemini)"
python3 tests/kiem_tra_doi_nha_cung_cap_ai.py || LOI=1

muc "9. Trợ lý AI báo đúng lý do khi hỏng"
python3 tests/test_tro_ly_ai_het_han_muc.py || LOI=1

muc "10. Phân quyền các endpoint thông báo"
python3 tests/test_quyen_thong_bao.py || LOI=1

muc "11. Hàng đợi thông báo (chia lô, đếm phần, lấy lại việc bỏ dở)"
python3 tests/test_hang_doi_thong_bao.py || LOI=1

muc "12. Tích hợp với Redis thật (tự bỏ qua nếu không có Redis)"
python3 tests/test_tich_hop_redis.py || LOI=1

muc "13. Firebase (dry_run — không gửi gì; tự bỏ qua nếu thiếu khoá/CSDL)"
python3 tests/kiem_tra_firebase.py || LOI=1

muc "14. Khoá bí mật lọt vào mã nguồn"
if grep -rEn "sk-proj-[A-Za-z0-9]|ITCdhv@|AI2025\\\\SQLEXPRESS|= *'sa'" \
     --include="*.py" . 2>/dev/null | grep -v __pycache__ | grep -v _luu_tru | grep -v tests/; then
  echo "   ❌ phát hiện khoá viết cứng"; LOI=1
else
  echo "   ✅ không có khoá nào trong mã nguồn"
fi

printf "\n%s\n" "════════════════════════════════════════"
if [ "$LOI" -eq 0 ]; then
  echo "✅ TẤT CẢ KIỂM TRA ĐỀU ĐẠT"
else
  echo "❌ CÓ KIỂM TRA KHÔNG ĐẠT — xem chi tiết ở trên"
fi
exit "$LOI"
