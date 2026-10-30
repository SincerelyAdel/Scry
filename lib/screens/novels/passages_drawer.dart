import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/passage.dart';
import '../../state/novels_provider.dart';
import '../../theme.dart';
import '../../widgets/passage_card.dart';
import 'library_screen.dart';

/// Holds the library with the saved passages behind it, on the left: a
/// swipe right anywhere opens them, a swipe left closes them again.
class PassagesDrawer extends StatefulWidget {
  const PassagesDrawer({super.key, required this.child});

  final Widget child;

  /// Opens the drawer from inside [child], as the header button does.
  static void open(BuildContext context) =>
      context.findAncestorStateOfType<_PassagesDrawerState>()?._open();

  @override
  State<PassagesDrawer> createState() => _PassagesDrawerState();
}

class _PassagesDrawerState extends State<PassagesDrawer>
    with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );

  double _width = 360;

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _open() => _anim.animateTo(1, curve: Curves.easeOutCubic);
  void _close() => _anim.animateTo(0, curve: Curves.easeOutCubic);

  void _drag(DragUpdateDetails d) {
    _anim.value += (d.primaryDelta ?? 0) / _width;
  }

  void _settle(DragEndDetails d) {
    final speed = d.primaryVelocity ?? 0;
    if (speed > 300) {
      _open();
    } else if (speed < -300) {
      _close();
    } else {
      _anim.value > 0.5 ? _open() : _close();
    }
  }

  Future<void> _openPassage(Passage p) async {
    final novels = context.read<NovelsProvider>();
    final novel = novels.byId(p.novelId);
    _close();
    if (novel == null) return;
    await openReader(
      context,
      novel,
      url: p.chapterUrl,
      number: p.chapterNumber,
      focus: (p.from, p.to),
    );
  }

  Future<void> _manage(Passage p) async {
    final novels = context.read<NovelsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Copy passage'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove from saved'),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'copy') {
      await Clipboard.setData(ClipboardData(text: p.text));
      messenger.showSnackBar(const SnackBar(content: Text('Passage copied')));
    } else if (choice == 'remove') {
      await novels.removePassage(p);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('Passage removed'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => novels.restorePassage(p),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    _width = size.width * 0.88 > 440 ? 440 : size.width * 0.88;
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final v = _anim.value;
        return PopScope(
          // Back closes the drawer first.
          canPop: v == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _close();
          },
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: _drag,
            onHorizontalDragEnd: _settle,
            child: Stack(
              children: [
                widget.child,
                if (v > 0)
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: _close,
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.32 * v),
                      ),
                    ),
                  ),
                if (v > 0)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: -_width * (1 - v),
                    width: _width,
                    child: _Panel(
                      onClose: _close,
                      onOpen: _openPassage,
                      onManage: _manage,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The saved passages, newest first.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.onClose,
    required this.onOpen,
    required this.onManage,
  });

  final VoidCallback onClose;
  final ValueChanged<Passage> onOpen;
  final ValueChanged<Passage> onManage;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final passages = context.watch<NovelsProvider>().passages;
    return Material(
      // A shade below the page, so the white cards stand up from it.
      color: dark ? c.bg : c.surfaceAlt,
      elevation: 16,
      shadowColor: Colors.black,
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: 'Saved passages',
                        children: [
                          if (passages.isNotEmpty)
                            TextSpan(
                              text: '  ${passages.length}',
                              style: TextStyle(
                                color: c.muted,
                                fontSize: 15,
                                fontFamily: kSerif,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                        ],
                      ),
                      style: TextStyle(
                        fontFamily: kSerif,
                        color: c.text,
                        fontSize: 21,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            Expanded(
              child: passages.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.bookmark_border,
                              size: 40,
                              color: c.accentLight,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No passages yet',
                              style: TextStyle(
                                fontFamily: kSerif,
                                color: c.text,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Hold a paragraph while reading to save it '
                              'here.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: c.muted,
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      itemCount: passages.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 16),
                      itemBuilder: (_, i) => PassageCard(
                        passage: passages[i],
                        onTap: () => onOpen(passages[i]),
                        onLongPress: () => onManage(passages[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
