import 'dart:async';

import 'package:flutter/material.dart';

class FaVerificationRequiredView extends StatelessWidget {
  const FaVerificationRequiredView({
    super.key,
    required this.title,
    required this.onRetry,
    required this.isBusy,
  });

  final String title;
  final Future<void> Function() onRetry;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Fur Affinity requires verification before this page can load.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: isBusy ? null : () => unawaited(onRetry()),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
