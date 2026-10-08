import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import 'package:intl/intl.dart';

import '../../push_routes.dart';

final notificationsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await ApiClient.instance.get('/notifications/');
  return List<Map<String, dynamic>>.from(res as List? ?? const []);
});

/// Unread count for the dot on the home bell.
final unreadNotificationsProvider = FutureProvider.autoDispose<int>((ref) async {
  final res = await ApiClient.instance.get('/notifications/unread-count') as Map<String, dynamic>;
  return (res['count'] as num?)?.toInt() ?? 0;
});

/// Everything the app has told the patient: booking decisions, payments,
/// visit updates. Tapping one opens the booking it is about, the same place
/// the push notification would have taken them.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, Map<String, dynamic> n) async {
    final id = n['id'] as String?;
    if (id != null && n['read_at'] == null) {
      // Best effort: a failed mark-read must not block opening the booking.
      try {
        await ApiClient.instance.patch('/notifications/$id/read', {});
      } on ApiException catch (_) {}
      ref.invalidate(notificationsProvider);
      ref.invalidate(unreadNotificationsProvider);
    }
    final route = patientPushRoute(CharakPushMessage(
      event: n['event'] as String? ?? '',
      bookingId: n['booking_id'] as String?,
    ));
    if (route != null && context.mounted) context.push(route);
  }

  Future<void> _readAll(WidgetRef ref) async {
    try {
      await ApiClient.instance.patch('/notifications/read-all', {});
    } on ApiException catch (_) {}
    ref.invalidate(notificationsProvider);
    ref.invalidate(unreadNotificationsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsProvider);
    final hasUnread = async.valueOrNull?.any((n) => n['read_at'] == null) ?? false;
    return CharakScreen(
      title: 'Notifications',
      actions: [
        if (hasUnread)
          CharakGhostButton(label: 'Mark all read', onPressed: () => _readAll(ref)),
      ],
      body: async.when(
        loading: () => const SingleChildScrollView(child: CharakSkeletonList()),
        error: (e, _) => CharakErrorState(error: e, onRetry: () => ref.invalidate(notificationsProvider)),
        data: (items) => items.isEmpty
            ? const Center(
                child: CharakEmptyState(
                  icon: LucideIcons.bell,
                  title: 'Nothing yet',
                  message: "When a doctor replies or a visit is coming up, you'll see it here.",
                ),
              )
            : RefreshIndicator(
                onRefresh: () => ref.refresh(notificationsProvider.future),
                color: CharakColors.primary,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(CharakSpacing.gutter, 4, CharakSpacing.gutter, 32),
                  children: [
                    CharakGroupedList(children: [
                      for (var i = 0; i < items.length; i++)
                        _NotificationRow(
                          n: items[i],
                          last: i == items.length - 1,
                          onTap: () => _open(context, ref, items[i]),
                        ),
                    ]),
                  ],
                ),
              ),
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  final Map<String, dynamic> n;
  final bool last;
  final VoidCallback onTap;
  const _NotificationRow({required this.n, required this.last, required this.onTap});

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    if (d.inDays < 7) return '${d.inDays} d ago';
    return DateFormat('d MMM').format(t);
  }

  @override
  Widget build(BuildContext context) {
    final unread = n['read_at'] == null;
    final at = DateTime.tryParse(n['created_at'] as String? ?? '')?.toLocal();
    return CharakListRow(
      title: n['title'] as String? ?? 'Update',
      subtitle: [
        if ((n['body'] as String?)?.isNotEmpty == true) n['body'] as String,
        if (at != null) _ago(at),
      ].join(' · '),
      leading: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: unread ? CharakColors.primary : CharakColors.border,
        ),
      ),
      last: last,
      onTap: onTap,
    );
  }
}
