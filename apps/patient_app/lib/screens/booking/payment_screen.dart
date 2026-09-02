import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:charak_core/charak_core.dart';
import '../shared/charak_button.dart';

class PaymentScreen extends ConsumerStatefulWidget {
  final String bookingId;
  const PaymentScreen({super.key, required this.bookingId});
  @override
  ConsumerState<PaymentScreen> createState() => _State();
}

class _State extends ConsumerState<PaymentScreen> {
  bool _loading = false;
  Map<String, dynamic>? _order;

  @override
  void initState() {
    super.initState();
    _createOrder();
  }

  Future<void> _createOrder() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.instance.post(
          '/payments/${widget.bookingId}/order', {});
      setState(() => _order = res as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: CharakColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pay() async {
    if (_order == null) return;
    setState(() => _loading = true);
    try {
      final key = _order!['razorpay_key'] as String? ?? '';

      if (key.startsWith('stub')) {
        // Dev mode: stub-complete the payment directly
        await ApiClient.instance.post(
            '/payments/${widget.bookingId}/stub-complete', {});
        if (mounted) context.go('/booking/${widget.bookingId}/confirmed');
        return;
      }

      // Production: open Razorpay checkout
      // razorpay_flutter SDK opens the checkout sheet here
      // razorpay.open({
      //   'key': key,
      //   'amount': _order!['amount'],
      //   'order_id': _order!['razorpay_order_id'],
      //   'name': 'Charak',
      //   'description': 'Consultation fee',
      // });
      // Handle payment success/failure via razorpay callbacks
      // On success: context.go('/booking/${widget.bookingId}/confirmed')

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add Razorpay key to enable live payments')),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: CharakColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = _order != null ? (_order!['amount'] as int) / 100 : 0.0;
    return Scaffold(
      backgroundColor: CharakColors.bgSubtle,
      appBar: AppBar(
        title: const Text('Payment'),
        backgroundColor: CharakColors.bg,
        foregroundColor: CharakColors.ink,
        elevation: 0,
      ),
      body: _loading && _order == null
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Expanded(child: Padding(
                padding: const EdgeInsets.all(CharakSpacing.lg),
                child: Column(children: [
                  const SizedBox(height: 32),
                  const Icon(Icons.lock_outline, color: CharakColors.primary, size: 48),
                  const SizedBox(height: 16),
                  Text('Secure Payment', style: CharakText.h1),
                  const SizedBox(height: 8),
                  Text('Consultation Fee',
                      style: CharakText.caption.copyWith(color: CharakColors.inkMuted)),
                  const SizedBox(height: 4),
                  Text('₹${amount.toStringAsFixed(0)}',
                      style: CharakText.display.copyWith(color: CharakColors.primary)),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF7F1),
                      borderRadius: BorderRadius.all(CharakRadius.card),
                    ),
                    child: Row(children: [
                      const Icon(Icons.info_outline, color: CharakColors.success, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Payment is processed securely via Razorpay. '
                          'The doctor will be confirmed once payment is received.',
                          style: CharakText.micro.copyWith(color: CharakColors.success),
                        ),
                      ),
                    ]),
                  ),
                ]),
              )),
              Padding(
                padding: const EdgeInsets.fromLTRB(CharakSpacing.base, 0, CharakSpacing.base, 24),
                child: CharakButton(
                  label: _order != null && (_order!['razorpay_key'] as String).startsWith('stub')
                      ? 'Confirm Payment (Dev Stub)'
                      : 'Pay ₹${amount.toStringAsFixed(0)}',
                  isLoading: _loading,
                  onPressed: _order != null ? _pay : null,
                ),
              ),
            ]),
    );
  }
}
