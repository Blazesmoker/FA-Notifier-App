import 'package:auto_size_text/auto_size_text.dart';
import 'package:material_ui/material_ui.dart';

class SubmissionManagementShrinkableText extends StatelessWidget {
  const SubmissionManagementShrinkableText(
    this.text, {
    super.key,
    this.style,
    this.maxLines = 1,
    this.minFontSize = 8,
    this.textAlign,
  });

  final String text;
  final TextStyle? style;
  final int maxLines;
  final double minFontSize;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return AutoSizeText(
      text,
      style: style,
      maxLines: maxLines,
      minFontSize: minFontSize,
      stepGranularity: 0.5,
      textAlign: textAlign,
      overflow: TextOverflow.clip,
    );
  }
}
