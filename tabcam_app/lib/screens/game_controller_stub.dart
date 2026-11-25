/// Off the web, the controllers come through the app's own code, on the
/// channel ([GameController.start]): nothing to watch here.
library;

/// Does nothing: only the web watches the browser's controllers.
void watchControllers(void Function(Set<int> pressed) buttons) {}
