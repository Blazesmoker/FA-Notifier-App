// lib/custom_drawer/drawer_user_controller.dart

import 'package:flutter/material.dart';
import 'home_drawer.dart';
import '../enums/drawer_index.dart';
import '../model/drawer_list.dart';
import '../model/user_profile.dart';
import '../app_theme.dart';
import '../model/notifications.dart';

class DrawerUserController extends StatefulWidget {
  const DrawerUserController({
    super.key,
    this.drawerWidth = 250,
    this.onDrawerCall,
    this.screenView,
    this.animatedIconData = AnimatedIcons.arrow_menu,
    this.menuView,
    this.drawerIsOpen,
    this.screenIndex,
    required this.onLogout,
    required this.userProfile,
    required this.onNoteCounterTap,
    required this.onNotesCountChanged,
    required this.onNotificationsUpdated,
    required this.onBadgeTap,
    this.enableSwipe = true,
  });

  final double drawerWidth;
  final Function(DrawerIndex)? onDrawerCall;
  final Widget? screenView;
  final Function(bool)? drawerIsOpen;
  final AnimatedIconData? animatedIconData;
  final Widget? menuView;
  final DrawerIndex? screenIndex;
  final Function onLogout;
  final UserProfile userProfile;
  final VoidCallback onNoteCounterTap;
  final Function(int) onNotesCountChanged;

  final Function(Notifications) onNotificationsUpdated;

  final Function(String) onBadgeTap;


  final bool enableSwipe;

  @override
  DrawerUserControllerState createState() => DrawerUserControllerState();
}

class DrawerUserControllerState extends State<DrawerUserController>
    with TickerProviderStateMixin {
  ScrollController? scrollController;
  AnimationController? iconAnimationController;
  AnimationController? animationController;

  double scrolloffset = 0.0;


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
    );
    iconAnimationController?.animateTo(
      1.0,
      duration: const Duration(milliseconds: 0),
      curve: Curves.fastOutSlowIn,
    );

    scrollController = ScrollController(initialScrollOffset: widget.drawerWidth);
    scrollController!.addListener(() {
      if (scrollController!.offset <= 0) {
        if (scrolloffset != 1.0) {
          setState(() {
            scrolloffset = 1.0;
            widget.drawerIsOpen?.call(true);
          });
        }
        iconAnimationController?.animateTo(
          0.0,
          duration: const Duration(milliseconds: 0),
          curve: Curves.fastOutSlowIn,
        );
      } else if (scrollController!.offset > 0 &&
          scrollController!.offset < widget.drawerWidth.floor()) {
        iconAnimationController?.animateTo(
          (scrollController!.offset * 100 / widget.drawerWidth) / 100,
          duration: const Duration(milliseconds: 0),
          curve: Curves.fastOutSlowIn,
        );
      } else {
        if (scrolloffset != 0.0) {
          setState(() {
            scrolloffset = 0.0;
            widget.drawerIsOpen?.call(false);
          });
        }
        iconAnimationController?.animateTo(
          1.0,
          duration: const Duration(milliseconds: 0),
          curve: Curves.fastOutSlowIn,
        );
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => getInitState());
  }

  Future<bool> getInitState() async {
    // Start with the drawer closed
    scrollController?.jumpTo(widget.drawerWidth);
    return true;
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
    var brightness = MediaQuery.of(context).platformBrightness;
    bool isLightMode = brightness == Brightness.light;

    return Scaffold(
      backgroundColor: isLightMode ? AppTheme.white : AppTheme.nearlyBlack,

      body: SingleChildScrollView(
        controller: scrollController,
        // Decide which scroll physics to use, based on _enableSwipe
        physics: _enableSwipe
            ? const PageScrollPhysics(parent: ClampingScrollPhysics())
            : const NeverScrollableScrollPhysics(),
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          height: MediaQuery.of(context).size.height,
          width: MediaQuery.of(context).size.width + widget.drawerWidth,
          child: Row(
            children: <Widget>[
              SizedBox(
                width: widget.drawerWidth,
                height: MediaQuery.of(context).size.height,
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
                        screenIndex: widget.screenIndex ?? DrawerIndex.HOME,
                        iconAnimationController: iconAnimationController,
                        callBackIndex: (DrawerIndex indexType) {

                          onDrawerClick();

                          widget.onDrawerCall?.call(indexType);
                        },
                        onLogout: widget.onLogout,
                        userProfile: widget.userProfile,
                        onNoteCounterTap: widget.onNoteCounterTap,
                        onNotesCountChanged: widget.onNotesCountChanged,

                        onNotificationsUpdated: widget.onNotificationsUpdated,
                        onBadgeTap: widget.onBadgeTap,
                      ),
                    );
                  },
                ),
              ),


              SizedBox(
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.white,
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: AppTheme.grey.withOpacity(0.55),
                        blurRadius: 24,
                      ),
                    ],
                  ),
                  child: Stack(
                    children: <Widget>[

                      IgnorePointer(
                        ignoring: scrolloffset == 1.0,
                        child: widget.screenView,
                      ),
                      // Tapping outside the drawer closes it
                      if (scrolloffset == 1.0)
                        InkWell(
                          onTap: onDrawerClick,
                        ),
                      // The top-left menu icon
                      if (widget.screenIndex != DrawerIndex.Notifications)
                        Padding(
                          padding: EdgeInsets.only(
                            top: MediaQuery.of(context).padding.top + 4,
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
    Key? key,
    required this.imageUrl,
    required this.fallbackAsset,
    this.radius = 24,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: imageUrl != null && imageUrl!.isNotEmpty
            ? Image.network(
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
