import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A page route that closes when the page is swiped to the right from
/// anywhere on it. The page follows the finger with the one below showing
/// behind it, and closes past a third of the width or on a quick flick.
class SwipeBackRoute<T> extends PageRoute<T>
    with MaterialRouteTransitionMixin<T> {
  SwipeBackRoute({required this.builder, super.settings});

  final WidgetBuilder builder;

  @override
  Widget buildContent(BuildContext context) =>
      SwipeBack(child: builder(context));

  // Keeps the page below painted, so it shows while swiping.
  @override
  bool get opaque => false;

  @override
  bool get maintainState => true;
}

/// See [SwipeBackRoute]. Only a clearly rightward swipe moves the page:
/// vertical scrolling, leftward drags (wide code blocks) and long-press
/// text selection work as before.
class SwipeBack extends StatefulWidget {
  const SwipeBack({super.key, required this.child});

  final Widget child;

  @override
  State<SwipeBack> createState() => _SwipeBackState();
}

class _SwipeBackState extends State<SwipeBack>
    with SingleTickerProviderStateMixin {
  /// How far the page has moved, as a share of its width.
  late final _offset = AnimationController(vsync: this);
  bool _closing = false;

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  void _update(DragUpdateDetails details) {
    if (_closing) return;
    final width = context.size?.width ?? 1;
    _offset.value += (details.primaryDelta ?? 0) / width;
  }

  void _end(DragEndDetails details) {
    if (_closing) return;
    final velocity = details.primaryVelocity ?? 0;
    if (_offset.value > 0.33 || (velocity > 700 && _offset.value > 0.02)) {
      _closing = true;
      _offset
          .animateTo(
            1,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
          )
          .whenComplete(() {
            if (mounted) Navigator.of(context).maybePop();
          });
    } else {
      _settle();
    }
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
          // The same widgets whether moved or not, so the page keeps its
          // state (scroll position and all) when a swipe starts.
          return FractionalTranslation(
            translation: Offset(_offset.value, 0),
            child: DecoratedBox(
              // A soft edge between this page and the one below.
              decoration: BoxDecoration(
                boxShadow: [
                  if (_offset.value > 0)
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 16,
                    ),
                ],
              ),
              child: child,
            ),
          );
        },
        child: widget.child,
      ),
    );
  }

  /// Catches rightward swipes over [child]. Used around the whole page,
  /// and by [SwipeBackArea] deeper inside it.
  Widget _detector(Widget child) {
    return RawGestureDetector(
      gestures: {
        _SwipeRightRecognizer:
            GestureRecognizerFactoryWithHandlers<_SwipeRightRecognizer>(
              () => _SwipeRightRecognizer(debugOwner: this),
              (r) => r
                ..onUpdate = _update
                ..onEnd = _end
                ..onCancel = () {
                  if (!_closing) _settle();
                },
            ),
      },
      child: child,
    );
  }
}

/// Lets a swipe over [child] close the page, ahead of anything above it.
///
/// Touches go to the innermost gesture handlers first, and a text
/// selection area (which on Android also follows sideways drags) would
/// otherwise take quick swipes. Put this just inside a SelectionArea.
class SwipeBackArea extends StatelessWidget {
  const SwipeBackArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final page = context.findAncestorStateOfType<_SwipeBackState>();
    return page == null ? child : page._detector(child);
  }
}

/// Claims a drag as soon as it moves clearly rightwards, a little sooner
/// than text selection (which on Android also follows sideways drags) or
/// scrolling would claim it. Gives up on anything else.
class _SwipeRightRecognizer extends OneSequenceGestureRecognizer {
  _SwipeRightRecognizer({super.debugOwner});

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
    if (_pointer != null) return;
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
      if (moved.dx > _slop && moved.dx > moved.dy.abs() * 1.5) {
        _accepted = true;
        resolve(GestureDisposition.accepted);
        _send(event.position, moved.dx);
      } else if (moved.dy.abs() > _slop || moved.dx < -_slop) {
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
  String get debugDescription => 'swipe right';
}
