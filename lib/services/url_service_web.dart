import 'dart:html' as html;

class UrlService {
  static Uri currentUri() => Uri.parse(html.window.location.href);
  static void replaceUrl(String url) => html.window.history.replaceState(null, '', url);
}
