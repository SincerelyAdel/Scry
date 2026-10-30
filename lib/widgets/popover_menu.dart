import 'package:flutter/material.dart';

import '../theme.dart';

/// An icon button in a bar that opens a small panel, growing out of the
/// button. A tap anywhere else closes it.
class PopoverButton extends StatefulWidget {
  const PopoverButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.panel,
  });

  final String tooltip;
  final Widget icon;

  /// Built while open, so it follows the latest state.
  final WidgetBuilder panel;

  @override
  State<PopoverButton> createState() => _PopoverButtonState();
}

class _PopoverButtonState extends State<PopoverButton>
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
                    child: widget.panel(context),
                  ),
                ),
              ),
            ),
          ),
          child: IconButton(
            tooltip: widget.tooltip,
            onPressed: _toggle,
            icon: widget.icon,
          ),
        ),
      ),
    );
  }
}

/// The panel's card: rows stacked, resizing smoothly as rows come and go.
class PopoverPanel extends StatelessWidget {
  const PopoverPanel({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
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
            child: Column(mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
      ),
    );
  }
}

/// A row with an icon, a title and line of explanation, and a switch.
class PopoverSwitch extends StatelessWidget {
  const PopoverSwitch({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final Widget icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
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
              child: PopoverLabel(title: title, subtitle: subtitle),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// A title over a muted line of explanation.
class PopoverLabel extends StatelessWidget {
  const PopoverLabel({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Column(
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
        Text(subtitle, style: TextStyle(color: c.muted, fontSize: 12.5)),
      ],
    );
  }
}

/// A thin rule between the main switch and the rest.
class PopoverDivider extends StatelessWidget {
  const PopoverDivider({super.key});

  @override
  Widget build(BuildContext context) => Divider(
    height: 8,
    indent: 12,
    endIndent: 12,
    color: context.palette.border,
  );
}

/// A small faint hint at the bottom of a panel.
class PopoverHint extends StatelessWidget {
  const PopoverHint({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: c.faint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: c.faint, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}
