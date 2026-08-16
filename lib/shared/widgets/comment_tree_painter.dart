import 'package:material_ui/material_ui.dart';

class CommentTreeLevels {
  const CommentTreeLevels({
    required this.previous,
    required this.next,
  });

  final int previous;
  final int next;
}

class CommentTreePainter extends CustomPainter {
  final int nestingLevel;
  final int previousNestingLevel;
  final int nextNestingLevel;

  const CommentTreePainter({
    required this.nestingLevel,
    required this.previousNestingLevel,
    required this.nextNestingLevel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (nestingLevel <= 0 && nextNestingLevel <= 0) {
      return;
    }

    const indentWidth = 16.0;
    const lineWidth = 3.0;
    const bottomSpacing = 6.0;
    final paint = Paint()
      ..color = const Color(0xFF191818)
      ..strokeWidth = lineWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;
    final contentHeight =
        (size.height - bottomSpacing).clamp(0.0, size.height).toDouble();
    final currentX = nestingLevel * indentWidth - (indentWidth / 2);
    final topJoinY = -bottomSpacing;

    if (nextNestingLevel > nestingLevel) {
      final nextX =
          nextNestingLevel * indentWidth - (indentWidth / 2);
      canvas.drawLine(
        Offset(nextX, contentHeight),
        Offset(nextX, size.height),
        paint,
      );
    }

    for (int level = 1; level < nestingLevel; level++) {
      final x = level * indentWidth - (indentWidth / 2);
      final startY = previousNestingLevel >= level ? topJoinY : 0.0;
      final endY = nextNestingLevel >= level ? size.height : contentHeight;
      if (endY <= startY) {
        continue;
      }
      canvas.drawLine(
        Offset(x, startY),
        Offset(x, endY),
        paint,
      );
    }

    final currentEndY =
        nextNestingLevel >= nestingLevel ? size.height : contentHeight;
    if (currentEndY > topJoinY) {
      canvas.drawLine(
        Offset(currentX, topJoinY),
        Offset(currentX, currentEndY),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CommentTreePainter oldDelegate) {
    return oldDelegate.nestingLevel != nestingLevel ||
        oldDelegate.previousNestingLevel != previousNestingLevel ||
        oldDelegate.nextNestingLevel != nextNestingLevel;
  }
}
