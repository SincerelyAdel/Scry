import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/topic.dart';
import '../theme.dart';

/// A RepoViewer-style card: surface fill, hairline border, rounded corners.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.all(16),
    this.highlight = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;

  /// Gold edge, e.g. for unread articles.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: highlight ? c.accent.withValues(alpha: 0.55) : c.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Small grey heading above a group of cards.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
      child: Text(
        text,
        style: TextStyle(
          color: context.palette.muted,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Big faint icon, serif title and a short line, centred. Scrollable so
/// pull-to-refresh still works around it.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 56, color: c.faint),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: kSerif,
                      color: c.text,
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: c.muted,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ],
                  if (action != null) ...[const SizedBox(height: 24), action!],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Side padding that keeps content a readable width on tablets.
double pagePadding(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  return width > 900 ? (width - 840) / 2 : 16;
}

/// Feed favicon, or the feed's initial in gold.
class FeedAvatar extends StatelessWidget {
  const FeedAvatar({
    super.key,
    required this.title,
    this.favicon,
    this.size = 36,
  });

  final String title;
  final Uint8List? favicon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final initial = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Text(
        title.isEmpty ? '?' : title.characters.first.toUpperCase(),
        style: TextStyle(
          fontFamily: kSerif,
          color: c.accent,
          fontSize: size * 0.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    final icon = favicon;
    if (icon == null || icon.isEmpty) return initial;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.18),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Image.memory(
        icon,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => initial,
      ),
    );
  }
}

/// A tag's colour on the current theme.
Color topicColor(BuildContext context, Topic topic) =>
    topic.color(isDark: context.palette.isDark);

/// A small rounded label: a feed's topic, "Paper", a read time.
class Tag extends StatelessWidget {
  const Tag(this.label, {super.key, this.icon, this.color});

  /// A topic's badge in its colour.
  factory Tag.topic(BuildContext context, Topic topic) =>
      Tag(topic.badge, color: topicColor(context, topic));

  final String label;
  final IconData? icon;

  /// Tints the label; plain grey when null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final fg = color ?? c.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color == null ? c.surfaceAlt : fg.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              height: 1.3,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Badges for an article in the reader: its tags, "Paper" for arXiv
/// papers, and the read time once the full text is known.
List<Widget> articleTags(
  BuildContext context, {
  required List<Topic> tags,
  required bool paper,
  required int? readMinutes,
}) {
  return [
    for (final tag in tags) Tag.topic(context, tag),
    if (paper) const Tag('Paper', icon: Icons.description_outlined),
    if (!paper && readMinutes != null)
      Tag('$readMinutes min', icon: Icons.schedule),
  ];
}

/// Small coloured dots for a list of tags, e.g. beside a feed's name.
class TagDots extends StatelessWidget {
  const TagDots(this.tags, {super.key, this.size = 8});

  final Iterable<Topic> tags;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final tag in tags)
          Container(
            width: size,
            height: size,
            margin: const EdgeInsets.only(left: 3),
            decoration: BoxDecoration(
              color: topicColor(context, tag),
              shape: BoxShape.circle,
            ),
          ),
      ],
    );
  }
}
