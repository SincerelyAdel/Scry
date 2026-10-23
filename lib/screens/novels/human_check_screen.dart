import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

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
  InAppWebViewController? _web;
  bool _saving = false;

  /// True when the page is the site's real content (search results, a
  /// novel, a chapter or a chapter list), not the check.
  static const _realPageScript = '''
    !!(document.querySelector('#arrticle, .r-fullstory-spec, article.shortstory')
       || /window\\.__DATA__/.test(document.documentElement.innerHTML))
  ''';

  Future<void> _onLoaded(InAppWebViewController web) async {
    if (_saving) return;
    final real = await web.evaluateJavascript(source: _realPageScript);
    if (real == true) await _finish();
  }

  /// Saves the browser's user agent and the site's cookies, then closes.
  Future<void> _finish() async {
    final web = _web;
    if (web == null || _saving) return;
    setState(() => _saving = true);
    final agent = await web.evaluateJavascript(source: 'navigator.userAgent');
    // Includes the cookies scripts can't see, which is where sites
    // usually keep the "check passed" token.
    final cookies = await CookieManager.instance().getCookies(
      url: WebUri(Ranobes.origin),
    );
    await RanobesSession.save(
      userAgent: agent is String && agent.isNotEmpty
          ? agent
          : RanobesSession.userAgent,
      cookies: cookies.map((c) => '${c.name}=${c.value}').join('; '),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify on ranobes.net'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _finish,
            child: const Text('Done'),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              'The site wants to check you\'re human. Match the pictures '
              'below; Scry continues on its own once the page opens.',
              style: TextStyle(color: c.muted, fontSize: 13.5, height: 1.4),
            ),
          ),
          Divider(height: 1, color: c.border),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.url)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                thirdPartyCookiesEnabled: true,
              ),
              onWebViewCreated: (web) => _web = web,
              onLoadStop: (web, _) => _onLoaded(web),
            ),
          ),
        ],
      ),
    );
  }
}
