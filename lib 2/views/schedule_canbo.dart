class WeeklySchedule {
  final String date;
  final String session;
  final String time;
  final String content;
  final String participants;
  final String location;
  final String chair;

  WeeklySchedule({
    required this.date,
    required this.session,
    required this.time,
    required this.content,
    required this.participants,
    required this.location,
    required this.chair,
  });

  factory WeeklySchedule.fromJson(Map<String, dynamic> json) {
    return WeeklySchedule(
      date: json['EventDate'] ?? '',
      session: json['Session'] ?? '',
      time: json['TimeValue'] ?? '',
      content: json['Content'] ?? '',
      participants: json['Participants'] ?? '',
      location: json['Location'] ?? '',
      chair: json['Chairperson'] ?? '',
    );
  }
}