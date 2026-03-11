import 'package:flutter/foundation.dart'; // 🔥 Cần thiết cho debugPrint
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:http/http.dart' as http; // 🔥 Cần thiết cho lệnh http.post
import 'dart:convert'; // 🔥 Cần thiết cho jsonEncode

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('vinhuni_notifs_v3.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE notifications (
        id INTEGER PRIMARY KEY,
        TieuDe TEXT,
        TomTat TEXT,
        NoiDung TEXT,
        NgayPhatHanh TEXT,
        IsRead INTEGER DEFAULT 0,
        NguoiDang TEXT,
        LoaiTin TEXT,
        is_deleted_local INTEGER DEFAULT 0 
      )
    ''');
  }

  Future<void> insertNotification(Map<String, dynamic> n) async {
    final db = await instance.database;
    
    // Kiểm tra xem tin này đã bị xóa local chưa
    final List<Map<String, dynamic>> existing = await db.query(
      'notifications',
      columns: ['is_deleted_local'],
      where: 'id = ?',
      whereArgs: [n['ID']],
    );

    if (existing.isNotEmpty && existing.first['is_deleted_local'] == 1) {
      return;
    }

    int isReadValue = 0;
    if (n['IsRead'] != null) {
      isReadValue = (n['IsRead'] is bool) ? (n['IsRead'] ? 1 : 0) : n['IsRead'];
    }

    await db.insert(
      'notifications',
      {
        'id': n['ID'],
        'TieuDe': n['TieuDe'] ?? '',
        'TomTat': n['TomTat'] ?? '',
        'NoiDung': n['NoiDung'] ?? '',
        'NgayPhatHanh': n['NgayPhatHanh'] ?? '',
        'IsRead': isReadValue,
        'NguoiDang': n['NguoiDang'] ?? 'Hệ thống',
        'LoaiTin': n['LoaiTin'] ?? 'GENERAL',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getOfflineNotifs() async {
    final db = await instance.database;
    final res = await db.query(
      'notifications', 
      where: 'is_deleted_local = 0', 
      orderBy: 'id DESC'
    );
    
    return res.map((n) => {
      'ID': n['id'],
      'TieuDe': n['TieuDe'],
      'TomTat': n['TomTat'],
      'NoiDung': n['NoiDung'],
      'NgayPhatHanh': n['NgayPhatHanh'],
      'IsRead': n['IsRead'] == 1,
      'NguoiDang': n['NguoiDang'],
      'LoaiTin': n['LoaiTin'],
    }).toList();
  }

  // Hàm xóa mềm local
  Future<void> softDelete(int id) async {
    final db = await instance.database;
    await db.update('notifications', {'is_deleted_local': 1}, where: 'id = ?', whereArgs: [id]);
  }

  // 🔥 Hàm xóa vĩnh viễn và đồng bộ Server
  Future<void> deletePermanently(int id, String studentId) async {
    final db = await instance.database;
    
    try {
      // 1. Ẩn ngay lập tức ở Local
      await db.update(
        'notifications', 
        {'is_deleted_local': 1}, 
        where: 'id = ?', 
        whereArgs: [id]
      );
      debugPrint("✅ Đã ẩn tin $id ở Local");

      // 2. Đồng bộ lệnh ẩn lên Server
      final response = await http.post(
        Uri.parse("https://mobi.vinhuni.edu.vn/api/hide-notif/$id"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"student_id": studentId}),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        debugPrint("✅ Đã đồng bộ ẩn tin $id lên Server");
      }
    } catch (e) {
      debugPrint("⚠️ Lỗi đồng bộ xóa tin: $e");
    }
  }
}