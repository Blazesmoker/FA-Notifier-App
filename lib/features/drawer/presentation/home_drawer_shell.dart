import 'package:material_ui/material_ui.dart';
import 'package:fanotifier/shared/widgets/fa_network_image.dart';
import 'package:fanotifier/features/drawer/presentation/home_drawer.dart';
import 'package:fanotifier/features/drawer/domain/drawer_index.dart';
import 'package:fanotifier/shared/fa/domain/user_profile.dart';
import 'package:fanotifier/shared/theme/app_theme.dart';
import 'package:fanotifier/shared/fa/domain/notifications.dart';

class HomeDrawerShell extends StatefulWidget {

  const HomeDrawerShell({
    super.key,
    this.drawerWidth = 250,
    this.onDrawerItemSelected,
    this.screenView,
    this.animatedIconData = AnimatedIcons.arrow_menu,
    this.menuView,
    this.onDrawerOpenChanged,
    this.selectedDrawerItem,
    required this.onLogout,
    required this.userProfile,
    required this.onNoteCounterTap,
    required this.onNotesCountChanged,
    required this.onNotificationsUpdated,
    required this.onBadgeTap,
    required this.onUserProfileChanged,
    this.isUserProfileLoading = false,
    this.enableSwipe = true,
  });

  final double drawerWidth;
  final Function(DrawerIndex)? onDrawerItemSelected;
  final Widget? screenView;
  final Function(bool)? onDrawerOpenChanged;
  final AnimatedIconData? animatedIconData;
  final Widget? menuView;
  final DrawerIndex? selectedDrawerItem;
  final Function onLogout;
  final UserProfile userProfile;
  final VoidCallback onNoteCounterTap;
  final Function(int) onNotesCountChanged;

  final Function(Notifications) onNotificationsUpdated;

  final Function(String) onBadgeTap;
  final VoidCallback onUserProfileChanged;

  final bool isUserProfileLoading;

  final bool enableSwipe;

  @override
  HomeDrawerShellState createState() => HomeDrawerShellState();
}

class HomeDrawerShellState extends State<HomeDrawerShell>
    with TickerProviderStateMixin {
  ScrollController? scrollController;
  AnimationController? iconAnimationController;
  AnimationController? animationController;

  bool isDrawerOpen = false;


  bool _initialDrawerPositionResolved = false;
  bool _initialDrawerPositionScheduled = false;

  bool _enableSwipe = true;

  @override
  void initState() {
    super.initState();


    _enableSwipe = widget.enableSwipe;

    animationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    iconAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 0),
      value: 1.0,
    );

    scrollController = ScrollController(
      initialScrollOffset: widget.drawerWidth,
      keepScrollOffset: false,
    );
    scrollController!.addListener(_handleDrawerScroll);

    _scheduleInitialDrawerPosition();
  }

  @override
  void didUpdateWidget(HomeDrawerShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.drawerWidth == widget.drawerWidth) return;

    final controller = scrollController;
    final wasClosed = !_initialDrawerPositionResolved ||
        controller == null ||
        !controller.hasClients ||
        controller.offset >= oldWidget.drawerWidth - 0.5;
    if (!wasClosed) return;

    _initialDrawerPositionResolved = false;
    _scheduleInitialDrawerPosition();
  }

  void _handleDrawerScroll() {
    final controller = scrollController;
    if (controller == null || !controller.hasClients) return;

    final position = controller.position;
    if (!position.hasContentDimensions || position.maxScrollExtent <= 0) return;

    final progress = ((controller.offset - position.minScrollExtent) /
            (position.maxScrollExtent - position.minScrollExtent))
        .clamp(0.0, 1.0)
        .toDouble();
    iconAnimationController?.value = progress;

    final nextIsDrawerOpen = controller.offset <= position.minScrollExtent;
    if (isDrawerOpen == nextIsDrawerOpen) return;

    setState(() {
      isDrawerOpen = nextIsDrawerOpen;
    });
    widget.onDrawerOpenChanged?.call(nextIsDrawerOpen);
  }

  void _scheduleInitialDrawerPosition() {
    if (_initialDrawerPositionResolved || _initialDrawerPositionScheduled) {
      return;
    }
    _initialDrawerPositionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialDrawerPositionScheduled = false;
      if (!mounted || _initialDrawerPositionResolved) return;

      final controller = scrollController;
      if (controller == null || !controller.hasClients) return;
      final position = controller.position;
      if (!position.hasContentDimensions || position.maxScrollExtent <= 0) {
        return;
      }

      _initialDrawerPositionResolved = true;
      controller.jumpTo(position.maxScrollExtent);
      _handleDrawerScroll();
    });
  }

  /// Sets the drawer's position based on the provided offset.
  void setDrawerPosition(double offset) {
    final clampedOffset = offset.clamp(0.0, widget.drawerWidth);
    scrollController?.jumpTo(clampedOffset);
  }

  /// Animates the drawer to the open position.
  void openDrawer() {
    scrollController?.animateTo(
      0.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.fastOutSlowIn,
    );
  }

  /// Animates the drawer to the closed position.
  void closeDrawer() {
    scrollController?.animateTo(
      widget.drawerWidth,
      duration: const Duration(milliseconds: 300),
      curve: Curves.fastOutSlowIn,
    );
  }

  /// Public method to enable/disable swiping from outside
  void setEnableSwipe(bool value) {
    setState(() {
      _enableSwipe = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final size = MediaQuery.sizeOf(context);
    final topPadding = MediaQuery.paddingOf(context).top;
    bool isLightMode = brightness == Brightness.light;

    return Scaffold(
      backgroundColor: isLightMode ? AppTheme.white : AppTheme.nearlyBlack,

      body: NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          _scheduleInitialDrawerPosition();
          return false;
        },
        child: SingleChildScrollView(
          controller: scrollController,
          // Decide which scroll physics to use, based on _enableSwipe
          physics: _enableSwipe
              ? const PageScrollPhysics(parent: ClampingScrollPhysics())
              : const NeverScrollableScrollPhysics(),
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            height: size.height,
            width: size.width + widget.drawerWidth,
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: widget.drawerWidth,
                  height: size.height,
                  child: AnimatedBuilder(
                    animation: iconAnimationController!,
                    builder: (BuildContext context, Widget? child) {
                      return Transform(
                        transform: Matrix4.translationValues(
                          scrollController!.offset,
                          0.0,
                          0.0,
                        ),
                        child: HomeDrawer(
                        selectedDrawerItem: widget.selectedDrawerItem ?? DrawerIndex.home,
                        iconAnimationController: iconAnimationController,
                        callBackIndex: (DrawerIndex indexType) {

                          onDrawerClick();

                          widget.onDrawerItemSelected?.call(indexType);
                        },
                        onLogout: widget.onLogout,
                        userProfile: widget.userProfile,
                        onNoteCounterTap: widget.onNoteCounterTap,
                        onNotesCountChanged: widget.onNotesCountChanged,

                        onNotificationsUpdated: widget.onNotificationsUpdated,
                        onBadgeTap: widget.onBadgeTap,
                        onUserProfileChanged: widget.onUserProfileChanged,
                        isUserProfileLoading: widget.isUserProfileLoading,
                        ),
                      );
                    },
                  ),
                ),


                SizedBox(
                width: size.width,
                height: size.height,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.white,
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: AppTheme.grey.withValues(alpha: 0.55),
                        blurRadius: 24,
                      ),
                    ],
                  ),
                  child: Stack(
                    children: <Widget>[

                      IgnorePointer(
                        ignoring: isDrawerOpen,
                        child: widget.screenView,
                      ),
                      // Tapping outside the drawer closes it
                      if (isDrawerOpen)
                        InkWell(
                          onTap: onDrawerClick,
                        ),
                      // The top-left menu icon
                      if (widget.selectedDrawerItem != DrawerIndex.notifications)
                        Padding(
                          padding: EdgeInsets.only(
                            top: topPadding + 4,
                            left: 8,
                          ),
                          child: SizedBox(
                            width: AppBar().preferredSize.height - 8,
                            height: AppBar().preferredSize.height - 8,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                  AppBar().preferredSize.height,
                                ),
                                child: Center(
                                  child: widget.menuView ??
                                      AnimatedIcon(
                                        color: isLightMode
                                            ? AppTheme.darkGrey
                                            : AppTheme.white,
                                        icon: widget.animatedIconData ??
                                            AnimatedIcons.arrow_menu,
                                        progress: iconAnimationController!,
                                      ),
                                ),
                                onTap: () {
                                  FocusScope.of(context).requestFocus(FocusNode());
                                  onDrawerClick();
                                },
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Toggle the drawer open/closed
  void onDrawerClick() {
    if (scrollController!.offset == 0.0) {

      closeDrawer();
    } else {

      openDrawer();
    }
  }
}

/// Custom widget to handle avatar images with fallback
class AvatarWidget extends StatelessWidget {
  final String? imageUrl;
  final String fallbackAsset;
  final double radius;

  const AvatarWidget({
    super.key,
    required this.imageUrl,
    required this.fallbackAsset,
    this.radius = 24,
  });

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: imageUrl != null && imageUrl!.isNotEmpty
            ? FaNetworkImage(
          imageUrl!,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Image.asset(
              fallbackAsset,
              fit: BoxFit.cover,
            );
          },
        )
            : Image.asset(
          fallbackAsset,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
