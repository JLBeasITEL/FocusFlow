// Cubre el indicador de progreso de recurrencia en la tarjeta de la lista
// (C7): "N de M" en modo repeticiones, "N completadas" sin denominador en
// modo fecha, y ausente cuando no hay límite puesto. Solo se prueba
// TareaLandscapeCard (widget standalone, fácil de aislar); el ListTile de
// home_screen.dart usa el mismo getter ya cubierto por
// tarea_limite_recurrencia_test.dart (Tarea.textoProgresoRecurrencia) y se
// verifica manualmente en dispositivo (ver checkpoint C7).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_tareas/models/tarea.dart';
import 'package:app_tareas/presentation/widgets/tarea_card_landscape.dart';
import 'package:app_tareas/providers/tema_provider.dart';

Tarea _tareaRecurrente({
  ModoLimiteRecurrencia modo = ModoLimiteRecurrencia.ninguno,
  int? repeticionesMaximas,
  int ocurrenciasCompletadas = 0,
}) {
  final fechaFutura = DateTime.now().add(const Duration(days: 5));
  return Tarea(
    id: 'cuota-1',
    titulo: 'Cuota crédito',
    urgenciaBase: 1,
    fechaLimite: fechaFutura,
    tipoRecurrencia: TipoRecurrencia.meses,
    intervalo: 1,
    diaAncla: fechaFutura.day,
    modoLimiteRecurrencia: modo,
    repeticionesMaximas: repeticionesMaximas,
    fechaLimiteRecurrencia: modo == ModoLimiteRecurrencia.fecha ? fechaFutura.add(const Duration(days: 300)) : null,
    ocurrenciasCompletadas: ocurrenciasCompletadas,
  );
}

Future<void> _pumpTarjeta(WidgetTester tester, Tarea tarea) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 260, child: TareaLandscapeCard(tarea: tarea, tema: TemaApp.clasico)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // La tarjeta formatea la fecha con DateFormat(..., 'es') sin importar
    // si hay o no límite de recurrencia; sin esto la carga de la tarjeta
    // lanza LocaleDataException.
    await initializeDateFormatting('es');
  });

  testWidgets('modo repeticiones muestra "N de M" junto al ícono de recurrencia', (tester) async {
    await _pumpTarjeta(
      tester,
      _tareaRecurrente(modo: ModoLimiteRecurrencia.repeticiones, repeticionesMaximas: 12, ocurrenciasCompletadas: 4),
    );

    expect(find.textContaining('4 de 12'), findsOneWidget);
  });

  testWidgets('modo fecha muestra "N completadas" sin denominador', (tester) async {
    await _pumpTarjeta(tester, _tareaRecurrente(modo: ModoLimiteRecurrencia.fecha, ocurrenciasCompletadas: 7));

    expect(find.textContaining('7 completadas'), findsOneWidget);
    expect(find.textContaining('7 de'), findsNothing);
  });

  testWidgets('sin límite no muestra ningún indicador de progreso', (tester) async {
    await _pumpTarjeta(tester, _tareaRecurrente());

    expect(find.textContaining(' de '), findsNothing);
    expect(find.textContaining('completadas'), findsNothing);
  });
}
