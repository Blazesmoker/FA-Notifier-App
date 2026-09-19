import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/submissions/presentation/widgets/submission_folder_management_styles.dart';

class RoundedGroupSection extends StatefulWidget {
  const RoundedGroupSection({
    super.key,
    required this.header,
    required this.nested,
  });

  final Widget header;
  final Widget nested;

  @override
  State<RoundedGroupSection> createState() => _RoundedGroupSectionState();
}

class _RoundedGroupSectionState extends State<RoundedGroupSection> {
  final GlobalKey _headerKey = GlobalKey();
  double _headerHeight = 0;

  void _measureHeader() {
    final renderObject =
        _headerKey.currentContext?.findRenderObject() as RenderBox?;
    if (!mounted || renderObject == null || !renderObject.hasSize) return;
    final height = renderObject.size.height;
    if ((_headerHeight - height).abs() < 0.5) return;
    setState(() => _headerHeight = height);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureHeader());
    return LayoutBuilder(
      builder: (context, constraints) {
        final nestedIndent = (constraints.maxWidth * 0.075)
            .clamp(16.0, 24.0)
            .toDouble();
        return CustomPaint(
          painter: _RoundedGroupSectionPainter(
            headerHeight: _headerHeight,
            nestedIndent: nestedIndent,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                key: _headerKey,
                padding: const EdgeInsets.all(16),
                child: widget.header,
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  nestedIndent + 16,
                  16,
                  16,
                  16,
                ),
                child: widget.nested,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RoundedGroupSectionPainter extends CustomPainter {
  const _RoundedGroupSectionPainter({
    required this.headerHeight,
    required this.nestedIndent,
  });

  final double headerHeight;
  final double nestedIndent;

  @override
  void paint(Canvas canvas, Size size) {
    const borderWidth = 1.0;
    const cornerRadius = 16.0;
    const notchRadius = 8.0;
    final bounds = Rect.fromLTWH(
      borderWidth / 2,
      borderWidth / 2,
      size.width - borderWidth,
      size.height - borderWidth,
    );
    final hasMeasuredSplit = headerHeight > cornerRadius + notchRadius &&
        headerHeight < size.height - cornerRadius - notchRadius;
    final path = hasMeasuredSplit
        ? _buildIndentedPath(
            bounds,
            headerHeight,
            nestedIndent,
            cornerRadius,
            notchRadius,
          )
        : (Path()
          ..addRRect(
            RRect.fromRectAndRadius(
              bounds,
              const Radius.circular(cornerRadius),
            ),
          ));
    canvas.drawPath(
      path,
      Paint()
        ..color = managementCard
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF303030)
        ..strokeWidth = borderWidth
        ..style = PaintingStyle.stroke,
    );
    if (!hasMeasuredSplit) return;
    final lineStart = headerHeight + notchRadius + 4;
    final lineEnd = size.height - cornerRadius;
    if (lineEnd <= lineStart) return;
    canvas.drawLine(
      Offset(nestedIndent / 2, lineStart),
      Offset(nestedIndent / 2, lineEnd),
      Paint()
        ..color = const Color(0xFF191818)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.butt,
    );
  }

  Path _buildIndentedPath(
    Rect bounds,
    double splitY,
    double indent,
    double radius,
    double stepRadius,
  ) {
    final left = bounds.left;
    final top = bounds.top;
    final right = bounds.right;
    final bottom = bounds.bottom;
    final nestedLeft = left + indent;
    return Path()
      ..moveTo(left + radius, top)
      ..lineTo(right - radius, top)
      ..quadraticBezierTo(right, top, right, top + radius)
      ..lineTo(right, bottom - radius)
      ..quadraticBezierTo(right, bottom, right - radius, bottom)
      ..lineTo(nestedLeft + radius, bottom)
      ..quadraticBezierTo(
        nestedLeft,
        bottom,
        nestedLeft,
        bottom - radius,
      )
      ..lineTo(nestedLeft, splitY + stepRadius)
      ..quadraticBezierTo(
        nestedLeft,
        splitY,
        nestedLeft - stepRadius,
        splitY,
      )
      ..lineTo(left + stepRadius, splitY)
      ..quadraticBezierTo(left, splitY, left, splitY - stepRadius)
      ..lineTo(left, top + radius)
      ..quadraticBezierTo(left, top, left + radius, top)
      ..close();
  }

  @override
  bool shouldRepaint(covariant _RoundedGroupSectionPainter oldDelegate) {
    return oldDelegate.headerHeight != headerHeight ||
        oldDelegate.nestedIndent != nestedIndent;
  }
}
