import 'package:material_ui/material_ui.dart';

class NotesSelectionLayout extends StatelessWidget {
  const NotesSelectionLayout({
    super.key,
    required this.isSelectionMode,
    required this.rowBuilder,
  });

  final bool isSelectionMode;
  final Widget Function(bool selecting) rowBuilder;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ExcludeSemantics(
          child: IgnorePointer(
            child: Opacity(
              opacity: 0,
              child: rowBuilder(false),
            ),
          ),
        ),
        Positioned.fill(child: rowBuilder(isSelectionMode)),
      ],
    );
  }
}

class NotesSelectionContent extends StatelessWidget {
  const NotesSelectionContent({
    super.key,
    required this.selecting,
    required this.child,
  });

  final bool selecting;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!selecting && !constraints.hasBoundedHeight) return child;

        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: constraints.maxWidth,
            child: child,
          ),
        );
      },
    );
  }
}
