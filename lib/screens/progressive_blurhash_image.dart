import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart' as fb;

class ProgressiveBlurHashImage extends StatefulWidget {
  final String imageUrl;
  final String blurHash;
  final double aspectRatio;

  const ProgressiveBlurHashImage({
    super.key,
    required this.imageUrl,
    required this.blurHash,
    required this.aspectRatio,
  });

  @override
  State<ProgressiveBlurHashImage> createState() => _ProgressiveBlurHashImageState();
}

class _ProgressiveBlurHashImageState extends State<ProgressiveBlurHashImage> {
  MemoryImage? _currentPlaceholder;
  int _currentResolution = 4;
  bool _isNetworkImageLoaded = false;
  Image? _networkImage;

  @override
  void initState() {
    super.initState();
    _generateNextBlur();
    _loadNetworkImage();
  }

  Future<void> _generateNextBlur() async {
    if (_isNetworkImageLoaded || _currentResolution > 128) return;
    try {
      // 1) Decode
      final decodedPixels = await fb.blurHashDecode(
        blurHash: widget.blurHash,
        width: _currentResolution,
        height: _currentResolution,
      );

      // 2) Convert ARGB to RGBA (bytes)
      final length = decodedPixels.length;
      final buffer = Uint8List(length * 4);
      for (int i = 0; i < length; i++) {
        final argb = decodedPixels[i];
        final a = (argb >> 24) & 0xFF;
        final r = (argb >> 16) & 0xFF;
        final g = (argb >> 8) & 0xFF;
        final b = argb & 0xFF;

        final offset = i * 4;
        buffer[offset + 0] = r;
        buffer[offset + 1] = g;
        buffer[offset + 2] = b;
        buffer[offset + 3] = a;
      }

      // 3) Update placeholder
      setState(() {
        _currentPlaceholder = MemoryImage(buffer);
      });


      _currentResolution *= 2;
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted && !_isNetworkImageLoaded) {
        _generateNextBlur();
      }
    } catch (e) {
      debugPrint('Error decoding blurHash: $e');
    }
  }

  void _loadNetworkImage() {
    final image = Image.network(widget.imageUrl, fit: BoxFit.cover);
    final stream = image.image.resolve(const ImageConfiguration());
    stream.addListener(ImageStreamListener(
          (info, syncCall) {
        setState(() {
          _networkImage = image;
          _isNetworkImageLoaded = true;
        });
      },
      onError: (exception, stackTrace) {
        debugPrint('Error loading network image: $exception');
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_currentPlaceholder != null)
            AnimatedOpacity(
              opacity: _isNetworkImageLoaded ? 0 : 1,
              duration: const Duration(milliseconds: 500),
              child: Image(
                image: _currentPlaceholder!,
                fit: BoxFit.cover,
              ),
            ),
          if (_networkImage != null)
            AnimatedOpacity(
              opacity: _isNetworkImageLoaded ? 1 : 0,
              duration: const Duration(milliseconds: 500),
              child: _networkImage,
            ),
        ],
      ),
    );
  }
}
