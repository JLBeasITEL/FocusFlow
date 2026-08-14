import 'widget_rutinas_service.dart';
import 'widget_tareas_service.dart';

// home_widget solo admite UN callback headless global por app
// (HomeWidget.registerInteractivityCallback reemplaza el handle anterior en
// vez de apilarlos), así que todos los widgets interactivos despachan desde
// acá según el host del Uri en vez de registrar cada uno el suyo.
@pragma('vm:entry-point')
Future<void> widgetsBackgroundCallback(Uri? uri) async {
  // tareasWidgetBackgroundCallback ya se auto-filtra por host
  // ('toggle_modo_tareas'); llamarlo siempre es un no-op para el resto.
  await tareasWidgetBackgroundCallback(uri);

  if (uri?.host == 'refrescar_rutinas') {
    await WidgetRutinasService.actualizar();
  }
}
