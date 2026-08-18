// lib/services/voice_control_service.dart
import 'package:dio/dio.dart' as dio;
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'vinhuni_api_client.dart'; 

class VoiceControlService {
  final _recorder = AudioRecorder();

  Future<void> start() async {
    if (await _recorder.hasPermission()) {
      final dir = await getApplicationDocumentsDirectory();
      await _recorder.start(const RecordConfig(), path: '${dir.path}/command.m4a');
    }
  }

  Future<Map<String, dynamic>?> stopAndExecute() async {
    final path = await _recorder.stop();
    if (path == null) return null;

    final formData = dio.FormData.fromMap({
      'file': await dio.MultipartFile.fromFile(path, filename: 'command.m4a'),
    });

    try {
      final res = await VinhUniClient.instance.post('/api/voice-control/execute', data: formData);
      return res.data; // Trả về JSON chứa target_route
    } catch (e) {
      return null;
    }
  }
}