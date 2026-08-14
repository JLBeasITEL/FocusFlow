import 'rutina_completar_headless.dart';
import 'widget_tareas_service.dart';

// home_widget solo admite UN callback headless global por app
// (HomeWidget.registerInteractivityCallback reemplaza el handle anterior en
// vez de apilarlos), así que todos los widgets interactivos que necesitan
// correr código SIN abrir la app despachan desde acá según el host del Uri.
@pragma('vm:entry-point')
Future<void> widgetsBackgroundCallback(Uri? uri) async {
  // tareasWidgetBackgroundCallback ya se auto-filtra por host
  // ('toggle_modo_tareas'); llamarlo siempre es un no-op para el resto.
  await tareasWidgetBackgroundCallback(uri);

  if (uri?.host == 'completar_rutina') {
    final id = uri?.queryParameters['id'];
    if (id != null && id.isNotEmpty) {
      await completarRutinaHeadless(id);
    }
  }
}
