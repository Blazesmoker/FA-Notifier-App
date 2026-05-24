import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

class InfoIconButton extends StatelessWidget {
  final String url;
  final String title;

  const InfoIconButton({
    Key? key,
    this.url = 'https://www.furaffinity.net/help/#tags-and-codes',
    this.title = 'Tags & Codes',
  }) : super(key: key);

  Future<void> _openDialog(BuildContext context) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const InfoWebViewDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: IconButton(
        tooltip: title,
        icon: const Icon(Icons.info_outline),
        onPressed: () => _openDialog(context),
      ),
    );
  }
}

class InfoWebViewDialog extends StatefulWidget {
  const InfoWebViewDialog({Key? key}) : super(key: key);

  @override
  State<InfoWebViewDialog> createState() => _InfoWebViewDialogState();
}

class _InfoWebViewDialogState extends State<InfoWebViewDialog> {
  InAppWebViewController? _controller;
  bool _isLoading = true;
  String? _errorMessage;

  static const String _hardcodedHtml = r'''
<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1.0"/>
  <title>Tags & Codes</title>
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }
    html, body {
      width: 100%;
      height: 100%;
      background: #0f1112;
      color: #c9d1d9;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      font-size: 14px;
      line-height: 1.5;
      overflow-x: hidden;
    }
    body {
      display: flex;
      justify-content: center;
      padding: 16px;
      overflow-y: auto;
    }
    .container {
      width: 100%;
      max-width: 800px;
    }
    .policy-item {
      background: #161b22;
      border: 1px solid #30363d;
      border-radius: 6px;
      padding: 16px;
    }
    .policy-list-row {
      margin-bottom: 20px;
      padding-bottom: 16px;
      border-bottom: 1px solid #21262d;
    }
    .policy-list-row:last-child {
      margin-bottom: 0;
      padding-bottom: 0;
      border-bottom: none;
    }
    h4 {
      color: #add8f5;
      font-size: 16px;
      font-weight: 600;
      margin-bottom: 12px;
    }
    p {
      margin-bottom: 8px;
      line-height: 1.6;
      word-wrap: break-word;
    }
    code {
      background: #0d1117;
      border: 1px solid #30363d;
      border-radius: 3px;
      padding: 2px 6px;
      font-family: 'Courier New', Courier, monospace;
      font-size: 13px;
      color: #79c0ff;
      white-space: pre-wrap;
      word-break: break-all;
    }
    br {
      display: block;
      content: "";
      margin: 4px 0;
    }
    b {
      font-weight: bold;
    }
    i {
      font-style: italic;
    }
    u {
      text-decoration: underline;
    }
    s {
      text-decoration: line-through;
    }
    sup {
      vertical-align: super;
      font-size: smaller;
    }
    sub {
      vertical-align: sub;
      font-size: smaller;
    }
    span.bbcode {
      display: inline;
    }
    span.bbcode_spoiler {
      background: #30363d;
      color: #30363d;
      padding: 2px 4px;
      border-radius: 3px;
      cursor: pointer;
      user-select: none;
      transition: color 0.2s ease;
    }
    span.bbcode_spoiler.revealed {
      color: #c9d1d9;
      background: #0d1117;
    }
    .bbcode_quote {
      display: block;
      background: #0d1117;
      border-left: 3px solid #58a6ff;
      padding: 8px 12px;
      margin: 8px 0;
      font-style: italic;
    }
    .bbcode_quote_name {
      display: block;
      font-weight: bold;
      margin-bottom: 4px;
      color: #58a6ff;
    }
    .bbcode_left {
      display: block;
      text-align: left;
    }
    .bbcode_center {
      display: block;
      text-align: center;
    }
    .bbcode_right {
      display: block;
      text-align: right;
    }
    h1.bbcode_h1 {
      font-size: 28px;
      font-weight: bold;
      margin: 12px 0;
      color: #c9d1d9;
    }
    h2.bbcode_h2 {
      font-size: 24px;
      font-weight: bold;
      margin: 10px 0;
      color: #c9d1d9;
    }
    h3.bbcode_h3 {
      font-size: 20px;
      font-weight: bold;
      margin: 8px 0;
      color: #c9d1d9;
    }
    h4.bbcode_h4 {
      font-size: 16px;
      font-weight: bold;
      margin: 6px 0;
      color: #c9d1d9;
    }
    h5.bbcode_h5 {
      font-size: 14px;
      font-weight: bold;
      margin: 4px 0;
      color: #c9d1d9;
    }
    hr {
  border: none;
  height: 1px;
  margin: 12px 0;
  background: linear-gradient(
    to right,
    transparent,
    #7d7d7d,
    transparent
  );
}
    a {
      color: #58a6ff;
      text-decoration: none;
      pointer-events: none;
      word-break: break-all;
    }
    .iconusername {
      display: inline-flex;
      align-items: center;
    }
    .iconusername img {
      vertical-align: middle;
      margin-right: 4px;
      max-width: 50px;
      max-height: 50px;
    }
    strong {
      font-weight: bold;
      color: #c9d1d9;
    }
    .parsed_nav_links {
      display: inline-block;
    }
    .link-block {
      display: block;
      margin: 8px 0;
      word-wrap: break-word;
    }
  </style>
  <script>
    document.addEventListener('DOMContentLoaded', function() {
      const spoilers = document.querySelectorAll('.bbcode_spoiler');
      spoilers.forEach(function(spoiler) {
        spoiler.addEventListener('click', function() {
          this.classList.toggle('revealed');
        });
      });
    });
  </script>
</head>
<body>
  <div class="container">
    <div class="policy-item policy-list user-submitted-links">
      <div class="policy-list-row">
        <h4>Text Formatting</h4>
        <p>
          <code>[b]bold text[/b]</code> <b class="bbcode bbcode_b">Bold Text</b>. Shortcut: CTRL+B<br>
          <code>[i]italic text[/i]</code> <i class="bbcode bbcode_i">Italic Text</i>. Shortcut: CTRL+I<br>
          <code>[u]underlined text[/u]</code> <u class="bbcode bbcode_u">Underlined Text</u>. Shortcut: CTRL+U<br>
          <code>[s]strike out text[/s]</code> <s class="bbcode bbcode_s">Strike Out Text</s><br>
          <code>Text [sup]supscripted[/sup]</code> Text <sup class="bbcode bbcode_sup">supscripted</sup><br>
          <code>Text [sub]subscripted[/sub]</code> Text <sub class="bbcode bbcode_sub">subscripted</sub><br>
          <code>[color=green]text[/color]</code> This is <span class="bbcode" style="color: green;">green</span> and This is <span class="bbcode" style="color: #ffcc00;">#ffcc00</span>. You can use either the color name or the "hex color code" that starts with a "#".<br>
          <code>[spoiler]spoiler text[/spoiler]</code><span class="bbcode bbcode_spoiler">This is a spoiler!</span><br>
        </p>
      </div>

      <div class="policy-list-row">
        <h4>Text Codes</h4>
        <p>
          <code>(c)</code> All your base are belong to us ©<br>
          <code>(tm)</code> 'Sup™<br>
          <code>(r)</code> Spam®<br>
        </p>
      </div>

      <div class="policy-list-row">
        <h4>Headers</h4>
        [h1]H1 heading[/h1]<br> <h1 class="bbcode bbcode_h1">H1 heading</h1><br>
        [h2]H2 heading[/h2]<br> <h2 class="bbcode bbcode_h2">H2 heading</h2><br>
        [h3]H3 heading[/h3]<br> <h3 class="bbcode bbcode_h3">H3 heading</h3><br>
        [h4]H4 heading[/h4]<br> <h4 class="bbcode bbcode_h4">H4 heading</h4><br>
        [h5]H5 heading[/h5]<br> <h5 class="bbcode bbcode_h5">H5 heading</h5><br>
      </div>

      <div class="policy-list-row">
        <h4>Horizontal divider</h4>
        <p>More then 5 dashes in a line are replaced with a horizontal divider.</p>
        <p>-----</p>
        <hr>
        <p></p>
      </div>

      <div class="policy-list-row">
        <h4>Positioning</h4>
        <p>
          [left]Left aligned text [/left]<br>
          <code class="bbcode bbcode_left">Left aligned text </code><br>
          [center]Centered text [/center]<br>
          <code class="bbcode bbcode_center">Centered text </code><br>
          [right]Right aligned text [/right]
          <code class="bbcode bbcode_right">Right aligned text </code>
        </p>
      </div>

      <div class="policy-list-row">
        <h4>Quotes</h4>
        <p>
          [quote]Example text.[/quote]
          <span class="bbcode bbcode_quote">Example text.</span><br>
          [quote=Fender]Example text.[/quote]
          <span class="bbcode bbcode_quote"><span class="bbcode_quote_name">Fender wrote:</span>Example text.</span>
        </p>
        <p><strong>Note:</strong> Nested quotes are not supported.</p>
      </div>

      <div class="policy-list-row">
        <h4>Links</h4>
        <p>
          Links automatically translate to recognized URLs, such as 
          <span class="link-block"><a href="https://www.furaffinity.net" title="https://www.furaffinity.net" class="auto_link">https://www.furaffinity.net</a>.</span>
        </p>
        <p>
          <code>[url=https://www.furaffinity.net/user/fender]Fender's page[/url]</code>
          <span class="link-block">Result: <a class="auto_link " href="https://www.furaffinity.net/user/fender">Fender's page</a></span>
        </p>
        <p>
          <code>[url=/user/fender]Relative Fender's Page[/url]</code>
          <span class="link-block">Result: <a class="auto_link external" href="https://www.furaffinity.net/user/fender" rel="nofollow ugc noreferrer noopener">Relative Fender's page</a></span>
        </p>
        <p>Long URLs will be automatically compressed to the first 60 or 70 or so characters.</p>
      </div>

      <div class="policy-list-row">
        <h4>YouTube</h4>
        <p>
          <span class="link-block"><code>[yt]https://www.youtube.com/embed/Qit3ALTelOo[/yt]</code></span>
          <strong>Note:</strong> YouTube embedding <i>only works</i> in journal bodies, nowhere else.<br>
          <br>
          <span class="link-block">Both https://www.youtube.com/watch?v=Qit3ALTelOo full video URLs and https://youtu.be/Qit3ALTelOo "share" URLs are supported.</span>
        </p>
      </div>

      <div class="policy-list-row">
        <h4>Icon Embedding</h4>
        <p>
          <code>:iconusername: or @@username</code> Add a user's avatar with their name tagged at the end.<br>
          <code>:iconfender:</code> <a href="/user/fender" class="iconusername"><img src="https://a.furaffinity.net/20260205/fender.gif" align="middle" title="fender" alt="fender">&nbsp;fender</a><br>
          <br>
          <code>:usernameicon:</code> Add a user's avatar <i>without</i> their the name.<br>
          <code>:fendericon:</code> <a href="/user/fender" class="iconusername"><img src="https://a.furaffinity.net/20260205/fender.gif" align="middle" title="fender" alt="fender"></a><br>
          <br>
          <code>:linkusername: or @username</code> Creates a link to a user's page.<br>
          <code>:linkfender:</code> <a href="/user/fender" class="linkusername">fender</a>
        </p>
      </div>

      <div class="policy-list-row">
        <h4>Comic Navigation</h4>
        <p>
          <code>[1896964, 1010790, 3277777]</code> <span class="parsed_nav_links"><a href="/view/1896964">&lt;&lt;&lt;&nbsp;PREV</a>&nbsp;|&nbsp;<a href="/view/1010790">FIRST</a>&nbsp;|&nbsp;<a href="/view/3277777">NEXT&nbsp;&gt;&gt;&gt;</a></span><br>
          <br>
          This is a quick way to create navigation links comics or submissions as part of a series.<br>
          <strong>Note:</strong> The numbers above represent the submission IDs.<br>
          <br>
          1. Only one whitespace character is allowed anywhere between the numbers, commas, and square brackets.<br>
          2. To disable a certain link, for example you don't have the "next" link on your latest piece or the "first" link on your first one, replace the ID with a dash, "-". and that link will be disabled.<br>
          3. Works only in submission descriptions.
        </p>
      </div>
    </div>
  </div>
</body>
</html>
''';

  @override
  void dispose() {
    try {
      _controller?.stopLoading();
    } catch (_) {}
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ds = MediaQuery.of(context).size;

    return Dialog(
      insetPadding: EdgeInsets.zero,
      backgroundColor: Colors.transparent,
      child: SizedBox(
        width: ds.width,
        height: ds.height,
        child: SafeArea(
          child: Scaffold(
            appBar: AppBar(
              backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
              elevation: 1,
              centerTitle: true,
              title: InkWell(
                onTap: () async {
                  final uri = Uri.parse(
                    'https://www.furaffinity.net/help/#tags-and-codes',
                  );
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(
                      Icons.open_in_new,
                      size: 22,
                    ),
                    SizedBox(width: 8),
                    Text('Tags & Codes'),
                  ],
                ),
              ),
              actions: [
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),

            body: Stack(
              children: [
                InAppWebView(
                  initialData: InAppWebViewInitialData(
                    data: _hardcodedHtml,
                    baseUrl: WebUri('https://www.furaffinity.net/help/#tags-and-codes'),
                    encoding: 'utf-8',
                    mimeType: 'text/html',
                  ),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    verticalScrollBarEnabled: true,
                    horizontalScrollBarEnabled: false,
                    transparentBackground: true,
                  ),
                  shouldOverrideUrlLoading: (controller, navigationAction) async {
                    final url = navigationAction.request.url;
                    if (url == null) {
                      return NavigationActionPolicy.ALLOW;
                    }

                    if (!navigationAction.isForMainFrame) {
                      return NavigationActionPolicy.ALLOW;
                    }

                    if (navigationAction.navigationType == NavigationType.LINK_ACTIVATED) {
                      final uri = Uri.tryParse(url.toString());
                      if (uri != null && await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                      return NavigationActionPolicy.CANCEL;
                    }

                    return NavigationActionPolicy.ALLOW;
                  },
                  onWebViewCreated: (controller) {
                    _controller = controller;
                  },
                  onLoadStop: (controller, uri) {
                    if (!mounted) return;
                    setState(() {
                      _isLoading = false;
                      _errorMessage = null;
                    });
                  },
                  onContentSizeChanged: (controller, oldContentSize, newContentSize) {
                    if (!mounted || !_isLoading) return;
                    if (newContentSize.width > 0 || newContentSize.height > 0) {
                      setState(() {
                        _isLoading = false;
                        _errorMessage = null;
                      });
                    }
                  },
                  onReceivedError: (controller, request, error) {
                    if (!mounted) return;
                    setState(() {
                      _isLoading = false;
                      _errorMessage =
                          'Page load error: ${error.description} (code ${error.type})';
                    });
                  },
                  onConsoleMessage: (controller, consoleMessage) {
                    try {
                      print('Console: ${consoleMessage.message}');
                    } catch (_) {}
                  },
                ),
                if (_isLoading)
                  const Positioned.fill(child: Center(child: CircularProgressIndicator())),
                if (!_isLoading && _errorMessage != null)
                  Positioned.fill(
                    child: Container(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _errorMessage!,
                                style: const TextStyle(fontSize: 16),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.open_in_new),
                                label: const Text('Open full page in browser'),
                                onPressed: () async {
                                  final uri = Uri.tryParse('https://www.furaffinity.net/help/#tags-and-codes');
                                  if (uri != null && await canLaunchUrl(uri)) {
                                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Cannot open external browser')),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
