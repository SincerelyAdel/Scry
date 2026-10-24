import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/settings_screen.dart';
import '../state/settings_provider.dart';
import '../theme.dart';

/// Shared with [AppHeader] so it can push pages from above the navigator.
final navigatorKey = GlobalKey<NavigatorState>();

/// The Scry bar fixed at the top of every page: the app name (tap it
/// to go back to the start), the Feeds / Novels switch, a light/dark toggle
/// and Settings. It sits above
/// the navigator, so it never scrolls away or slides out with a page.
class AppHeader extends StatefulWidget {
  const AppHeader({super.key});

  static const height = 52.0;

  @override
  State<AppHeader> createState() => _AppHeaderState();
}

class _AppHeaderState extends State<AppHeader> {
  bool _settingsOpen = false;

  void _home() => navigatorKey.currentState?.popUntil((r) => r.isFirst);

  Future<void> _settings() async {
    final nav = navigatorKey.currentState;
    if (nav == null || _settingsOpen) return;
    _settingsOpen = true;
    await nav.push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    _settingsOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    // No tooltips: the header sits outside the navigator's overlay.
    Widget button(IconData icon, String label, VoidCallback onTap) => Semantics(
      label: label,
      button: true,
      child: IconButton(
        icon: Icon(icon, color: c.muted, size: 22),
        onPressed: onTap,
      ),
    );
    return Material(
      color: c.bg,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: AppHeader.height,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.border)),
          ),
          child: Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _home,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Gold into the icon's purple.
                      ShaderMask(
                        blendMode: BlendMode.srcIn,
                        shaderCallback: (bounds) =>
                            c.goldViolet().createShader(bounds),
                        child: const Icon(Icons.auto_awesome, size: 22),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Scry',
                        style: TextStyle(
                          fontFamily: kSerif,
                          color: c.text,
                          fontSize: 21,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const _ModeSwitch(),
              const Spacer(),
              button(
                c.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                c.isDark ? 'Light mode' : 'Dark mode',
                () => context.read<SettingsProvider>().setThemeMode(
                  c.isDark ? ThemeMode.light : ThemeMode.dark,
                ),
              ),
              button(Icons.settings_outlined, 'Settings', _settings),
            ],
          ),
        ),
      ),
    );
  }
}

/// Feeds or Novels: two pills, the chosen one filled. Switching closes any
/// open pages first.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch();

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final mode = context.select<SettingsProvider, AppMode>((s) => s.mode);

    Widget pill(AppMode value, IconData icon, String label) {
      final selected = mode == value;
      return Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (selected) return;
            navigatorKey.currentState?.popUntil((r) => r.isFirst);
            context.read<SettingsProvider>().setMode(value);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? c.button : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: selected ? c.onButton : c.muted),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? c.onButton : c.muted,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          pill(AppMode.feeds, Icons.rss_feed, 'Feeds'),
          pill(AppMode.novels, Icons.auto_stories_outlined, 'Novels'),
        ],
      ),
    );
  }
}
