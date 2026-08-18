// lib/views/schedule_canbo.dart

class WeeklySchedule {
  final int id;
  final String date;
  final String session;
  final String time;
  final String content;
  final String participants;
  final String location;
  final String chair;

  WeeklySchedule({
    required this.id,
    required this.date,
    required this.session,
    required this.time,
    required this.content,
    required this.participants,
    required this.location,
    required this.chair,
  });

  // --- Chuyển từ JSON (API) sang Object ---
  factory WeeklySchedule.fromJson(Map<String, dynamic> json) {
    return WeeklySchedule(
      id: json['ScheduleId'] ?? 0,
      date: json['EventDate'] ?? '',
      session: json['Session'] ?? '',
      time: json['TimeValue'] ?? '',
      content: json['Content'] ?? '',
      participants: json['Participants'] ?? '',
      location: json['Location'] ?? '',
      chair: json['Chairperson'] ?? '',
    );
  }

  // --- Chuyển từ Map (SQLite) sang Object ---
  factory WeeklySchedule.fromMap(Map<String, dynamic> map) {
    return WeeklySchedule(
      id: map['ScheduleId'] ?? 0,
      date: map['EventDate'] ?? '',
      session: map['Session'] ?? '',
      time: map['TimeValue'] ?? '',
      content: map['Content'] ?? '',
      participants: map['Participants'] ?? '',
      location: map['Location'] ?? '',
      chair: map['Chairperson'] ?? '',
    );
  }

  // --- Chuyển từ Object sang Map để lưu xuống SQLite ---
  Map<String, dynamic> toMap() {
    return {
      'ScheduleId': id,
      'EventDate': date,
      'Session': session,
      'TimeValue': time,
      'Content': content,
      'Participants': participants,
      'Location': location,
      'Chairperson': chair,
    };
  }
}