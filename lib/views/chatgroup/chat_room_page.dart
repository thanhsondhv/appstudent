import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinhuni_app/services/database_helper.dart'; 
import '../../services/vinhuni_api_client.dart'; 
import 'widgets/chat_bubble.dart'; 
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:vinhuni_app/services/onedrive_service.dart'; 
import 'package:dio/dio.dart';
import 'widgets/chat_input_bar.dart';

class ChatRoomPage extends StatefulWidget {
  final String groupId;
  final String userCode;

  const ChatRoomPage({super.key, required this.groupId, required this.userCode});

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  late IO.Socket _socket;
  List<dynamic> _messages = [];
  bool _isLoading = true;
  String _groupName = "Đang kết nối...";
  String _myName = "";
  String _myAvatar = "";
  bool _isSelectionMode = false; 
  Set<dynamic> _selectedIds = {}; 
  Map<String, dynamic>? _replyingTo;
  bool _isAdmin = false;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initData();
    _connectSocket();
  }

  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(15))),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.image, color: Colors.green, size: 28),
              title: const Text("Hình ảnh / Bộ sưu tập", style: TextStyle(fontWeight: FontWeight.w500)),
              onTap: () { Navigator.pop(ctx); _pickAndUploadMultimedia(FileType.image, "IMAGE"); },
            ),
            ListTile(
              leading: const Icon(Icons.video_collection, color: Colors.orange, size: 28),
              title: const Text("Video clip", style: TextStyle(fontWeight: FontWeight.w500)),
              onTap: () { Navigator.pop(ctx); _pickAndUploadMultimedia(FileType.video, "VIDEO"); },
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file, color: Colors.blue, size: 28),
              title: const Text("Tài liệu / File khác", style: TextStyle(fontWeight: FontWeight.w500)),
              onTap: () { Navigator.pop(ctx); _pickAndUploadMultimedia(FileType.any, "FILE"); },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUploadMultimedia(FileType pickType, String msgType) async {
    try {
      String? msToken = await OneDriveService().getValidToken(context);
      if (msToken == null) return;

      FilePickerResult? result = await FilePicker.platform.pickFiles(type: pickType);
      
      if (result != null && result.files.single.path != null) {
        String filePath = result.files.single.path!;
        String fileName = result.files.single.name;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Đang tải $fileName lên OneDrive..."), duration: const Duration(seconds: 2))
        );

        FormData formData = FormData.fromMap({
          "user_code": widget.userCode,
          "ms_token": msToken,
          "file": await MultipartFile.fromFile(filePath, filename: fileName),
        });

        final res = await VinhUniClient.instance.post("/api/v1/chat/upload-onedrive", data: formData);

        if (res.statusCode == 200) {
           String fileUrl = res.data['file_url'];
           
           _socket.emit('send_message', {
              "group_id": widget.groupId,
              "sender_code": widget.userCode,
              "sender_name": _myName, 
              "content": fileName, 
              "message_type": msgType, 
              "file_url": fileUrl,
              
              // 🔥 ĐÃ THÊM DÒNG NÀY: Truyền Token lên Socket để Python dùng tải File
              "ms_token": msToken     
           });
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Lỗi hệ thống khi tải tệp lên!"), backgroundColor: Colors.red)
      );
    }
  }

  Future<void> _initData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_code', widget.userCode);
    if (mounted) {
      setState(() {
        _myName = prefs.getString('full_name') ?? prefs.getString('user_name') ?? "Cán bộ"; 
        _myAvatar = 'https://mobi.vinhuni.edu.vn/api/get-avatar/?student_id=${widget.userCode}';
      });
    }
    
    final localGroups = await DatabaseHelper.instance.getChatGroups();
    final thisGroup = localGroups.firstWhere((g) => g['GroupId'].toString() == widget.groupId.toString(), orElse: () => {});
    if (thisGroup.isNotEmpty && mounted) setState(() => _groupName = thisGroup['GroupName']);

    final rawLocal = await DatabaseHelper.instance.getChatHistory(widget.groupId);
    if (mounted) {
      setState(() {
        _messages = rawLocal.map((m) => Map<String, dynamic>.from(m)).toList();
        _isLoading = false;
      });
      _scrollToBottom(animate: false);
    }

    try {
      final joinRes = await VinhUniClient.instance.post(
        "/api/v1/chat/join",
        data: {"group_id": widget.groupId, "user_code": widget.userCode}
      );
      
      if (joinRes.statusCode == 200 && mounted) {
        setState(() {
          _isAdmin = joinRes.data['is_admin'] ?? false; 
          _groupName = joinRes.data['group_name'] ?? _groupName; 
        });
      }
    } catch (e) {
      debugPrint("❌ Lỗi lấy quyền Admin: $e");
    }

    try {
      final res = await VinhUniClient.instance.get("/api/v1/chat/history/${widget.groupId}"); 
      if (res.statusCode == 200) {
        List<dynamic> serverMsgs = res.data; 
        for (var m in serverMsgs) { 
          await DatabaseHelper.instance.saveChatMessage(m); 
        }
        
        final clean = await DatabaseHelper.instance.getChatHistory(widget.groupId);
        if (mounted) {
          setState(() {
            _messages = clean.map((m) => Map<String, dynamic>.from(m)).toList();
          });
          _scrollToBottom(animate: false);
        }
      }
    } catch (e) { 
      debugPrint("❌ Lỗi đồng bộ lịch sử: $e"); 
    }
  }

  void _connectSocket() {
    _socket = IO.io('https://mobi.vinhuni.edu.vn', IO.OptionBuilder()
        .setTransports(['websocket']).setPath('/socket.io').enableAutoConnect().build());

    _socket.onConnect((_) {
      _socket.emit('join_room', {"group_id": widget.groupId, "user_code": widget.userCode});
    });

    _socket.on('receive_message', (data) {
      if (mounted) {
        setState(() {
          Map<String, dynamic> newMessage = Map<String, dynamic>.from(data);
          bool exists = _messages.any((m) => m['MessageId'].toString() == newMessage['MessageId'].toString());
          if (!exists) { _messages.add(newMessage); }
        });
        _scrollToBottom();
        DatabaseHelper.instance.saveChatMessage(data);
      }
    });

    _socket.on('message_deleted', (data) async {
      if (mounted) {
        dynamic msgId = data['MessageId'] ?? data['message_id'];
        if (msgId != null) {
          await DatabaseHelper.instance.updateMessageDeletedLocal(msgId);
          setState(() {
            for (var m in _messages) {
              if (m['MessageId'].toString() == msgId.toString()) {
                m['IsDeleted'] = 1; 
              }
            }
          });
        }
      }
    });

    // 🔥 THÊM "LỖ TAI" MỚI: Lắng nghe khi có thành viên khác thả tim
    _socket.on('message_reacted', (data) {
      if (mounted) {
        setState(() {
          dynamic msgId = data['message_id'];
          String emoji = data['reaction_type'];
          
          for (var m in _messages) {
            if (m['MessageId'].toString() == msgId.toString()) {
              if (m['Reactions'] is Map) {
                // Nếu đã có người thả trước đó, cộng dồn số lượng
                m['Reactions'][emoji] = (m['Reactions'][emoji] ?? 0) + 1;
              } else {
                // Nếu đây là người đầu tiên thả tim cho tin nhắn này
                m['Reactions'] = {emoji: 1};
              }
            }
          }
        });
      }
    });
  }

  void _sendMessage({String type = "TEXT"}) {
    String content = type == "LIKE" ? "👍" : _messageController.text.trim();
    if (content.isEmpty) return;

    final Map<String, dynamic> messagePayload = {
      "group_id": widget.groupId,
      "sender_code": widget.userCode,
      "sender_name": _myName, 
      "content": content,
      "message_type": type,
      "reply_to_id": _replyingTo?['MessageId'],
      "reply_to_name": _replyingTo?['SenderName']
    };

    _socket.emit('send_message', messagePayload);
    _messageController.clear();
    if (mounted) setState(() => _replyingTo = null);
  }

 // 🔥 ĐÃ FIX: Hàm cuộn thông minh, phân biệt giữa lúc mới mở phòng và lúc có tin nhắn mới
  void _scrollToBottom({bool animate = true}) {
    // addPostFrameCallback đảm bảo Flutter đã vẽ xong giao diện rồi mới tính toán cuộn
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        // Thêm độ trễ cực nhỏ (50ms) để các Widget Image/File kịp bung kích thước
        Future.delayed(const Duration(milliseconds: 50), () {
          if (!_scrollController.hasClients) return;
          
          if (animate) {
            // Cuộn mượt mà (Dành cho lúc có người gửi tin nhắn mới)
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300), 
              curve: Curves.easeOut
            );
          } else {
            // Nhảy chớp nhoáng (Dành cho lúc tải dữ liệu ban đầu, chống giật màn hình)
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
      }
    });
  }

  // 🔥 HÀM MỚI 1: HIỂN THỊ DIALOG CHỌN NHÓM ĐỂ CHUYỂN TIẾP
  void _showForwardBottomSheet(dynamic messageToForward) async {
    final localGroups = await DatabaseHelper.instance.getChatGroups();

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6, maxChildSize: 0.9, minChildSize: 0.4, expand: false,
          builder: (_, controller) {
            return Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text("Chuyển tiếp tin nhắn", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
                const Divider(height: 1),
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.blue.withOpacity(0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue.withOpacity(0.15))),
                  child: Row(
                    children: [
                      const Icon(Icons.shortcut, color: Colors.blue, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          messageToForward['MessageContent'] ?? messageToForward['content'] ?? "[Đính kèm]",
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: controller,
                    itemCount: localGroups.length,
                    itemBuilder: (context, index) {
                      final group = localGroups[index];
                      if (group['GroupId'].toString() == widget.groupId.toString()) return const SizedBox.shrink();

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue.shade50, 
                          child: Text(group['GroupName'][0].toUpperCase(), style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.bold, fontSize: 14))
                        ),
                        title: Text(group['GroupName'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade900,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            elevation: 0
                          ),
                          onPressed: () {
                            _executeForward(messageToForward, group['GroupId'].toString());
                            Navigator.pop(ctx);
                          },
                          child: const Text("GỬI", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 🔥 HÀM MỚI 2: THỰC THI CHUYỂN TIẾP GỬI ĐI
  void _executeForward(dynamic originalMessage, String targetGroupId) {
    Map<String, dynamic> forwardPayload = {
      "group_id": targetGroupId,
      "sender_code": widget.userCode,
      "sender_name": _myName,
      "content": originalMessage['MessageContent'] ?? originalMessage['content'],
      "message_type": originalMessage['MessageType'] ?? "TEXT",
      "file_url": originalMessage['FileUrl'] ?? originalMessage['file_url'],
    };

    _socket.emit('send_message', forwardPayload);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Đã chuyển tiếp tin nhắn thành công!"), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating)
    );
  }

  void _showAddMemberModal() {
    List<dynamic> _searchResults = [];
    bool _isSearching = false;
    Timer? _debounce;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            void _performSearch(String query) {
              if (_debounce?.isActive ?? false) _debounce!.cancel();
              _debounce = Timer(const Duration(milliseconds: 500), () async {
                if (query.trim().isEmpty) {
                  setModalState(() { _searchResults = []; _isSearching = false; });
                  return;
                }
                
                setModalState(() { _isSearching = true; });
                try {
                  final res = await VinhUniClient.instance.get(
                    "/api/admin/search-user", 
                    queryParameters: {"q": query}
                  );
                  if (res.statusCode == 200) {
                    setModalState(() {
                      _searchResults = res.data;
                      _isSearching = false;
                    });
                  }
                } catch (e) {
                  setModalState(() { _isSearching = false; });
                  debugPrint("❌ Lỗi tìm kiếm: $e");
                }
              });
            }

            void _addSelectedMember(String userId, String userName) async {
              try {
                final res = await VinhUniClient.instance.post(
                  "/api/v1/chat/groups/add-members",
                  data: {
                    "group_id": widget.groupId,
                    "members": [userId]
                  }
                );
                
                if (res.statusCode == 200) {
                  Navigator.pop(ctx); 
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(content: Text("Đã thêm $userName vào nhóm!"), backgroundColor: Colors.green)
                  );
                  
                  _socket.emit('send_message', {
                    "group_id": widget.groupId,
                    "sender_code": widget.userCode,
                    "sender_name": _myName, 
                    "content": "Đã thêm $userName vào nhóm.",
                    "message_type": "SYSTEM",
                  });
                }
              } catch (e) {
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text("Lỗi khi thêm thành viên!"), backgroundColor: Colors.red)
                );
              }
            }

            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Container(
                height: MediaQuery.of(ctx).size.height * 0.7, 
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text("Thêm thành viên", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: "Tìm theo tên hoặc mã Cán bộ/SV...",
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0)
                      ),
                      onChanged: _performSearch,
                    ),
                    const SizedBox(height: 10),
                    if (_isSearching) const CircularProgressIndicator(),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final user = _searchResults[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue.shade100,
                              backgroundImage: NetworkImage('https://mobi.vinhuni.edu.vn/api/get-avatar/?student_id=${user["id"]}'),
                              onBackgroundImageError: (_, __) {},
                              child: Text(user["name"][0], style: TextStyle(color: Colors.blue.shade900)),
                            ),
                            title: Text(user["name"], style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(user["id"]),
                            trailing: IconButton(
                              icon: const Icon(Icons.add_circle, color: Colors.blue, size: 30),
                              onPressed: () => _addSelectedMember(user["id"], user["name"]),
                            ),
                          );
                        },
                      ),
                    )
                  ],
                ),
              ),
            );
          }
        );
      }
    );
  }

  void _showMembersModal() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return FutureBuilder<dynamic>(
          future: VinhUniClient.instance.get("/api/v1/chat/members/${widget.groupId}"),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
            }
            
            if (!snapshot.hasData || snapshot.data.data == null) {
              return const SizedBox(height: 100, child: Center(child: Text("Không có dữ liệu")));
            }

            List<dynamic> members = snapshot.data.data;

            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Thành viên (${members.length})", 
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Divider(),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: members.length,
                      itemBuilder: (context, index) {
                        final m = members[index];
                        int role = m['role'] ?? 3;
                        
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: NetworkImage('https://mobi.vinhuni.edu.vn/api/get-avatar/?student_id=${m["id"]}'),
                            onBackgroundImageError: (_, __) {},
                            child: Text(m["name"][0]),
                          ),
                          title: Text(m["name"], style: const TextStyle(fontWeight: FontWeight.w500)),
                          subtitle: Text(m["id"]),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: role == 1 ? Colors.red.shade50 : Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              role == 1 ? "Trưởng nhóm" : (role == 2 ? "Phó nhóm" : "Thành viên"),
                              style: TextStyle(fontSize: 10, color: role == 1 ? Colors.red : Colors.blue.shade900, fontWeight: FontWeight.bold),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (_isAdmin) ...[
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.delete_forever, color: Colors.red),
                      title: const Text("Giải tán nhóm", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
                      onTap: () {
                        Navigator.pop(ctx); 
                        _confirmDisbandGroup(); 
                      },
                    ),
                  ]
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDisbandGroup() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Cảnh báo nguy hiểm", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: const Text("Bạn có chắc chắn muốn giải tán nhóm này không? Toàn bộ tin nhắn và danh sách thành viên sẽ bị xóa vĩnh viễn trên Server."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Hủy", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx); 
              try {
                final res = await VinhUniClient.instance.delete(
                  "/api/v1/chat/delete_group/${widget.groupId}",
                  queryParameters: {"user_code": widget.userCode}
                );

                if (res.statusCode == 200) {
                  await DatabaseHelper.instance.deleteChatGroupLocal(widget.groupId);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Đã giải tán nhóm thành công!"), backgroundColor: Colors.green)
                  );
                  Navigator.pop(context, true); 
                }
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Lỗi: Không thể giải tán nhóm!"), backgroundColor: Colors.red)
                );
              }
            },
            child: const Text("Giải tán", style: TextStyle(color: Colors.white)),
          )
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        iconTheme: const IconThemeData(color: Colors.white),
        backgroundColor: Colors.blue.shade900,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_groupName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          Text("Nhóm: ${widget.groupId}", style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.people_alt_outlined),
            tooltip: "Thành viên nhóm",
            onPressed: _showMembersModal,
          ),
          IconButton(
            icon: const Icon(Icons.person_add_alt_1),
            tooltip: "Thêm thành viên",
            onPressed: _showAddMemberModal,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Column(children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController, 
                itemCount: _messages.length, 
                itemBuilder: (context, index) => _buildMessageItem(_messages[index])
              )
            ),
            
            if (_replyingTo != null) _buildReplyPreview(),
            
            // 🔥 ĐÃ THAY ĐỔI Ở ĐÂY: Gọi thanh ChatInputBar mới thay vì _buildInputArea cũ
            _isSelectionMode 
              ? _buildSelectionActionBar() 
              : ChatInputBar(
                  controller: _messageController,
                  onSend: () => _sendMessage(type: _messageController.text.isEmpty ? "LIKE" : "TEXT"),
                  onAttachImage: () => _pickAndUploadMultimedia(FileType.image, "IMAGE"),
                  onAttachVideo: () => _pickAndUploadMultimedia(FileType.video, "VIDEO"),
                  onAttachFile: () => _pickAndUploadMultimedia(FileType.any, "FILE"),
                ),
          ]),
    );
  }

  Widget _buildMessageItem(Map<String, dynamic> data) {
    bool isMe = (data['SenderCode'] ?? data['sender_code']).toString() == widget.userCode.toString();
    dynamic msgId = data['MessageId'];

    return ChatBubble(
      data: data,
      isMe: isMe,
      isSelectionMode: _isSelectionMode,
      isSelected: _selectedIds.contains(msgId),
      onReply: (m) { setState(() => _replyingTo = m); _scrollToBottom(); },
      onReact: (id, e) async {
        _socket.emit('react_message', {"message_id": id, "reaction_type": e, "group_id": widget.groupId, "user_code": widget.userCode});
        setState(() {
          for (var m in _messages) {
            if (m['MessageId'].toString() == id.toString()) {
              if (m['Reactions'] is Map) {
                m['Reactions'][e] = (m['Reactions'][e] ?? 0) + 1;
              } else {
                m['Reactions'] = {e: 1};
              }
              
              // 🔥 THÊM DÒNG NÀY: Lưu ngay cụm cảm xúc vừa đổi xuống SQLite máy mình
              DatabaseHelper.instance.updateMessageReactionLocal(id, m['Reactions']);
            }
          }
        });
      },
      onRecall: (id) => _socket.emit('delete_message', {"message_id": id, "group_id": widget.groupId}),
      onDeleteLocal: (id) => _confirmDeleteMessage(id),
      onForward: (msg) => _showForwardBottomSheet(msg), 
      onSelect: () {
        setState(() {
          if (_selectedIds.contains(msgId)) { _selectedIds.remove(msgId); if (_selectedIds.isEmpty) _isSelectionMode = false; } 
          else { _selectedIds.add(msgId); }
        });
      },
      onEnterMultiSelect: () { setState(() { _isSelectionMode = true; _selectedIds.add(msgId); }); },
    );
  }
  


  Widget _buildReplyPreview() => Container(
    padding: const EdgeInsets.all(10), color: Colors.white,
    child: Row(children: [
      const Icon(Icons.reply, color: Colors.blue), const SizedBox(width: 8),
      Expanded(child: Text("Trả lời: ${_replyingTo!['MessageContent']}", maxLines: 1, overflow: TextOverflow.ellipsis)),
      IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _replyingTo = null))
    ])
  );

  Widget _buildSelectionActionBar() {
    return Container(padding: const EdgeInsets.symmetric(vertical: 10), color: Colors.white, child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
      IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: _confirmDeleteMultiple),
      IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() { _isSelectionMode = false; _selectedIds.clear(); })),
    ]));
  }

  void _confirmDeleteMessage(dynamic id) {
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("Xóa tin nhắn?"), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Hủy")), TextButton(onPressed: () async { Navigator.pop(ctx); await DatabaseHelper.instance.deleteChatMessageLocal(id); setState(() => _messages.removeWhere((m) => m['MessageId'].toString() == id.toString())); }, child: const Text("Xóa", style: TextStyle(color: Colors.red)))]));
  }

  void _confirmDeleteMultiple() {
    showDialog(context: context, builder: (ctx) => AlertDialog(title: Text("Xóa ${_selectedIds.length} tin nhắn?"), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Hủy")), TextButton(onPressed: () async { Navigator.pop(ctx); for (var id in _selectedIds) { await DatabaseHelper.instance.deleteChatMessageLocal(id); } setState(() { _messages.removeWhere((m) => _selectedIds.contains(m['MessageId'])); _isSelectionMode = false; _selectedIds.clear(); }); }, child: const Text("Xóa", style: TextStyle(color: Colors.red)))]));
  }

  @override
  void dispose() { _socket.dispose(); _messageController.dispose(); _scrollController.dispose(); super.dispose(); }
}