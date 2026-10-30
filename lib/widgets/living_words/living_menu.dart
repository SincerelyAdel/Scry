import 'package:flutter/material.dart';

import '../../state/settings_provider.dart';
import '../../theme.dart';
import '../popover_menu.dart';
import 'lexicon.dart';

/// The living-words button in the reader's bar, beside the cats. Its panel
/// turns the effects on or off, the page's mood with them, and how quickly
/// a word grows.
class LivingWordsMenuButton extends StatelessWidget {
  const LivingWordsMenuButton({
    super.key,
    required this.on,
    required this.mood,
    required this.speed,
    required this.playing,
    required this.onChanged,
    required this.onMood,
    required this.onSpeed,
  });

  final bool on;
  final bool mood;
  final LivingSpeed speed;

  /// The effect playing now, shown in the panel.
  final ValueNotifier<LivingEffect?> playing;

  final ValueChanged<bool> onChanged;
  final ValueChanged<bool> onMood;
  final ValueChanged<LivingSpeed> onSpeed;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return PopoverButton(
      tooltip: 'Living words',
      icon: on
          ? ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (b) => c.goldViolet().createShader(b),
              child: const Icon(Icons.auto_awesome, color: Colors.white),
            )
          : Icon(Icons.auto_awesome_outlined, color: c.muted),
      panel: (context) => PopoverPanel(
        children: [
          PopoverSwitch(
            icon: Icon(
              on ? Icons.auto_awesome : Icons.auto_awesome_outlined,
              size: 22,
              color: on ? c.accent : c.muted,
            ),
            title: 'Living words',
            subtitle: 'Words like fire and venom come alive',
            value: on,
            onChanged: onChanged,
          ),
          if (on) ...[
            const PopoverDivider(),
            PopoverSwitch(
              icon: Icon(Icons.wallpaper_outlined, size: 22, color: c.muted),
              title: 'Page mood',
              subtitle: "The page takes on the word's mood",
              value: mood,
              onChanged: onMood,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Center(
                      child: Icon(Icons.speed, size: 22, color: c.muted),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: PopoverLabel(
                      title: 'Grows',
                      subtitle: 'How quickly a word takes hold',
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<LivingSpeed>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: [
                    for (final s in LivingSpeed.values)
                      ButtonSegment(value: s, label: Text(s.label)),
                  ],
                  selected: {speed},
                  onSelectionChanged: (v) => onSpeed(v.first),
                ),
              ),
            ),
            ValueListenableBuilder<LivingEffect?>(
              valueListenable: playing,
              builder: (_, effect, _) => PopoverHint(
                icon: effect == null
                    ? Icons.info_outline
                    : Icons.play_circle_outline,
                text: effect == null
                    ? 'Tap a word to lead the page; tap it again to silence it.'
                    : 'Leading: ${effect.label}. Tap it to silence.',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
