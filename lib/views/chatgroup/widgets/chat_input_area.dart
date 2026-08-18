import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ChatBubble extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isMe;
  final Map<String, dynamic>? originalMsg; // Dùng để hiển thị nội dung tin nhắn được Reply
  final Function(Map<String, dynamic>) onReply;
  final Function(int, String) onReact;
  final Function(int) onRecall;      // Thu hồi (Xóa phía server cho mọi người)
  final Function(int) onDeleteLocal; // Xóa (Chỉ ẩn ở máy mình)

  const ChatBubble({
    super.key,
    required this.data,
    required this.isMe,
    this.originalMsg,
    required this.onReply,
    required this.onReact,
    required this.onRecall,
    required this.onDeleteLocal,
  });

  @override
  Widget build(BuildContext context) {
    bool isDeleted = data['IsDeleted'] == true || data['IsDeleted'] == 1;
    String time = _formatTime(data['CreatedAt']);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onLongPress: () => _showContextMenu(context),
                child: Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDeleted ? Colors.grey.shade100 : (isMe ? const Color(0xFFE3F2FD) : Colors.white),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black12, width: 0.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- HIỂN THỊ REPLY (Thanh dọc xanh, nền xanh nhạt) ---
                      if (originalMsg != null && !isDeleted) _buildReplyArea(),
                      
                      const SizedBox(height: 5),
                      
                      // --- NỘI DUNG TIN NHẮN ---
                      isDeleted 
                        ? const Text("Tin nhắn đã bị thu hồi", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey))
                        : Text(data['MessageContent'] ?? "", style: const TextStyle(fontSize: 15)),
                      
                      const SizedBox(height: 4),
                      
                      // --- THỜI GIAN ---
                      Text(time, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    ],
                  ),
                ),
              ),
              
              // --- ĐẾM TƯƠNG TÁC (REACTION COUNT) ---
              if (!isDeleted && data['Reaction'] != null)
                Positioned(
                  bottom: -10, 
                  right: isMe ? 10 : null, 
                  left: isMe ? null : 10,
                  child: _buildReactionCount(data['Reaction']),
                ),
            ],
          ),
          // Trạng thái "Đã gửi" dưới tin nhắn của mình
          if (isMe && !isDeleted) _buildStatus(),
        ],
      ),
    );
  }

  Widget _buildReplyArea() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(width: 3, color: Colors.blue.shade700), // Thanh dọc xanh đậm
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(originalMsg!['SenderCode'] ?? "Cán bộ", 
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900, fontSize: 12)),
                    Text(originalMsg!['MessageContent'] ?? "", 
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black54, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReactionCount(String emoji) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 2),
          const Text("1", style: TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildStatus() => const Padding(
    padding: EdgeInsets.only(top: 4), 
    child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.done, size: 12, color: Colors.grey), Text(" Đã gửi", style: TextStyle(fontSize: 10, color: Colors.grey))])
  );

  String _formatTime(dynamic date) {
    if (date == null) return "";
    try {
      DateTime dt = DateTime.parse(date.toString());
      return DateFormat('HH:mm').format(dt);
    } catch (_) { return ""; }
  }

  void _showContextMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 15),
          // Hàng icon cảm xúc
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ["❤️", "👍", "😄", "😮", "😭", "😡"].map((e) => GestureDetector(
              onTap: () { onReact(data['MessageId'], e); Navigator.pop(ctx); }, 
              child: Text(e, style: const TextStyle(fontSize: 30))
            )).toList(),
          ),
          const Divider(),
          ListTile(leading: const Icon(Icons.format_quote), title: const Text("Trả lời"), onTap: () { Navigator.pop(ctx); onReply(data); }),
          ListTile(leading: const Icon(Icons.copy), title: const Text("Sao chép"), onTap: () => Navigator.pop(ctx)),
          if (isMe) ListTile(
            leading: const Icon(Icons.refresh, color: Colors.orange), 
            title: const Text("Thu hồi (Xóa cho mọi người)"), 
            onTap: () { Navigator.pop(ctx); onRecall(data['MessageId']); }
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red), 
            title: const Text("Xóa (Chỉ ở phía tôi)"), 
            onTap: () { Navigator.pop(ctx); onDeleteLocal(data['MessageId']); }
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}