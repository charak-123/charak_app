import 'package:charak_core/charak_core.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the phone's calendar (Google Calendar, or the browser) with the
/// booking filled in, for the patient to save. No calendar permission needed:
/// the event is created by the calendar app, not by us.
Future<bool> addBookingToCalendar(Map<String, dynamic> booking) async {
  final start = DateTime.tryParse(booking['scheduled_start'] as String? ?? '')?.toUtc();
  if (start == null) return false;
  final end = start.add(const Duration(minutes: 30));
  String stamp(DateTime d) =>
      '${d.toIso8601String().replaceAll(RegExp(r'[-:]'), '').split('.').first}Z';
  final doctor = CharakFormat.doctor((booking['doctors'] as Map?)?['name'] as String?);
  final channel = booking['channel'] as String?;
  final uri = Uri.https('calendar.google.com', '/calendar/render', {
    'action': 'TEMPLATE',
    'text': '${CharakFormat.channel(channel)} with $doctor',
    'dates': '${stamp(start)}/${stamp(end)}',
    'details': channel == 'home_visit'
        ? 'CHARAK home visit. The doctor comes to the address on your booking.'
        : 'CHARAK online consult. Join from the booking in the CHARAK app.',
    if (booking['patient_address'] is String) 'location': booking['patient_address'] as String,
  });
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
