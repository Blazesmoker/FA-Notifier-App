import 'package:material_ui/material_ui.dart';

class NotificationTabScrollView extends StatelessWidget {
  const NotificationTabScrollView({
    super.key,
    required this.storageKey,
    required this.scrollController,
    required this.actions,
    required this.slivers,
  });

  final PageStorageKey<String> storageKey;
  final ScrollController scrollController;
  final Widget actions;
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      key: storageKey,
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFloatingHeader(
          animationStyle: MediaQuery.disableAnimationsOf(context)
              ? AnimationStyle.noAnimation
              : const AnimationStyle(
                  duration: Duration(milliseconds: 220),
                  reverseDuration: Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  reverseCurve: Curves.easeOutCubic,
                ),
          child: ColoredBox(
            color: Colors.black,
            isAntiAlias: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                actions,
                const Divider(
                  height: 4,
                  thickness: 4,
                  color: Color(0xFF111111),
                ),
              ],
            ),
          ),
        ),
        ...slivers,
        SliverToBoxAdapter(
          child: SizedBox(height: MediaQuery.paddingOf(context).bottom),
        ),
      ],
    );
  }
}
