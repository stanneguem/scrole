import 'package:intl/intl.dart';

/// Modèle représentant un jour ouvert de l'événement.
class EventOpenDay {
  final DateTime date;
  final bool isOpen;

  const EventOpenDay({
    required this.date,
    this.isOpen = true,
  });

  String get dateString => DateFormat('yyyy-MM-dd').format(date);

  factory EventOpenDay.fromJson(Map<String, dynamic> json) {
    DateTime parsedDate;
    final dateStr = json['date']?.toString() ?? '';
    if (dateStr.contains('T')) {
      parsedDate = DateTime.parse(dateStr);
    } else if (dateStr.isNotEmpty) {
      final parts = dateStr.split('-');
      if (parts.length == 3) {
        parsedDate = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      } else {
        parsedDate = DateTime.parse(dateStr);
      }
    } else {
      parsedDate = DateTime.now();
    }

    return EventOpenDay(
      date: DateTime(parsedDate.year, parsedDate.month, parsedDate.day),
      isOpen: json['is_open'] != false,
    );
  }
}

/// Modèle représentant un jour planifié par l'utilisateur.
class EventPlannedDay {
  final DateTime date;

  const EventPlannedDay({required this.date});

  String get dateString => DateFormat('yyyy-MM-dd').format(date);

  factory EventPlannedDay.fromJson(Map<String, dynamic> json) {
    DateTime parsedDate;
    final dateStr = json['date']?.toString() ?? '';
    if (dateStr.contains('T')) {
      parsedDate = DateTime.parse(dateStr);
    } else if (dateStr.isNotEmpty) {
      final parts = dateStr.split('-');
      if (parts.length == 3) {
        parsedDate = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      } else {
        parsedDate = DateTime.parse(dateStr);
      }
    } else {
      parsedDate = DateTime.now();
    }

    return EventPlannedDay(
      date: DateTime(parsedDate.year, parsedDate.month, parsedDate.day),
    );
  }
}

/// Modèle représentant les statistiques de participation par jour pour le gestionnaire.
class EventDayAttendance {
  final DateTime date;
  final int plannedAttendees;

  const EventDayAttendance({
    required this.date,
    required this.plannedAttendees,
  });

  String get dateString => DateFormat('yyyy-MM-dd').format(date);

  factory EventDayAttendance.fromJson(Map<String, dynamic> json) {
    DateTime parsedDate;
    final dateStr = json['date']?.toString() ?? '';
    if (dateStr.contains('T')) {
      parsedDate = DateTime.parse(dateStr);
    } else if (dateStr.isNotEmpty) {
      final parts = dateStr.split('-');
      if (parts.length == 3) {
        parsedDate = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      } else {
        parsedDate = DateTime.parse(dateStr);
      }
    } else {
      parsedDate = DateTime.now();
    }

    return EventDayAttendance(
      date: DateTime(parsedDate.year, parsedDate.month, parsedDate.day),
      plannedAttendees: (json['planned_attendees'] as num?)?.toInt() ?? 0,
    );
  }
}
