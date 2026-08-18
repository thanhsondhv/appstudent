import 'package:vinhuni_app/services/vinhuni_api_client.dart';

class TeamsService {
  // Lấy danh sách Chat (1-1, Meeting)
  Future<List<dynamic>> getMyChats() async {
    try {
      final response = await VinhUniClient.instance.get('/api/ms-chat/my-chats');
      return response.data['value'] ?? [];
    } catch (e) { return []; }
  }

  // Lấy danh sách Nhóm (Teams)
  Future<List<dynamic>> getMyTeams() async {
    try {
      final response = await VinhUniClient.instance.get('/api/ms-chat/my-teams');
      return response.data['value'] ?? [];
    } catch (e) { return []; }
  }

  // Lấy danh sách Kênh (Channels)
  Future<List<dynamic>> getChannels(String teamId) async {
    try {
      final response = await VinhUniClient.instance.get('/api/ms-chat/teams/$teamId/channels');
      return response.data['value'] ?? [];
    } catch (e) { return []; }
  }

  // Lấy tin nhắn Chat cá nhân
  Future<List<dynamic>> getMessages(String chatId) async {
    try {
      final response = await VinhUniClient.instance.get('/api/ms-chat/messages/$chatId');
      return response.data['value'] ?? [];
    } catch (e) { return []; }
  }

  // Lấy tin nhắn Kênh (Nhóm)
  Future<List<dynamic>> getChannelMessages(String teamId, String channelId) async {
    try {
      final response = await VinhUniClient.instance.get('/api/ms-chat/teams/$teamId/channels/$channelId/messages');
      return response.data['value'] ?? [];
    } catch (e) { return []; }
  }

  // 🔥 HÀM GỬI DUY NHẤT: Dùng cho cả Chat và Nhóm
  Future<bool> sendMessage(String chatId, String content, {String? teamId}) async {
    try {
      final response = await VinhUniClient.instance.post(
        '/api/ms-chat/send',
        data: {"chatId": chatId, "content": content, "teamId": teamId},
      );
      return response.statusCode == 201 || response.statusCode == 200;
    } catch (e) { return false; }
  }
}