import 'web_utils_stub.dart'
if (dart.library.html) 'web_utils_web.dart';

abstract class WebUtils {
  static WebUtils getInstance() => getWebUtils();
  void initializeLifecycleListeners(Function saveCallback);
}