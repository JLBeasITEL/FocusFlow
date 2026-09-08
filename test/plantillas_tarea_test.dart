// Ejercita el flujo real de "Plantillas" descrito por el usuario, corriendo
// el widget de producción (AddTareaModal) y sus providers reales contra
// SharedPreferences en memoria, sin reimplementar la lógica en el test:
// guardar el formulario actual como plantilla (dentro de "Más opciones"),
// reabrir el modal, aplicarla con "Usar plantilla" y renombrarla/eliminarla
// desde el lápiz ("Editar plantillas").
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_tareas/core/app_messenger.dart';
import 'package:app_tareas/presentation/widgets/add_tarea_modal.dart';

Future<void> _abrirModalNuevaTarea(WidgetTester tester) async {
  // Con Subtareas + Plantillas ahora dentro de "Más opciones", el modal
  // expandido es más alto y ancho que el viewport de prueba por defecto
  // (800x600): eso dejaba widgets fuera de pantalla (tap fallido) y hacía
  // que el Wrap de botones de plantillas se partiera en dos líneas.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        scaffoldMessengerKey: scaffoldMessengerKey,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const AddTareaModal(),
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

// Subtareas y Plantillas viven dentro de "Más opciones" y no se muestran
// hasta expandirla.
Future<void> _expandirMasOpciones(WidgetTester tester) async {
  await tester.tap(find.text('Más opciones (Descripción y Esfuerzo)'));
  await tester.pumpAndSettle();
}

// Las pantallas de diálogo del flujo ("Nuevo grupo", "Guardar como
// plantilla", "Renombrar plantilla") solo tienen un TextField cada una.
Future<void> _escribirEnDialogo(WidgetTester tester, String texto) async {
  final campo = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
  await tester.enterText(campo, texto);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('subtareas y plantillas están escondidas hasta expandir Más opciones', (tester) async {
    await _abrirModalNuevaTarea(tester);

    expect(find.text('Subtareas'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Guardar como plantilla'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Usar plantilla'), findsNothing);
    expect(find.byTooltip('Editar plantillas'), findsNothing);

    await _expandirMasOpciones(tester);

    expect(find.text('Subtareas'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Guardar como plantilla'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Usar plantilla'), findsOneWidget);
    expect(find.byTooltip('Editar plantillas'), findsOneWidget);
  });

  testWidgets('la sección de plantillas aparece debajo de Subtareas, con "Usar plantilla" entre Guardar y el lápiz', (tester) async {
    await _abrirModalNuevaTarea(tester);
    await _expandirMasOpciones(tester);

    final ySubtareas = tester.getTopLeft(find.text('Subtareas')).dy;
    final yWrapPlantillas = tester.getTopLeft(find.byType(Wrap)).dy;
    final yGuardarTarea = tester.getTopLeft(find.widgetWithText(ElevatedButton, 'Guardar')).dy;

    // Subtareas antes que la fila de plantillas, y esta antes del botón final.
    expect(ySubtareas, lessThan(yWrapPlantillas));
    expect(yWrapPlantillas, lessThan(yGuardarTarea));

    // "Usar plantilla" queda entre "Guardar como plantilla" y el lápiz: se
    // verifica el orden real de los hijos del Wrap (no coordenadas en
    // pantalla, que con Wrap dependen del ancho disponible y no son
    // confiables como prueba de orden).
    final wrap = tester.widget<Wrap>(find.byType(Wrap));
    expect(wrap.children, hasLength(3));
    bool tieneDescendiente(Widget child, Finder matching) =>
        find.descendant(of: find.byWidget(child), matching: matching).evaluate().isNotEmpty;
    expect(tieneDescendiente(wrap.children[0], find.text('Guardar como plantilla')), isTrue);
    expect(tieneDescendiente(wrap.children[1], find.text('Usar plantilla')), isTrue);
    expect(tieneDescendiente(wrap.children[2], find.byTooltip('Editar plantillas')), isTrue);
  });

  testWidgets('guardar como plantilla, reabrir el formulario y aplicarla con "Usar plantilla"', (tester) async {
    await _abrirModalNuevaTarea(tester);

    // Grupo distinto de 'General', para probar que también se guarda.
    await tester.tap(find.byTooltip('Nuevo grupo'));
    await tester.pumpAndSettle();
    await _escribirEnDialogo(tester, 'Casa');
    await tester.tap(find.widgetWithText(TextButton, 'Crear'));
    await tester.pumpAndSettle();
    expect(find.text('Casa'), findsOneWidget); // valor ahora seleccionado en el desplegable

    // Título
    await tester.enterText(find.widgetWithText(TextField, '¿Qué hay que hacer?'), 'Lavar el auto');
    await tester.pumpAndSettle();

    // Urgencia
    await tester.tap(find.text('Alto'));
    await tester.pumpAndSettle();
    expect(tester.widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>)).selected, {3});

    // Subtareas y Plantillas están dentro de "Más opciones".
    await _expandirMasOpciones(tester);

    // Subtarea
    await tester.tap(find.text('Subtareas'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Agregar paso...'), 'Enjabonar');
    await tester.tap(find.byIcon(Icons.add_circle));
    await tester.pumpAndSettle();
    expect(find.text('Enjabonar'), findsOneWidget);

    // Guardar como plantilla
    await tester.tap(find.widgetWithText(OutlinedButton, 'Guardar como plantilla'));
    await tester.pumpAndSettle();
    await _escribirEnDialogo(tester, 'Limpieza semanal');
    await tester.tap(find.widgetWithText(TextButton, 'Guardar'));
    // Pump acotado (no pumpAndSettle): el SnackBar vive 5s simulados y
    // pumpAndSettle avanzaría el reloj falso hasta que se auto-cierre solo,
    // dejando el texto invisible antes de poder revisarlo.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Plantilla "Limpieza semanal" guardada'), findsOneWidget);

    // Cerramos el modal (simulando que el usuario abandona sin guardar la
    // tarea) y abrimos uno completamente nuevo y en blanco.
    Navigator.of(tester.element(find.byType(AddTareaModal))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    // El formulario nuevo está vacío y "Más opciones" vuelve a estar cerrada.
    expect(find.widgetWithText(OutlinedButton, 'Usar plantilla'), findsNothing);
    await _expandirMasOpciones(tester);
    expect(tester.widget<TextField>(find.widgetWithText(TextField, '¿Qué hay que hacer?')).controller!.text, isEmpty);

    // "Usar plantilla" abre un selector; tocar la plantilla la aplica y cierra.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Usar plantilla'));
    await tester.pumpAndSettle();
    expect(find.text('Limpieza semanal'), findsOneWidget);
    expect(find.text('Lavar el auto'), findsOneWidget); // subtítulo con el título de la tarea
    // El selector no tiene íconos de renombrar/eliminar: solo elige.
    expect(find.byTooltip('Renombrar'), findsNothing);
    expect(find.byTooltip('Eliminar'), findsNothing);

    await tester.tap(find.text('Limpieza semanal'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Plantilla "Limpieza semanal" aplicada'), findsOneWidget);

    expect(tester.widget<TextField>(find.widgetWithText(TextField, '¿Qué hay que hacer?')).controller!.text, 'Lavar el auto');
    expect(find.text('Enjabonar'), findsOneWidget);
    expect(find.text('Casa'), findsOneWidget); // grupo restaurado
    expect(tester.widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>)).selected, {3});

    // Deja correr el timer de 5s del último SnackBar antes de que termine el
    // test: si no, flutter_test falla con "Timer is still pending".
    await tester.pumpAndSettle();
  });

  testWidgets('"Usar plantilla" sin plantillas guardadas avisa en vez de abrir un selector vacío', (tester) async {
    await _abrirModalNuevaTarea(tester);
    await _expandirMasOpciones(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Usar plantilla'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Todavía no tienes plantillas guardadas'), findsOneWidget);

    await tester.pumpAndSettle();
  });

  testWidgets('renombrar y eliminar una plantilla desde "Editar plantillas" (el lápiz)', (tester) async {
    await _abrirModalNuevaTarea(tester);
    await _expandirMasOpciones(tester);

    await tester.enterText(find.widgetWithText(TextField, '¿Qué hay que hacer?'), 'Regar las plantas');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Guardar como plantilla'));
    await tester.pumpAndSettle();
    await _escribirEnDialogo(tester, 'Riego semanal');
    await tester.tap(find.widgetWithText(TextButton, 'Guardar'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Editar plantillas'));
    await tester.pumpAndSettle();
    expect(find.text('Riego semanal'), findsOneWidget);

    // Tocar la fila en este diálogo NO aplica la plantilla (eso es cosa de
    // "Usar plantilla"): el diálogo sigue abierto.
    await tester.tap(find.text('Riego semanal'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    // Renombrar
    await tester.tap(find.byTooltip('Renombrar'));
    await tester.pumpAndSettle();
    await _escribirEnDialogo(tester, 'Riego de plantas');
    await tester.tap(find.widgetWithText(TextButton, 'Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Riego de plantas'), findsOneWidget);
    expect(find.text('Riego semanal'), findsNothing);

    // Eliminar (con confirmación)
    await tester.tap(find.byTooltip('Eliminar'));
    await tester.pumpAndSettle();
    expect(find.text('¿Eliminar la plantilla "Riego de plantas"?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Eliminar'));
    await tester.pumpAndSettle();

    expect(find.text('Riego de plantas'), findsNothing);
    expect(find.text('Todavía no tienes plantillas guardadas.'), findsOneWidget);
  });
}
