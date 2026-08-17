import 'dart:convert';
import 'package:flutter/material.dart'; // Necesario para TimeOfDay
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/rutina.dart';
import '../services/notificaciones_service.dart';
import '../services/widget_rutinas_service.dart';
import '../services/widget_progreso_service.dart';
import 'monedas_provider.dart';

// ============================================================
// rachaPorMoneda — unidad fija del hito de racha que otorga moneda
// ------------------------------------------------------------
// FIJO en 7, sin importar cuántos días/semana tenga programada la
// rutina: antes se usaba rutina.horarios.length (diasPorSemana) como
// divisor, pero eso hacía que rutinas de pocos días/semana festejaran
// demasiado seguido (con 1 día/semana, CADA completada festejaba,
// porque cualquier racha % 1 == 0) y que el "hito semanal" no
// significara lo mismo entre rutinas. Con 7 fijo, el hito es el mismo
// para todas: racha=7 → 1 moneda, racha=14 → 2 monedas, racha=21 → 3,
// y así sucesivamente sin tope — compartido por rutina_card.dart (el
// diálogo de felicitación) y por toggleCompletada (el otorgamiento
// real), para que ambos disparen exactamente en los mismos hitos.
// ============================================================
const int rachaPorMoneda = 7;

class RutinaNotifier extends Notifier<List<Rutina>> {
  static const String _storageKey = 'lista_rutinas_v2';

  // Guard de reentrancia: evita que dos llamadas concurrentes sobre la
  // misma rutina (p. ej. doble tap en el checkbox) interlacen su ciclo de
  // cancelar/reprogramar notificaciones y se pisen al guardar
  // notificacionesActivas, dejando IDs huérfanos imposibles de cancelar.
  final Set<String> _idsEnProceso = {};

  @override
  List<Rutina> build() {
    _cargarRutinas();
    return [];
  }

  // --- CALCULADORA DE PROGRESO DIARIO ---
  double get progresoDiario {
    final hoy = DateTime.now().weekday; // 1 = Lunes, 7 = Domingo
    
    final rutinasDeHoy = state.where((r) => r.horarios.containsKey(hoy)).toList();
    
    if (rutinasDeHoy.isEmpty) return 0.0;
    
    final completadas = rutinasDeHoy.where((r) => r.completada).length;
    
    return completadas / rutinasDeHoy.length;
  }

  // Todo el cuerpo va envuelto en try/catch (igual que NotaNotifier._cargarNotas):
  // sin esto, CUALQUIER excepción imprevista a mitad de esta función (parseo,
  // relleno de colchón, plugin de notificaciones, etc.) queda sin capturar y
  // aborta silenciosamente esta llamada. Eso es especialmente grave cuando
  // _cargarRutinas se invoca desde BackupService.importarBackup: al ser una
  // cadena de awaits secuencial sobre varios providers, una excepción acá
  // puede impedir que se recarguen los que faltan, dejándolos con el estado
  // viejo en memoria aunque los datos ya se hayan escrito bien en disco.
  Future<void> _cargarRutinas() async {
    try {
      await _cargarRutinasInterno();
    } catch (e) {
      debugPrint('Error al cargar rutinas: $e');
    }
  }

  Future<void> _cargarRutinasInterno() async {
    final prefs = await SharedPreferences.getInstance();
    final String? rutinasJson = prefs.getString(_storageKey);

    if (rutinasJson != null) {
      final List<dynamic> listaDecodificada = jsonDecode(rutinasJson);
      final List<Rutina> rutinas = listaDecodificada.map((item) => Rutina.fromJson(item)).toList();

      final ahora = DateTime.now();
      final hoyStr = ahora.toIso8601String().split('T')[0];
      final hoyFecha = DateTime(ahora.year, ahora.month, ahora.day);
      
      bool huboCambios = false;

      state = rutinas.map((r) {
        Rutina rutinaActualizada = r;
        
        // 1. Desmarcar si es un nuevo día
        if (r.fechaCompletada != hoyStr && r.completada) {
          rutinaActualizada = rutinaActualizada.copyWith(completada: false);
          huboCambios = true;
        }

        // 1b. Lo mismo para "omitida" (ver toggleOmitida): es un estado de
        // SOLO hoy, igual que completada.
        if (r.fechaOmitida != hoyStr && r.omitida) {
          rutinaActualizada = rutinaActualizada.copyWith(omitida: false);
          huboCambios = true;
        }

        // 2. Verificar rachas perdidas instantáneamente
        if (rutinaActualizada.racha > 0 && rutinaActualizada.fechaCompletada != null) {
          try {
            DateTime ultima = DateTime.parse(rutinaActualizada.fechaCompletada!);
            final fechaUltima = DateTime(ultima.year, ultima.month, ultima.day);

            if (!fechaUltima.isAtSameMomentAs(hoyFecha)) {
              int diasPasados = hoyFecha.difference(fechaUltima).inDays;
              for (int i = 1; i < diasPasados; i++) {
                final diaRevision = hoyFecha.subtract(Duration(days: i));
                if (rutinaActualizada.horarios.containsKey(diaRevision.weekday - 1)) {
                  // Si ese día programado fue OMITIDO a propósito (pagado con
                  // monedas), no cuenta como racha perdida: es justamente el
                  // efecto que la moneda compra. Seguimos revisando días más
                  // atrás en vez de cortar acá.
                  if (rutinaActualizada.historialOmisiones.contains(_claveFecha(diaRevision))) {
                    continue;
                  }
                  rutinaActualizada = rutinaActualizada.copyWith(racha: 0);
                  huboCambios = true;
                  break;
                }
              }
            }
          } catch (_) {}
        }
        return rutinaActualizada;
      }).toList();

      // Con await: si no se espera, el actualizar() incondicional del widget
      // más abajo podría ejecutarse ANTES de que este guardado termine de
      // escribir a disco, y leería datos viejos.
      if (huboCambios) await _guardarRutinas();

      // 3. Rellenar el colchón de notificaciones de forma segura al abrir la
      // app — SOLO donde realmente haga falta (ver _rellenarColchonSiHaceFalta).
      // Con "await" en cada iteración: cada rutina termina su ciclo completo
      // antes de pasar a la siguiente, evitando que dos rutinas distintas se
      // crucen entre sí durante el arranque.
      //
      // Medición temporal (quitar cuando se confirme el impacto en producción):
      // cuenta cuántas rutinas activas hicieron trabajo real (reset o relleno)
      // contra cuántas se saltaron por tener colchón suficiente.
      int totalRutinasActivas = 0;
      int rutinasConTrabajoReal = 0;
      for (var rutina in state) {
        if (rutina.activa) {
          totalRutinasActivas++;
          // Marcamos la rutina como "en proceso" mientras se rellena su
          // colchón. Sin esto, si el usuario la elimina justo en este
          // instante (la pantalla de gestión ya está disponible aunque
          // este relleno automático siga corriendo en segundo plano),
          // eliminarRutina podría capturar notificacionesActivas ANTES de
          // que este relleno le agregue los IDs recién programados,
          // cancelar solo los viejos, y borrar la rutina del estado —
          // dejando esas alarmas nuevas programadas en Android para
          // siempre, sin ningún registro en la app que permita
          // cancelarlas. Ver la nota completa en eliminarRutina.
          if (_idsEnProceso.contains(rutina.id)) continue;
          _idsEnProceso.add(rutina.id);
          bool huboTrabajoReal = false;
          try {
            huboTrabajoReal = await _rellenarColchonSiHaceFalta(rutina);
          } finally {
            _idsEnProceso.remove(rutina.id);
          }
          if (huboTrabajoReal) rutinasConTrabajoReal++;
        }
      }
      print(
        "🔔 DEBUG: 📊 Apertura de app — rutinas activas: $totalRutinasActivas "
        "| con trabajo real (reset/relleno): $rutinasConTrabajoReal "
        "| saltadas (colchón suficiente): ${totalRutinasActivas - rutinasConTrabajoReal}",
      );
    }

    // Incondicional (no solo cuando huboCambios): el reseteo por cambio de
    // día ocurre arriba y hoy por hoy es la única señal de que el widget
    // necesita refrescarse aunque no haya habido ningún cambio real.
    //
    // Con await: si no se espera, dos sincronizaciones disparadas en
    // sucesión rápida (ej. varias altas/bajas seguidas) pueden resolverse
    // fuera de orden — la más vieja podría terminar de escribir DESPUÉS de
    // la más nueva y dejar el widget mostrando datos desactualizados. Al
    // esperar aquí, cada mutación deja el widget al día antes de que la
    // siguiente pueda empezar la suya.
    await WidgetRutinasService.actualizar();
    // El anillo de Rutinas del widget de Progreso lee los totales que la
    // línea de arriba acaba de publicar: se recalcula después, no antes.
    await WidgetProgresoService.actualizar();
  }

  Future<void> _guardarRutinas() async {
    final prefs = await SharedPreferences.getInstance();
    final String rutinasCodificadas = jsonEncode(state.map((r) => r.toJson()).toList());
    await prefs.setString(_storageKey, rutinasCodificadas);
    // Mantiene el widget de pantalla de inicio de Rutinas en sync con cada
    // creación/edición/completado, ya que todos pasan por este método.
    // Con await (ver nota de _cargarRutinas): evita que sincronizaciones
    // concurrentes se resuelvan fuera de orden.
    await WidgetRutinasService.actualizar();
    // Mismo motivo que arriba: el widget de Progreso depende de los totales
    // que WidgetRutinasService.actualizar() acaba de publicar.
    await WidgetProgresoService.actualizar();
  }

  // --- LÓGICA DE NOTIFICACIONES PARA RUTINAS ---

  // Generador de ID base determinístico. Sigue siendo útil para crear
  // IDs NUEVOS al programar, pero YA NO se usa para "adivinar" qué
  // cancelar — eso ahora se hace con la lista guardada en el modelo.
  //
  // NOTA: acotamos el resultado con "% 100000" para dejar espacio de
  // sobra a los offsets que se le suman después (día de la semana,
  // aviso de 1hr antes, recordatorios secundarios, y ahora también el
  // "colchón" de varias semanas). Sin este límite, un baseId cercano
  // al máximo de 32 bits sumado a esos offsets podría desbordarse al
  // pasar por el canal nativo hacia Android.
  int _generarIdNumerico(String id) {
    int hash = 0;
    for (int i = 0; i < id.length; i++) {
      hash = (31 * hash + id.codeUnitAt(i)) & 0x7FFFFFFF; // Límite seguro de 32-bits
    }
    return hash % 100000;
  }

  // Reemplaza POR COMPLETO notificacionesActivas y, opcionalmente,
  // ultimaFechaProgramada (si se omite, se deja como estaba, por el
  // patrón "??" de copyWith). Es el paso final de
  // _resetCompletoNotificacionesRutina: "anotar qué quedó realmente
  // programado, y hasta qué fecha llega el colchón".
  Future<void> _guardarListaDeIds(String rutinaId, List<int> ids, {DateTime? ultimaFechaProgramada, Map<String, List<int>>? idsPorOcurrencia}) async {
    state = [
      for (final r in state)
        if (r.id == rutinaId)
          r.copyWith(
            notificacionesActivas: ids,
            ultimaFechaProgramada: ultimaFechaProgramada,
            idsPorOcurrencia: idsPorOcurrencia,
          )
        else
          r,
    ];
    // Con await: este es el registro de qué IDs quedan realmente programados
    // en Android; si no se persiste antes de que la app se cierre, la
    // próxima sesión no sabría qué cancelar.
    await _guardarRutinas();
  }

  // Variante para el camino de "relleno" (_rellenarColchonSiHaceFalta):
  // AGREGA los IDs nuevos a los que ya había (sin tocar ni descartar los
  // existentes, que siguen siendo válidos y ya están sonando en Android)
  // y actualiza ultimaFechaProgramada al nuevo final del colchón.
  Future<void> _agregarIdsYActualizarFecha(String rutinaId, List<int> idsNuevos, DateTime nuevaUltimaFecha, {Map<String, List<int>> idsPorOcurrenciaNuevos = const {}}) async {
    state = [
      for (final r in state)
        if (r.id == rutinaId)
          r.copyWith(
            notificacionesActivas: [...r.notificacionesActivas, ...idsNuevos],
            ultimaFechaProgramada: nuevaUltimaFecha,
            idsPorOcurrencia: {...r.idsPorOcurrencia, ...idsPorOcurrenciaNuevos},
          )
        else
          r,
    ];
    await _guardarRutinas();
  }

  // ============================================================
  // RESET COMPLETO — comportamiento histórico, sin cambios de fondo
  // ------------------------------------------------------------
  // Flujo:
  // 1. Cancela EXACTAMENTE los IDs que están guardados en
  //    rutina.notificacionesActivas (sin recalcular nada).
  // 2. Si la rutina está inactiva, guarda una lista vacía y termina.
  // 3. Si está activa, programa las notificaciones nuevas y va
  //    anotando cada ID que efectivamente se programó.
  // 4. Al final, guarda esa lista nueva de IDs en el modelo, junto con
  //    ultimaFechaProgramada (la fecha del occurrence más lejano que
  //    quedó programado), para que la PRÓXIMA vez se sepa exactamente
  //    qué cancelar y si hace falta rellenar el colchón.
  //
  // Se usa cuando el horario pudo haber cambiado (crear/editar/activar
  // una rutina) o al forzar una resincronización manual: en esos casos
  // SÍ hace falta empezar de cero para no dejar notificaciones con el
  // horario viejo. Ver _rellenarColchonSiHaceFalta para el camino
  // incremental que NO reprograma todo en cada apertura de la app.
  // ============================================================
  Future<void> _resetCompletoNotificacionesRutina(Rutina rutina) async {
    print("🔔 DEBUG: -- INICIANDO RESET COMPLETO DE ALARMAS --");
    print("🔔 DEBUG: Rutina: '${rutina.titulo}' | Completada: ${rutina.completada} | IDs previos: ${rutina.notificacionesActivas}");

    // 1. Cancelamos EXACTAMENTE lo que se había programado la última vez.
    // Ya no hay fórmula que recalcular: solo tomamos la lista tal cual está guardada.
    await NotificacionesService().cancelarListaDeIds(rutina.notificacionesActivas);
    print("🔔 DEBUG: Notificaciones previas canceladas por ID exacto.");

    // 2. Si la rutina no está activa, no programamos nada nuevo.
    if (!rutina.activa) {
      await _guardarListaDeIds(rutina.id, []);
      print("🔔 DEBUG: La rutina está inactiva. Proceso terminado.");
      return;
    }

    final int baseId = _generarIdNumerico(rutina.id);
    final ahora = DateTime.now();
    final List<int> nuevosIds = []; // Aquí acumulamos TODO lo que programemos en este ciclo
    final Map<String, List<int>> mapaPorFecha = {}; // IDs agrupados por fecha exacta (ver idsPorOcurrencia)
    DateTime? fechaMasLejana; // El final real del colchón: se guarda en ultimaFechaProgramada

    // ============================================================
    // COLCHÓN DE VARIAS SEMANAS
    // ------------------------------------------------------------
    // Como ya no usamos matchDateTimeComponents (que le pedía a Android
    // reprogramar automáticamente cada semana, pero causaba fallos de
    // cancelación), ahora CADA notificación es de una sola ocurrencia.
    // Eso significa que, sin este colchón, la reprogramación de la
    // "semana siguiente" dependería de que el usuario abra la app,
    // marque algo, o edite la rutina en algún momento antes de esa fecha.
    //
    // Para no depender de ningún patrón de uso, programamos de una vez
    // la próxima ocurrencia MÁS 3 semanas adicionales (4 en total).
    // Así, aunque el usuario no abra la app durante casi un mes, las
    // alarmas siguen sonando con normalidad. El colchón se "recarga" a 4
    // semanas completas cada vez que hace falta (ver
    // _rellenarColchonSiHaceFalta).
    // ============================================================
    //
    // BAJADO de 4 a 2 semanas (ver también programarRecordatoriosSecundarios
    // en notificaciones_service.dart, bajado de 3 a 1 recordatorio): Android
    // tiene un límite DURO de 500 alarmas concurrentes por app (lanza
    // IllegalStateException "Maximum limit of concurrent alarms 500 reached"
    // desde Android 12+). Con el diseño anterior, una sola rutina de 7 días
    // ya generaba 4 semanas × 5 alarmas/ocurrencia × 7 días = 140 alarmas;
    // con apenas 4 rutinas de 7 días activas ya se superaba el límite. Al
    // llegar ahí, las llamadas de zonedSchedule para las semanas más lejanas
    // (2, 3, 4) fallaban con esa excepción, que quedaba atrapada en un
    // try-catch silencioso (solo un print) — por eso las rutinas dejaban de
    // sonar después de la primera semana, sin ningún error visible. Con 2
    // semanas × 3 alarmas/ocurrencia, esa misma rutina de 7 días usa 42
    // alarmas: se puede tener muchas más rutinas activas sin acercarse al
    // límite.
    const int semanasColchon = 2;

    for (var entry in rutina.horarios.entries) {
      final diaIndex = entry.key;
      final hora = entry.value;
      final int idExactoBase = baseId + diaIndex;

      DateTime proximaFecha = _calcularProximaFecha(diaIndex, hora);

      // Si ya se completó hoy, empujamos la primera ocurrencia 7 días.
      // El colchón de semanas adicionales se calcula A PARTIR de esta
      // fecha ya corregida, así que el resto del colchón sigue intacto.
      if (rutina.completada &&
          proximaFecha.year == ahora.year &&
          proximaFecha.month == ahora.month &&
          proximaFecha.day == ahora.day) {
        proximaFecha = proximaFecha.add(const Duration(days: 7));
        print("🔔 DEBUG: ⏩ Rutina de hoy marcada completa. Primera ocurrencia del colchón: $proximaFecha");
      } else {
        print("🔔 DEBUG: ⏰ Primera ocurrencia del colchón: $proximaFecha");
      }

      // Programamos "semanasColchon" ocurrencias consecutivas hacia adelante.
      for (int semana = 0; semana < semanasColchon; semana++) {
        final fechaDeEstaSemana = proximaFecha.add(Duration(days: 7 * semana));
        // Cada semana tiene su propio "espacio" de 100,000 en el ID,
        // para que nunca choque con el aviso de 1hr antes (+1000) ni
        // con los recordatorios secundarios (+10000, +20000, +30000).
        final int idDeEstaSemana = idExactoBase + (semana * 100000);

        if (fechaMasLejana == null || fechaDeEstaSemana.isAfter(fechaMasLejana)) {
          fechaMasLejana = fechaDeEstaSemana;
        }

        // IDs de ESTA ocurrencia (todos sus recordatorios) agrupados por su
        // fecha exacta, para que toggleCompletada pueda cancelar solo lo de
        // hoy sin tocar el resto del colchón.
        final String claveFecha = _claveFecha(fechaDeEstaSemana);
        final List<int> idsDeEstaOcurrencia = mapaPorFecha.putIfAbsent(claveFecha, () => []);

        final fechaUnaHoraAntes = fechaDeEstaSemana.subtract(const Duration(hours: 1));

        // Aviso 1 hora antes
        if (fechaUnaHoraAntes.isAfter(ahora)) {
          await NotificacionesService().programarAlertaRutina(
            id: idDeEstaSemana + 1000,
            titulo: 'Preparación de hábito',
            body: 'Tu hábito "${rutina.titulo}" comienza en 1 hora.',
            fechaVisual: fechaUnaHoraAntes,
            iconoCode: rutina.iconoCode,
            esAlarmaFullScreen: false,
            esInsistente: false,
          );
          nuevosIds.add(idDeEstaSemana + 1000);
          idsDeEstaOcurrencia.add(idDeEstaSemana + 1000);
        }

        // Aviso a la hora exacta
        await NotificacionesService().programarAlertaRutina(
          id: idDeEstaSemana,
          titulo: '¡Es hora de tu hábito!',
          body: 'Es momento de: ${rutina.titulo}',
          fechaVisual: fechaDeEstaSemana,
          iconoCode: rutina.iconoCode,
          esAlarmaFullScreen: true,
          esInsistente: true,
        );
        nuevosIds.add(idDeEstaSemana);
        idsDeEstaOcurrencia.add(idDeEstaSemana);

        // Recordatorios secundarios (cada hora, hasta 3 veces) de ESTA semana del colchón.
        final idsSecundarios = await NotificacionesService().programarRecordatoriosSecundarios(
          idDeEstaSemana,
          rutina.titulo,
          fechaDeEstaSemana,
        );
        nuevosIds.addAll(idsSecundarios);
        idsDeEstaOcurrencia.addAll(idsSecundarios);
      }
    }

    // 4. Guardamos la lista real y completa de IDs que quedaron programados
    // (las 4 semanas de colchón, para todos los días de la rutina) y la
    // fecha del occurrence más lejano, para saber con certeza qué cancelar
    // y cuándo hará falta rellenar la próxima vez.
    await _guardarListaDeIds(rutina.id, nuevosIds, ultimaFechaProgramada: fechaMasLejana, idsPorOcurrencia: mapaPorFecha);
    print("🔔 DEBUG: -- FINALIZÓ EL RESET COMPLETO. Nuevos IDs guardados: $nuevosIds | Colchón hasta: $fechaMasLejana --");
  }

  // Formato yyyy-MM-dd, igual al usado para fechaCompletada, para usar
  // como clave de idsPorOcurrencia.
  String _claveFecha(DateTime fecha) => fecha.toIso8601String().split('T')[0];

  // ============================================================
  // TOP-UP INCREMENTAL — el camino que corre en cada apertura de la app
  // ------------------------------------------------------------
  // En vez de cancelar y reprogramar todo siempre, solo hace trabajo
  // (llamadas nativas de cancelar/programar) cuando el colchón de 4
  // semanas realmente lo necesita:
  //
  // a. Sin ultimaFechaProgramada (rutina creada antes de este campo, o
  //    recién restaurada de un respaldo de otro dispositivo): no
  //    sabemos qué tan lleno está el colchón real en ESTE dispositivo,
  //    así que sembramos el campo con un reset completo.
  // b. Con colchón de 2 semanas o más: no hace ninguna llamada nativa.
  // c. Con colchón corto (menos de 2 semanas, incluyendo el caso de
  //    colchón ya agotado): agrega SOLO las ocurrencias nuevas
  //    necesarias para volver a tener 4 semanas desde hoy, sin tocar
  //    ni cancelar lo que ya estaba programado y sigue siendo válido.
  //
  // Los IDs de las ocurrencias nuevas usan como multiplicador de semana
  // la cantidad de semanas transcurridas desde una época fija más un
  // offset grande (ver offsetSemanaRelleno abajo), en vez del contador
  // 0..3 que usa el reset completo. Así, para un mismo día de la
  // semana, cada fecha real tiene un multiplicador propio y siempre
  // creciente en el tiempo — nunca se repite un ID que ya esté activo,
  // sin importar cuántos rellenos incrementales hayan pasado desde el
  // último reset completo (ver verificación detallada en el README).
  // ============================================================
  Future<bool> _rellenarColchonSiHaceFalta(Rutina rutina) async {
    // a. Sembrar el campo la primera vez (o tras restaurar un respaldo), o
    // MIGRAR una rutina que ya tiene notificaciones activas pero fue
    // guardada antes de que existiera idsPorOcurrencia (ver nota extensa
    // en el modelo Rutina sobre por qué las rutinas dejaban de sonar tras
    // completarlas una vez). En ambos casos, un reset completo siembra el
    // campo desde cero de forma segura.
    if (rutina.ultimaFechaProgramada == null ||
        (rutina.notificacionesActivas.isNotEmpty && rutina.idsPorOcurrencia.isEmpty)) {
      print("🔔 DEBUG: 🌱 '${rutina.titulo}' sin ultimaFechaProgramada o sin idsPorOcurrencia. Sembrando con reset completo.");
      await _resetCompletoNotificacionesRutina(rutina);
      return true;
    }

    final ahora = DateTime.now();
    final int diasDeColchon = rutina.ultimaFechaProgramada!.difference(ahora).inDays;

    // b. Colchón suficiente: cero llamadas nativas.
    // Umbral bajado de 14 a 7 días, proporcional al colchón objetivo (ver
    // nota extensa en _resetCompletoNotificacionesRutina sobre el límite de
    // 500 alarmas de Android): con objetivo de 2 semanas, rellenamos cuando
    // queda menos de la mitad (1 semana), igual que antes era la mitad de 4.
    if (diasDeColchon >= 7) {
      print("🔔 DEBUG: ✅ '${rutina.titulo}' con colchón suficiente ($diasDeColchon días). Se omite trabajo.");
      return false;
    }

    // c. Colchón corto (o agotado): rellenamos solo lo que falta.
    print("🔔 DEBUG: ⏳ '${rutina.titulo}' con colchón corto ($diasDeColchon días). Rellenando...");

    final int baseId = _generarIdNumerico(rutina.id);
    const int semanasColchonObjetivo = 2;
    final DateTime limiteColchon = ahora.add(const Duration(days: 7 * semanasColchonObjetivo));

    // Época fija + offset grande: garantiza que el multiplicador de semana
    // de un relleno nunca caiga en el rango 0..3 que usa el reset completo,
    // sin importar qué tan lejos en el futuro esté "ahora".
    final DateTime epoca = DateTime(2020, 1, 1);
    const int offsetSemanaRelleno = 1000;

    final List<int> idsNuevos = [];
    final Map<String, List<int>> mapaPorFechaNuevo = {};
    DateTime fechaMasLejana = rutina.ultimaFechaProgramada!;

    for (var entry in rutina.horarios.entries) {
      final diaIndex = entry.key;
      final hora = entry.value;
      final int idExactoBase = baseId + diaIndex;

      // Nos saltamos las ocurrencias que ya están cubiertas por el colchón
      // actual (todavía activas, no las tocamos ni las recontamos).
      DateTime siguienteFecha = _calcularProximaFecha(diaIndex, hora);
      while (!siguienteFecha.isAfter(rutina.ultimaFechaProgramada!)) {
        siguienteFecha = siguienteFecha.add(const Duration(days: 7));
      }

      // Mismo criterio que en el reset completo: si la primera ocurrencia
      // NUEVA cae hoy y la rutina ya se completó hoy, la empujamos 7 días.
      if (rutina.completada &&
          siguienteFecha.year == ahora.year &&
          siguienteFecha.month == ahora.month &&
          siguienteFecha.day == ahora.day) {
        siguienteFecha = siguienteFecha.add(const Duration(days: 7));
      }

      while (!siguienteFecha.isAfter(limiteColchon)) {
        final int semanasDesdeEpoca = siguienteFecha.difference(epoca).inDays ~/ 7;
        final int idDeEstaOcurrencia = idExactoBase + ((offsetSemanaRelleno + semanasDesdeEpoca) * 100000);

        final String claveFecha = _claveFecha(siguienteFecha);
        final List<int> idsDeEstaOcurrencia = mapaPorFechaNuevo.putIfAbsent(claveFecha, () => []);

        final fechaUnaHoraAntes = siguienteFecha.subtract(const Duration(hours: 1));

        if (fechaUnaHoraAntes.isAfter(ahora)) {
          await NotificacionesService().programarAlertaRutina(
            id: idDeEstaOcurrencia + 1000,
            titulo: 'Preparación de hábito',
            body: 'Tu hábito "${rutina.titulo}" comienza en 1 hora.',
            fechaVisual: fechaUnaHoraAntes,
            iconoCode: rutina.iconoCode,
            esAlarmaFullScreen: false,
            esInsistente: false,
          );
          idsNuevos.add(idDeEstaOcurrencia + 1000);
          idsDeEstaOcurrencia.add(idDeEstaOcurrencia + 1000);
        }

        await NotificacionesService().programarAlertaRutina(
          id: idDeEstaOcurrencia,
          titulo: '¡Es hora de tu hábito!',
          body: 'Es momento de: ${rutina.titulo}',
          fechaVisual: siguienteFecha,
          iconoCode: rutina.iconoCode,
          esAlarmaFullScreen: true,
          esInsistente: true,
        );
        idsNuevos.add(idDeEstaOcurrencia);
        idsDeEstaOcurrencia.add(idDeEstaOcurrencia);

        final idsSecundarios = await NotificacionesService().programarRecordatoriosSecundarios(
          idDeEstaOcurrencia,
          rutina.titulo,
          siguienteFecha,
        );
        idsNuevos.addAll(idsSecundarios);
        idsDeEstaOcurrencia.addAll(idsSecundarios);

        if (siguienteFecha.isAfter(fechaMasLejana)) {
          fechaMasLejana = siguienteFecha;
        }

        siguienteFecha = siguienteFecha.add(const Duration(days: 7));
      }
    }

    if (idsNuevos.isEmpty) {
      print("🔔 DEBUG: '${rutina.titulo}' no generó ocurrencias nuevas al rellenar.");
      return false;
    }

    await _agregarIdsYActualizarFecha(rutina.id, idsNuevos, fechaMasLejana, idsPorOcurrenciaNuevos: mapaPorFechaNuevo);
    print("🔔 DEBUG: -- RELLENO TERMINADO. IDs agregados: $idsNuevos | Colchón ahora hasta: $fechaMasLejana --");
    return true;
  }

  DateTime _calcularProximaFecha(int diaSemana, TimeOfDay hora) {
    final ahora = DateTime.now();
    int targetWeekday = diaSemana + 1; // Dart: 1=Lunes, 7=Domingo

    DateTime fecha = DateTime(ahora.year, ahora.month, ahora.day, hora.hour, hora.minute);

    while (fecha.weekday != targetWeekday || fecha.isBefore(ahora)) {
      fecha = fecha.add(const Duration(days: 1));
    }
    return fecha;
  }

  // --- MÉTODOS DE ACCIÓN ---

  Future<void> addRutina(Rutina rutina) async {
    // tarea_provider.dart ya lo hacía para tareas, pero acá faltaba: cada
    // rutina nueva agenda muchas alarmas (hasta 4 semanas de colchón por
    // día programado), así que vale la pena reforzar aquí también el
    // permiso de ignorar optimización de batería estándar de Android.
    await NotificacionesService().solicitarPermisosEspeciales();
    state = [...state, rutina];
    await _guardarRutinas();
    // Rutina nueva: no hay nada que "rellenar", siempre reset completo.
    await _resetCompletoNotificacionesRutina(rutina);
  }

  Future<void> editarRutina(Rutina rutinaEditada) async {
    // IMPORTANTE: conservamos los notificacionesActivas que ya tenía la
    // rutina ANTES de la edición, para que _resetCompletoNotificacionesRutina
    // pueda cancelarlos correctamente (si el formulario de edición no
    // trae ese dato, se perdería el rastro de lo programado anteriormente).
    if (_idsEnProceso.contains(rutinaEditada.id)) return;
    _idsEnProceso.add(rutinaEditada.id);
    try {
      final rutinaAnterior = state.firstWhere((r) => r.id == rutinaEditada.id, orElse: () => rutinaEditada);
      final rutinaConHistorial = rutinaEditada.copyWith(
        notificacionesActivas: rutinaAnterior.notificacionesActivas,
      );

      state = [
        for (final r in state)
          if (r.id == rutinaConHistorial.id) rutinaConHistorial else r,
      ];
      await _guardarRutinas();
      // El horario pudo haber cambiado: hace falta empezar de cero para no
      // dejar notificaciones colgadas con el horario viejo.
      await _resetCompletoNotificacionesRutina(rutinaConHistorial);
    } finally {
      _idsEnProceso.remove(rutinaEditada.id);
    }
  }

  Future<void> toggleActiva(String id) async {
    if (_idsEnProceso.contains(id)) return;
    _idsEnProceso.add(id);
    try {
      state = [
        for (final r in state)
          if (r.id == id) r.copyWith(activa: !r.activa) else r,
      ];
      await _guardarRutinas();

      final rutinaActualizada = state.firstWhere((r) => r.id == id);
      // Activar/desactivar cambia el resultado completo de la gestión
      // (nada programado vs. colchón de 4 semanas): reset completo.
      await _resetCompletoNotificacionesRutina(rutinaActualizada);
    } finally {
      _idsEnProceso.remove(id);
    }
  }

  // ============================================================
  // toggleCompletada — con CANCELACIÓN PRIORITARIA
  // ------------------------------------------------------------
  // Si el usuario está marcando la rutina como completada (no
  // desmarcándola), lo PRIMERO que hacemos —antes de tocar el
  // estado, antes de guardar nada— es cancelar la notificación de
  // HOY. Esto elimina cualquier ventana de tiempo en la que esa
  // notificación podría dispararse mientras el resto de la lógica
  // (actualizar racha, guardar, reprogramar) todavía se está
  // ejecutando.
  //
  // IMPORTANTE: solo cancelamos rutinaAntes.idsPorOcurrencia[hoy], NO
  // toda la lista notificacionesActivas. Antes se cancelaba la lista
  // completa (el colchón de varias semanas, de TODOS los días de la
  // rutina), pero ultimaFechaProgramada no se tocaba — así que
  // _rellenarColchonSiHaceFalta creía que el colchón seguía lleno y
  // nunca reprogramaba nada. Resultado: con solo marcar la rutina
  // como completada UNA vez, todas sus ocurrencias futuras (de todos
  // los días programados) quedaban canceladas en Android para
  // siempre, hasta que la fecha (ya obsoleta) del colchón se
  // acercara a menos de 7 días — lo cual hacía que las rutinas
  // dejaran de sonar aproximadamente una semana después de la
  // primera vez que se completaban. Ver [[idsPorOcurrencia]] en el
  // modelo Rutina.
  // ============================================================
  Future<void> toggleCompletada(String id) async {
    if (_idsEnProceso.contains(id)) return;
    _idsEnProceso.add(id);
    try {
      final rutinaAntes = state.firstWhere((r) => r.id == id);
      final hoy = DateTime.now().toIso8601String().split('T')[0];

      // Cancelación inmediata y prioritaria, solo al MARCAR como completa
      // (no al desmarcar), y solo de los IDs que corresponden EXACTAMENTE
      // a hoy — nunca tocamos el resto del colchón.
      final List<int> idsDeHoy = rutinaAntes.idsPorOcurrencia[hoy] ?? const [];
      final bool seCancelaronIdsDeHoy = !rutinaAntes.completada && idsDeHoy.isNotEmpty;
      if (seCancelaronIdsDeHoy) {
        await NotificacionesService().cancelarListaDeIds(idsDeHoy);
        print("🔔 DEBUG: ⚡ Cancelación prioritaria (solo hoy) ejecutada para '${rutinaAntes.titulo}': $idsDeHoy");
      }

      state = [
        for (final r in state)
          if (r.id == id)
            r.copyWith(
              completada: !r.completada,
              racha: !r.completada ? r.racha + 1 : (r.racha > 0 ? r.racha - 1 : 0),
              fechaCompletada: !r.completada ? hoy : null,
              // Una completada real "paga" cualquier racha de omisiones
              // seguidas: la próxima omisión vuelve a costar 1 moneda.
              omisionesSeguidas: !r.completada ? 0 : r.omisionesSeguidas,
              // Quitamos los IDs de hoy (ya cancelados) de ambos registros,
              // para que la contabilidad del colchón siga siendo exacta.
              // Solo si de verdad los cancelamos arriba (nunca al desmarcar).
              notificacionesActivas: !seCancelaronIdsDeHoy
                  ? null
                  : r.notificacionesActivas.where((i) => !idsDeHoy.contains(i)).toList(),
              idsPorOcurrencia: !seCancelaronIdsDeHoy
                  ? null
                  : ({...r.idsPorOcurrencia}..remove(hoy)),
            )
          else
            r,
      ];
      // Con await: acotamos la ventana en la que un cierre abrupto de la app
      // dejaría en disco un 'completada' desincronizado del estado en memoria
      // (y de lo que ya se canceló/reprogramó en Android).
      await _guardarRutinas();

      final rutinaActualizada = state.firstWhere((r) => r.id == id);
      // Al completar se consume una ocurrencia del colchón: puede que
      // amerite rellenar, pero el horario no cambió, así que no hace
      // falta un reset completo (la cancelación prioritaria de arriba ya
      // se encargó de la notificación de HOY).
      await _rellenarColchonSiHaceFalta(rutinaActualizada);

      // ============================================================
      // OTORGAMIENTO DE MONEDAS DE RACHA
      // ------------------------------------------------------------
      // Solo al MARCAR como completada (no al desmarcar), y usando
      // EXACTAMENTE el mismo criterio de "racha cumplida" que dispara
      // el diálogo de felicitación en rutina_card.dart: cada vez que
      // la racha llega a un nuevo múltiplo de rachaPorMoneda (7, 14,
      // 21, 28...) se otorga 1 moneda MÁS — sin tope, se repite
      // indefinidamente mientras la racha siga creciendo. Vive acá (no
      // en el widget) para que sea la fuente de verdad única, sin
      // depender de que la UI esté montada.
      // ============================================================
      if (!rutinaAntes.completada) {
        final int nuevaRacha = rutinaActualizada.racha;
        if (nuevaRacha % rachaPorMoneda == 0) {
          await ref.read(monedasProvider.notifier).agregar(1);
          print("🪙 DEBUG: +1 moneda de racha por hito cumplido en '${rutinaAntes.titulo}' (racha=$nuevaRacha)");
        }
      }
    } finally {
      _idsEnProceso.remove(id);
    }
  }

  // ============================================================
  // toggleOmitida — "comodín" pagado con monedas de racha
  // ------------------------------------------------------------
  // Permite saltar la ocurrencia de HOY sin romper la racha (ver el
  // chequeo de historialOmisiones en _cargarRutinas), pagando con
  // monedas ganadas al alcanzar hitos de racha (ver el otorgamiento en
  // toggleCompletada). El costo sube con cada omisión CONSECUTIVA de
  // la MISMA rutina (sin una completada real de por medio) para
  // desalentar el abuso: 1ª omisión = 1 moneda, 2ª = 2, 3ª = 3...
  //
  // Es un toggle, igual que toggleCompletada: si ya estaba omitida,
  // deshacerlo reembolsa EXACTAMENTE lo que costó (omisionesSeguidas
  // ya incrementado equivale al costo que se cobró). Igual que al
  // desmarcar una completada (ver toggleCompletada), NO se reprograma
  // la notificación puntual de hoy que quedó cancelada — sería una
  // reprogramación cara (cancela y reconstruye TODO el colchón) solo
  // para un aviso cuya hora probablemente ya pasó de todos modos.
  //
  // Devuelve false SOLO cuando no alcanzan las monedas para omitir (no
  // se cambia nada en ese caso, para que la UI pueda avisarle al
  // usuario); true en cualquier otro resultado.
  // ============================================================
  Future<bool> toggleOmitida(String id) async {
    if (_idsEnProceso.contains(id)) return false;
    _idsEnProceso.add(id);
    try {
      final rutinaAntes = state.firstWhere((r) => r.id == id);
      final hoy = DateTime.now().toIso8601String().split('T')[0];

      if (rutinaAntes.omitida) {
        // --- Deshacer la omisión: reembolso ---
        final int reembolso = rutinaAntes.omisionesSeguidas;
        await ref.read(monedasProvider.notifier).agregar(reembolso);

        state = [
          for (final r in state)
            if (r.id == id)
              r.copyWith(
                omitida: false,
                omisionesSeguidas: r.omisionesSeguidas > 0 ? r.omisionesSeguidas - 1 : 0,
                historialOmisiones: r.historialOmisiones.where((f) => f != hoy).toList(),
              )
            else
              r,
        ];
        await _guardarRutinas();

        // Mismo criterio que toggleCompletada al desmarcar: no hace falta
        // ninguna llamada nativa acá (el colchón restante sigue intacto y
        // sigue siendo válido), _rellenarColchonSiHaceFalta solo actúa si
        // de verdad hace falta.
        final rutinaActualizada = state.firstWhere((r) => r.id == id);
        await _rellenarColchonSiHaceFalta(rutinaActualizada);
        return true;
      }

      // --- Marcar como omitida: exige monedas suficientes ---
      final int costo = rutinaAntes.omisionesSeguidas + 1;
      final bool pudoPagar = await ref.read(monedasProvider.notifier).gastar(costo);
      if (!pudoPagar) {
        print("🪙 DEBUG: omisión rechazada para '${rutinaAntes.titulo}': faltan monedas (costo=$costo)");
        return false;
      }

      // Cancelación prioritaria de la notificación de HOY, mismo criterio
      // que toggleCompletada.
      final List<int> idsDeHoy = rutinaAntes.idsPorOcurrencia[hoy] ?? const [];
      if (idsDeHoy.isNotEmpty) {
        await NotificacionesService().cancelarListaDeIds(idsDeHoy);
      }

      final DateTime limiteHistorial = DateTime.now().subtract(const Duration(days: 60));

      state = [
        for (final r in state)
          if (r.id == id)
            r.copyWith(
              omitida: true,
              fechaOmitida: hoy,
              omisionesSeguidas: r.omisionesSeguidas + 1,
              notificacionesActivas: idsDeHoy.isEmpty
                  ? null
                  : r.notificacionesActivas.where((i) => !idsDeHoy.contains(i)).toList(),
              idsPorOcurrencia: idsDeHoy.isEmpty
                  ? null
                  : ({...r.idsPorOcurrencia}..remove(hoy)),
              // Recortado a 60 días: alcanza de sobra para el chequeo de
              // racha perdida en _cargarRutinas sin crecer sin límite.
              historialOmisiones: [
                ...r.historialOmisiones.where((f) {
                  final fecha = DateTime.tryParse(f);
                  return fecha != null && fecha.isAfter(limiteHistorial);
                }),
                hoy,
              ],
            )
          else
            r,
      ];
      await _guardarRutinas();

      final rutinaActualizada = state.firstWhere((r) => r.id == id);
      await _rellenarColchonSiHaceFalta(rutinaActualizada);
      return true;
    } finally {
      _idsEnProceso.remove(id);
    }
  }

  // Fuerza una relectura completa desde SharedPreferences, descartando el
  // estado en memoria. Se usa tras restaurar un respaldo, donde los datos
  // en disco cambiaron por fuera del ciclo normal de esta clase.
  Future<void> recargarDesdeDisco() async {
    await _cargarRutinas();
  }

  Future<void> resincronizarTodasLasAlarmas() async {
    // Botón "Reparar notificaciones": es justamente el mecanismo de "por si
    // algo se desincronizó", así que siempre fuerza el reset completo, sin
    // importar qué tan lleno esté el colchón de cada rutina.
    for (final rutina in state) {
      if (rutina.activa) {
        // Mismo motivo que en _cargarRutinas: si otra operación ya está
        // trabajando sobre esta rutina (p. ej. se está eliminando en este
        // mismo instante), la saltamos en vez de arriesgarnos a la misma
        // condición de carrera que eliminarRutina ahora evita (ver ese
        // método) — programar alarmas nuevas justo cuando la rutina está
        // siendo borrada del estado las dejaría huérfanas para siempre.
        if (_idsEnProceso.contains(rutina.id)) continue;
        _idsEnProceso.add(rutina.id);
        try {
          await _resetCompletoNotificacionesRutina(rutina);
        } finally {
          _idsEnProceso.remove(rutina.id);
        }
      }
    }
  }

  Future<void> incrementarRacha(String id) async {
    state = [
      for (final r in state)
        if (r.id == id) r.copyWith(racha: r.racha + 1) else r,
    ];
    await _guardarRutinas();
  }

  // ============================================================
  // eliminarRutina — con espera por operaciones en curso
  // ------------------------------------------------------------
  // Antes, este método no respetaba el candado _idsEnProceso que sí
  // usan editarRutina/toggleActiva/toggleCompletada. El caso real que
  // esto rompía: _rellenarColchonSiHaceFalta (el relleno automático del
  // colchón de notificaciones, que corre en CADA apertura de la app,
  // ver _cargarRutinas) primero programa las alarmas nuevas en Android
  // y solo AL FINAL las guarda en notificacionesActivas.
  //
  // Si el usuario eliminaba la rutina justo en medio de ese proceso,
  // eliminarRutina capturaba la lista VIEJA de IDs (sin los recién
  // programados), cancelaba solo esos, y borraba la rutina del state.
  // Cuando el relleno terminaba de programar y trataba de guardar los
  // IDs nuevos, la rutina ya no existía — un no-op silencioso. Las
  // alarmas nuevas quedaban programadas en Android para siempre, sin
  // ningún registro en la app que permitiera cancelarlas después: esto
  // es lo que hacía sonar rutinas ya eliminadas hace tiempo.
  //
  // Ahora esperamos (con un tope de 10s, por si algo más se quedó
  // atascado sosteniendo el candado) a que cualquier operación en curso
  // termine antes de capturar la lista de IDs a cancelar.
  // ============================================================
  Future<void> eliminarRutina(String id) async {
    int intentos = 0;
    while (_idsEnProceso.contains(id) && intentos < 100) {
      await Future.delayed(const Duration(milliseconds: 100));
      intentos++;
    }
    _idsEnProceso.add(id);
    try {
      // Pudo haber sido eliminada mientras esperábamos (p. ej. doble tap
      // en el botón de eliminar).
      final int index = state.indexWhere((r) => r.id == id);
      if (index == -1) return;
      final rutina = state[index];

      state = state.where((r) => r.id != id).toList();
      await _guardarRutinas();

      await NotificacionesService().cancelarListaDeIds(rutina.notificacionesActivas);
    } finally {
      _idsEnProceso.remove(id);
    }
  }
}

final rutinaProvider = NotifierProvider<RutinaNotifier, List<Rutina>>(() {
  return RutinaNotifier();
});