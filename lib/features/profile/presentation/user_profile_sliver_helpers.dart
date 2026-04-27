import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

class FixedSliverPersistentHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  FixedSliverPersistentHeaderDelegate({
    required this.child,
    required this.height,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(covariant FixedSliverPersistentHeaderDelegate oldDelegate) {
    return oldDelegate.child != child || oldDelegate.height != height;
  }
}

class NavigationSliderSliverDelegate extends SliverPersistentHeaderDelegate {
  final double minHeight;
  final double maxHeight;
  final Widget child;

  NavigationSliderSliverDelegate({
    required this.minHeight,
    required this.maxHeight,
    required this.child,
  });

  @override
  double get minExtent => minHeight;

  @override
  double get maxExtent => max(maxHeight, minHeight);

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(NavigationSliderSliverDelegate oldDelegate) {
    return false;
  }
}

class CollapsibleSliverPersistentHeader extends SliverPersistentHeaderDelegate {
  final double minHeight;
  final double maxHeight;
  final Widget child;

  CollapsibleSliverPersistentHeader({
    required this.minHeight,
    required this.maxHeight,
    required this.child,
  });

  @override
  double get minExtent => minHeight;

  @override
  double get maxExtent => max(maxHeight, minHeight);

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    // Calculate the current height based on shrinkOffset
    double currentHeight = maxExtent - shrinkOffset;
    if (currentHeight < minExtent) {
      currentHeight = minExtent;
    }

    // Calculate opacity based on shrinkOffset
    double opacity = (currentHeight - minExtent) / (maxExtent - minExtent);
    if (opacity < 0.0) opacity = 0.0;
    if (opacity > 1.0) opacity = 1.0;

    return Opacity(
      opacity: opacity,
      child: child,
    );
  }

  @override
  bool shouldRebuild(CollapsibleSliverPersistentHeader oldDelegate) {
    return maxHeight != oldDelegate.maxHeight ||
        minHeight != oldDelegate.minHeight ||
        child != oldDelegate.child;
  }
}

/// A custom navigation slider widget to replace the TabBar.
class NavigationSlider<T> extends StatefulWidget {
  final List<T> sections;
  final TabController tabController;
  final String Function(T) getTabTitle;
  final IconData Function(T) getIconForSection;
  final void Function(int index, bool isAlreadySelected)? onTabTapped;

  const NavigationSlider({
    Key? key,
    required this.sections,
    required this.tabController,
    required this.getTabTitle,
    required this.getIconForSection,
    this.onTabTapped,
  }) : super(key: key);

  @override
  _NavigationSliderState<T> createState() => _NavigationSliderState<T>();
}

class _NavigationSliderState<T> extends State<NavigationSlider<T>> {
  int _selectedIndex = 0;
  final ScrollController _listScrollController = ScrollController();

  void _scrollToCenter(int index) {
    final itemWidth = 106.0;
    final screenWidth = MediaQuery.of(context).size.width;
    final targetScrollOffset = (itemWidth * index) - (screenWidth / 2) + (itemWidth / 2);

    _listScrollController.animateTo(
      targetScrollOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  void initState() {
    super.initState();

    _selectedIndex = widget.tabController.index;
    widget.tabController.addListener(_onTabChanged);
    widget.tabController.animation?.addListener(_onAnimationChanged);
  }

  @override
  void dispose() {
    widget.tabController.removeListener(_onTabChanged);
    widget.tabController.animation?.removeListener(_onAnimationChanged);
    super.dispose();
  }

  void _onTabChanged() {
    if (widget.tabController.indexIsChanging) {
      setState(() {
        _selectedIndex = widget.tabController.index;
      });
      _scrollToCenter(_selectedIndex);
    }
  }

  void _onAnimationChanged() {
    if (widget.tabController.animation == null) return;
    int newIndex = widget.tabController.animation!.value.round();
    if (newIndex != _selectedIndex) {
      setState(() {
        _selectedIndex = newIndex;
      });
      _scrollToCenter(_selectedIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(
          height: 4.0,
          color: Color(0xFF111111),
          thickness: 4.0,
        ),
        Container(
          color: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: SizedBox(
            height: 54,
            child: ListView(
              controller: _listScrollController,
              scrollDirection: Axis.horizontal,
              physics: Platform.isIOS
                  ? const ClampingScrollPhysics() // more native for iOS
                  : const ClampingScrollPhysics(), // default for Android
              children: widget.sections.asMap().entries.map((entry) {
                final index = entry.key;
                final section = entry.value;
                final isSelected = _selectedIndex == index;

                return GestureDetector(
                  onTap: () {
                    bool isAlreadySelected = index == _selectedIndex;
                    if (isAlreadySelected) {
                      widget.onTabTapped?.call(index, true);
                    } else {
                      widget.tabController.animateTo(index);
                    }
                  },
                  child: SizedBox(
                    width: 106,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 1.4, vertical: 6.0),
                      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFE09321) : const Color(0xFF1F1F1F),
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            widget.getIconForSection(section),
                            color: Colors.white,
                            size: 20.0,
                          ),
                          const SizedBox(width: 4.0),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                widget.getTabTitle(section),
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const Divider(
          height: 4.0,
          color: Color(0xFF111111),
          thickness: 4.0,
        ),
      ],
    );
  }
}


