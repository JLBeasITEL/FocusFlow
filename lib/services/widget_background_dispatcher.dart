import 'widget_tareas_service.dart';
import 'widget_notas_service.dart';
import 'widget_progreso_service.dart';

// home_widget solo admite UN callback headless global por app
// (HomeWidget.registerInteractivityCallback reemplaza el handle anterior en
// vez de apilarlos), así que todos los widgets interactivos que necesitan
// correr código SIN abrir la app despachan desde acá según el host del Uri.
@pragma('vm:entry-point')
Future<void> widgetsBackgroundCallback(Uri? uri) async {
  // Cada callback ya se auto-filtra por su propio host
  // ('toggle_modo_tareas' / 'toggle_cantidad_notas' / 'refrescar_progreso');
  // llamarlos siempre es un no-op para el resto.
  await tareasWidgetBackgroundCallback(uri);
  await notasWidgetBackgroundCallback(uri);
  await progresoWidgetBackgroundCallback(uri);
}
