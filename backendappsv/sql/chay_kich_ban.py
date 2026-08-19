"""
Chạy một tệp .sql có nhiều lô lệnh ngăn bởi GO.

pyodbc không hiểu `GO` — đó là từ khoá của công cụ sqlcmd, không phải của
SQL Server. Gửi cả tệp một lần sẽ báo lỗi cú pháp. Tệp này tách theo GO rồi
gửi từng lô, và in ra mọi thông điệp PRINT của kịch bản.

Chạy:  python sql/chay_kich_ban.py sql/<tên-tệp>.sql
"""

from __future__ import annotations

import re
import sys
import time
import warnings
from pathlib import Path

warnings.filterwarnings("ignore")

GOC = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(GOC))


def chay(duong_dan: Path) -> int:
    import pyodbc
    from core.settings import settings

    if not duong_dan.exists():
        print(f"❌ Không thấy tệp: {duong_dan}")
        return 1

    noi_dung = duong_dan.read_text(encoding="utf-8")
    # Tách theo dòng chỉ có mỗi GO
    cac_lo = [l.strip() for l in re.split(r"^\s*GO\s*$", noi_dung, flags=re.M | re.I)]
    cac_lo = [l for l in cac_lo if l]

    print(f"📄 {duong_dan.name} — {len(cac_lo)} lô lệnh")
    print(f"🗄️  {settings.db.safe_repr}\n")

    t0 = time.time()
    try:
        with pyodbc.connect(settings.db.local_conn_str, timeout=15, autocommit=True) as conn:
            cur = conn.cursor()
            for i, lo in enumerate(cac_lo, 1):
                t = time.time()
                try:
                    cur.execute(lo)
                    # Vét hết các tập kết quả để lấy được thông điệp PRINT
                    while True:
                        try:
                            cur.fetchall()
                        except pyodbc.ProgrammingError:
                            pass
                        if not cur.nextset():
                            break
                except pyodbc.Error as exc:
                    print(f"  ❌ Lô {i} lỗi: {str(exc)[:200]}")
                    print(f"     {lo.strip().splitlines()[0][:100]}")
                    return 1

                # pyodbc chỉ có `.messages` từ bản 5 trở đi. Bản cũ hơn không
                # lấy được nội dung PRINT — vẫn chạy đúng, chỉ là ít lời hơn.
                tin_nhan = getattr(conn, "messages", None)
                if tin_nhan:
                    for tin in list(tin_nhan):
                        van_ban = str(tin[1]).split("]")[-1].strip()
                        if van_ban:
                            print(f"  {van_ban}")
                    tin_nhan.clear()

                giay = time.time() - t
                if giay > 1:
                    print(f"     (lô {i}: {giay:.1f}s)")
    except Exception as exc:  # noqa: BLE001
        print(f"❌ Không kết nối được: {str(exc)[:180]}")
        return 1

    print(f"\n✅ Xong sau {time.time() - t0:.1f} giây")
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(chay(Path(sys.argv[1])))
