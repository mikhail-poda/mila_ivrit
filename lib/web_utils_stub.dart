import 'web_utils.dart';

class WebUtilsStub implements WebUtils {
  @override
  void initializeLifecycleListeners(Function saveCallback) {
    // Do nothing on non-web platforms
  }
}

WebUtils getWebUtils() => WebUtilsStub();