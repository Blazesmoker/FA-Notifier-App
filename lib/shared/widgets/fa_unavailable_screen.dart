import 'dart:async';

import 'package:flutter/material.dart';

import 'package:FANotifier/shared/fa/fa_request_coordinator.dart';

class FaUnavailableScreen extends StatefulWidget {
  const FaUnavailableScreen({
    super.key,
    required this.message,
    this.onRefresh,
    this.title = 'Fur Affinity is temporarily unavailable',
  });

  final String message;
  final Future<void> Function()? onRefresh;
  final String title;

  @override
  State<FaUnavailableScreen> createState() => _FaUnavailableScreenState();
}

class _FaUnavailableScreenState extends State<FaUnavailableScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = FaRequestCoordinator.instance.status.value;
    final remaining = snapshot.remaining;
    final seconds = remaining.inSeconds + (remaining.inMilliseconds % 1000 > 0 ? 1 : 0);
    final canRefresh = widget.onRefresh != null && seconds <= 0;

    return Container(
      color: Colors.black,
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off,
                color: Color(0xFFE09321),
                size: 48,
              ),
              const SizedBox(height: 18),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: canRefresh ? widget.onRefresh : null,
                icon: const Icon(Icons.refresh),
                label: Text(seconds > 0 ? 'Refresh in ${seconds}s' : 'Refresh'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE09321),
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: Colors.grey.shade800,
                  disabledForegroundColor: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
