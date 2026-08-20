import 'package:flutter/material.dart';
import 'package:charak_core/charak_core.dart';

// Stub — fully implemented in Chunk 2 (Day 25)
class EarningsTab extends StatelessWidget {
  const EarningsTab({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Earnings')),
    body: Center(
      child: Text('Earnings will appear here after completed visits.',
          style: CharakText.body.copyWith(color: CharakColors.inkMuted),
          textAlign: TextAlign.center),
    ),
  );
}
