import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    // 🔥 Nâng cấp v6 để đảm bảo cấu trúc bảng được khởi tạo sạch sẽ
    _database = await _initDB('vinhuni_notifs_v6.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  // --- [PHẦN 1: TẠO CẤU TRÚC BẢNG - CHỈ CHẠY 1 LẦN KHI TẠO DB] ---
  Future _createDB(Database db, int version) async {
    // 1. Bảng Thông báo (Notifications)
    await db.execute('''
      CREATE TABLE notifications (
        id INTEGER PRIMARY KEY,
        UserCode TEXT,
        TieuDe TEXT,
        TomTat TEXT,
        NoiDung TEXT,
        NgayPhatHanh TEXT,
        IsRead INTEGER DEFAULT 0,
        NguoiDang TEXT,
        LoaiTin TEXT,
        TabGroup TEXT,
        is_deleted_local INTEGER DEFAULT 0 
      )
    ''');
    await db.execute('''
      CREATE TABLE tbl_StaffSchedule (
        ScheduleId INTEGER PRIMARY KEY,
        EventDate TEXT,        -- YYYY-MM-DD
        Session TEXT,          -- Sáng, Chiều, Tối
        TimeValue TEXT,        -- 07:30...
        Content TEXT,          -- Nội dung công tác
        Participants TEXT,     -- Thành phần tham dự
        Location TEXT,         -- Địa điểm
        Chairperson TEXT,      -- Người chủ trì
        EventHash TEXT,        -- Để check xem bản ghi có thay đổi ko
        TargetGroups TEXT,     -- Nhóm đối tượng (CB, SV...)
        IsNotified INTEGER,    -- 0: Chưa, 1: Rồi
        IsModified INTEGER,    -- Đánh dấu lịch bị sửa
        CreatedAt TEXT,
        UpdatedAt TEXT,
        IsReminderSent INTEGER -- Đã nhắc lịch chưa
      )
    ''');

    // 2. Bảng Văn bản PDF (Documents Cache)
    await db.execute('''
      CREATE TABLE documents (
        id INTEGER PRIMARY KEY,
        title TEXT,
        category TEXT,
        url TEXT,
        publish_date TEXT,
        last_updated TEXT
      )
    ''');
    

    // 3. Bảng Lịch thi & Bộ lọc lịch thi
    await db.execute('CREATE TABLE exam_filters (StudentId TEXT PRIMARY KEY, RawJson TEXT)');
    await db.execute('CREATE TABLE exams (KeyId TEXT PRIMARY KEY, ExamJson TEXT, LastUpdated TEXT)');

    // 4. Bảng Lịch học & Bộ lọc lịch học
    await db.execute('CREATE TABLE schedule_filters (StudentId TEXT PRIMARY KEY, RawJson TEXT)');
    await db.execute('CREATE TABLE schedules (KeyId TEXT PRIMARY KEY, ScheduleJson TEXT, LastUpdated TEXT)');

    // 5. Bảng Điểm & Bộ lọc điểm
    await db.execute('CREATE TABLE grade_filters (StudentId TEXT PRIMARY KEY, FilterJson TEXT)');
    await db.execute('CREATE TABLE grades (KeyId TEXT PRIMARY KEY, GradeJson TEXT)');

    // 6. Bảng Thống kê sinh viên (Student Stats)
    await db.execute('CREATE TABLE student_stats (StudentId TEXT PRIMARY KEY, StatsJson TEXT)');
  }

  // --- [PHẦN 2: CÁC HÀM XỬ LÝ VĂN BẢN PDF] ---
  Future<void> syncFullWeeklySchedule(List<dynamic> dataList) async {
  final db = await instance.database;
  final batch = db.batch();

  for (var item in dataList) {
    batch.insert(
      'tbl_StaffSchedule',
      {
        'ScheduleId': item['ScheduleId'],
        'EventDate': item['EventDate'],
        'Session': item['Session'],
        'TimeValue': item['TimeValue'],
        'Content': item['Content'],
        'Participants': item['Participants'],
        'Location': item['Location'],
        'Chairperson': item['Chairperson'],
        'EventHash': item['EventHash'],
        'TargetGroups': item['TargetGroups'],
        'IsNotified': item['IsNotified'] == true ? 1 : 0,
        'IsModified': item['IsModified'] == true ? 1 : 0,
        'CreatedAt': item['CreatedAt'],
        'UpdatedAt': item['UpdatedAt'],
        'IsReminderSent': item['IsReminderSent'] == true ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  await batch.commit(noResult: true);
}
  // Lấy lịch theo ngày được chọn
Future<List<Map<String, dynamic>>> getSchedulesByDate(String date) async {
  final db = await instance.database;
  return await db.query(
    'tbl_StaffSchedule',
    where: 'EventDate = ?',
    whereArgs: [date],
    orderBy: 'TimeValue ASC',
  );
}
// 1. Lấy toàn bộ lịch từ máy lên
Future<List<Map<String, dynamic>>> getAllStaffSchedules() async {
  final db = await instance.database;
  return await db.query('tbl_StaffSchedule', orderBy: 'EventDate ASC, TimeValue ASC');
}

// 2. Đồng bộ toàn bộ lịch vào máy (Dùng Batch cho nhanh)

// Tìm kiếm lịch theo nội dung hoặc người chủ trì (Search cực nhanh)
Future<List<Map<String, dynamic>>> searchSchedule(String query) async {
  final db = await instance.database;
  return await db.query(
    'tbl_StaffSchedule',
    where: 'Content LIKE ? OR Chairperson LIKE ?',
    whereArgs: ['%$query%', '%$query%'],
  );
}
  Future<void> saveDocumentsCache(List<dynamic> docs) async {
    try {
      final db = await instance.database;
      final batch = db.batch();
      for (var doc in docs) {
        batch.insert(
          'documents',
          {
            'id': doc['id'],
            'title': doc['title'] ?? '',
            'category': doc['category'] ?? '',
            'url': doc['url'] ?? '',
            'publish_date': doc['publish_date'] ?? '',
            'last_updated': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      debugPrint("✅ Đã lưu ${docs.length} văn bản vào SQLite");
    } catch (e) {
      debugPrint("❌ Lỗi saveDocumentsCache: $e");
    }
  }

  Future<List<Map<String, dynamic>>> getCachedDocuments() async {
    try {
      final db = await instance.database;
      return await db.query('documents', orderBy: 'publish_date DESC', limit: 50);
    } catch (e) {
      debugPrint("❌ Lỗi getCachedDocuments: $e");
      return [];
    }
  }

  // --- [PHẦN 3: CÁC HÀM XỬ LÝ THÔNG BÁO] ---

  Future<List<Map<String, dynamic>>> getOfflineNotifs(String userCode) async {
    final db = await instance.database;
    final cleanId = userCode.toUpperCase().replaceFirst(RegExp(r'^(SV|CB)'), '');
    final res = await db.query(
      'notifications', 
      where: 'is_deleted_local = 0 AND UserCode = ?', 
      whereArgs: [cleanId],
      orderBy: 'id DESC'
    );
    return res.map((n) => {
      'ID': n['id'], 'TieuDe': n['TieuDe'], 'TomTat': n['TomTat'],
      'NoiDung': n['NoiDung'], 'NgayPhatHanh': n['NgayPhatHanh'],
      'IsRead': n['IsRead'] == 1, 'NguoiDang': n['NguoiDang'],
      'LoaiTin': n['LoaiTin'], 'TabGroup': n['TabGroup'],
    }).toList();
  }

  Future<void> insertNotification(Map<String, dynamic> n, String userCode) async {
    final db = await instance.database;
    final cleanId = userCode.toUpperCase().replaceFirst(RegExp(r'^(SV|CB)'), '');
    await db.insert('notifications', {
      'id': n['ID'], 'UserCode': cleanId, 'TieuDe': n['TieuDe'] ?? '',
      'TomTat': n['TomTat'] ?? '', 'NoiDung': n['NoiDung'] ?? '',
      'NgayPhatHanh': n['NgayPhatHanh'] ?? '',
      'IsRead': (n['IsRead'] == true || n['IsRead'] == 1) ? 1 : 0,
      'NguoiDang': n['NguoiDang'] ?? 'Hệ thống',
      'LoaiTin': n['LoaiTin'] ?? 'GENERAL', 'TabGroup': n['TabGroup'] ?? 'GENERAL',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deletePermanently(int id, String studentId) async {
    final db = await instance.database;
    await db.update('notifications', {'is_deleted_local': 1}, where: 'id = ?', whereArgs: [id]);
    try {
      await http.post(Uri.parse("https://mobi.vinhuni.edu.vn/api/hide-notif/$id"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"student_id": studentId}),
      ).timeout(const Duration(seconds: 5));
    } catch (e) { debugPrint("⚠️ Lỗi xóa tin: $e"); }
  }

  // --- [PHẦN 4: LỊCH THI, LỊCH HỌC, ĐIỂM SỐ] ---

  // Điểm
  Future<void> saveGradeFilters(String sid, List data) async {
    final db = await instance.database;
    await db.insert('grade_filters', {'StudentId': sid, 'FilterJson': jsonEncode(data)}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<List?> getGradeFilters(String sid) async {
    final db = await instance.database;
    final res = await db.query('grade_filters', where: 'StudentId = ?', whereArgs: [sid]);
    return res.isNotEmpty ? jsonDecode(res.first['FilterJson'] as String) : null;
  }
  Future<void> saveGrades(String sid, String y, String s, String p, List data) async {
    final db = await instance.database;
    await db.insert('grades', {'KeyId': "${sid}_${y}_${s}_$p", 'GradeJson': jsonEncode(data)}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<List?> getGrades(String sid, String y, String s, String p) async {
    final db = await instance.database;
    final res = await db.query('grades', where: 'KeyId = ?', whereArgs: ["${sid}_${y}_${s}_$p"]);
    return res.isNotEmpty ? jsonDecode(res.first['GradeJson'] as String) : null;
  }

  // Thống kê & Lịch học
  Future<void> saveStudentStats(String sid, List data) async {
    final db = await instance.database;
    await db.insert('student_stats', {'StudentId': sid, 'StatsJson': jsonEncode(data)}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<List?> getStudentStats(String sid) async {
    final db = await instance.database;
    final res = await db.query('student_stats', where: 'StudentId = ?', whereArgs: [sid]);
    return res.isNotEmpty ? jsonDecode(res.first['StatsJson'] as String) : null;
  }
  Future<void> saveScheduleFilters(String sid, List data) async {
    final db = await instance.database;
    await db.insert('schedule_filters', {'StudentId': sid, 'RawJson': jsonEncode(data)}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<List?> getScheduleFilters(String sid) async {
    final db = await instance.database;
    final res = await db.query('schedule_filters', where: 'StudentId = ?', whereArgs: [sid]);
    return res.isNotEmpty ? jsonDecode(res.first['RawJson'] as String) : null;
  }
  Future<void> saveSchedule(String sid, String y, String s, String w, String p, List data) async {
    final db = await instance.database;
    await db.insert('schedules', {'KeyId': "${sid}_${y}_${s}_${w}_$p", 'ScheduleJson': jsonEncode(data), 'LastUpdated': DateTime.now().toIso8601String()}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<List?> getSchedule(String sid, String y, String s, String w, String p) async {
    final db = await instance.database;
    final res = await db.query('schedules', where: 'KeyId = ?', whereArgs: ["${sid}_${y}_${s}_${w}_$p"]);
    return res.isNotEmpty ? jsonDecode(res.first['ScheduleJson'] as String) : null;
  }

  // Lịch thi
  Future<void> saveExamFilters(String studentId, List data) async {
    final db = await instance.database;
    await db.insert('exam_filters', {'StudentId': studentId, 'RawJson': jsonEncode(data)}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<List?> getExamFilters(String studentId) async {
    final db = await instance.database;
    final res = await db.query('exam_filters', where: 'StudentId = ?', whereArgs: [studentId]);
    return res.isNotEmpty ? jsonDecode(res.first['RawJson'] as String) : null;
  }
  Future<void> saveExams(String studentId, String year, String semester, List data) async {
    final db = await instance.database;
    await db.insert('exams', {'KeyId': "${studentId}_${year}_$semester", 'ExamJson': jsonEncode(data), 'LastUpdated': DateTime.now().toIso8601String()}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<List?> getExams(String studentId, String year, String semester) async {
    final db = await instance.database;
    final res = await db.query('exams', where: 'KeyId = ?', whereArgs: ["${studentId}_${year}_$semester"]);
    return res.isNotEmpty ? jsonDecode(res.first['ExamJson'] as String) : null;
  }
}