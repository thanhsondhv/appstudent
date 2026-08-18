import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart' as dio;
import 'package:speech_to_text/speech_to_text.dart';
import 'package:vinhuni_app/services/vinhuni_api_client.dart'; 

class SecretaryService {
  final _audioRecorder = AudioRecorder();
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;

  Future<bool> initLiveSTT() async {
    _speechEnabled = await _speechToText.initialize(
      onError: (val) => print('❌ Lỗi Live STT: $val'),
      onStatus: (val) => print('ℹ️ Trạng thái: $val'),
    );
    return _speechEnabled;
  }

  Future<void> start({required Function(String) onLiveResult}) async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/vinhuni_meeting.m4a';
        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100), 
          path: path
        );
      }
      if (_speechEnabled) {
        _speechToText.listen(
          onResult: (result) => onLiveResult(result.recognizedWords),
          localeId: "vi_VN", 
          partialResults: true, 
          listenMode: ListenMode.dictation,
        );
      }
    } catch (e) { print("❌ Lỗi khởi động: $e"); }
  }

  // 🔥 HÀM GỬI DATA: Ép truyền rawText để tránh lỗi "0 ký tự"
  Future<dynamic> stopAndUpload({
    required String rawText, 
    required String role, 
    String userName = "Người dùng VinhUni"
  }) async {
    await _speechToText.stop();
    final path = await _audioRecorder.stop();
    
    if (rawText.trim().isEmpty) return {"status": "error", "message": "Dữ liệu trống"};

    final formData = dio.FormData.fromMap({
      'file': path != null ? await dio.MultipartFile.fromFile(path, filename: 'vinhuni_audio.m4a') : null,
      'raw_text': rawText,
      'user_name': userName,
      'role': role,
    });

    try {
      final res = await VinhUniClient.instance.post(
        '/api/secretary/transcribe', 
        data: formData,
        options: dio.Options(receiveTimeout: const Duration(seconds: 240)),
      );
      return res.data; 
    } catch (e) { return null; }
  }

  // 🔵 Định dạng cho Cán bộ
  String formatForStaff(Map<String, dynamic> data) {
    return "📌 BIÊN BẢN HỌP HÀNH CHÍNH - VINHUNI\n"
           "Thời gian: ${DateTime.now()}\\n\n"
           "I. TÓM TẮT: ${data['summary']}\n\n"
           "II. CHI TIẾT: ${data['clean_text']}\n\n"
           "III. ĐẦU VIỆC: ${(data['tasks'] as List).join(', ')}";
  }

  // 🟠 Định dạng cho Sinh viên
  String formatForStudent(Map<String, dynamic> data) {
    return "🎓 TÀI LIỆU ÔN TẬP - VINHUNI\n\n"
           "1. TÓM TẮT BÀI GIẢNG: ${data['summary']}\n\n"
           "2. KIẾN THỨC TRỌNG TÂM: ${data['clean_text']}\n\n"
           "3. CÂU HỎI GỢI Ý: ${(data['tasks'] as List).join('\\n- ')}";
  }
}