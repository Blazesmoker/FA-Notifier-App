import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fanotifier/features/submissions/presentation/widgets/submission_folder_management_styles.dart';
import 'package:fanotifier/features/submissions/presentation/widgets/submission_management_shrinkable_text.dart';

class FolderColorDialog extends StatefulWidget {
  const FolderColorDialog({
    super.key,
    required this.folderName,
    required this.initialColor,
  });

  final String folderName;
  final Color initialColor;

  @override
  State<FolderColorDialog> createState() => _FolderColorDialogState();
}

class _FolderColorDialogState extends State<FolderColorDialog> {
  static const List<Color> _presets = <Color>[
    Color(0xFFE53935),
    Color(0xFFE09321),
    Color(0xFFF9A825),
    Color(0xFF43A047),
    Color(0xFF00897B),
    Color(0xFF0097A7),
    Color(0xFF1E88E5),
    Color(0xFF3949AB),
    Color(0xFF8E24AA),
    Color(0xFFD81B60),
    Color(0xFF6D4C41),
    Color(0xFF546E7A),
  ];

  late HSVColor _hsvColor;
  late final TextEditingController _hexController;
  String? _hexError;

  Color get _color => _hsvColor.toColor();

  @override
  void initState() {
    super.initState();
    _hsvColor = HSVColor.fromColor(widget.initialColor);
    _hexController = TextEditingController(text: _hexFor(_color));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _selectColor(Color color) {
    setState(() {
      _hsvColor = HSVColor.fromColor(color);
      _hexController.text = _hexFor(color);
      _hexController.selection = TextSelection.collapsed(
        offset: _hexController.text.length,
      );
      _hexError = null;
    });
  }

  void _updateSaturationAndValue(double saturation, double value) {
    setState(() {
      _hsvColor = _hsvColor.withSaturation(saturation).withValue(value);
      _hexController.text = _hexFor(_color);
      _hexError = null;
    });
  }

  void _updateHue(double hue) {
    setState(() {
      _hsvColor = _hsvColor.withHue(hue);
      _hexController.text = _hexFor(_color);
      _hexError = null;
    });
  }

  void _updateHex(String value) {
    final color = _parseHex(value);
    setState(() {
      _hexError = color == null
          ? 'Use #RRGGBB or Flutter 0xAARRGGBB format.'
          : null;
      if (color != null) _hsvColor = HSVColor.fromColor(color);
    });
  }

  String _hexFor(Color color) {
    final value = color.toARGB32().toRadixString(16).padLeft(8, '0');
    return '#${value.substring(2).toUpperCase()}';
  }

  Color? _parseHex(String input) {
    var value = input.trim();
    if (value.startsWith('Color(') && value.endsWith(')')) {
      value = value.substring(6, value.length - 1).trim();
    }
    if (value.startsWith('#')) value = value.substring(1);
    if (value.toLowerCase().startsWith('0x')) value = value.substring(2);
    if (value.length == 3) {
      value = value.split('').map((character) => '$character$character').join();
    }
    if (value.length == 8) value = value.substring(2);
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(value)) return null;
    return Color(0xFF000000 | int.parse(value, radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final foreground =
        _color.computeLuminance() > 0.42 ? Colors.black : Colors.white;
    final mediaQuery = MediaQuery.of(context);
    final dialogWidth =
        (mediaQuery.size.width - 36).clamp(244.0, 408.0).toDouble();
    final dialogHeight = (mediaQuery.size.height -
            mediaQuery.viewInsets.bottom -
            48)
        .clamp(300.0, 680.0)
        .toDouble();
    final pickerWidth = dialogWidth - 40;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      backgroundColor: managementCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Edit folder color',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: _color,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: foreground.withValues(alpha: 0.55),
                            width: 1.2,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          child: SubmissionManagementShrinkableText(
                            widget.folderName,
                            maxLines: 2,
                            minFontSize: 10,
                            style: TextStyle(
                              color: foreground,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Drag anywhere below. The floating preview stays away from your finger.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _SaturationValuePicker(
                        width: pickerWidth,
                        hsvColor: _hsvColor,
                        onChanged: _updateSaturationAndValue,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Hue',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      _HuePicker(
                        width: pickerWidth,
                        hue: _hsvColor.hue,
                        onChanged: _updateHue,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Quick colors',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final preset in _presets)
                            _ColorPresetButton(
                              color: preset,
                              selected:
                                  preset.toARGB32() == _color.toARGB32(),
                              onTap: () => _selectColor(preset),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _hexController,
                        autocorrect: false,
                        enableSuggestions: false,
                        textCapitalization: TextCapitalization.characters,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Paste or enter a color',
                          hintText: '#E09321',
                          helperText: '#RRGGBB, RGB, or 0xAARRGGBB',
                          errorText: _hexError,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: _updateHex,
                        onSubmitted: (_) {
                          if (_hexError == null) {
                            FocusScope.of(context).unfocus();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _hexError == null
                        ? () => Navigator.of(context).pop(_color)
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: _color,
                      foregroundColor: foreground,
                    ),
                    child: const Text('Save color'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EagerPointerDragArea extends StatelessWidget {
  const _EagerPointerDragArea({
    required this.onPositionChanged,
    required this.child,
  });

  final ValueChanged<Offset> onPositionChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: <Type, GestureRecognizerFactory>{
        EagerGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
          () => EagerGestureRecognizer(),
          (_) {},
        ),
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) => onPositionChanged(event.localPosition),
        onPointerMove: (event) => onPositionChanged(event.localPosition),
        child: child,
      ),
    );
  }
}

class _SaturationValuePicker extends StatelessWidget {
  const _SaturationValuePicker({
    required this.width,
    required this.hsvColor,
    required this.onChanged,
  });

  final double width;
  final HSVColor hsvColor;
  final void Function(double saturation, double value) onChanged;

  @override
  Widget build(BuildContext context) {
    const height = 190.0;
    final selection = Offset(
      hsvColor.saturation * width,
      (1 - hsvColor.value) * height,
    );
    final bubbleX =
        selection.dx.clamp(22.0, width - 22.0).toDouble() - 22;
    final bubbleCenterY =
        selection.dy > 70 ? selection.dy - 52 : selection.dy + 52;
    final bubbleY =
        bubbleCenterY.clamp(22.0, height - 22.0).toDouble() - 22;

    void update(Offset position) {
      onChanged(
        (position.dx / width).clamp(0.0, 1.0).toDouble(),
        (1 - position.dy / height).clamp(0.0, 1.0).toDouble(),
      );
    }

    return _EagerPointerDragArea(
      onPositionChanged: update,
      child: SizedBox(
        width: width,
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _SaturationValuePainter(hue: hsvColor.hue),
                ),
              ),
              Positioned(
                left: selection.dx.clamp(0.0, width).toDouble() - 10,
                top: selection.dy.clamp(0.0, height).toDouble() - 10,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: const [
                        BoxShadow(color: Colors.black87, blurRadius: 3),
                      ],
                    ),
                    child: const SizedBox(width: 20, height: 20),
                  ),
                ),
              ),
              Positioned(
                left: bubbleX,
                top: bubbleY,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: hsvColor.toColor(),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black87,
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: const SizedBox(width: 44, height: 44),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaturationValuePainter extends CustomPainter {
  const _SaturationValuePainter({required this.hue});

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, HSVColor.fromAHSV(1, hue, 1, 1).toColor()],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_SaturationValuePainter oldDelegate) {
    return hue != oldDelegate.hue;
  }
}

class _HuePicker extends StatelessWidget {
  const _HuePicker({
    required this.width,
    required this.hue,
    required this.onChanged,
  });

  final double width;
  final double hue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    void update(Offset position) {
      onChanged((position.dx / width).clamp(0.0, 1.0).toDouble() * 360);
    }

    return _EagerPointerDragArea(
      onPositionChanged: update,
      child: SizedBox(
        width: width,
        height: 38,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              top: 6,
              bottom: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFFF0000),
                      Color(0xFFFFFF00),
                      Color(0xFF00FF00),
                      Color(0xFF00FFFF),
                      Color(0xFF0000FF),
                      Color(0xFFFF00FF),
                      Color(0xFFFF0000),
                    ],
                  ),
                  border: Border.all(color: Colors.white54),
                ),
              ),
            ),
            Positioned(
              left: (hue / 360 * width).clamp(0.0, width).toDouble() - 5,
              top: 1,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(color: Colors.black87, blurRadius: 3),
                    ],
                  ),
                  child: const SizedBox(width: 10, height: 36),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorPresetButton extends StatelessWidget {
  const _ColorPresetButton({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: _colorLabel(color),
      child: Material(
        color: color,
        shape: CircleBorder(
          side: BorderSide(
            color: selected ? Colors.white : Colors.white38,
            width: selected ? 3 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: selected
                ? Icon(
                    Icons.check_rounded,
                    color: color.computeLuminance() > 0.42
                        ? Colors.black
                        : Colors.white,
                  )
                : null,
          ),
        ),
      ),
    );
  }

  String _colorLabel(Color color) {
    final value = color.toARGB32().toRadixString(16).padLeft(8, '0');
    return 'Color ${value.substring(2).toUpperCase()}';
  }
}
