import 'package:material_ui/material_ui.dart';

class HomeDrawerModeSwitch extends StatefulWidget {
  const HomeDrawerModeSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final Future<void> Function(bool) onChanged;

  @override
  State<HomeDrawerModeSwitch> createState() => _HomeDrawerModeSwitchState();
}

class _HomeDrawerModeSwitchState extends State<HomeDrawerModeSwitch>
    with SingleTickerProviderStateMixin {
  static const double _thumbTravel = 42;
  late final AnimationController _progress;
  bool _pending = false;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: widget.value ? 1 : 0,
    );
  }

  @override
  void didUpdateWidget(HomeDrawerModeSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _dragging = false;
      _settle(widget.value);
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  void _settle(bool value) {
    _progress.animateTo(
      value ? 1 : 0,
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _requestChange(bool value) async {
    if (_pending) return;
    _settle(value);
    if (value == widget.value) return;
    setState(() {
      _pending = true;
    });
    try {
      await widget.onChanged(value);
    } finally {
      if (mounted) {
        setState(() {
          _pending = false;
        });
        _settle(widget.value);
      }
    }
  }

  void _startDrag(DragStartDetails details) {
    if (_pending) return;
    _dragging = true;
    _progress.stop();
  }

  void _updateDrag(DragUpdateDetails details) {
    if (!_dragging || _pending) return;
    _progress.value = (_progress.value + details.delta.dx / _thumbTravel)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  void _endDrag(DragEndDetails details) {
    if (!_dragging || _pending) return;
    _dragging = false;
    final velocity = details.primaryVelocity ?? 0;
    final target = velocity.abs() >= 300
        ? velocity > 0
        : _progress.value == 0.5
            ? widget.value
            : _progress.value > 0.5;
    _requestChange(target);
  }

  void _cancelDrag() {
    if (!_dragging) return;
    _dragging = false;
    _settle(widget.value);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'NSFW mode',
      toggled: widget.value,
      enabled: !_pending,
      onTap: _pending ? null : () => _requestChange(!widget.value),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: () => _requestChange(!widget.value),
        onHorizontalDragStart: _startDrag,
        onHorizontalDragUpdate: _updateDrag,
        onHorizontalDragEnd: _endDrag,
        onHorizontalDragCancel: _cancelDrag,
        child: AnimatedBuilder(
          animation: _progress,
          builder: (context, child) {
            final progress = _progress.value;
            return Container(
              width: 68,
              height: 30,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: Color.lerp(
                  const Color(0xFF111111),
                  const Color(0xFFE09321),
                  progress,
                ),
              ),
              child: Stack(
                children: [
                  Opacity(
                    opacity: progress,
                    child: Container(
                      width: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.centerLeft,
                      child: const Text(
                        'NSFW',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                          fontSize: 11.6,
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Opacity(
                      opacity: 1 - progress,
                      child: Container(
                        width: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.centerRight,
                        child: const Text(
                          ' SFW',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 11.6,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment(-1 + 2 * progress, 0),
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color.lerp(Colors.white, Colors.black, progress),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
