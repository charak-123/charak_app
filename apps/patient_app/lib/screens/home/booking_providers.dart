import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:charak_core/charak_core.dart';

/// All of the current patient's bookings — shared by the Bookings and
/// History tabs so both stay in sync after a refresh.
final patientBookingsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await ApiClient.instance.get('/bookings/patient/list');
  return (res as List).cast<Map<String, dynamic>>();
});

/// Which HomeShell tab is showing. Screens outside the shell (e.g. an empty
/// state's "Browse doctors" button) set this before navigating to `/home` so
/// the shell opens on the right tab instead of wherever it was left.
final homeTabIndexProvider = StateProvider<int>((ref) => 0);
