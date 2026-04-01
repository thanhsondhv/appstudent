class WeeklySchedule {
  final int id;
  final String date;
  final String session;
  final String time;
  final String content;
  final String participants;
  final String location;
  final String chair;
  final String eventHash;
  final String targetGroups;
  final int isNotified;
  final int isModified;
  final String createdAt;
  final String updatedAt;
  final int isReminderSent;

  WeeklySchedule({
    required this.id,
    required this.date,
    required this.session,
    required this.time,
    required this.content,
    required this.participants,
    required this.location,
    required this.chair,
    this.eventHash = '',
    this.targetGroups = '',
    this.isNotified = 0,
    this.isModified = 0,
    this.createdAt = '',
    this.updatedAt = '',
    this.isReminderSent = 0,
  });

  // --- 1. CHUYỂN TỪ JSON (API) SANG OBJECT ---
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
      eventHash: json['EventHash'] ?? '',
      targetGroups: json['TargetGroups'] ?? '',
      // Xử lý kiểu bool từ API sang int (0/1) cho SQLite
      isNotified: (json['IsNotified'] == true || json['IsNotified'] == 1) ? 1 : 0,
      isModified: (json['IsModified'] == true || json['IsModified'] == 1) ? 1 : 0,
      createdAt: json['CreatedAt'] ?? '',
      updatedAt: json['UpdatedAt'] ?? '',
      isReminderSent: (json['IsReminderSent'] == true || json['IsReminderSent'] == 1) ? 1 : 0,
    );
  }

  // --- 2. CHUYỂN TỪ MAP (SQLITE) SANG OBJECT ---
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
      eventHash: map['EventHash'] ?? '',
      targetGroups: map['TargetGroups'] ?? '',
      isNotified: map['IsNotified'] ?? 0,
      isModified: map['IsModified'] ?? 0,
      createdAt: map['CreatedAt'] ?? '',
      updatedAt: map['UpdatedAt'] ?? '',
      isReminderSent: map['IsReminderSent'] ?? 0,
    );
  }

  // --- 3. CHUYỂN TỪ OBJECT SANG MAP (ĐỂ LƯU XUỐNG SQLITE) ---
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
      'EventHash': eventHash,
      'TargetGroups': targetGroups,
      'IsNotified': isNotified,
      'IsModified': isModified,
      'CreatedAt': createdAt,
      'UpdatedAt': updatedAt,
      'IsReminderSent': isReminderSent,
    };
  }
}