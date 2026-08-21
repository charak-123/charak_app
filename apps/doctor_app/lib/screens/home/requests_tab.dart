import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:charak_core/charak_core.dart';
import 'package:intl/intl.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _incomingProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await ApiClient.instance.get('/bookings/doctor/incoming');
  return List<Map<String, dynamic>>.from(res as List);
});

// ── RequestsTab ───────────────────────────────────────────────────────────────

class RequestsTab extends ConsumerStatefulWidget {
  const RequestsTab({super.key});
  @override
  ConsumerState<RequestsTab> createState() => _RequestsTabState();
}

class _RequestsTabState extends ConsumerState<RequestsTab> {
  StreamSubscription? _realtimeSub;
  final Set<String> _seen = {};

  @override
  void initState() {
    super.initState();
    _subscribeRealtime();
  }

  void _subscribeRealtime() {
    final doctorId = ref.read(authProvider).user?['id'];
    if (doctorId == null) return;

    _realtimeSub = Supabase.instance.client
        .from('bookings')
        .stream(primaryKey: ['id'])
        .eq('doctor_id', doctorId)
        .listen((rows) {
      final newRequests = rows.where(
        (r) => r['status'] == 'requested' && !_seen.contains(r['id'] as String),
      );
      if (newRequests.isNotEmpty && mounted) {
        for (final r in newRequests) {
          _seen.add(r['id'] as String);
        }
        ref.invalidate(_incomingProvider);
      }
    });
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final incoming = ref.watch(_incomingProvider);
    return Scaffold(
      backgroundColor: CharakColors.bgSubtle,
      appBar: AppBar(
        title: const Text('New Requests'),
        backgroundColor: CharakColors.bg,
        foregroundColor: CharakColors.ink,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_incomingProvider),
          ),
        ],
      ),
      body: incoming.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, color: CharakColors.danger, size: 40),
            const SizedBox(height: 8),
            Text('Failed to load requests', style: CharakText.body.copyWith(color: CharakColors.inkMuted)),
            TextButton(onPressed: () => ref.invalidate(_incomingProvider), child: const Text('Retry')),
          ]),
        ),
        data: (bookings) => bookings.isEmpty
            ? const _EmptyState()
            : ListView.separated(
                padding: const EdgeInsets.all(CharakSpacing.base),
                itemCount: bookings.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) => _RequestCard(booking: bookings[i]),
              ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.inbox_outlined, size: 64, color: CharakColors.border),
      const SizedBox(height: 16),
      Text('No new requests', style: CharakText.h2.copyWith(color: CharakColors.inkMuted)),
      const SizedBox(height: 4),
      Text('New patient requests will appear here',
          style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
    ]),
  );
}

class _RequestCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  const _RequestCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    final patient = booking['users'] as Map<String, dynamic>?;
    final name    = patient?['name'] as String? ?? 'Patient';
    final channel = booking['channel'] as String? ?? '';
    final start   = booking['scheduled_start'] as String? ?? '';
    final dt      = start.isNotEmpty ? DateTime.tryParse(start)?.toLocal() : null;
    final dateStr = dt != null ? DateFormat('EEE d MMM, h:mm a').format(dt) : '—';

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: CharakDurations.newRequest,
      curve: Curves.easeOut,
      builder: (ctx, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 16 * (1 - v)), child: child),
      ),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(CharakRadius.card),
          side: const BorderSide(color: CharakColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.all(CharakRadius.card),
          onTap: () => context.push('/request/${booking['id']}'),
          child: Padding(
            padding: const EdgeInsets.all(CharakSpacing.base),
            child: Row(children: [
              _ChannelIcon(channel: channel),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: CharakText.bodyMed),
                const SizedBox(height: 2),
                Text(dateStr, style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3CD),
                  borderRadius: BorderRadius.all(CharakRadius.pill),
                ),
                child: Text('NEW', style: CharakText.micro.copyWith(color: CharakColors.warning)),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: CharakColors.inkMuted),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ChannelIcon extends StatelessWidget {
  final String channel;
  const _ChannelIcon({required this.channel});
  @override
  Widget build(BuildContext context) {
    final isHome = channel == 'home_visit';
    return Container(
      width: 44, height: 44,
      decoration: BoxDecoration(
        color: isHome ? const Color(0xFFEAF7F1) : CharakColors.primarySoft,
        borderRadius: BorderRadius.all(CharakRadius.card),
      ),
      child: Icon(
        isHome ? Icons.home_outlined : Icons.videocam_outlined,
        color: isHome ? CharakColors.success : CharakColors.primary,
        size: 22,
      ),
    );
  }
}
