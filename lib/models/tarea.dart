import 'package:uuid/uuid.dart';

const _uuid = Uuid();

// Sentinel para distinguir "no se pasó el parámetro" de "se pasó null a
// propósito" en copyWith. Sin esto, `campo ?? this.campo` ignora los null
// explícitos y no hay forma de borrar fechaLimite/descripcion al editar.
const _sinCambio = Object();

// Persistido como string (name/byName en toJson/fromJson), NO como índice:
// un índice se corrompe silenciosamente si el orden de los valores cambia
// alguna vez, un string no.
enum TipoRecurrencia { ninguna, dias, meses }

// Cómo se limita una recurrencia (caso de uso: una compra a crédito a 12
// meses, frecuencia mensual y periodo "12 repeticiones"). Mutuamente
// excluyente con la fecha: el usuario elige UN modo o ninguno, nunca ambos a
// la vez. Mismo patrón de persistencia por nombre que TipoRecurrencia.
enum ModoLimiteRecurrencia { ninguno, repeticiones, fecha }

// Mismo patrón que ItemLista en models/nota.dart (texto + completado marcable),
// pero con id propio y estable: las operaciones de subtareas (toggle, eliminar,
// reordenar) necesitan identificar un ítem sin depender de su posición en la lista.
class ItemSubtarea {
  final String id;
  String texto;
  bool completado;

  ItemSubtarea({String? id, required this.texto, this.completado = false}) : id = id ?? _uuid.v4();

  ItemSubtarea copyWith({String? texto, bool? completado}) =>
      ItemSubtarea(id: id, texto: texto ?? this.texto, completado: completado ?? this.completado);

  Map<String, dynamic> toJson() => {'id': id, 'texto': texto, 'completado': completado};

  factory ItemSubtarea.fromJson(Map<String, dynamic> json) => ItemSubtarea(
    id: json['id'] ?? _uuid.v4(),
    texto: json['texto'] ?? '',
    completado: json['completado'] ?? false,
  );
}

class Tarea {
  bool get estaAtrasada {
    // Si no tiene fecha límite o ya la marcaste como completada, no está atrasada
    if (fechaLimite == null || esCompletada) return false;
    
    // Comparamos el reloj actual de tu celular con la fecha límite guardada
    return fechaLimite!.isBefore(DateTime.now());
  }
  final String id;
  final String titulo;
  final String? descripcion;
  final DateTime? fechaLimite;
  final double? horasEstimadas; // NUEVO: ¿Cuánto tiempo te tomará hacerla? (admite decimales)
  final int urgenciaBase; // La urgencia manual que eliges si no usas el auto-piloto
  final bool esCompletada;
  final String grupo;
  final List<ItemSubtarea> subtareas;

  // --- RECURRENCIA POR INTERVALO ---
  // Una sola instancia viva por tarea: al completarla (ver
  // TareaNotifier.toggleTarea), en vez de archivarla se recalcula
  // fechaLimite con siguienteFecha() y esCompletada vuelve a false en el
  // mismo copyWith, atómicamente. Nunca debe persistirse esCompletada=true
  // en una tarea recurrente, porque la limpieza diaria de
  // TareaNotifier._cargarTareasInterno la borraría para siempre.
  final TipoRecurrencia tipoRecurrencia;
  final int? intervalo; // N días o N meses, según tipoRecurrencia
  final int? diaAncla; // 1-31, solo para meses; se fija al crear/editar y no cambia entre ocurrencias
  // Guarda el fechaLimite que tenía la tarea justo antes de la última vez
  // que se completó, para poder deshacer (ver
  // TareaNotifier.deshacerRecurrente) y para que WidgetProgresoService
  // pueda seguir contándola como "completada hoy" aunque su fechaLimite ya
  // haya avanzado a la próxima ocurrencia.
  final DateTime? fechaLimiteAnterior;
  // Mismo propósito que fechaLimiteAnterior pero para el checklist: guarda
  // las subtareas tal como estaban (con sus completado=true) justo antes de
  // resetearlas al reagendar una recurrente, para que
  // TareaNotifier.deshacerRecurrente pueda devolverlas a ese estado. null
  // cuando no hay nada que deshacer (tarea sin subtareas, o ya deshecha).
  final List<ItemSubtarea>? subtareasAnterior;
  // Mismo propósito que fechaLimiteAnterior/subtareasAnterior, pero para el
  // contador histórico: guarda ocurrenciasCompletadas tal como estaba justo
  // antes del evento que se podría deshacer. Necesario porque no todo evento
  // que archiva/avanza una recurrente incrementa el contador de la misma
  // manera: completar una ocurrencia SÍ lo sube en 1 (toggleTarea), pero
  // archivar al editar un tope ya superado (TareaNotifier.archivarDirectamente)
  // NO completa nada, así que no debe tocarlo. Sin este respaldo explícito,
  // TareaNotifier._reconstruirTrasDeshacer tendría que adivinar cuánto restar
  // según de dónde vino el archivado — fuente de bugs sutiles en el contador.
  final int? ocurrenciasCompletadasAnterior;

  // --- LÍMITE DE RECURRENCIA ---
  // Sin límite (modoLimiteRecurrencia == ninguno) es el comportamiento de
  // siempre: la tarea se repite para siempre. Con límite, la tarea deja de
  // recalcular su próxima fecha al agotarse y en su lugar se archiva (ver
  // TareaNotifier.toggleTarea) — ese archivado vive fuera de este modelo.
  final ModoLimiteRecurrencia modoLimiteRecurrencia;
  final int? repeticionesMaximas; // solo con modo == repeticiones
  final DateTime? fechaLimiteRecurrencia; // solo con modo == fecha
  // Cuenta CADA completación de una ocurrencia, incluso sin límite puesto:
  // es histórico real (nunca se resetea al editar), así que si el usuario le
  // agrega un límite más adelante a una tarea que ya venía repitiéndose, el
  // progreso mostrado ("4 de 12") refleja el historial verdadero en vez de
  // arrancar mintiendo desde 0.
  final int ocurrenciasCompletadas;

  Tarea({
    String? id,
    required this.titulo,
    this.descripcion,
    this.fechaLimite,
    this.horasEstimadas,
    required this.urgenciaBase,
    this.esCompletada = false,
    this.grupo = 'General',
    List<ItemSubtarea>? subtareas,
    this.tipoRecurrencia = TipoRecurrencia.ninguna,
    this.intervalo,
    this.diaAncla,
    this.fechaLimiteAnterior,
    this.subtareasAnterior,
    this.ocurrenciasCompletadasAnterior,
    this.modoLimiteRecurrencia = ModoLimiteRecurrencia.ninguno,
    this.repeticionesMaximas,
    this.fechaLimiteRecurrencia,
    this.ocurrenciasCompletadas = 0,
  }) : id = id ?? _uuid.v4(),
       subtareas = subtareas ?? [];

  // Progreso de subtareas ya calculado una sola vez aquí, para que la UI
  // (indicador "2/5" y barra de progreso) no repita este conteo en cada build.
  (int completadas, int total) get progresoSubtareas {
    final total = subtareas.length;
    final completadas = subtareas.where((s) => s.completado).length;
    return (completadas, total);
  }

  double get porcentajeSubtareas {
    final (completadas, total) = progresoSubtareas;
    if (total == 0) return 0.0;
    return completadas / total;
  }

  // Texto neutro para mostrar el progreso de una recurrencia con límite (ej.
  // "4 de 12" para cuotas, pero sirve para cualquier cosa, no solo pagos).
  // En modo fecha se muestra sin denominador ("4 completadas"): no hay un
  // total real conocido, y una fracción estimada mentiría más de lo que
  // informa apenas la tarea se completa tarde o temprano. null sin límite
  // puesto: no hay nada que mostrar.
  String? get textoProgresoRecurrencia {
    switch (modoLimiteRecurrencia) {
      case ModoLimiteRecurrencia.ninguno:
        return null;
      case ModoLimiteRecurrencia.repeticiones:
        return '$ocurrenciasCompletadas de ${repeticionesMaximas ?? '?'}';
      case ModoLimiteRecurrencia.fecha:
        return '$ocurrenciasCompletadas completadas';
    }
  }

  // --- MOTOR DE URGENCIA INTELIGENTE ---
  // Al usar 'get', la urgencia se recalcula automáticamente cada vez que la pantalla la lee
  int get urgencia {
    // 1. Si está completada o no tiene fecha límite, no hay nada que calcular:
    // usamos la urgencia manual de toda la vida.
    if (esCompletada || fechaLimite == null) {
      return urgenciaBase;
    }

    final ahora = DateTime.now();
    final tiempoRestante = fechaLimite!.difference(ahora);

    // 2. Auto-piloto por horas estimadas: el más preciso, porque lo llenó el
    // usuario a mano. Tiene prioridad sobre el de recurrencia si ambos aplican.
    if (horasEstimadas != null) {
      // Si ya se pasó la fecha o si el tiempo que falta es IGUAL O MENOR al que necesitas
      if (tiempoRestante.inHours <= horasEstimadas!) {
        return 4; // MUY ALTO (¡Empieza ahora!)
      }
      // Si tienes un "colchón" del 50% de tiempo extra
      else if (tiempoRestante.inHours <= (horasEstimadas! * 1.5).round()) {
        return 3; // ALTO
      }
      // Si tienes el doble de tiempo necesario
      else if (tiempoRestante.inHours <= (horasEstimadas! * 2).round()) {
        return 2; // MEDIO
      }
      // Si tienes muchísimo tiempo de sobra
      else {
        return 1; // BAJO
      }
    }

    // 3. Sin horas estimadas: si la tarea es recurrente, la urgencia sube
    // sola a medida que se acerca la fecha, en proporción a qué tan seguido
    // se repite (una tarea mensual se pone urgente mucho antes que una
    // diaria). "Mes" se aproxima a 30 días: alcanza para esto, no hace falta
    // exactitud de calendario.
    if (tipoRecurrencia != TipoRecurrencia.ninguna && intervalo != null) {
      final horasIntervalo = (tipoRecurrencia == TipoRecurrencia.dias ? intervalo! : intervalo! * 30) * 24;

      if (tiempoRestante.inHours <= horasIntervalo * 0.10) {
        return 4; // MUY ALTO: queda 10% o menos del intervalo
      } else if (tiempoRestante.inHours <= horasIntervalo * 0.25) {
        return 3; // ALTO: queda 25% o menos
      } else if (tiempoRestante.inHours <= horasIntervalo * 0.50) {
        return 2; // MEDIO: queda la mitad o menos
      } else {
        return 1; // BAJO: sobra tiempo
      }
    }

    // 4. Nada de lo anterior aplica: urgencia 100% manual.
    return urgenciaBase;
  }

  // Calcula la próxima fecha límite de una tarea recurrente a partir de la
  // fechaLimite ACTUAL (no de "ahora"): si la tarea se completa tarde, la
  // siguiente ocurrencia sigue siendo relativa a cuándo debía vencer, no a
  // cuándo se completó de verdad. Devuelve null si no aplica (sin
  // recurrencia, sin fecha, o sin intervalo configurado).
  DateTime? siguienteFecha() {
    if (tipoRecurrencia == TipoRecurrencia.ninguna || fechaLimite == null || intervalo == null) {
      return null;
    }
    final base = fechaLimite!;

    if (tipoRecurrencia == TipoRecurrencia.dias) {
      return base.add(Duration(days: intervalo!));
    }

    // meses: se avanza `intervalo` meses conservando diaAncla (el día del
    // mes original) como referencia, en vez del día de `base` — así
    // "31 ene" recortado a "28 feb" no se queda pegado en 28 para siempre:
    // la siguiente ocurrencia vuelve a intentar el día 31 (-> 31 mar).
    final ancla = diaAncla ?? base.day;
    final mesesTotales = base.month - 1 + intervalo!;
    final anioDestino = base.year + mesesTotales ~/ 12;
    final mesDestino = mesesTotales % 12 + 1;
    // día 0 del mes siguiente al destino == último día del mes destino.
    final ultimoDiaMesDestino = DateTime(anioDestino, mesDestino + 1, 0).day;
    final diaFinal = ancla > ultimoDiaMesDestino ? ultimoDiaMesDestino : ancla;

    return DateTime(anioDestino, mesDestino, diaFinal, base.hour, base.minute);
  }

  // ¿Completar la ocurrencia ACTUAL agota el límite de la recurrencia? Se
  // consulta ANTES de sumar la completación de hoy, por eso compara contra
  // ocurrenciasCompletadas + 1 (repeticiones) o contra la fecha que tendría
  // la ocurrencia siguiente (fecha): si esa próxima fecha ya no cabe dentro
  // del límite, la de hoy fue la última. TareaNotifier.toggleTarea usa esto
  // para decidir entre "recalcular y seguir" o "archivar".
  bool get completarAgotaLimite {
    if (tipoRecurrencia == TipoRecurrencia.ninguna) return false;
    switch (modoLimiteRecurrencia) {
      case ModoLimiteRecurrencia.ninguno:
        return false;
      case ModoLimiteRecurrencia.repeticiones:
        if (repeticionesMaximas == null) return false;
        return ocurrenciasCompletadas + 1 >= repeticionesMaximas!;
      case ModoLimiteRecurrencia.fecha:
        if (fechaLimiteRecurrencia == null) return false;
        final proxima = siguienteFecha();
        // Sin próxima fecha calculable (falta intervalo, etc.) no hay más
        // ocurrencias posibles de todos modos: se considera agotado.
        return proxima == null || proxima.isAfter(fechaLimiteRecurrencia!);
    }
  }

  // ¿El estado YA GUARDADO supera el límite actual? A diferencia de
  // completarAgotaLimite (que mira hacia adelante, al completar), este mira
  // hacia atrás: se usa al EDITAR una tarea recurrente para detectar que el
  // usuario bajó el tope por debajo de lo ya completado (ej. tenía 12 cuotas,
  // lleva 8, y lo cambia a 6) o adelantó la fecha límite antes de la
  // ocurrencia vigente. En ese caso la tarea ya terminó y debe archivarse al
  // guardar, sin esperar a una próxima completación que no va a llegar.
  bool get yaAgotoLimite {
    if (tipoRecurrencia == TipoRecurrencia.ninguna) return false;
    switch (modoLimiteRecurrencia) {
      case ModoLimiteRecurrencia.ninguno:
        return false;
      case ModoLimiteRecurrencia.repeticiones:
        return repeticionesMaximas != null && ocurrenciasCompletadas >= repeticionesMaximas!;
      case ModoLimiteRecurrencia.fecha:
        return fechaLimiteRecurrencia != null && fechaLimite != null && fechaLimite!.isAfter(fechaLimiteRecurrencia!);
    }
  }

  Tarea copyWith({
    String? id,
    String? titulo,
    Object? descripcion = _sinCambio,
    Object? fechaLimite = _sinCambio,
    Object? horasEstimadas = _sinCambio,
    int? urgenciaBase,
    bool? esCompletada,
    String? grupo,
    List<ItemSubtarea>? subtareas,
    TipoRecurrencia? tipoRecurrencia,
    Object? intervalo = _sinCambio,
    Object? diaAncla = _sinCambio,
    Object? fechaLimiteAnterior = _sinCambio,
    Object? subtareasAnterior = _sinCambio,
    Object? ocurrenciasCompletadasAnterior = _sinCambio,
    ModoLimiteRecurrencia? modoLimiteRecurrencia,
    Object? repeticionesMaximas = _sinCambio,
    Object? fechaLimiteRecurrencia = _sinCambio,
    int? ocurrenciasCompletadas,
  }) {
    return Tarea(
      id: id ?? this.id,
      titulo: titulo ?? this.titulo,
      descripcion: identical(descripcion, _sinCambio) ? this.descripcion : descripcion as String?,
      fechaLimite: identical(fechaLimite, _sinCambio) ? this.fechaLimite : fechaLimite as DateTime?,
      horasEstimadas: identical(horasEstimadas, _sinCambio) ? this.horasEstimadas : horasEstimadas as double?,
      urgenciaBase: urgenciaBase ?? this.urgenciaBase,
      esCompletada: esCompletada ?? this.esCompletada,
      grupo: grupo ?? this.grupo,
      subtareas: subtareas ?? this.subtareas.map((s) => ItemSubtarea(id: s.id, texto: s.texto, completado: s.completado)).toList(),
      tipoRecurrencia: tipoRecurrencia ?? this.tipoRecurrencia,
      intervalo: identical(intervalo, _sinCambio) ? this.intervalo : intervalo as int?,
      diaAncla: identical(diaAncla, _sinCambio) ? this.diaAncla : diaAncla as int?,
      fechaLimiteAnterior: identical(fechaLimiteAnterior, _sinCambio) ? this.fechaLimiteAnterior : fechaLimiteAnterior as DateTime?,
      subtareasAnterior: identical(subtareasAnterior, _sinCambio) ? this.subtareasAnterior : subtareasAnterior as List<ItemSubtarea>?,
      ocurrenciasCompletadasAnterior: identical(ocurrenciasCompletadasAnterior, _sinCambio) ? this.ocurrenciasCompletadasAnterior : ocurrenciasCompletadasAnterior as int?,
      modoLimiteRecurrencia: modoLimiteRecurrencia ?? this.modoLimiteRecurrencia,
      repeticionesMaximas: identical(repeticionesMaximas, _sinCambio) ? this.repeticionesMaximas : repeticionesMaximas as int?,
      fechaLimiteRecurrencia: identical(fechaLimiteRecurrencia, _sinCambio) ? this.fechaLimiteRecurrencia : fechaLimiteRecurrencia as DateTime?,
      ocurrenciasCompletadas: ocurrenciasCompletadas ?? this.ocurrenciasCompletadas,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'titulo': titulo,
      'descripcion': descripcion,
      'fechaLimite': fechaLimite?.toIso8601String(),
      'horasEstimadas': horasEstimadas, // Guardamos este nuevo dato
      'urgenciaBase': urgenciaBase,
      'esCompletada': esCompletada,
      'grupo': grupo,
      'subtareas': subtareas.map((s) => s.toJson()).toList(),
      'tipoRecurrencia': tipoRecurrencia.name,
      'intervalo': intervalo,
      'diaAncla': diaAncla,
      'fechaLimiteAnterior': fechaLimiteAnterior?.toIso8601String(),
      'subtareasAnterior': subtareasAnterior?.map((s) => s.toJson()).toList(),
      'modoLimiteRecurrencia': modoLimiteRecurrencia.name,
      'repeticionesMaximas': repeticionesMaximas,
      'fechaLimiteRecurrencia': fechaLimiteRecurrencia?.toIso8601String(),
      'ocurrenciasCompletadas': ocurrenciasCompletadas,
      'ocurrenciasCompletadasAnterior': ocurrenciasCompletadasAnterior,
    };
  }

  factory Tarea.fromJson(Map<String, dynamic> json) {

    return Tarea(

      id: json['id'],
      titulo: json['titulo'],
      descripcion: json['descripcion'],
      fechaLimite: json['fechaLimite'] != null ? DateTime.parse(json['fechaLimite']) : null,
      // (json['horasEstimadas'] as num?) porque datos antiguos lo guardaron como int
      horasEstimadas: (json['horasEstimadas'] as num?)?.toDouble(),
      urgenciaBase: json['urgencia'] ?? json['urgenciaBase'] ?? 1, // Retrocompatibilidad
      esCompletada: json['esCompletada'] as bool? ?? false,
      grupo: json['grupo'] ?? 'General',
      // Retrocompatibilidad: tareas guardadas antes de esta feature no tienen
      // este campo en su JSON, así que caen en la lista vacía por defecto.
      subtareas: (json['subtareas'] as List?)?.map((s) => ItemSubtarea.fromJson(s as Map<String, dynamic>)).toList() ?? [],
      // Tareas guardadas antes de esta feature (o con un string desconocido/
      // corrupto) no rompen: caen en TipoRecurrencia.ninguna, el mismo
      // comportamiento que ya tenían.
      tipoRecurrencia: TipoRecurrencia.values.asNameMap()[json['tipoRecurrencia'] as String?] ?? TipoRecurrencia.ninguna,
      intervalo: json['intervalo'] as int?,
      diaAncla: json['diaAncla'] as int?,
      fechaLimiteAnterior: json['fechaLimiteAnterior'] != null ? DateTime.tryParse(json['fechaLimiteAnterior'] as String) : null,
      // Ausente en tareas guardadas antes de este campo: cae en null, igual
      // que fechaLimiteAnterior.
      subtareasAnterior: (json['subtareasAnterior'] as List?)?.map((s) => ItemSubtarea.fromJson(s as Map<String, dynamic>)).toList(),
      // Ausente igual que los otros "Anterior": null, nada que restaurar.
      ocurrenciasCompletadasAnterior: json['ocurrenciasCompletadasAnterior'] as int?,
      // Backups/tareas de antes de esta feature no traen estos campos: caen
      // en "sin límite" (mismo comportamiento infinito que ya tenían) y
      // contador en 0, nunca en un estado que luzca como ya agotado.
      modoLimiteRecurrencia: ModoLimiteRecurrencia.values.asNameMap()[json['modoLimiteRecurrencia'] as String?] ?? ModoLimiteRecurrencia.ninguno,
      repeticionesMaximas: json['repeticionesMaximas'] as int?,
      fechaLimiteRecurrencia: json['fechaLimiteRecurrencia'] != null ? DateTime.tryParse(json['fechaLimiteRecurrencia'] as String) : null,
      ocurrenciasCompletadas: json['ocurrenciasCompletadas'] as int? ?? 0,
    );
  }
}