// views/chatgroup/widgets/chat_input_bar.dart
import 'package:flutter/material.dart';

class ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttachImage;
  final VoidCallback onAttachVideo;
  final VoidCallback onAttachFile;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onAttachImage,
    required this.onAttachVideo,
    required this.onAttachFile,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200, width: 1)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. THANH CÔNG CỤ ZALO (ICONS)
            Row(
              children: [
                _buildToolIcon(Icons.image_outlined, Colors.green, onAttachImage),
                _buildToolIcon(Icons.video_collection_outlined, Colors.orange, onAttachVideo),
                _buildToolIcon(Icons.attach_file_outlined, Colors.blue, onAttachFile),
                _buildToolIcon(Icons.emoji_emotions_outlined, Colors.amber.shade700, () {
                  // TODO: Hiện bảng Sticker
                }),
                _buildToolIcon(Icons.alternate_email, Colors.grey.shade700, () {
                  // TODO: Hiện tag @ thành viên
                  controller.text += "@";
                }),
              ],
            ),
            const SizedBox(height: 5),
            
            // 2. Ô NHẬP TEXT VÀ NÚT GỬI
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: TextField(
                      controller: controller,
                      maxLines: 4,
                      minLines: 1,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: "Nhập tin nhắn...",
                        hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, child) {
                    bool isTyping = value.text.trim().isNotEmpty;
                    return InkWell(
                      onTap: onSend,
                      borderRadius: BorderRadius.circular(25),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isTyping ? Colors.blue.shade600 : Colors.grey.shade200,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isTyping ? Icons.send : Icons.thumb_up, 
                          color: isTyping ? Colors.white : Colors.blue.shade600, 
                          size: 22
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolIcon(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Icon(icon, color: color, size: 26),
      ),
    );
  }
}