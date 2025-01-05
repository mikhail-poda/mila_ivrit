import 'dart:html' as html;
import 'web_utils.dart';

class WebUtilsWeb implements WebUtils {
  DateTime? _lastEventTime;
  static const Duration _minEventInterval = Duration(milliseconds: 1000);

  @override
  void initializeLifecycleListeners(Function saveCallback) {
    void handleSaveEvent() {
      final now = DateTime.now();
      if (_lastEventTime != null &&
          now.difference(_lastEventTime!) < _minEventInterval) {
        return;
      }
      _lastEventTime = now;
      saveCallback();
    }

    html.window.onBeforeUnload.listen((event) {
      handleSaveEvent();
    });

    html.document.onVisibilityChange.listen((event) {
      if (html.document.hidden ?? false) {
        handleSaveEvent();
      }
    });
  }
}

WebUtils getWebUtils() => WebUtilsWeb();