import 'package:flutter/material.dart';

/// 서버 시간 문자열("HH:mm:ss" 또는 "HH:mm") → "오전/오후 h:mm". 초는 절대
/// 표시하지 않는다. [raw]가 null이면 null(종일 표현).
String? formatServerTimeKorean(String? raw) {
  if (raw == null) return null;
  final parts = raw.split(':');
  final hour = int.tryParse(parts[0]);
  if (hour == null) return null;
  final minute = parts.length > 1 ? parts[1] : '00';
  return _formatKorean(hour, minute);
}

/// [TimeOfDay] → "오전/오후 h:mm".
String formatTimeOfDayKorean(TimeOfDay time) {
  return _formatKorean(time.hour, time.minute.toString().padLeft(2, '0'));
}

String _formatKorean(int hour, String minute) {
  final period = hour < 12 ? '오전' : '오후';
  final hour12 = hour % 12 == 0 ? 12 : hour % 12;
  return '$period $hour12:$minute';
}
