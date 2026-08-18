import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class DatabaseHelper {
  // --- [PHẦN 1: KHỞI TẠO SINGLETON] ---
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    // 🔥 Version 3 để đảm bảo có đầy đủ bảng Menu và Chat
    _database = await _initDB('vinhuni_notifs_v6.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(
      path, 
      version: 3, 
      onCreate: _createDB,
      onUpgrade: _onUpgrade
    );
  }

  // --- [PHẦN 2: TẠO CẤU TRÚC BẢNG] ---
  Future _createDB(Database db, int version) async {
    // 1. Bảng Thông báo
    await db.execute('''
      CREATE TABLE notifications (
        id INTEGER PRIMARY KEY, UserCode TEXT, TieuDe TEXT, TomTat TEXT,
        NoiDung TEXT, NgayPhatHanh TEXT, IsRead INTEGER DEFAULT 0,
        NguoiDang TEXT, LoaiTin TEXT, TabGroup TEXT, is_deleted_local INTEGER DEFAULT 0 
      )
    ''');

    // 2. Bảng Lịch công tác cán bộ
    await db.execute('''
      CREATE TABLE tbl_StaffSchedule (
        ScheduleId INTEGER PRIMARY KEY, EventDate TEXT, Session TEXT,
        TimeValue TEXT, Content TEXT, Participants TEXT, Location TEXT,
        Chairperson TEXT, EventHash TEXT, TargetGroups TEXT, IsNotified INTEGER,
        IsModified INTEGER, CreatedAt TEXT, UpdatedAt TEXT, IsReminderSent INTEGER
      )
    ''');

    // 3. Bảng Văn bản PDF
    await db.execute('''
      CREATE TABLE documents (
        id INTEGER PRIMARY KEY, title TEXT, category TEXT, url TEXT,
        publish_date TEXT, last_updated TEXT
      )
    ''');
    
    // 4. Các bảng JSON Cache (Điểm, Lịch học, Lịch thi)
    await db.execute('CREATE TABLE exam_filters (StudentId TEXT PRIMARY KEY, RawJson TEXT)');
    await db.execute('CREATE TABLE exams (KeyId TEXT PRIMARY KEY, ExamJson TEXT, LastUpdated TEXT)');
    await db.execute('CREATE TABLE schedule_filters (StudentId TEXT PRIMARY KEY, RawJson TEXT)');
    await db.execute('CREATE TABLE schedules (KeyId TEXT PRIMARY KEY, ScheduleJson TEXT, LastUpdated TEXT)');
    await db.execute('CREATE TABLE grade_filters (StudentId TEXT PRIMARY KEY, FilterJson TEXT)');
    await db.execute('CREATE TABLE grades (KeyId TEXT PRIMARY KEY, GradeJson TEXT)');
    await db.execute('CREATE TABLE student_stats (StudentId TEXT PRIMARY KEY, StatsJson TEXT)');

    // 5. Bảng Menu động
    await db.execute('CREATE TABLE IF NOT EXISTS app_menu (id INTEGER PRIMARY KEY, MenuJson TEXT)');

    // 6. Các bảng Chat
    await _createChatTables(db);
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) await _createChatTables(db);
    if (oldVersion < 3) {
      await db.execute('CREATE TABLE IF NOT EXISTS app_menu (id INTEGER PRIMARY KEY, MenuJson TEXT)');
    }
  }

  Future<void> _createChatTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_groups (
        GroupId TEXT PRIMARY KEY, GroupName TEXT, LastMessage TEXT, 
        LastTime TEXT, UnreadCount INTEGER DEFAULT 0, GroupType TEXT, AvatarUrl TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_hidden_blacklist (MessageId INTEGER PRIMARY KEY)
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_messages (
        MessageId INTEGER PRIMARY KEY, GroupId TEXT, SenderCode TEXT, 
        SenderName TEXT, SenderAvatar TEXT, MessageContent TEXT, 
        MessageType TEXT, FileUrl TEXT, ReplyToId INTEGER, Reaction TEXT, 
        IsDeleted INTEGER DEFAULT 0, is_hidden_local INTEGER DEFAULT 0, CreatedAt TEXT
      )
    ''');
  }

  // --- [PHẦN 3: MENU OFFLINE SERVICE] ---
  Future<void> saveAppMenu(List<dynamic> menuData) async {
    final db = await database;
    await db.insert('app_menu', {'id': 1, 'MenuJson': jsonEncode(menuData)}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<dynamic>> getAppMenu() async {
    final db = await database;
    try {
      final res = await db.query('app_menu', where: 'id = 1');
      if (res.isNotEmpty) return jsonDecode(res.first['MenuJson'] as String);
    } catch (e) { debugPrint("❌ Lỗi getAppMenu: $e"); }
    return [];
  }

  // --- [PHẦN 4: THÔNG BÁO SERVICE] ---
  Future<List<Map<String, dynamic>>> getOfflineNotifs(String userCode) async {
    final db = await database;
    final cleanId = userCode.toUpperCase().replaceFirst(RegExp(r'^(SV|CB)'), '');
    return await db.query('notifications', where: 'is_deleted_local = 0 AND UserCode = ?', whereArgs: [cleanId], orderBy: 'id DESC', limit: 50);
  }

Future<void> insertNotification(Map<String, dynamic> n, String userCode) async {
    final db = await database;
    final cleanId = userCode.toUpperCase().replaceFirst(RegExp(r'^(SV|CB)'), '');
    
    // 1. Kiểm tra xem tin này đã tồn tại dưới máy chưa
    final List<Map<String, dynamic>> existing = await db.query(
      'notifications',
      columns: ['is_deleted_local', 'IsRead'],
      where: 'id = ?',
      whereArgs: [n['ID']],
    );

    // 2. Nếu đã xóa thì không nạp lại
    if (existing.isNotEmpty && existing.first['is_deleted_local'] == 1) return; 

    // 🔥 3. KHIÊN BẢO VỆ TRẠNG THÁI ĐỌC (Smart Merge)
    int finalIsRead = (n['IsRead'] == true || n['IsRead'] == 1) ? 1 : 0;
    
    // NẾU dươi máy đã đọc (1), thì bỏ qua kết quả Server gửi về, chốt luôn là 1.
    if (existing.isNotEmpty && existing.first['IsRead'] == 1) {
      finalIsRead = 1; 
    }

    // 4. Tiến hành Insert/Update an toàn
    await db.insert('notifications', {
      'id': n['ID'], 
      'UserCode': cleanId, 
      'TieuDe': n['TieuDe'] ?? '',
      'TomTat': n['TomTat'] ?? '', 
      'NoiDung': n['NoiDung'] ?? '',
      'NgayPhatHanh': n['NgayPhatHanh'] ?? '',
      'IsRead': finalIsRead, // 🔥 Sử dụng biến đã được bảo vệ
      'NguoiDang': n['NguoiDang'] ?? 'Hệ thống',
      'LoaiTin': n['LoaiTin'] ?? 'GENERAL', 
      'TabGroup': n['TabGroup'] ?? 'GENERAL',
      'is_deleted_local': 0 
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  /// Đánh dấu một thông báo đã đọc.
  ///
  /// (Trước 18/08/2026 còn một hàm `updateNotificationReadStatus` làm y hệt
  /// nhưng không nơi nào gọi — đã gỡ bỏ để chỉ còn một cách làm.)
  Future<int> updateReadStatus(int id) async {
    final db = await database;
    return await db.update(
      'notifications',
      {'IsRead': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Đánh dấu toàn bộ thông báo của một người là đã đọc.
  ///
  /// Bổ sung 18/08/2026: nút "Đánh dấu tất cả đã đọc" trước đây chỉ đóng hộp
  /// thoại vì không có hàm nào để gọi.
  Future<int> markAllAsRead(String userCode) async {
    final db = await database;
    final cleanId = userCode.toUpperCase().replaceFirst(RegExp(r'^(SV|CB)'), '');
    return await db.update(
      'notifications',
      {'IsRead': 1},
      where: 'UserCode = ? AND IsRead = 0 AND is_deleted_local = 0',
      whereArgs: [cleanId],
    );
  }

  /// Ẩn một thông báo khỏi danh sách tại máy.
  ///
  /// Đánh dấu ẩn thay vì xoá hẳn, để lần đồng bộ sau máy chủ gửi lại tin đó
  /// thì nó không hiện lên lần nữa — xem `insertNotification`.
  Future<int> softDeleteNotification(int id) async {
    final db = await database;
    return await db.update(
      'notifications',
      {'is_deleted_local': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Số thông báo chưa đọc — dùng cho huy hiệu trên biểu tượng ứng dụng.
  Future<int> getUnreadCount(String userCode) async {
    final db = await database;
    final cleanId = userCode.toUpperCase().replaceFirst(RegExp(r'^(SV|CB)'), '');
    final kq = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM notifications '
      'WHERE UserCode = ? AND IsRead = 0 AND is_deleted_local = 0',
      [cleanId],
    );
    return (kq.first['c'] as int?) ?? 0;
  }

  // --- [PHẦN 5: CHAT SERVICE] ---
  Future<void> saveChatGroups(List<dynamic> groups) async {
    final db = await database;
    
    // 🔥 ĐÃ FIX: Quét sạch toàn bộ cache nhóm cũ dưới máy trước khi nạp cái mới.
    // Giúp tống khứ vĩnh viễn các nhóm rác, nhóm đã rời khỏi SQLite.
    await db.delete('chat_groups'); 

    final batch = db.batch();
    for (var g in groups) {
      batch.insert('chat_groups', {
        'GroupId': g['GroupId'].toString(), 'GroupName': g['GroupName'],
        'LastMessage': g['LastMessage'], 'LastTime': g['LastTime'],
        'UnreadCount': g['UnreadCount'] ?? 0, 'GroupType': g['GroupType'] ?? 'GENERAL',
        'AvatarUrl': g['AvatarUrl'] ?? '',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getChatGroups() async {
    final db = await database;
    return await db.query('chat_groups', orderBy: 'LastTime DESC');
  }

  Future<void> saveChatMessage(Map<String, dynamic> m) async {
    final db = await database;
    int msgId = int.parse(m['MessageId'].toString());
    
    String rawSender = m['SenderCode'] ?? m['sender_code'] ?? "";
    String cleanSender = rawSender.toUpperCase().replaceFirst(RegExp(r'^(SV|CB)'), '');

    // 🔥 BƯỚC 1: Đọc thêm cột 'Reaction' từ SQLite lên để làm dữ liệu dự phòng
    final List<Map<String, dynamic>> existing = await db.query(
      'chat_messages',
      columns: ['is_hidden_local', 'IsDeleted', 'Reaction'], 
      where: 'MessageId = ?',
      whereArgs: [msgId],
    );

    int currentDeleted = (m['IsDeleted'] == true || m['IsDeleted'] == 1) ? 1 : 0;

    if (existing.isNotEmpty) {
      if (existing.first['is_hidden_local'] == 1) return; // Bảo vệ xóa
      if (existing.first['IsDeleted'] == 1) currentDeleted = 1; // Bảo vệ thu hồi
    }

    // 🔥 BƯỚC 2: CƠ CHẾ GHI ĐÈ THÔNG MINH (SMART MERGE)
    dynamic reactionData = m['Reactions'] ?? m['Reaction'];
    String? reactionStr;
    
    if (reactionData != null) {
      // Nếu API Server hoặc Socket có trả về dữ liệu -> Ưu tiên mã hóa cái mới
      if (reactionData is Map || reactionData is List) {
        reactionStr = jsonEncode(reactionData);
      } else {
        reactionStr = reactionData.toString();
      }
    } else if (existing.isNotEmpty && existing.first['Reaction'] != null) {
      // 🚨 CHỐT CHẶN BẢO VỆ: Nếu Server trả về rỗng (null), NHƯNG máy đang có icon -> GIỮ LẠI DATA CỦA MÁY
      reactionStr = existing.first['Reaction'].toString();
    }

    // BƯỚC 3: Lưu xuống CSDL
    await db.insert('chat_messages', {
      'MessageId': msgId, 
      'GroupId': m['GroupId'].toString(),
      'SenderCode': cleanSender,
      'SenderName': m['SenderName'] ?? m['sender_name'] ?? "Người dùng",
      'SenderAvatar': m['SenderAvatar'] ?? m['sender_avatar'],
      'MessageContent': m['MessageContent'] ?? m['content'],
      'MessageType': m['MessageType'] ?? 'TEXT', 
      'FileUrl': m['FileUrl'],
      'ReplyToId': m['ReplyToId'], 
      'Reaction': reactionStr, // 🔥 Đã được bảo vệ an toàn
      'IsDeleted': currentDeleted,
      'is_hidden_local': 0, 
      'CreatedAt': m['CreatedAt'].toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // 🔥 ĐỔI LỆNH DELETE THÀNH LỆNH UPDATE CỜ ẨN (Để tránh bị API nạp lại)
  Future<void> deleteChatMessageLocal(dynamic messageId) async {
    final db = await database;
    await db.update(
      'chat_messages', 
      {'is_hidden_local': 1}, // Cắm cờ ẩn vĩnh viễn ở máy này
      where: 'MessageId = ?', 
      whereArgs: [int.parse(messageId.toString())]
    );
  }

  // 🔥 HÀM MỚI: Đổi trạng thái tin nhắn thành "Đã thu hồi"
  Future<int> updateMessageDeletedLocal(dynamic messageId) async {
    final db = await database;
    return await db.update(
      'chat_messages', 
      {'IsDeleted': 1}, 
      where: 'MessageId = ?', 
      whereArgs: [int.parse(messageId.toString())],
    );
  }
Future<void> clearMenuCache() async {
  final db = await database;
  await db.delete('app_menu', where: 'id = 1');
  debugPrint("🗑️ [SQLite] Đã xóa cache Menu.");
}
// 🔥 Hàm xóa thông báo local (Đánh dấu flag)
Future<int> deleteNotificationLocal(int id) async {
  final db = await database;
  return await db.update(
    'notifications', 
    {'is_deleted_local': 1}, 
    where: 'id = ?', 
    whereArgs: [id]
  );
}
  Future<List<Map<String, dynamic>>> getChatHistory(String groupId) async {
    final db = await database;
    final List<Map<String, dynamic>> res = await db.query(
      'chat_messages', 
      where: 'GroupId = ? AND is_hidden_local = 0', 
      whereArgs: [groupId], 
      orderBy: 'MessageId ASC'
    );
    
    // 🔥 ĐÃ SỬA: Đọc cột 'Reaction' từ SQLite lên, giải mã ngược thành Map 'Reactions' cấp cho giao diện hiển thị
    return res.map((row) {
      final map = Map<String, dynamic>.from(row);
      if (map['Reaction'] != null && map['Reaction'].toString().isNotEmpty) {
        try {
          map['Reactions'] = jsonDecode(map['Reaction'] as String);
        } catch (_) {
          // Fallback nếu dữ liệu cũ chỉ là chuỗi text thông thường
          map['Reactions'] = map['Reaction']; 
        }
      }
      return map;
    }).toList();
  }
// 🔥 HÀM MỚI: Cập nhật nhanh cụm cảm xúc vào SQLite khi có người thả tim
  Future<void> updateMessageReactionLocal(dynamic messageId, dynamic reactions) async {
    final db = await database;
    String? reactionStr;
    if (reactions is Map || reactions is List) {
      reactionStr = jsonEncode(reactions);
    } else if (reactions != null) {
      reactionStr = reactions.toString();
    }
    
    await db.update(
      'chat_messages',
      {'Reaction': reactionStr},
      where: 'MessageId = ?',
      whereArgs: [int.parse(messageId.toString())],
    );
    debugPrint("❤️ [SQLite] Đã lưu cảm xúc mới cho tin nhắn: $messageId");
  }
  

  // 🔥 FIX LỖI: Hàm xóa nhóm chat cho chat_group_list_page.dart
  Future<void> deleteChatGroupLocal(String groupId) async {
    final db = await database;
    await db.delete('chat_groups', where: 'GroupId = ?', whereArgs: [groupId]);
    debugPrint("🗑️ [SQLite] Đã xóa nhóm chat: $groupId");
  }

  // --- [PHẦN 6: LỊCH VÀ VĂN BẢN] ---
  Future<void> syncFullWeeklySchedule(List<dynamic> dataList) async {
    final db = await database;
    final batch = db.batch();
    for (var item in dataList) {
      batch.insert('tbl_StaffSchedule', {
        'ScheduleId': item['ScheduleId'], 'EventDate': item['EventDate'],
        'Session': item['Session'], 'TimeValue': item['TimeValue'],
        'Content': item['Content'], 'Participants': item['Participants'],
        'Location': item['Location'], 'Chairperson': item['Chairperson'],
        'EventHash': item['EventHash'], 'TargetGroups': item['TargetGroups'],
        'IsNotified': item['IsNotified'] == true ? 1 : 0,
        'IsModified': item['IsModified'] == true ? 1 : 0,
        'CreatedAt': item['CreatedAt'], 'UpdatedAt': item['UpdatedAt'],
        'IsReminderSent': item['IsReminderSent'] == true ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> saveDocumentsCache(List<dynamic> docs) async {
    final db = await database;
    final batch = db.batch();
    for (var doc in docs) {
      batch.insert('documents', {
        'id': doc['id'], 'title': doc['title'] ?? '', 'category': doc['category'] ?? '',
        'url': doc['url'] ?? '', 'publish_date': doc['publish_date'] ?? '',
        'last_updated': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  // --- [PHẦN 7: JSON CACHE ĐẦY ĐỦ] ---
  Future<void> saveStudentStats(String sid, List data) async {
    final db = await database;
    await db.insert('student_stats', {'StudentId': sid, 'StatsJson': jsonEncode(data)}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<List?> getStudentStats(String sid) async {
    final db = await database;
    final res = await db.query('student_stats', where: 'StudentId = ?', whereArgs: [sid]);
    return res.isNotEmpty ? jsonDecode(res.first['StatsJson'] as String) : null;
  }
  
  Future<void> saveGradeFilters(String sid, List data) async {
    final db = await database;
    await db.insert('grade_filters', {'StudentId': sid, 'FilterJson': jsonEncode(data)}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<List?> getGradeFilters(String sid) async {
    final db = await database;
    final res = await db.query('grade_filters', where: 'StudentId = ?', whereArgs: [sid]);
    return res.isNotEmpty ? jsonDecode(res.first['FilterJson'] as String) : null;
  }

  Future<void> saveGrades(String sid, String y, String s, String p, List data) async {
    final db = await database;
    await db.insert('grades', {'KeyId': "${sid}_${y}_${s}_$p", 'GradeJson': jsonEncode(data)}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<List?> getGrades(String sid, String y, String s, String p) async {
    final db = await database;
    final res = await db.query('grades', where: 'KeyId = ?', whereArgs: ["${sid}_${y}_${s}_$p"]);
    return res.isNotEmpty ? jsonDecode(res.first['GradeJson'] as String) : null;
  }

  Future<void> saveScheduleFilters(String sid, List data) async {
    final db = await database;
    await db.insert('schedule_filters', {'StudentId': sid, 'RawJson': jsonEncode(data)}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<List?> getScheduleFilters(String sid) async {
    final db = await database;
    final res = await db.query('schedule_filters', where: 'StudentId = ?', whereArgs: [sid]);
    return res.isNotEmpty ? jsonDecode(res.first['RawJson'] as String) : null;
  }

  Future<void> saveSchedule(String sid, String y, String s, String w, String p, List data) async {
    final db = await database;
    await db.insert('schedules', {'KeyId': "${sid}_${y}_${s}_${w}_$p", 'ScheduleJson': jsonEncode(data), 'LastUpdated': DateTime.now().toIso8601String()}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<List?> getSchedule(String sid, String y, String s, String w, String p) async {
    final db = await database;
    final res = await db.query('schedules', where: 'KeyId = ?', whereArgs: ["${sid}_${y}_${s}_${w}_$p"]);
    return res.isNotEmpty ? jsonDecode(res.first['ScheduleJson'] as String) : null;
  }

  Future<void> saveExamFilters(String sid, List data) async {
    final db = await database;
    await db.insert('exam_filters', {'StudentId': sid, 'RawJson': jsonEncode(data)}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<List?> getExamFilters(String sid) async {
    final db = await database;
    final res = await db.query('exam_filters', where: 'StudentId = ?', whereArgs: [sid]);
    return res.isNotEmpty ? jsonDecode(res.first['RawJson'] as String) : null;
  }

  Future<void> saveExams(String sid, String year, String semester, List data) async {
    final db = await database;
    await db.insert('exams', {'KeyId': "${sid}_${year}_$semester", 'ExamJson': jsonEncode(data), 'LastUpdated': DateTime.now().toIso8601String()}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<List?> getExams(String sid, String year, String semester) async {
    final db = await database;
    final res = await db.query('exams', where: 'KeyId = ?', whereArgs: ["${sid}_${year}_$semester"]);
    return res.isNotEmpty ? jsonDecode(res.first['ExamJson'] as String) : null;
  }

  // --- [PHẦN 8: HÀM TIỆN ÍCH] ---
  Future<List<Map<String, dynamic>>> getCachedDocuments() async {
    final db = await database;
    return await db.query('documents', orderBy: 'publish_date DESC', limit: 50);
  }

  Future<List<Map<String, dynamic>>> getAllStaffSchedules() async {
    final db = await database;
    return await db.query('tbl_StaffSchedule', orderBy: 'EventDate ASC, TimeValue ASC');
  }

  Future<String?> getLoggedInUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_code')?.replaceAll(RegExp(r'[^0-9]'), '');
  }

}