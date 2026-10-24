import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A page route that closes when the page is pinched in (zoomed out) with
/// two fingers. The page shrinks with the fingers, the one below showing
/// behind it, and closes once it's down to [PinchBack.closeAt].
class PinchBackRoute<T> extends PageRoute<T>
    with MaterialRouteTransitionMixin<T> {
  PinchBackRoute({required this.builder, this.slideFrom, super.settings});

  final WidgetBuilder builder;

  /// Slides the page in sideways instead of the usual transition: 1 from
  /// the right (the next item), -1 from the left (the previous one).
  final int? slideFrom;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final from = slideFrom;
    if (from == null) {
      return super.buildTransitions(
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }
    return SlideTransition(
      position: Tween(
        begin: Offset(from.toDouble(), 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    );
  }

  @override
  Widget buildContent(BuildContext context) =>
      PinchBack(child: builder(context));

  // Keeps the page below painted, so it shows while pinching.
  @override
  bool get opaque => false;

  @override
  bool get maintainState => true;
}

/// See [PinchBackRoute]. Only watches the pointers, so scrolling, taps and
/// text selection under it work as before.
class PinchBack extends StatefulWidget {
  const PinchBack({super.key, required this.child, this.onClose});

  final Widget child;

  /// Called instead of closing the page, when set.
  final VoidCallback? onClose;

  /// The page closes when pinched to this share of its size.
  static const closeAt = 0.82;

  @override
  State<PinchBack> createState() => _PinchBackState();
}

class _PinchBackState extends State<PinchBack>
    with SingleTickerProviderStateMixin {
  /// The page's size, 1 untouched.
  late final _scale = AnimationController(vsync: this, value: 1, upperBound: 1);
  final Map<int, Offset> _pointers = {};
  double? _startSpan;
  bool _closing = false;

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  double get _span {
    final points = _pointers.values.take(2).toList();
    return (points[0] - points[1]).distance;
  }

  void _down(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) {
      _startSpan = _span;
      _scale.stop();
    }
  }

  void _move(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    final start = _startSpan;
    if (start == null || start < 1 || _pointers.length < 2 || _closing) {
      return;
    }
    // Only zooming out moves it; spreading the fingers does nothing.
    final ratio = (_span / start).clamp(0.0, 1.0);
    // A little resistance, so a pinch has to mean it.
    _scale.value = 1 - (1 - ratio) * 0.7;
  }

  void _up(PointerEvent e) {
    final wasPinching = _pointers.length >= 2 && _startSpan != null;
    _pointers.remove(e.pointer);
    if (!wasPinching || _closing) return;
    _startSpan = null;
    if (_scale.value <= PinchBack.closeAt) {
      _close();
    } else {
      _scale.animateTo(
        1,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _close() {
    _closing = true;
    _scale
        .animateTo(
          0.6,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
        )
        .whenComplete(() {
          if (!mounted) return;
          final onClose = widget.onClose;
          if (onClose != null) {
            onClose();
            _closing = false;
            _scale.value = 1;
          } else {
            Navigator.of(context).maybePop();
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) {
          final s = _scale.value;
          // The same widgets whether shrunk or not, so the page keeps its
          // state (scroll position and all) when a pinch starts.
          return Transform.scale(
            scale: s,
            child: Opacity(
              opacity: (0.4 + (s - 0.6) * 1.5).clamp(0.0, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(s < 1 ? 24 : 0),
                  boxShadow: [
                    if (s < 1)
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 24,
                      ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(s < 1 ? 24 : 0),
                  child: child,
                ),
              ),
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// Moves to the next or previous item (chapter, article) on a sideways
/// swipe: left for the next, right for the previous. The page follows the
/// finger a little and shows where it's going.
///
/// Only a clearly sideways swipe counts: vertical scrolling and long-press
/// text selection work as before. Put [SwipeNavArea] just inside any
/// SelectionArea below it, so selection doesn't take quick swipes.
class SwipeNav extends StatefulWidget {
  const SwipeNav({
    super.key,
    required this.child,
    this.onNext,
    this.onPrevious,
    this.nextLabel = 'Next',
    this.previousLabel = 'Previous',
  });

  final Widget child;

  /// Null when there's nothing that way.
  final VoidCallback? onNext;
  final VoidCallback? onPrevious;

  final String nextLabel;
  final String previousLabel;

  @override
  State<SwipeNav> createState() => _SwipeNavState();
}

class _SwipeNavState extends State<SwipeNav>
    with SingleTickerProviderStateMixin {
  /// How far the finger has moved, as a share of the width; negative is
  /// leftwards (towards the next).
  late final _offset = AnimationController(
    vsync: this,
    lowerBound: -1,
    upperBound: 1,
    value: 0,
  );

  /// Share of the width that counts as a swipe.
  static const _threshold = 0.22;

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  void _update(DragUpdateDetails details) {
    final width = context.size?.width ?? 1;
    var value = _offset.value + (details.primaryDelta ?? 0) / width;
    // Nothing that way: it barely moves.
    if (value < 0 && widget.onNext == null) value = math.max(value, -0.04);
    if (value > 0 && widget.onPrevious == null) value = math.min(value, 0.04);
    _offset.value = value;
  }

  void _end(DragEndDetails details) {
    final v = details.primaryVelocity ?? 0;
    final value = _offset.value;
    VoidCallback? action;
    if (value < -_threshold || (v < -800 && value < -0.04)) {
      action = widget.onNext;
    } else if (value > _threshold || (v > 800 && value > 0.04)) {
      action = widget.onPrevious;
    }
    _settle();
    action?.call();
  }

  void _settle() => _offset.animateTo(
    0,
    duration: const Duration(milliseconds: 220),
    curve: Curves.easeOutCubic,
  );

  @override
  Widget build(BuildContext context) {
    return _detector(
      AnimatedBuilder(
        animation: _offset,
        builder: (context, child) {
          final value = _offset.value;
          final reached = (value.abs() / _threshold).clamp(0.0, 1.0);
          final goingNext = value < 0;
          final label = goingNext ? widget.nextLabel : widget.previousLabel;
          final possible = goingNext
              ? widget.onNext != null
              : widget.onPrevious != null;
          return Stack(
            children: [
              FractionalTranslation(
                // Follows the finger at half speed.
                translation: Offset(value * 0.5, 0),
                child: child,
              ),
              if (value != 0 && possible)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Align(
                      alignment: goingNext
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Opacity(
                        opacity: reached,
                        child: _Hint(
                          label: label,
                          next: goingNext,
                          ready: reached >= 1,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
        child: widget.child,
      ),
    );
  }

  /// Catches sideways swipes over [child]. Used around the whole page,
  /// and by [SwipeNavArea] deeper inside it.
  Widget _detector(Widget child) {
    return RawGestureDetector(
      gestures: {
        SidewaysSwipeRecognizer:
            GestureRecognizerFactoryWithHandlers<SidewaysSwipeRecognizer>(
              () => SidewaysSwipeRecognizer(debugOwner: this),
              (r) => r
                ..onUpdate = _update
                ..onEnd = _end
                ..onCancel = _settle,
            ),
      },
      child: child,
    );
  }
}

/// The arrow and label at the edge while swiping.
class _Hint extends StatelessWidget {
  const _Hint({required this.label, required this.next, required this.ready});

  final String label;
  final bool next;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = Icon(
      next ? Icons.chevron_right : Icons.chevron_left,
      color: ready ? scheme.onPrimary : scheme.onSurface,
    );
    final text = Text(
      label,
      style: TextStyle(
        color: ready ? scheme.onPrimary : scheme.onSurface,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
    );
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ready ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: next
            ? [text, const SizedBox(width: 2), icon]
            : [icon, const SizedBox(width: 2), text],
      ),
    );
  }
}

/// Lets a sideways swipe over [child] move to the next or previous item,
/// ahead of anything above it.
///
/// Touches go to the innermost gesture handlers first, and a text
/// selection area (which on Android also follows sideways drags) would
/// otherwise take quick swipes. Put this just inside a SelectionArea.
class SwipeNavArea extends StatelessWidget {
  const SwipeNavArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final nav = context.findAncestorStateOfType<_SwipeNavState>();
    return nav == null ? child : nav._detector(child);
  }
}

/// Claims a one-finger drag as soon as it moves clearly sideways, a little
/// sooner than text selection or scrolling would claim it. Gives up on
/// anything else, and when a second finger comes down (a pinch).
class SidewaysSwipeRecognizer extends OneSequenceGestureRecognizer {
  SidewaysSwipeRecognizer({super.debugOwner});

  /// Movement before deciding; under the usual touch slop of 8 or more.
  static const _slop = 6.0;

  GestureDragUpdateCallback? onUpdate;
  GestureDragEndCallback? onEnd;
  VoidCallback? onCancel;

  int? _pointer;
  Offset _start = Offset.zero;
  bool _accepted = false;
  VelocityTracker? _velocity;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_pointer != null) {
      // A second finger: a pinch, not a swipe.
      if (_accepted) {
        _accepted = false;
        onCancel?.call();
      }
      resolve(GestureDisposition.rejected);
      return;
    }
    super.addAllowedPointer(event);
    _pointer = event.pointer;
    _start = event.position;
    _accepted = false;
    _velocity = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;
    if (event is PointerMoveEvent) {
      _velocity?.addPosition(event.timeStamp, event.position);
      if (_accepted) {
        _send(event.position, event.delta.dx);
        return;
      }
      final moved = event.position - _start;
      if (moved.dx.abs() > _slop && moved.dx.abs() > moved.dy.abs() * 1.5) {
        _accepted = true;
        resolve(GestureDisposition.accepted);
        _send(event.position, moved.dx);
      } else if (moved.dy.abs() > _slop) {
        resolve(GestureDisposition.rejected);
        stopTrackingPointer(event.pointer);
      }
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      if (_accepted) {
        final speed = _velocity?.getVelocity().pixelsPerSecond.dx ?? 0;
        onEnd?.call(
          DragEndDetails(
            velocity: Velocity(pixelsPerSecond: Offset(speed, 0)),
            primaryVelocity: speed,
          ),
        );
        _accepted = false;
      } else {
        resolve(GestureDisposition.rejected);
      }
      stopTrackingPointer(event.pointer);
    }
  }

  void _send(Offset position, double dx) {
    onUpdate?.call(
      DragUpdateDetails(
        globalPosition: position,
        delta: Offset(dx, 0),
        primaryDelta: dx,
      ),
    );
  }

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {
    if (_accepted) onCancel?.call();
    _accepted = false;
    stopTrackingPointer(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _pointer = null;
    _velocity = null;
  }

  @override
  String get debugDescription => 'sideways swipe';
}
