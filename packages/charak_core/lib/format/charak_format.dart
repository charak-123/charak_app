import 'package:intl/intl.dart';

/// One way to print the things every screen prints: doctor names, money,
/// initials and the consult channel. Screens never format these by hand, so
/// "Dr. Dr. Meera", "₹1100" and "Home Visit" vs "Home visit" can't creep back.
abstract final class CharakFormat {
  static final _honorific = RegExp(r'^(dr|mr|mrs|ms|prof)\.?\s+', caseSensitive: false);
  static final _inr = NumberFormat.decimalPattern('en_IN');

  /// A doctor's display name with exactly one "Dr." in front, whether or not
  /// the stored name already has it. [fallback] when the name is unknown.
  static String doctor(String? name, {String fallback = 'The doctor'}) {
    final bare = _bare(name);
    return bare.isEmpty ? fallback : 'Dr. $bare';
  }

  /// A person's name with any honorific removed.
  static String _bare(String? name) => (name ?? '').trim().replaceFirst(_honorific, '').trim();

  /// Up to two initials, ignoring honorifics: "Dr. Meera Kulkarni" → "MK".
  static String initials(String? name) {
    final parts = _bare(name).split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  /// Rupees with Indian digit grouping: 1100 → "₹1,100", 125000 → "₹1,25,000".
  /// Paise only when there are any.
  static String rupees(num? amount) {
    if (amount == null) return '—';
    final whole = amount == amount.roundToDouble();
    final text = whole
        ? _inr.format(amount.round())
        : NumberFormat('#,##,##0.00', 'en_IN').format(amount);
    return '₹$text';
  }

  /// An Indian mobile in the way people read it: "+919820011223" →
  /// "+91 98200 11223". Other numbers are returned as stored.
  static String phone(String? e164) {
    final p = (e164 ?? '').replaceAll(' ', '');
    final m = RegExp(r'^\+91(\d{5})(\d{5})$').firstMatch(p);
    return m == null ? p : '+91 ${m.group(1)} ${m.group(2)}';
  }

  /// "Today, 6:00 PM", "Tomorrow, 10:00 AM", "Thu 8 Oct, 5:30 PM": how the
  /// boards write an appointment. Local time.
  static String dayTime(DateTime when, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final d = when.toLocal();
    final days = DateTime(d.year, d.month, d.day).difference(DateTime(n.year, n.month, n.day)).inDays;
    final day = switch (days) {
      0 => 'Today',
      1 => 'Tomorrow',
      -1 => 'Yesterday',
      _ => DateFormat('EEE d MMM').format(d),
    };
    return '$day, ${DateFormat('h:mm a').format(d)}';
  }

  /// "Online consult" / "Home visit" — sentence case, the way the design
  /// system writes them.
  static String channel(String? channel) => switch (channel) {
        'home_visit' => 'Home visit',
        'online_consult' || 'online' => 'Online consult',
        _ => 'Consult',
      };
}
