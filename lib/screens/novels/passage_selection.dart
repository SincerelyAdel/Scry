import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';

/// Which paragraphs of a chapter are held to be saved as a passage, and a
/// saved one being shown on its return.
class PassageSelectionController extends ChangeNotifier {
  final _keys = <int, GlobalKey>{};

  (int, int)? _selection;
  (int, int)? _shown;
  int _lift = 0;

  /// The paragraphs held, first and last; null when none.
  (int, int)? get selection => _selection;

  /// A saved passage shown for a moment after opening it.
  (int, int)? get shown => _shown;

  /// Counts each new card, so it lifts off the page afresh.
  int get lift => _lift;

  GlobalKey keyFor(int index) => _keys.putIfAbsent(index, GlobalKey.new);

  /// Holds paragraph [index] alone.
  void select(int index) {
    _selection = (index, index);
    _shown = null;
    _lift++;
    notifyListeners();
  }

  /// Stretches the held paragraphs.
  void stretch(int from, int to) {
    if (_selection == (from, to)) return;
    _selection = (from, to);
    notifyListeners();
  }

  void clear() {
    if (_selection == null && _shown == null) return;
    _selection = null;
    _shown = null;
    notifyListeners();
  }

  /// Shows a saved passage: scrolled to, lifted, then let go.
  void reveal(int from, int to) {
    _selection = null;
    _shown = (from, to);
    _lift++;
    notifyListeners();
  }

  void _settle(int lift) {
    if (_lift != lift || _shown == null) return;
    _shown = null;
    notifyListeners();
  }
}

/// A paragraph that can be held to start a passage.
class PassageParagraph extends StatelessWidget {
  const PassageParagraph({
    super.key,
    required this.controller,
    required this.index,
    required this.child,
  });

  final PassageSelectionController controller;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () {
        HapticFeedback.mediumImpact();
        controller.select(index);
      },
      child: KeyedSubtree(key: controller.keyFor(index), child: child),
    );
  }
}

/// The chapter text with the held paragraphs raised on a white card, and a
/// handle on two corners: hold one, then drag to stretch the passage a
/// whole paragraph at a time.
class PassageSelection extends StatefulWidget {
  const PassageSelection({
    super.key,
    required this.controller,
    required this.scroll,
    required this.gutter,
    required this.child,
  });

  final PassageSelectionController controller;
  final ScrollController scroll;

  /// Space at each side of the text; the card reaches into it.
  final double gutter;
  final Widget child;

  @override
  State<PassageSelection> createState() => _PassageSelectionState();
}

class _PassageSelectionState extends State<PassageSelection> {
  final _stack = GlobalKey();
  Rect? _rect;
  int _shownLift = -1;
  bool _fading = false;
  Timer? _settle;

  /// Which handle is held: true for the start, false for the end.
  bool? _dragging;

  static const _outX = 12.0;
  static const _outY = 10.0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(PassageSelection old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _settle?.cancel();
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  (int, int)? get _range =>
      widget.controller.selection ?? widget.controller.shown;

  void _changed() {
    final c = widget.controller;
    final shown = c.shown;
    if (shown != null && c.lift != _shownLift) {
      _shownLift = c.lift;
      _fading = false;
      _settle?.cancel();
      // Scroll it into view first, then let it rest a moment and go.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final target = c.keyFor(shown.$1).currentContext;
        if (target != null && target.mounted) {
          await Scrollable.ensureVisible(
            target,
            alignment: 0.18,
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
          );
        }
        if (!mounted) return;
        setState(() {});
        final lift = c.lift;
        _settle = Timer(const Duration(milliseconds: 2400), () {
          if (!mounted) return;
          setState(() => _fading = true);
          _settle = Timer(const Duration(milliseconds: 500), () {
            _fading = false;
            c._settle(lift);
          });
        });
      });
    }
    if (mounted) setState(() {});
  }

  /// Where the paragraphs [from] to [to] sit in the stack.
  Rect? _measure((int, int) range) {
    final stack = _stack.currentContext?.findRenderObject();
    if (stack is! RenderBox || !stack.hasSize) return null;
    Rect? out;
    for (var i = range.$1; i <= range.$2; i++) {
      final box = widget.controller
          .keyFor(i)
          .currentContext
          ?.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      final at = box.localToGlobal(Offset.zero, ancestor: stack);
      final r = at & box.size;
      out = out == null ? r : out.expandToInclude(r);
    }
    return out;
  }

  void _remeasure() {
    final range = _range;
    final rect = range == null ? null : _measure(range);
    if (rect != _rect && mounted) setState(() => _rect = rect);
  }

  /// The paragraph nearest a point on screen.
  int? _paragraphAt(double y) {
    final c = widget.controller;
    int? best;
    var gap = double.infinity;
    for (final MapEntry(key: i, value: key) in c._keys.entries) {
      final box = key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      final d = y < top ? top - y : (y > bottom ? y - bottom : 0.0);
      if (d < gap) {
        gap = d;
        best = i;
      }
    }
    return best;
  }

  void _drag(Offset global) {
    final sel = widget.controller.selection;
    final start = _dragging;
    if (sel == null || start == null) return;
    // Near the top or bottom of the screen, the page follows.
    final height = MediaQuery.sizeOf(context).height;
    final scroll = widget.scroll;
    if (scroll.hasClients) {
      final p = scroll.position;
      if (global.dy < 120) {
        scroll.jumpTo((p.pixels - 14).clamp(0, p.maxScrollExtent));
      } else if (global.dy > height - 140) {
        scroll.jumpTo((p.pixels + 14).clamp(0, p.maxScrollExtent));
      }
    }
    final i = _paragraphAt(global.dy);
    if (i == null) return;
    if (start) {
      widget.controller.stretch(i < sel.$2 ? i : sel.$2, sel.$2);
    } else {
      widget.controller.stretch(sel.$1, i > sel.$1 ? i : sel.$1);
    }
  }

  Widget _handle(bool start, double left, double top) {
    return Positioned(
      left: left,
      top: top,
      width: 44,
      height: 44,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          // A short hold first, so a passing scroll doesn't catch it.
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(
                  duration: const Duration(milliseconds: 150),
                ),
                (r) => r
                  ..onLongPressStart = (d) {
                    HapticFeedback.selectionClick();
                    setState(() => _dragging = start);
                  }
                  ..onLongPressMoveUpdate = (d) {
                    _drag(d.globalPosition);
                  }
                  ..onLongPressEnd = (_) {
                    setState(() => _dragging = null);
                  }
                  ..onLongPressCancel = () {
                    setState(() => _dragging = null);
                  },
              ),
        },
        child: Semantics(
          label: start ? 'Stretch the start' : 'Stretch the end',
          child: Center(
            child: AnimatedScale(
              scale: _dragging == start ? 1.18 : 1,
              duration: const Duration(milliseconds: 160),
              child: Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: Color(0xFFF6F4EE),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Color(0x0F1F1E1D), spreadRadius: 1),
                    BoxShadow(
                      color: Color(0x2E1F1E1D),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.unfold_more,
                  size: 18,
                  color: Color(0xFF55534D),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _remeasure());
    final c = widget.controller;
    final range = _range;
    final rect = range == null ? null : _rect;
    final selecting = c.selection != null;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      // A tap away from the held paragraphs lets them go.
      onTap: selecting ? c.clear : null,
      child: LayoutBuilder(
        builder: (context, box) {
          final width = box.maxWidth;
          return Stack(
            key: _stack,
            clipBehavior: Clip.none,
            children: [
              if (rect != null)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                  left: rect.left - _outX,
                  top: rect.top - _outY,
                  width: rect.width + _outX * 2,
                  height: rect.height + _outY * 2,
                  child: AnimatedOpacity(
                    opacity: _fading ? 0 : 1,
                    duration: const Duration(milliseconds: 500),
                    child: _LiftCard(key: ValueKey(c.lift), high: selecting),
                  ),
                ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: widget.gutter),
                child: widget.child,
              ),
              if (rect != null && selecting) ...[
                _handle(
                  true,
                  (rect.left - _outX - 22).clamp(0, width - 44),
                  rect.top - _outY - 22,
                ),
                _handle(
                  false,
                  (rect.right + _outX - 22).clamp(0, width - 44),
                  rect.bottom + _outY - 22,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// A white card that lifts off the page: it rises a little too far, then
/// settles.
class _LiftCard extends StatelessWidget {
  const _LiftCard({super.key, required this.high});

  /// Higher while being picked than when shown on return.
  final bool high;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeOutBack,
      builder: (context, v, _) {
        final lift = v.clamp(0.0, 1.2);
        return Transform.translate(
          offset: Offset(0, -2 * lift),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color.lerp(
                (dark ? const Color(0xFF1F1F1F) : Colors.white).withValues(
                  alpha: 0,
                ),
                dark ? const Color(0xFF1F1F1F) : Colors.white,
                v.clamp(0.0, 1.0),
              ),
              borderRadius: BorderRadius.circular(14),
              border: dark ? Border.all(color: c.border) : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: (dark ? 0.5 : 0.08) * v.clamp(0.0, 1.0),
                  ),
                  blurRadius: 4 * lift,
                  offset: Offset(0, 2 * lift),
                ),
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha:
                        (dark ? 0.6 : (high ? 0.2 : 0.14)) * v.clamp(0.0, 1.0),
                  ),
                  blurRadius: (high ? 40 : 28) * lift,
                  offset: Offset(0, (high ? 18 : 10) * lift),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The bar shown while paragraphs are held: save them, copy them, or let
/// them go.
class PassageToolbar extends StatelessWidget {
  const PassageToolbar({
    super.key,
    required this.controller,
    required this.onSave,
    required this.onCopy,
  });

  final PassageSelectionController controller;
  final Future<void> Function(int from, int to) onSave;
  final Future<void> Function(int from, int to) onCopy;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final sel = controller.selection;
        const ink = Color(0xFFF4F2EC);
        return IgnorePointer(
          ignoring: sel == null,
          child: AnimatedSlide(
            offset: sel == null ? const Offset(0, 1.6) : Offset.zero,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: sel == null ? 0 : 1,
              duration: const Duration(milliseconds: 200),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Material(
                    color: const Color(0xFF2A2926),
                    elevation: 8,
                    shadowColor: Colors.black,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFE9CC6E),
                              minimumSize: const Size(44, 48),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              textStyle: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onPressed: sel == null
                                ? null
                                : () {
                                    controller.clear();
                                    onSave(sel.$1, sel.$2);
                                  },
                            icon: const Icon(Icons.bookmark_add_outlined),
                            label: Text(
                              sel == null || sel.$1 == sel.$2
                                  ? 'Save passage'
                                  : 'Save ${sel.$2 - sel.$1 + 1} paragraphs',
                            ),
                          ),
                          IconButton(
                            tooltip: 'Copy',
                            color: ink,
                            icon: const Icon(Icons.copy_outlined),
                            onPressed: sel == null
                                ? null
                                : () {
                                    controller.clear();
                                    onCopy(sel.$1, sel.$2);
                                  },
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Done',
                            color: ink,
                            icon: const Icon(Icons.close),
                            onPressed: controller.clear,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
