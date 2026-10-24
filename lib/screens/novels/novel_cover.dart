import 'dart:io';

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/net_image.dart';

/// A novel's cover at book proportions (2:3), or its initial when there's
/// no picture.
class NovelCover extends StatelessWidget {
  const NovelCover({
    super.key,
    required this.url,
    required this.title,
    this.width = 96,
  });

  final String? url;
  final String title;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final height = width * 1.5;
    final url = this.url;
    if (url != null) {
      // Fixed size, so a picture that fails to load doesn't shift things.
      return SizedBox(
        width: width,
        height: height,
        child: url.startsWith('http')
            ? NetImage(url, width: width, height: height, radius: 8)
            // An imported book's cover, saved on the device.
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(url),
                  width: width,
                  height: height,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
      );
    }
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: Text(
        title.isEmpty ? '?' : title.characters.first.toUpperCase(),
        style: TextStyle(
          fontFamily: kSerif,
          color: c.accent,
          fontSize: width * 0.4,
        ),
      ),
    );
  }
}
