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
    // 🔥 Đổi sang v4 để cập nhật thêm cột UserCode và TabGroup
    _database = await _initDB('vinhuni_notifs_v4.db');
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
        UserCode TEXT,        -- 🔥 Mã SV/CB để lọc tin riêng
        TieuDe TEXT,
        TomTat TEXT,
        NoiDung TEXT,
        NgayPhatHanh TEXT,
        IsRead INTEGER DEFAULT 0,
        NguoiDang TEXT,
        LoaiTin TEXT,
        TabGroup TEXT,       -- 🔥 Để chia 4 Tab
        is_deleted_local INTEGER DEFAULT 0 
      )
    ''');
  }

  // Lấy tin offline theo UserCode
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
      'ID': n['id'],
      'TieuDe': n['TieuDe'],
      'TomTat': n['TomTat'],
      'NoiDung': n['NoiDung'],
      'NgayPhatHanh': n['NgayPhatHanh'],
      'IsRead': n['IsRead'] == 1,
      'NguoiDang': n['NguoiDang'],
      'LoaiTin': n['LoaiTin'],
      'TabGroup': n['TabGroup'],
    }).toList();
  }

  Future<void> insertNotification(Map<String, dynamic> n, String userCode) async {
    final db = await instance.database;
    final cleanId = userCode.toUpperCase().replaceFirst(RegExp(r'^(SV|CB)'), '');

    await db.insert(
      'notifications',
      {
        'id': n['ID'],
        'UserCode': cleanId,
        'TieuDe': n['TieuDe'] ?? '',
        'TomTat': n['TomTat'] ?? '',
        'NoiDung': n['NoiDung'] ?? '',
        'NgayPhatHanh': n['NgayPhatHanh'] ?? '',
        'IsRead': (n['IsRead'] == true || n['IsRead'] == 1) ? 1 : 0,
        'NguoiDang': n['NguoiDang'] ?? 'Hệ thống',
        'LoaiTin': n['LoaiTin'] ?? 'GENERAL',
        'TabGroup': n['TabGroup'] ?? 'GENERAL',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deletePermanently(int id, String studentId) async {
    final db = await instance.database;
    await db.update('notifications', {'is_deleted_local': 1}, where: 'id = ?', whereArgs: [id]);
    try {
      await http.post(
        Uri.parse("https://mobi.vinhuni.edu.vn/api/hide-notif/$id"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"student_id": studentId}),
      ).timeout(const Duration(seconds: 5));
    } catch (e) { debugPrint("⚠️ Lỗi xóa tin: $e"); }
  }
}