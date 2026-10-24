import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'cat_painter.dart';
import 'cat_sim.dart';

/// Cats wandering about behind [child], seen from above. They keep to the
/// middle of the page; a tap on one sends it running (and its neighbours).
/// [resting] makes them sit or lie down; [shooed] sends them to the edges,
/// where only their heads peek in.
///
/// Taps are only watched, never taken: everything in [child] works as
/// before.
class CatLayer extends StatefulWidget {
  const CatLayer({
    super.key,
    required this.child,
    this.enabled = true,
    this.resting = false,
    this.shooed = false,
    this.opacity = 1,
  });

  final Widget child;
  final bool enabled;
  final bool resting;
  final bool shooed;

  /// How strongly the cats show, so they don't fight with the text.
  final double opacity;

  @override
  State<CatLayer> createState() => _CatLayerState();
}

class _CatLayerState extends State<CatLayer>
    with SingleTickerProviderStateMixin {
  final _pack = CatPack();
  final _frame = ValueNotifier<int>(0);
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  Size _size = Size.zero;

  Offset? _down;
  Duration _downAt = Duration.zero;
  int _pointers = 0;

  @override
  void initState() {
    super.initState();
    _apply();
    if (widget.enabled) _ticker.start();
  }

  @override
  void didUpdateWidget(CatLayer old) {
    super.didUpdateWidget(old);
    _apply();
    if (widget.enabled && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!widget.enabled && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _apply() {
    // Reduced motion: they sit still.
    final still = MediaQueryData.fromView(
      WidgetsBinding.instance.platformDispatcher.views.first,
    ).disableAnimations;
    _pack
      ..resting = widget.resting || still
      ..shooed = widget.shooed;
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero
        ? 1 / 60
        : (now - _last).inMicroseconds / 1e6;
    _last = now;
    _pack.tick(dt, _size);
    _frame.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (e) {
            _pointers++;
            _down = _pointers == 1 ? e.localPosition : null;
            _downAt = e.timeStamp;
          },
          onPointerUp: (e) {
            _pointers = (_pointers - 1).clamp(0, 10);
            final down = _down;
            _down = null;
            // A quick tap that didn't move: a touch, not a scroll.
            if (down == null ||
                (e.localPosition - down).distance > 12 ||
                e.timeStamp - _downAt > const Duration(milliseconds: 350)) {
              return;
            }
            _pack.tap(e.localPosition);
          },
          onPointerCancel: (_) {
            _pointers = (_pointers - 1).clamp(0, 10);
            _down = null;
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: CatPainter(
                      _pack,
                      repaint: _frame,
                      opacity: widget.opacity,
                    ),
                  ),
                ),
              ),
              widget.child,
            ],
          ),
        );
      },
    );
  }
}
