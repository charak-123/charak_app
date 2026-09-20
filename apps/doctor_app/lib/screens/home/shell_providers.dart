import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which HomeShell tab is showing. Screens outside the shell (e.g. Profile's
/// "Slot blocking" row) set this before navigating to `/home` so the shell
/// opens on the right tab instead of wherever it was left.
final doctorTabIndexProvider = StateProvider<int>((ref) => 0);
