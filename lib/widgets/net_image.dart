import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../services/ranobes_session.dart';
import '../theme.dart';

/// Pictures from ranobes.net (novel covers): fetched one at a time with the
/// headers of the browser that passed the site's human check, so a screen
/// full of covers doesn't trip its rate limit. Kept for 90 days.
final _ranobesImages = CacheManager(
  Config(
    'ranobesImages',
    stalePeriod: const Duration(days: 90),
    fileService: HttpFileService()..concurrentFetches = 1,
  ),
);

/// The cache and headers to load [url] with: the defaults for most sites.
({BaseCacheManager? manager, Map<String, String>? headers}) _cacheFor(
  String url,
) => RanobesSession.appliesTo(url)
    ? (manager: _ranobesImages, headers: RanobesSession.headers())
    : (manager: null, headers: null);

/// A web image, kept on disk after the first view so it shows offline.
/// Shows a soft placeholder while loading and nothing if it fails.
class NetImage extends StatelessWidget {
  const NetImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.radius = 10,
    this.zoomable = false,
    this.caption,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double radius;

  /// Tap to open full screen, with pinch to zoom.
  final bool zoomable;

  /// Shown under the image in the full-screen view.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final source = _cacheFor(url);
    Widget image = CachedNetworkImage(
      imageUrl: url,
      cacheManager: source.manager,
      httpHeaders: source.headers,
      width: width,
      height: height,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 180),
      placeholder: (_, _) =>
          Container(width: width, height: height ?? 160, color: c.surfaceAlt),
      errorWidget: (_, _, _) => const SizedBox.shrink(),
    );
    image = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: image,
    );
    if (!zoomable) return image;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ImageViewer(url: url, caption: caption),
        ),
      ),
      child: MouseRegion(cursor: SystemMouseCursors.zoomIn, child: image),
    );
  }
}

/// A full-screen image with pinch and double-tap zoom, and its caption.
class ImageViewer extends StatefulWidget {
  const ImageViewer({super.key, required this.url, this.caption});

  final String url;
  final String? caption;

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  final _transform = TransformationController();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _toggleZoom(TapDownDetails d) {
    if (_transform.value != Matrix4.identity()) {
      _transform.value = Matrix4.identity();
      return;
    }
    final p = d.localPosition;
    _transform.value = Matrix4.identity()
      ..translateByDouble(-p.dx, -p.dy, 0, 1)
      ..scaleByDouble(2.5, 2.5, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    final caption = widget.caption;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onDoubleTapDown: _toggleZoom,
              onDoubleTap: () {},
              child: InteractiveViewer(
                transformationController: _transform,
                maxScale: 6,
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: widget.url,
                    cacheManager: _cacheFor(widget.url).manager,
                    httpHeaders: _cacheFor(widget.url).headers,
                    fit: BoxFit.contain,
                    placeholder: (_, _) => const CircularProgressIndicator(),
                    errorWidget: (_, _, _) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 48,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (caption != null && caption.isNotEmpty)
            SafeArea(
              top: false,
              child: Container(
                constraints: const BoxConstraints(maxHeight: 200),
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: SingleChildScrollView(
                  child: Text(
                    caption,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
