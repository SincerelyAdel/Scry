import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/feed_fetcher.dart';
import '../../services/ranobes.dart';
import '../../services/ranobes_session.dart';
import '../../state/novels_provider.dart';
import '../../theme.dart';

/// Opens ranobes.net in an in-app browser so the person can pass its
/// image-matching "are you human" check. Resolves to true once it's
/// passed and the browser's identity is saved for the app's own requests.
Future<bool> passHumanCheck(BuildContext context, String url) async {
  final novels = context.read<NovelsProvider>();
  final passed = await Navigator.of(
    context,
  ).push<bool>(MaterialPageRoute(builder: (_) => HumanCheckScreen(url: url)));
  if (passed == true) novels.humanCheckPassed();
  return passed == true;
}

/// A "Verify I'm human" button when [error] is ranobes.net's check, else
/// null. [onPassed] runs once it's passed, to try again.
Widget? humanCheckAction(
  BuildContext context,
  Object? error,
  VoidCallback onPassed,
) {
  if (error is! HumanCheckRequired) return null;
  return FilledButton.icon(
    onPressed: () async {
      if (await passHumanCheck(context, error.url)) onPassed();
    },
    icon: const Icon(Icons.verified_user_outlined),
    label: const Text("Verify I'm human"),
  );
}

/// The same as a snack bar, for errors shown that way.
void showHumanCheckSnack(
  BuildContext context,
  HumanCheckRequired error,
  VoidCallback onPassed,
) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 10),
        content: const Text("ranobes.net wants to check you're human"),
        action: SnackBarAction(
          label: 'Verify',
          onPressed: () async {
            if (await passHumanCheck(context, error.url)) onPassed();
          },
        ),
      ),
    );
}

class HumanCheckScreen extends StatefulWidget {
  const HumanCheckScreen({super.key, required this.url});

  final String url;

  @override
  State<HumanCheckScreen> createState() => _HumanCheckScreenState();
}

class _HumanCheckScreenState extends State<HumanCheckScreen> {
  /// Reads the in-app browser's cookies (see MainActivity.kt).
  static const _cookies = MethodChannel('scry/cookies');

  late final WebViewController _web;
  bool _saving = false;

  /// The page is loading or being tidied; hidden meanwhile.
  bool _loading = true;

  /// Passed: shows a tick for a moment before closing.
  bool _passed = false;

  /// Show the site as it is, when tidying hid something needed.
  bool _fullPage = false;

  /// True when the page is the site's real content (search results, a
  /// novel, a chapter or a chapter list), not the check.
  static const _realPageScript = r"""
    !!(document.querySelector('#arrticle, .r-fullstory-spec, article.shortstory')
       || /window\.__DATA__/.test(document.documentElement.innerHTML))
  """;

  /// Hides the website around the check (header, menus, ads, footer), so
  /// only the puzzle shows, on Scry's background. Finds the check by the
  /// usual names for it, then the smallest block around it holding both
  /// pictures and the instructions. Leaves the page alone when it finds
  /// nothing.
  static String _tidyScript(AppPalette c) {
    String hex(Color color) =>
        '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    return _tidyTemplate
        .replaceAll('BG_COLOR', hex(c.bg))
        .replaceAll('TEXT_COLOR', hex(c.text))
        .replaceAll('BUTTON_COLOR', hex(c.button))
        .replaceAll('ON_BUTTON', hex(c.onButton));
  }

  static const _tidyTemplate = r"""
(function () {
  var names = ['captcha', 'challenge', 'antibot', 'robot', 'human', 'verify'];
  var target = null;
  outer:
  for (var i = 0; i < names.length; i++) {
    var n = names[i];
    var found = document.querySelectorAll(
      '[id*="' + n + '" i], [class*="' + n + '" i], form[action*="' + n + '" i]');
    for (var j = 0; j < found.length; j++) {
      if (found[j].offsetHeight > 40) { target = found[j]; break outer; }
    }
  }
  if (!target) {
    var forms = document.querySelectorAll('form');
    for (var k = 0; k < forms.length; k++) {
      if (forms[k].querySelector('img, canvas, input[type="radio"], button')) {
        target = forms[k]; break;
      }
    }
  }
  if (!target) return 'none';
  function enough(el) {
    return el.querySelector('img, canvas, svg, [style*="background"]') &&
      (el.innerText || '').trim().length >= 15;
  }
  for (var up = 0; up < 5 && !enough(target) && target.parentElement &&
       target.parentElement !== document.body; up++) {
    target = target.parentElement;
  }
  var node = target;
  while (node && node !== document.body && node.parentElement) {
    var parent = node.parentElement;
    for (var c = 0; c < parent.children.length; c++) {
      var child = parent.children[c];
      if (child !== node && !/^(SCRIPT|STYLE|LINK)$/.test(child.tagName)) {
        child.style.setProperty('display', 'none', 'important');
      }
    }
    var reset = { margin: '0', padding: '0', background: 'transparent',
      border: '0', 'box-shadow': 'none', 'max-width': 'none', width: 'auto' };
    if (parent !== document.body) {
      for (var key in reset) parent.style.setProperty(key, reset[key], 'important');
    }
    node = parent;
  }
  target.style.setProperty('margin', '0 auto', 'important');
  target.style.setProperty('max-width', '100%', 'important');
  target.style.setProperty('box-sizing', 'border-box', 'important');
  var style = document.createElement('style');
  style.textContent =
    'html, body { background: BG_COLOR !important; margin: 0 !important; }' +
    'body { padding: 16px !important; box-sizing: border-box;' +
    ' color: TEXT_COLOR !important; font: 15px/1.45 sans-serif !important; }' +
    'body * { color: TEXT_COLOR !important; background-color: transparent; }' +
    'img { max-width: 100% !important; height: auto; border-radius: 8px; }' +
    'button, input[type="submit"], input[type="button"] {' +
    ' background: BUTTON_COLOR !important; color: ON_BUTTON !important;' +
    ' border: 0 !important; border-radius: 12px !important;' +
    ' padding: 10px 20px !important; font-weight: 600 !important; }';
  document.head.appendChild(style);
  var meta = document.querySelector('meta[name="viewport"]');
  if (!meta) {
    meta = document.createElement('meta');
    meta.name = 'viewport';
    document.head.appendChild(meta);
  }
  meta.content = 'width=device-width, initial-scale=1';
  return 'ok';
})()
""";

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted && !_passed) setState(() => _loading = true);
          },
          onPageFinished: _onLoaded,
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _web.setBackgroundColor(context.palette.bg).ignore();
  }

  Future<void> _onLoaded(String _) async {
    if (_saving) return;
    try {
      final real = await _web.runJavaScriptReturningResult(_realPageScript);
      // Android hands back a bool; other platforms may give 'true' or 1.
      if (real == true || real == 'true' || real == 1) {
        await _finish();
        return;
      }
      if (!_fullPage && mounted) {
        await _web.runJavaScript(_tidyScript(context.palette));
      }
    } on Exception {
      // The page is still changing; the next load checks again.
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Saves the browser's user agent and the site's cookies, then closes.
  Future<void> _finish() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _passed = true;
      _loading = false;
    });
    final agent = await _web.getUserAgent();
    // Includes the cookies scripts can't see, which is where sites
    // usually keep the "check passed" token.
    final cookies = await _cookies.invokeMethod<String>('get', {
      'url': Ranobes.origin,
    });
    await RanobesSession.save(
      userAgent: agent != null && agent.isNotEmpty
          ? agent
          : RanobesSession.userAgent,
      cookies: cookies ?? '',
    );
    // A moment to see the tick.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (mounted) Navigator.of(context).pop(true);
  }

  void _toggleFullPage() {
    setState(() {
      _fullPage = !_fullPage;
      _loading = true;
    });
    _web.reload();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: const Text('Quick check'),
        actions: [
          IconButton(
            tooltip: _fullPage ? 'Show only the check' : 'Show the whole page',
            icon: Icon(
              _fullPage ? Icons.crop_free : Icons.open_in_full,
              size: 20,
            ),
            onPressed: _saving ? null : _toggleFullPage,
          ),
          TextButton(
            onPressed: _saving ? null : _finish,
            child: const Text('Done'),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c.accent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.verified_user_outlined,
                      color: c.accent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'ranobes.net checks now and then that a person is '
                      "reading. Pick the matching picture; Scry carries on "
                      "by itself once it's passed.",
                      style: TextStyle(
                        color: c.muted,
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.bg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: c.border),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(17),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Hidden while loading, so the untidied site
                        // doesn't flash up first.
                        Opacity(
                          opacity: _loading || _passed ? 0 : 1,
                          child: WebViewWidget(controller: _web),
                        ),
                        if (_loading)
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(),
                                const SizedBox(height: 14),
                                Text(
                                  'Opening the check…',
                                  style: TextStyle(color: c.muted),
                                ),
                              ],
                            ),
                          ),
                        if (_passed) const _Verified(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The tick shown once the check is passed.
class _Verified extends StatelessWidget {
  const _Verified();

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.6, end: 1),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
        builder: (_, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: c.success, size: 64),
            const SizedBox(height: 10),
            Text(
              'Verified',
              style: TextStyle(fontFamily: kSerif, color: c.text, fontSize: 22),
            ),
          ],
        ),
      ),
    );
  }
}
