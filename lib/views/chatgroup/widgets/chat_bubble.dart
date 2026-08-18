import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; 
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart'; 
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:vinhuni_app/services/onedrive_service.dart'; 
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

// ==========================================================
// 1. WIDGET CHAT BUBBLE CHÍNH
// ==========================================================
class ChatBubble extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isMe;
  final bool isSelectionMode;
  final bool isSelected;
  final Map<String, dynamic>? originalMsg;
  final Function(Map<String, dynamic>) onReply;
  final Function(dynamic, String) onReact;
  final Function(dynamic) onRecall;
  final Function(dynamic) onDeleteLocal;
  final VoidCallback onSelect;
  final VoidCallback onEnterMultiSelect;
  final Function(Map<String, dynamic>)? onForward; 

  const ChatBubble({
    super.key, required this.data, required this.isMe,
    this.isSelectionMode = false, this.isSelected = false,
    this.originalMsg, required this.onReply, required this.onReact,
    required this.onRecall, required this.onDeleteLocal,
    required this.onSelect, required this.onEnterMultiSelect,
    this.onForward,
  });

  @override
  Widget build(BuildContext context) {
    bool isDeleted = data['IsDeleted'] == true || data['IsDeleted'] == 1 || data['is_deleted'] == true || data['is_deleted'] == 1;
    String senderId = (data['SenderCode'] ?? data['sender_code'] ?? "").toString();
    String senderName = data['SenderName'] ?? data['sender_name'] ?? data['FullName'] ?? (isMe ? "Bạn" : "Người dùng");
    String avatarUrl = "https://mobi.vinhuni.edu.vn/api/get-avatar/?student_id=$senderId";
    String content = data['MessageContent'] ?? data['content'] ?? data['message_content'] ?? "";
    String time = _formatTime(data['CreatedAt'] ?? DateTime.now().toString());

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) _buildAvatar(avatarUrl, senderName),
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe) Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 4),
                  child: Text(senderName, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                ),
                Stack(
                  clipBehavior: Clip.none, 
                  children: [
                    InkWell(
                      onTap: isSelectionMode ? onSelect : null,
                      onLongPress: (isSelectionMode || isDeleted) ? null : () => _showContextMenu(context),
                      onDoubleTap: (isSelectionMode || isDeleted) ? null : () {
                        onReact(data['MessageId'], '❤️');
                      },
                      child: Container(
                        color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.transparent,
                        child: _buildBubbleBody(isDeleted, content, time, isMe),
                      ),
                    ),
                    if (!isDeleted && data['Reactions'] != null)
                      Positioned(
                        bottom: -10, 
                        right: isMe ? 5 : null,
                        left: isMe ? null : 5,
                        child: _buildReactionBadge(data['Reactions']),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- HÀM VẼ BỘ ĐẾM SỐ LƯỢNG CẢM XÚC (ĐÃ FIX: HIỂN THỊ NHIỀU ICON SÁT NHAU) ---
  Widget _buildReactionBadge(dynamic reactions) {
    if (reactions == null) return const SizedBox.shrink();

    List<String> emojisToDisplay = [];
    int totalCount = 0;

    // Xử lý nếu dữ liệu là Map (Nhiều người thả nhiều loại cảm xúc)
    if (reactions is Map) {
      if (reactions.isEmpty) return const SizedBox.shrink();
      
      reactions.forEach((key, value) {
        // Đảm bảo value là số nguyên
        int count = value is int ? value : int.tryParse(value.toString()) ?? 0;
        if (count > 0) {
          emojisToDisplay.add(key.toString());
          totalCount += count;
        }
      });
    } 
    // Xử lý fallback nếu dữ liệu chỉ là chuỗi
    else if (reactions is String) {
      emojisToDisplay.add(reactions);
      totalCount = 1;
    }

    // Nếu sau khi lọc không có icon nào thì ẩn đi
    if (emojisToDisplay.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade300, width: 1),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 3, offset: const Offset(0, 1))
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Duyệt vòng lặp in TẤT CẢ các icon ra, xếp sát nhau
          ...emojisToDisplay.map((e) => Padding(
            padding: const EdgeInsets.only(right: 2), // Khoảng cách nhỏ giữa các icon
            child: Text(e, style: const TextStyle(fontSize: 12)),
          )),
          
          // 2. In TỔNG SỐ LƯỢNG (Nếu > 1 thì mới hiện số)
          if (totalCount > 1) ...[
            const SizedBox(width: 3),
            Text("$totalCount", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          ]
        ],
      ),
    );
  }

  String? _extractYouTubeId(String text) {
    RegExp regExp = RegExp(
        r"(?:https?:\/\/)?(?:www\.)?(?:youtube\.com\/(?:[^\/\n\s]+\/\S+\/|(?:v|e(?:mbed)?)\/|\S*?[?&]v=)|youtu\.be\/)([a-zA-Z0-9_-]{11})");
    Match? match = regExp.firstMatch(text);
    return match?.group(1);
  }

  Widget _buildBubbleBody(bool isDeleted, String content, String time, bool isMe) {
    String msgType = (data['MessageType'] ?? data['message_type'] ?? "TEXT").toString().toUpperCase();
    String? fileUrl = data['FileUrl'] ?? data['file_url'];
    String fileName = content.isNotEmpty ? content : "Tệp đính kèm";

    String? ytId = (msgType == "TEXT") ? _extractYouTubeId(content) : null;
    bool hasReply = originalMsg != null || data['ReplyToId'] != null || data['reply_to_id'] != null;

    return Container(
      constraints: const BoxConstraints(maxWidth: 270),
      padding: (isDeleted || (msgType == "TEXT" && ytId == null)) 
          ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10) 
          : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: isDeleted ? Colors.grey.shade100 : (isMe ? const Color(0xFF0054A6) : Colors.white),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16), topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isMe ? 16 : 0), bottomRight: Radius.circular(isMe ? 0 : 16),
        ),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, 2))],
        border: Border.all(color: isMe ? Colors.transparent : Colors.black12, width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (hasReply && !isDeleted) 
          Padding(padding: const EdgeInsets.only(top: 8, left: 8, right: 8), child: _buildReplyArea()),
        
        if (isDeleted)
          const Text("Tin nhắn đã bị thu hồi", style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Colors.grey))
        else if (ytId != null)
          Container(
            width: 260,
            decoration: BoxDecoration(
              color: isMe ? Colors.white.withOpacity(0.1) : Colors.red.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12)
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                YoutubeInAppWidget(videoId: ytId), 
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(content, style: TextStyle(color: isMe ? Colors.white : Colors.black87, fontSize: 13)),
                )
              ],
            ),
          )
        else if (msgType == "IMAGE" && fileUrl != null)
          GestureDetector(
            onTap: () => _openLinkExternally(fileUrl),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: OneDriveSecureImage(fileName: fileName), 
            ),
          )
        else if (msgType == "VIDEO" && fileUrl != null)
          GestureDetector(
            onTap: () => _openLinkExternally(fileUrl),
            child: Container(
              width: 250, padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isMe ? Colors.white.withOpacity(0.15) : Colors.orange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(15)
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.video_library, color: isMe ? Colors.white : Colors.orange, size: 36),
                    const SizedBox(width: 10),
                    Expanded(child: Text(fileName, style: TextStyle(color: isMe ? Colors.white : Colors.black87, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis)),
                  ]),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(color: isMe ? Colors.white24 : Colors.orange.shade100, borderRadius: BorderRadius.circular(8)),
                    child: Center(child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.play_circle_fill, color: isMe ? Colors.white : Colors.orange.shade800, size: 16),
                        const SizedBox(width: 5),
                        Text("Phát Video", style: TextStyle(color: isMe ? Colors.white : Colors.orange.shade800, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    )),
                  )
                ],
              ),
            ),
          )
        else if (msgType == "FILE" && fileUrl != null)
          GestureDetector(
            onTap: () => _openLinkExternally(fileUrl),
            child: Container(
              width: 250, padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isMe ? Colors.white.withOpacity(0.15) : Colors.blue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(15)
              ),
              child: Row(children: [
                Icon(Icons.description, color: isMe ? Colors.white : Colors.blue.shade700, size: 36),
                const SizedBox(width: 10),
                Expanded(child: Text(fileName, style: TextStyle(color: isMe ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, decoration: TextDecoration.underline), maxLines: 2, overflow: TextOverflow.ellipsis)),
              ]),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(content, style: TextStyle(fontSize: 15, color: isMe ? Colors.white : Colors.black87)),
          ),
        
        Padding(
          padding: const EdgeInsets.only(right: 14, left: 14, bottom: 8, top: 4),
          child: Text(time, style: TextStyle(fontSize: 9, color: isMe ? Colors.white70 : Colors.grey)),
        ),
      ]),
    );
  }

  Widget _buildReplyArea() {
    String replyName = originalMsg?['SenderName'] ?? data['ReplyToName'] ?? data['reply_to_name'] ?? "Thành viên";
    String replyContent = originalMsg?['MessageContent'] ?? originalMsg?['content'] ?? data['ReplyToContent'] ?? data['reply_to_content'] ?? "Tin nhắn đính kèm";

    return Container(
      padding: const EdgeInsets.all(6),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(6)),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 3, color: Colors.blue.shade700),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(replyName, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                const SizedBox(height: 2),
                Text(replyContent, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: Colors.black54)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openLinkExternally(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication); 
    } catch (e) {
      debugPrint("❌ Lỗi mở Link: $e");
    }
  }

  void _showContextMenu(BuildContext context) {
    String content = data['MessageContent'] ?? data['content'] ?? data['message_content'] ?? "";

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 15),
            
            // 🔥 ĐÃ FIX: Bọc InkWell và Padding để mở rộng vùng chạm (hitbox) cho Icon
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: ["❤️", "👍", "😄", "😮", "😭", "😡"].map((e) => Material(
                color: Colors.transparent, // Cần Material để hiện hiệu ứng sóng (ripple)
                child: InkWell(
                  borderRadius: BorderRadius.circular(30), // Bo góc cho hiệu ứng tròn
                  onTap: () { 
                    Navigator.pop(ctx); // Đóng menu trước
                    onReact(data['MessageId'], e); // Gửi cảm xúc
                  }, 
                  child: Padding(
                    padding: const EdgeInsets.all(12.0), // Mở rộng vùng bấm ra 12px mỗi chiều
                    child: Text(e, style: const TextStyle(fontSize: 30)),
                  )
                ),
              )).toList(),
            ),
            
            const Divider(height: 25),
            
            _menuItem(Icons.reply, "Trả lời tin nhắn", () { 
              Navigator.pop(ctx); 
              onReply(data); 
            }),
            
            _menuItem(Icons.copy, "Sao chép văn bản", () { 
              Clipboard.setData(ClipboardData(text: content));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Đã sao chép tin nhắn!")));
            }),

            _menuItem(Icons.shortcut, "Chuyển tiếp tin nhắn", () { 
              Navigator.pop(ctx);
              if (onForward != null) {
                onForward!(data); 
              }
            }),

            _menuItem(Icons.checklist, "Chọn nhiều tin nhắn cùng lúc", () { 
              Navigator.pop(ctx); 
              onEnterMultiSelect(); 
            }),
            
            if (isMe) 
              _menuItem(Icons.refresh, "Thu hồi (Xóa phía mọi người)", () { 
                Navigator.pop(ctx); 
                onRecall(data['MessageId']); 
              }, color: Colors.orange.shade800),
            
            _menuItem(Icons.delete_outline, "Xóa tin nhắn (Chỉ phía tôi)", () { 
                Navigator.pop(ctx); 
                onDeleteLocal(data['MessageId']); 
              }, color: Colors.red),
            
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _menuItem(IconData icon, String title, VoidCallback onTap, {Color? color}) {
    return ListTile(
      leading: Icon(icon, color: color ?? Colors.black87), 
      title: Text(title, style: TextStyle(color: color ?? Colors.black87, fontWeight: FontWeight.w500, fontSize: 14)), 
      onTap: onTap
    );
  }

  Widget _buildAvatar(String url, String name) => Padding(
    padding: const EdgeInsets.only(right: 8, top: 4),
    child: CircleAvatar(radius: 16, backgroundColor: Colors.white, child: ClipOval(child: CachedNetworkImage(
      imageUrl: url, 
      fit: BoxFit.cover, 
      memCacheWidth: 100,  
      memCacheHeight: 100, 
      placeholder: (context, url) => const CircularProgressIndicator(strokeWidth: 1), 
      errorWidget: (ctx, err, stack) => Text(name.isNotEmpty ? name[0].toUpperCase() : "U", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))))),
  );
  
  String _formatTime(dynamic date) { try { return DateFormat('HH:mm').format(DateTime.parse(date.toString())); } catch (_) { return ""; } }
} 

// ==========================================================
// 2. WIDGET TRÌNH PHÁT YOUTUBE TRỰC TIẾP TRONG CHAT
// ==========================================================
class YoutubeInAppWidget extends StatefulWidget {
  final String videoId;
  const YoutubeInAppWidget({super.key, required this.videoId});

  @override
  State<YoutubeInAppWidget> createState() => _YoutubeInAppWidgetState();
}

class _YoutubeInAppWidgetState extends State<YoutubeInAppWidget> {
  late YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController(
      initialVideoId: widget.videoId,
      flags: const YoutubePlayerFlags(autoPlay: false, mute: false),
    );
  }

  @override
  void dispose() {
    _controller.dispose(); 
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 🔥 SỬ DỤNG AspectRatio ĐỂ GIỮ KHUNG ỔN ĐỊNH CHO LISTVIEW
    return AspectRatio(
      aspectRatio: 16 / 9, 
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: YoutubePlayer(
          controller: _controller,
          showVideoProgressIndicator: true,
          progressIndicatorColor: Colors.red,
          // Tính năng giúp chặn video nuốt sự kiện cuộn
          bottomActions: [
            CurrentPosition(),
            ProgressBar(isExpanded: true),
            RemainingDuration(),
          ],
        ),
      ),
    );
  }
}


// ==========================================================
// 3. WIDGET TẢI VÀ HIỂN THỊ ẢNH ONEDRIVE (CÓ CACHE SIÊU TỐC)
// ==========================================================
class OneDriveSecureImage extends StatefulWidget {
  final String fileName;
  const OneDriveSecureImage({super.key, required this.fileName});

  @override
  State<OneDriveSecureImage> createState() => _OneDriveSecureImageState();
}

class _OneDriveSecureImageState extends State<OneDriveSecureImage> {
  // ... (Giữ nguyên hàm _fetchAndCacheImage của bạn) ...
  Future<Uint8List?> _fetchAndCacheImage() async {
    try {
      String safeName = Uri.encodeComponent(widget.fileName);
      String cacheKey = "vinhuni_onedrive_$safeName"; 

      FileInfo? cachedFile = await DefaultCacheManager().getFileFromCache(cacheKey);
      if (cachedFile != null) {
        return await cachedFile.file.readAsBytes();
      }

      String? token = await OneDriveService().getValidToken(context);
      if (token == null) return null;

      String apiUrl = "https://graph.microsoft.com/v1.0/me/drive/root:/VinhUni_Chat/$safeName:/content";
      
      final response = await Dio().get<List<int>>(
        apiUrl,
        options: Options(headers: {"Authorization": "Bearer $token"}, responseType: ResponseType.bytes),
      );
      
      Uint8List bytes = Uint8List.fromList(response.data!);
      await DefaultCacheManager().putFile(apiUrl, bytes, key: cacheKey, fileExtension: "jpg");
      return bytes;
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _fetchAndCacheImage(), 
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: 250, height: 180, // 🔥 Cố định 180
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (snapshot.hasError || snapshot.data == null) {
          return Container(
            width: 250, height: 180, // 🔥 Phải đồng bộ 250x180
            decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(10)),
            child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
          );
        }
        return Image.memory(
          snapshot.data!, 
          fit: BoxFit.cover, 
          width: 250,
          height: 180, // 🔥 CHỐT CHẶN TẠI ĐÂY: Không cho ảnh bung bậy bạ làm giật ListView
          cacheWidth: 800, 
        );
      },
    );
  }
}