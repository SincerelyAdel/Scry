import 'package:flutter/material.dart';

import '../../theme.dart';

/// A cat's head: ears, cheeks, eyes and a nose, outlined like Material's
/// outlined icons.
class CatIcon extends StatelessWidget {
  const CatIcon({super.key, this.size = 24, this.color, this.filled = false});

  final double size;
  final Color? color;

  /// A solid head (cats on) rather than an outline.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? IconTheme.of(context).color ?? Colors.white;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _CatIconPainter(color, filled)),
    );
  }
}

class _CatIconPainter extends CustomPainter {
  const _CatIconPainter(this.color, this.filled);

  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    // Drawn on a 24-unit square.
    final head = Path()
      ..moveTo(4.2, 13.6)
      ..lineTo(4.4, 4.2)
      ..quadraticBezierTo(4.5, 3.4, 5.2, 3.8)
      ..lineTo(9.4, 7.2)
      ..quadraticBezierTo(12, 6.4, 14.6, 7.2)
      ..lineTo(18.8, 3.8)
      ..quadraticBezierTo(19.5, 3.4, 19.6, 4.2)
      ..lineTo(19.8, 13.6)
      ..cubicTo(19.8, 18.2, 16.4, 20.6, 12, 20.6)
      ..cubicTo(7.6, 20.6, 4.2, 18.2, 4.2, 13.6)
      ..close();
    final nose = Path()
      ..moveTo(10.9, 16)
      ..lineTo(13.1, 16)
      ..lineTo(12, 17.3)
      ..close();
    final eyes = [
      Rect.fromCenter(center: const Offset(9, 13), width: 2, height: 2.6),
      Rect.fromCenter(center: const Offset(15, 13), width: 2, height: 2.6),
    ];
    if (filled) {
      // A solid head with the eyes and nose cut out.
      canvas
        ..saveLayer(Offset.zero & const Size(24, 24), Paint())
        ..drawPath(head, Paint()..color = color);
      final cut = Paint()..blendMode = BlendMode.clear;
      for (final eye in eyes) {
        canvas.drawOval(eye, cut);
      }
      canvas
        ..drawPath(nose, cut)
        ..restore();
      return;
    }
    canvas.drawPath(
      head,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round,
    );
    final ink = Paint()..color = color;
    for (final eye in eyes) {
      canvas.drawOval(eye, ink);
    }
    canvas.drawPath(nose, ink);
  }

  @override
  bool shouldRepaint(_CatIconPainter old) =>
      old.color != color || old.filled != filled;
}

/// The cat button in the reader's bar. It opens a small panel, growing out
/// of the button, with everything about the cats: on or off, resting, and
/// shooed to the edges.
class CatMenuButton extends StatefulWidget {
  const CatMenuButton({
    super.key,
    required this.on,
    required this.resting,
    required this.shooed,
    required this.onChanged,
    required this.onRest,
    required this.onShoo,
  });

  final bool on;
  final bool resting;
  final bool shooed;
  final ValueChanged<bool> onChanged;
  final ValueChanged<bool> onRest;
  final ValueChanged<bool> onShoo;

  @override
  State<CatMenuButton> createState() => _CatMenuButtonState();
}

class _CatMenuButtonState extends State<CatMenuButton>
    with SingleTickerProviderStateMixin {
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  final _group = Object();
  late final _open = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    reverseDuration: const Duration(milliseconds: 140),
  );

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_portal.isShowing) {
      _close();
    } else {
      _portal.show();
      _open.forward(from: 0);
    }
  }

  void _close() {
    if (!_portal.isShowing) return;
    _open.reverse().whenComplete(() {
      if (mounted && _open.isDismissed) _portal.hide();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final icon = widget.on
        ? ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (b) => c.goldViolet().createShader(b),
            child: const CatIcon(filled: true, color: Colors.white),
          )
        : CatIcon(color: c.muted);
    return TapRegion(
      groupId: _group,
      onTapOutside: (_) => _close(),
      child: CompositedTransformTarget(
        link: _link,
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (context) => CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(-4, 4),
            child: Align(
              alignment: Alignment.topRight,
              child: TapRegion(
                groupId: _group,
                onTapOutside: (_) => _close(),
                child: FadeTransition(
                  opacity: CurvedAnimation(
                    parent: _open,
                    curve: Curves.easeOut,
                  ),
                  child: ScaleTransition(
                    alignment: Alignment.topRight,
                    scale: CurvedAnimation(
                      parent: _open,
                      curve: Curves.easeOutBack,
                      reverseCurve: Curves.easeIn,
                    ),
                    child: _CatPanel(
                      on: widget.on,
                      resting: widget.resting,
                      shooed: widget.shooed,
                      onChanged: widget.onChanged,
                      onRest: widget.onRest,
                      onShoo: widget.onShoo,
                    ),
                  ),
                ),
              ),
            ),
          ),
          child: IconButton(tooltip: 'Cats', onPressed: _toggle, icon: icon),
        ),
      ),
    );
  }
}

class _CatPanel extends StatelessWidget {
  const _CatPanel({
    required this.on,
    required this.resting,
    required this.shooed,
    required this.onChanged,
    required this.onRest,
    required this.onShoo,
  });

  final bool on;
  final bool resting;
  final bool shooed;
  final ValueChanged<bool> onChanged;
  final ValueChanged<bool> onRest;
  final ValueChanged<bool> onShoo;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    Widget option({
      required Widget icon,
      required String title,
      required String subtitle,
      required bool value,
      required ValueChanged<bool> onChanged,
    }) {
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              SizedBox(width: 24, child: Center(child: icon)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(color: c.muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      );
    }

    return Material(
      color: c.surface,
      elevation: 8,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 290,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                option(
                  icon: CatIcon(
                    size: 22,
                    color: on ? c.accent : c.muted,
                    filled: on,
                  ),
                  title: 'Cats',
                  subtitle: 'Wandering behind the text',
                  value: on,
                  onChanged: onChanged,
                ),
                if (on) ...[
                  Divider(
                    height: 8,
                    indent: 12,
                    endIndent: 12,
                    color: c.border,
                  ),
                  option(
                    icon: Icon(
                      Icons.bedtime_outlined,
                      size: 22,
                      color: c.muted,
                    ),
                    title: 'Rest',
                    subtitle: 'They sit or lie down',
                    value: resting,
                    onChanged: onRest,
                  ),
                  option(
                    icon: Icon(
                      Icons.visibility_off_outlined,
                      size: 22,
                      color: c.muted,
                    ),
                    title: 'Shoo away',
                    subtitle: 'Only their heads peek in',
                    value: shooed,
                    onChanged: onShoo,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.touch_app_outlined,
                          size: 16,
                          color: c.faint,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Tap a cat to scare it off',
                            style: TextStyle(color: c.faint, fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
