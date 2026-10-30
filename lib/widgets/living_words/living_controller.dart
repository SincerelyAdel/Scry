import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../state/settings_provider.dart';
import 'lexicon.dart';

/// Runs the living words of a chapter.
///
/// Every living word on screen plays its own effect, growing while it stays
/// in view. One word at a time leads: it sets the page mood and spreads into
/// the words around it. With no leader, the first word to come fully into
/// view takes the lead and keeps it until it leaves the screen; then it
/// fades and the next can lead. Tapping a word makes it lead at once;
/// tapping the leader silences it, the word itself included, until it is
/// tapped again.
class LivingWordsController {
  LivingWordsController() {
    _ticker = Ticker(_tick);
  }

  late final Ticker _ticker;
  Timer? _watch;
  Duration _last = Duration.zero;

  final _words = <int, _Entry>{};

  /// Words that have led and shouldn't take the lead again by themselves.
  final _spent = <int>{};

  /// Words tapped quiet.
  final _hushed = <int>{};

  /// Each word's own strength, 0 to 1, before easing.
  final _self = <int, double>{};

  /// Words with some part on screen, as of the last look.
  var _onScreen = <int>{};

  /// The word leading now, by id, or null.
  final active = ValueNotifier<int?>(null);

  /// The leading word's effect, or null. Follows [active].
  final effect = ValueNotifier<LivingEffect?>(null);

  /// Ticks every frame while any word plays.
  final frame = ValueNotifier<int>(0);

  /// The screen the reader fills.
  Size screen = Size.zero;

  /// Grow time.
  LivingSpeed speed = LivingSpeed.normal;

  /// Reduced motion: effects hold still.
  bool still = false;

  double _level = 0;
  bool _leaving = false;
  double _time = 0;
  double _sinceCheck = 0;

  static double _ease(double x) {
    final s = x.clamp(0.0, 1.0);
    return s * s * (3 - 2 * s);
  }

  /// The leading word's hold on the page, eased, 0 to 1.
  double get level => _ease(_level);

  /// A word's own strength, eased, 0 to 1.
  double selfLevel(int id) => _ease(_self[id] ?? 0);

  /// Whether a word has been tapped quiet.
  bool isHushed(int id) => _hushed.contains(id);

  /// How far the leading word's spread reaches at full strength. Blood
  /// runs further than the rest.
  double get reach {
    final base = (screen.shortestSide * 0.42).clamp(200.0, 360.0);
    return effect.value == LivingEffect.blood ? base * 1.5 : base;
  }

  /// The strength of a word [distance] away from the leading one. The
  /// circle widens as the leader grows; inside it, words nearer the middle
  /// take on more of the effect.
  double strengthAt(double distance) {
    final l = level;
    final radius = reach * l;
    if (radius <= 0 || distance >= radius) return 0;
    // Blood soaks outward more gradually, like an infection.
    final falloff = effect.value == LivingEffect.blood ? 1.2 : 1.6;
    return l * (1 - math.pow(distance / radius, falloff));
  }

  /// The middle of the leading word, on screen.
  Offset? get centre {
    final id = active.value;
    final box = id == null ? null : _words[id]?.box();
    if (box == null || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  /// Seconds of motion; frozen under reduced motion.
  double get time => still ? 0 : _time;

  bool _enabled = false;
  bool get enabled => _enabled;
  set enabled(bool on) {
    if (on == _enabled) return;
    _enabled = on;
    if (on) {
      _watch = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => _look(),
      );
    } else {
      _watch?.cancel();
      _watch = null;
      _stop();
      _self.clear();
      if (_ticker.isActive) _ticker.stop();
    }
  }

  /// A new chapter: every word starts fresh.
  void reset() {
    _stop();
    _spent.clear();
    _hushed.clear();
    _self.clear();
  }

  void register(int id, LivingEffect effect, RenderBox? Function() box) {
    _words[id] = _Entry(effect, box);
  }

  /// A leading word that goes away is stopped on the next frame, not here:
  /// this runs while the tree is being torn down.
  void unregister(int id) {
    _words.remove(id);
    _self.remove(id);
  }

  /// A tap on a living word: it takes the lead, or, if it leads already,
  /// falls silent.
  void tap(int id) {
    final entry = _words[id];
    if (!_enabled || entry == null) return;
    if (active.value == id && !_leaving) {
      _hushed.add(id);
      _leaving = true;
    } else {
      final old = active.value;
      if (old != null) _spent.add(old);
      _hushed.remove(id);
      _spent.remove(id);
      _lead(id);
    }
    _run();
  }

  void dispose() {
    _watch?.cancel();
    _ticker.dispose();
    active.dispose();
    effect.dispose();
    frame.dispose();
  }

  void _lead(int id) {
    _level = 0;
    _leaving = false;
    _sinceCheck = 0;
    // A new leader: the paragraphs let go of the old spread first.
    active.value = null;
    effect.value = null;
    active.value = id;
    effect.value = _words[id]!.effect;
  }

  void _stop() {
    final id = active.value;
    if (id != null) _spent.add(id);
    active.value = null;
    effect.value = null;
    _level = 0;
    _leaving = false;
  }

  void _run() {
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  Rect? _rect(_Entry e) {
    final box = e.box();
    if (box == null || !box.attached || !box.hasSize || screen.isEmpty) {
      return null;
    }
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Whether the word's box sits comfortably on screen.
  bool _inView(_Entry e) {
    final rect = _rect(e);
    if (rect == null) return false;
    return rect.top >= screen.height * 0.12 &&
        rect.bottom <= screen.height * 0.92;
  }

  /// Whether any of the word is on screen.
  bool _visible(_Entry e) {
    final rect = _rect(e);
    if (rect == null) return false;
    return rect.bottom > 0 && rect.top < screen.height;
  }

  /// Finds the words on screen, and a leader when there's none.
  void _look() {
    _onScreen = {
      for (final MapEntry(key: id, value: e) in _words.entries)
        if (_visible(e)) id,
    };
    if (active.value == null) {
      int? best;
      double bestTop = double.infinity;
      for (final id in _onScreen) {
        final e = _words[id]!;
        if (_spent.contains(id) || _hushed.contains(id) || !_inView(e)) {
          continue;
        }
        final top = _rect(e)!.top;
        if (top < bestTop) {
          bestTop = top;
          best = id;
        }
      }
      if (best != null) _lead(best);
    }
    if (_busy) _run();
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero
        ? 1 / 60
        : ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = now;
    _time += dt;

    // Each word's own effect: grows on screen, fades off it, and falls
    // quiet when silenced.
    for (final id in {..._onScreen, ..._self.keys}) {
      final was = _self[id] ?? 0;
      final hushed = _hushed.contains(id);
      final next = !hushed && _onScreen.contains(id) && _words.containsKey(id)
          ? math.min(1.0, was + dt / speed.seconds)
          : was - dt / (hushed ? 1.5 : 3);
      if (next <= 0) {
        _self.remove(id);
      } else {
        _self[id] = next;
      }
    }

    final id = active.value;
    if (id != null) {
      final entry = _words[id];
      if (entry == null) {
        _stop();
      } else {
        _sinceCheck += dt;
        // The leader holds on while any of it is on screen.
        if (!_leaving && _sinceCheck > 0.2) {
          _sinceCheck = 0;
          if (!_visible(entry)) _leaving = true;
        }
        if (_leaving) {
          // Fades out over a second and a half from full strength.
          _level -= dt / 1.5;
          if (_level <= 0) _stop();
        } else {
          _level = math.min(1.0, _level + dt / speed.seconds);
        }
      }
    }

    frame.value++;
    if (!_busy) _ticker.stop();
  }

  /// Whether anything is playing or about to.
  bool get _busy =>
      active.value != null ||
      _self.isNotEmpty ||
      _onScreen.any((id) => !_hushed.contains(id));
}

class _Entry {
  _Entry(this.effect, this.box);

  final LivingEffect effect;
  final RenderBox? Function() box;
}
