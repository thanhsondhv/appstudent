import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinhuni_app/services/teams_service.dart';

class TeamsMessageScreen extends StatefulWidget {
  final String chatId;
  final String chatTitle;
  final String? teamId;

  const TeamsMessageScreen({super.key, required this.chatId, required this.chatTitle, this.teamId});

  @override
  State<TeamsMessageScreen> createState() => _TeamsMessageScreenState();
}

class _TeamsMessageScreenState extends State<TeamsMessageScreen> {
  final TeamsService _teamsService = TeamsService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  List<dynamic> _messages = [];
  bool _isLoading = true;
  String myMsId = ""; 
  StreamSubscription<RemoteMessage>? _fcmSubscription;

  @override
  void initState() {
    super.initState();
    _loadMyMsId();
    _loadMessages();
    _initFirebaseListener();
  }

  @override
  void dispose() {
    _fcmSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _initFirebaseListener() {
    _fcmSubscription = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      String? incomingChatId = message.data['chat_id'];
      if (incomingChatId == widget.chatId && mounted) {
        _loadMessages(isBackground: true); 
      }
    });
  }

  Future<void> _loadMyMsId() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => myMsId = prefs.getString('ms_user_id') ?? ""); 
  }

  Future<void> _loadMessages({bool isBackground = false}) async {
    try {
      if (!isBackground) setState(() => _isLoading = true);
      List<dynamic> data = (widget.teamId != null && widget.teamId!.isNotEmpty) 
          ? await _teamsService.getChannelMessages(widget.teamId!, widget.chatId)
          : await _teamsService.getMessages(widget.chatId);
      
      if (mounted) {
        setState(() { _messages = data; _isLoading = false; });
        if (isBackground) _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSendText() async {
    if (_messageController.text.trim().isEmpty) return;
    String content = _messageController.text.trim();
    _messageController.clear();
    
    bool success = await _teamsService.sendMessage(widget.chatId, content, teamId: widget.teamId);
    if (success) {
      await Future.delayed(const Duration(milliseconds: 500)); 
      _loadMessages(isBackground: true); 
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chatTitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF4B53BC),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF4B53BC)))
              : ListView.builder(
                  controller: _scrollController,
                  reverse: true, 
                  itemCount: _messages.length,
                  itemBuilder: (context, index) => _buildMessageBubble(_messages[index]),
                ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(dynamic msg) {
    final senderObj = msg['from']?['user'] ?? {};
    bool isMe = senderObj['id'] != null && senderObj['id'] == myMsId; 
    String content = (msg['body']?['content'] ?? "").toString().replaceAll(RegExp(r'<[^>]*>|&nbsp;'), "").trim();

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: isMe ? const Color(0xFFE2E4F6) : Colors.white, borderRadius: BorderRadius.circular(10)),
        child: Text(content),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.white,
      child: Row(children: [
        Expanded(child: TextField(controller: _messageController, decoration: const InputDecoration(hintText: "Nhập tin nhắn..."))),
        IconButton(icon: const Icon(Icons.send, color: Color(0xFF4B53BC)), onPressed: _handleSendText),
      ]),
    );
  }
}