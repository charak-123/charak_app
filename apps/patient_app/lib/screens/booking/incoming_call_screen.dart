import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';

/// A doctor is ringing about a booking: answer or decline, full screen, the
/// way a phone call looks. Reached from the ringing watcher (the app is open)
/// or a `call.incoming` push that arrived while the app was in use. A tap on
/// the notification itself goes straight into the call instead: that tap is
/// the answer.
///
/// Rings for [ringFor] from [rangAt], then closes on its own, since nobody is
/// on the other end any more. Declining tells the doctor, whose screen would
/// otherwise keep saying "Ringing…".
class IncomingCallScreen extends StatefulWidget {
  final String bookingId;
  final String? callId;
  final String? doctorName;
  final String? doctorPhotoUrl;
  final DateTime? rangAt;
  final Duration ringFor;

  const IncomingCallScreen({
    super.key,
    required this.bookingId,
    this.callId,
    this.doctorName,
    this.doctorPhotoUrl,
    this.rangAt,
    this.ringFor = const Duration(seconds: 60),
  });

  /// Built from the ringing watcher's answer, or a push's data (which has
  /// only the booking).
  factory IncomingCallScreen.fromJson(String bookingId, Map<String, dynamic>? j) => IncomingCallScreen(
        bookingId: bookingId,
        callId: j?['call_id'] as String?,
        doctorName: j?['doctor_name'] as String?,
        doctorPhotoUrl: j?['doctor_photo_url'] as String?,
        rangAt: DateTime.tryParse(j?['rang_at'] as String? ?? ''),
        ringFor: Duration(seconds: (j?['ring_seconds'] as num?)?.toInt() ?? 60),
      );

  /// The booking whose call is on screen, so the watcher and a push for the
  /// same ring don't stack a second one.
  static String? showingFor;

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: CharakMotion.live);
  Timer? _timeout;
  Timer? _buzz;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    IncomingCallScreen.showingFor = widget.bookingId;
    final rang = widget.rangAt ?? DateTime.now();
    final left = widget.ringFor - DateTime.now().difference(rang);
    _timeout = Timer(left.isNegative ? Duration.zero : left, () {
      if (mounted) context.pop();
    });
    // A buzz every couple of seconds, like a phone ringing on silent.
    HapticFeedback.heavyImpact();
    _buzz = Timer.periodic(const Duration(seconds: 2), (_) => HapticFeedback.heavyImpact());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (charakReduceMotion(context)) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    if (IncomingCallScreen.showingFor == widget.bookingId) IncomingCallScreen.showingFor = null;
    _timeout?.cancel();
    _buzz?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  void _stopRinging() {
    _timeout?.cancel();
    _buzz?.cancel();
    _pulse.stop();
  }

  void _accept() {
    _stopRinging();
    context.pushReplacement('/booking/${widget.bookingId}/call');
  }

  Future<void> _decline() async {
    _stopRinging();
    setState(() => _busy = true);
    try {
      var callId = widget.callId;
      // A push carries only the booking; look the call up to decline it.
      if (callId == null) {
        final res = await ApiClient.instance.get('/bookings/patient/ringing-call') as Map<String, dynamic>?;
        final call = res?['call'] as Map<String, dynamic>?;
        if (call?['booking_id'] == widget.bookingId) callId = call?['call_id'] as String?;
      }
      if (callId != null) {
        await ApiClient.instance.post('/bookings/${widget.bookingId}/clarification-call/$callId/decline', {});
      }
    } catch (_) {
      // Declining is a courtesy to the doctor; the call stops ringing here
      // either way, and the doctor can still mark it missed.
    }
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final name = CharakFormat.doctor(widget.doctorName ?? 'Your doctor');
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: CharakCallColors.field,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 40),
            child: Column(children: [
              Text('Incoming video call',
                  style: CharakText.label.copyWith(color: CharakCallColors.peerSub)),
              const SizedBox(height: 40),
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, child) {
                  final t = _pulse.value;
                  return Stack(alignment: Alignment.center, children: [
                    // One ring spreading out and fading, every 1.6s.
                    Container(
                      width: 128 + 56 * t,
                      height: 128 + 56 * t,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: CharakPalette.blue400.withValues(alpha: 0.28 * (1 - t)),
                      ),
                    ),
                    child!,
                  ]);
                },
                child: CharakAvatar(name: name, imageUrl: widget.doctorPhotoUrl, radius: 64, circle: true),
              ),
              const SizedBox(height: 28),
              Text(name,
                  textAlign: TextAlign.center,
                  style: CharakText.titleLarge.copyWith(color: CharakPalette.ink50)),
              const SizedBox(height: 8),
              Text('is calling about your booking request',
                  textAlign: TextAlign.center,
                  style: CharakText.body.copyWith(color: CharakCallColors.peerSub)),
              const Spacer(),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _Answer(
                  label: 'Decline',
                  icon: LucideIcons.phoneOff,
                  color: CharakColors.danger,
                  onTap: _busy ? null : _decline,
                ),
                _Answer(
                  label: 'Accept',
                  icon: LucideIcons.video,
                  color: CharakPalette.blue500,
                  onTap: _busy ? null : _accept,
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Answer extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _Answer({required this.label, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CharakPressable(
            onTap: onTap,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, size: 28, color: CharakPalette.ink50),
            ),
          ),
          const SizedBox(height: 10),
          Text(label, style: CharakText.label.copyWith(color: CharakPalette.ink50)),
        ]),
      );
}
