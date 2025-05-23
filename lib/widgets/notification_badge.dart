import 'package:flutter/material.dart';

class NotificationBadge extends StatelessWidget {
  final String count;
  final String label;

  const NotificationBadge({Key? key, required this.count, required this.label}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (count == '0') {
      return const SizedBox(); // Don't show anything if count is 0
    }

    return Container(

      constraints: const BoxConstraints(
        minWidth: 10,
        minHeight: 10,

        maxWidth: 50,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 11),
      decoration: BoxDecoration(
        color: Color(0xFFE09321),
        borderRadius: BorderRadius.circular(20),
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '$count$label',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
