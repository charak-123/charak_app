import 'package:flutter/material.dart';
import 'package:charak_core/charak_core.dart';

// Stub — fully implemented in Chunk 2 (Day 17)
class RequestsTab extends StatelessWidget {
  const RequestsTab({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Requests')),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_outlined, size: 48, color: CharakColors.border),
          const SizedBox(height: CharakSpacing.base),
          Text('No incoming requests', style: CharakText.body.copyWith(color: CharakColors.inkMuted)),
          const SizedBox(height: CharakSpacing.sm),
          Text('Requests will appear here once patients book with you.',
              style: CharakText.caption.copyWith(color: CharakColors.inkMuted),
              textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
