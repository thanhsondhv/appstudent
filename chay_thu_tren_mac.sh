#!/usr/bin/env bash
#
# Dựng trọn môi trường thử trên máy Mac rồi chạy kiểm thử.
#
#   ./chay_thu_tren_mac.sh                      → khởi động backend + chạy các bài không cần mật khẩu
#   ./chay_thu_tren_mac.sh <tài khoản> <mật khẩu>  → chạy thêm bài đăng nhập trọn luồng
#
# Mật khẩu chỉ nằm trong dòng lệnh của bạn, không ghi vào tệp nào.
#
# Cần: máy ảo iOS đang chạy, và mạng thấy được SQL Server của trường.

set -uo pipefail
cd "$(dirname "$0")"

GOC_BE="backendappsv"
NHAT_KY="/tmp/vinhuni_backend_thu.log"
DB="${DB_SERVER:-172.26.26.253}"

do_() { printf "\033[1m%s\033[0m\n" "$*"; }
ok()  { printf "  \033[32m✅\033[0m %s\n" "$*"; }
xx()  { printf "  \033[31m❌\033[0m %s\n" "$*"; }

# ── 1. Máy ảo ────────────────────────────────────────────────────────────
do_ "1. Máy ảo iOS"
UDID=$(xcrun simctl list devices booted -j 2>/dev/null \
        | python3 -c "import sys,json;d=json.load(sys.stdin)['devices'];print(next((x['udid'] for v in d.values() for x in v if x.get('state')=='Booted'),''))" 2>/dev/null)
if [ -z "$UDID" ]; then
  xx "Chưa có máy ảo nào đang chạy. Mở Simulator rồi chạy lại."
  exit 1
fi
ok "đang dùng $UDID"

# ── 2. Địa chỉ máy Mac trong mạng ────────────────────────────────────────
do_ "2. Địa chỉ máy Mac"
IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)
if [ -z "$IP" ]; then xx "Không lấy được địa chỉ IP"; exit 1; fi
MAY_CHU="http://$IP:8000"
ok "$MAY_CHU"

# ── 3. Cơ sở dữ liệu ─────────────────────────────────────────────────────
do_ "3. Cơ sở dữ liệu"
if nc -z -G 4 "$DB" 1433 2>/dev/null; then
  ok "$DB:1433 tới được"
else
  xx "$DB:1433 KHÔNG tới được — cần VPN, hoặc đang ở mạng trường thì bỏ VPN đi"
  exit 1
fi

# ── 4. Khởi động backend ─────────────────────────────────────────────────
do_ "4. Backend"
pkill -f "chay_thu_cuc_bo" 2>/dev/null
sleep 2
find "$GOC_BE" -name __pycache__ -type d -not -path '*/venv/*' -exec rm -rf {} + 2>/dev/null
( cd "$GOC_BE" && DB_SERVER="$DB" python3 -u chay_thu_cuc_bo.py > "$NHAT_KY" 2>&1 & )

printf "  … đang khởi động (nạp cả tầng AI nên hơi lâu)"
for i in $(seq 1 40); do
  if curl -sS -o /dev/null -m 3 "http://127.0.0.1:8000/kiem-tra-cuc-bo" 2>/dev/null; then
    echo; ok "sẵn sàng sau ~$((i*3)) giây"
    break
  fi
  printf "."
  sleep 3
  if [ "$i" = 40 ]; then
    echo; xx "Backend không lên sau 2 phút. Xem $NHAT_KY"
    tail -20 "$NHAT_KY"
    exit 1
  fi
done
grep -aE "Dùng trọn app|Lùi về chế độ" "$NHAT_KY" | head -2 | sed 's/^/  /'

# ── 5. Đo tốc độ ─────────────────────────────────────────────────────────
do_ "5. Tốc độ các endpoint nóng"
for E in "kiem-tra-cuc-bo" "api/app-menu" "api/count-unread/1679" "api/get-notifs/1679?page=1"; do
  t=$(curl -sS -o /dev/null -m 60 -w "%{time_total}" "http://127.0.0.1:8000/$E" 2>/dev/null)
  # Trên 2 giây là có gì đó không ổn — trước khi tối ưu, mọi endpoint đều 15 giây
  if awk "BEGIN{exit !($t > 2)}"; then
    xx "$(printf '%-30s %s giây — CHẬM BẤT THƯỜNG' "${E%%\?*}" "$t")"
  else
    ok "$(printf '%-30s %s giây' "${E%%\?*}" "$t")"
  fi
done

# ── 6. Kiểm thử backend ──────────────────────────────────────────────────
do_ "6. Kiểm thử backend"
LOI_BE=0
KQ_BE=$(mktemp)
( cd "$GOC_BE" && DB_SERVER="$DB" bash tests/chay_tat_ca.sh > "$KQ_BE" 2>&1 ) || LOI_BE=1
grep -aE "TẤT CẢ|❌|⏭️" "$KQ_BE" | sed 's/^/  /'
rm -f "$KQ_BE"

# ── 7. Kiểm thử ứng dụng trên máy ảo ─────────────────────────────────────
do_ "7. Kiểm thử ứng dụng"
DINH_NGHIA=(--dart-define=MAY_CHU="$MAY_CHU")
if [ "$#" -ge 2 ]; then
  DINH_NGHIA+=(--dart-define=TAI_KHOAN="$1" --dart-define=MAT_KHAU="$2")
  echo "  (có tài khoản → chạy cả bài đăng nhập trọn luồng)"
else
  echo "  (không có tài khoản → bỏ qua bài đăng nhập)"
  echo "  Chạy lại kèm tài khoản:  ./chay_thu_tren_mac.sh <tài khoản> <mật khẩu>"
fi

# Chạy TỪNG TỆP một, không đưa cả thư mục cho flutter test.
#
# `flutter test integration_test/` gộp nhiều tệp vào một lượt và treo vô hạn
# trên thiết bị thật — đã gặp: 11 phút không nhúc nhích, trong khi từng tệp
# chạy riêng chỉ mất vài giây. Vòng lặp này vừa tránh được, vừa cho biết tệp
# nào hỏng thay vì cả cụm.
LOI_UD=0
KQ=$(mktemp)
for TEP in integration_test/*_test.dart; do
  echo
  printf "  \033[1m%s\033[0m\n" "$(basename "$TEP")"
  # Ghi ra tệp rồi lọc, thay vì nối ống thẳng — nối ống thì mã thoát nhận được
  # là của grep chứ không phải của flutter test, và bài hỏng sẽ bị coi là đạt.
  flutter test "$TEP" -d "$UDID" "${DINH_NGHIA[@]}" > "$KQ" 2>&1 || LOI_UD=1
  grep -aE "^[0-9]{2}:[0-9]{2} \+|…|✅|❌|⏭️|Expected|Actual|reason:|Bỏ qua|All tests passed" \
       "$KQ" | sed 's/^/    /'
done
rm -f "$KQ"

echo
# Kết luận phải tính CẢ backend lẫn ứng dụng.
#
# Bản đầu chỉ nhìn kết quả phía ứng dụng, nên in "tất cả đều đạt" ngay bên dưới
# một dòng "❌ CÓ KIỂM TRA KHÔNG ĐẠT" của backend. Một bản tóm tắt nói sai còn
# tệ hơn không có bản tóm tắt nào — người đọc tin nó rồi bỏ qua phần chi tiết.
if [ "$LOI_BE" -ne 0 ] || [ "$LOI_UD" -ne 0 ]; then
  do_ "Xong — CÓ KIỂM TRA KHÔNG ĐẠT"
  [ "$LOI_BE" -ne 0 ] && echo "  • backend: xem mục 6 bên trên"
  [ "$LOI_UD" -ne 0 ] && echo "  • ứng dụng: xem mục 7 bên trên"
  TRANG_THAI=1
else
  do_ "Xong — tất cả đều đạt"
  TRANG_THAI=0
fi
echo "  Nhật ký backend: $NHAT_KY"
echo "  Backend vẫn đang chạy ở $MAY_CHU — dừng bằng: pkill -f chay_thu_cuc_bo"

exit "$TRANG_THAI"
