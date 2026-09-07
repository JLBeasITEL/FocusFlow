import 'package:flutter/material.dart';

class Rutina {
  final String id;
  final String titulo;
  final String? descripcion;
  final Map<int, TimeOfDay> horarios; 
  final int iconoCode;
  final bool activa;
  final int racha; 
  final bool completada; 
  final String? fechaCompletada;
  final bool esFlexible; 

  // ============================================================
  // NUEVO CAMPO: notificacionesActivas
  // ------------------------------------------------------------
  // Guarda la lista EXACTA de IDs de notificación que quedaron
  // programados en el sistema (Android AlarmManager) la última vez
  // que se ejecutó _gestionarNotificacionesRutina().
  //
  // Por qué existe: antes, para cancelar una notificación, el código
  // RECALCULABA el ID a partir de una fórmula matemática (hash del id
  // + offsets). Si ese cálculo no coincidía EXACTO con el ID que se
  // usó al programar (por overflow de enteros, timing, etc.), la
  // cancelación fallaba en silencio y la notificación seguía sonando.
  //
  // Ahora, en vez de recalcular, simplemente anotamos aquí los IDs
  // reales que se usaron al programar, y para cancelar usamos
  // exactamente esa lista. Ya no hay adivinanza posible.
  // ============================================================
  final List<int> notificacionesActivas;

  // ============================================================
  // NUEVO CAMPO: ultimaFechaProgramada
  // ------------------------------------------------------------
  // Fecha del occurrence MÁS LEJANO que quedó efectivamente
  // programado la última vez que se gestionaron las notificaciones
  // de esta rutina (el final del colchón de 4 semanas). Con esto,
  // cada apertura de la app puede decidir si el colchón todavía
  // alcanza (y no hacer ninguna llamada nativa) o si hace falta
  // rellenarlo, en vez de cancelar/reprogramar todo siempre.
  //
  // null = "todavía no se sabe" (rutina creada antes de este campo,
  // o recién restaurada de un respaldo de otro dispositivo): fuerza
  // un reset completo una sola vez para sembrarlo. Nunca debe causar
  // un crash si falta o viene corrupto.
  // ============================================================
  final DateTime? ultimaFechaProgramada;

  // ============================================================
  // NUEVO CAMPO: idsPorOcurrencia
  // ------------------------------------------------------------
  // Mapa de fecha (yyyy-MM-dd) -> lista de IDs de notificación
  // programados para ESA fecha específica. Antes, toggleCompletada
  // cancelaba TODA la lista notificacionesActivas (el colchón
  // completo de varias semanas, de TODOS los días de la rutina) al
  // marcar como completada, pero dejaba ultimaFechaProgramada sin
  // tocar — así que _rellenarColchonSiHaceFalta creía que el
  // colchón seguía lleno y no reprogramaba nada, dejando la rutina
  // sin ninguna alarma real hasta que la fecha (obsoleta) del
  // colchón se acercara a menos de 7 días. Esto es lo que hacía que
  // las rutinas dejaran de sonar aproximadamente una semana después
  // de completarlas por primera vez.
  //
  // Con este mapa, toggleCompletada puede cancelar EXACTAMENTE los
  // IDs de hoy sin tocar el resto del colchón.
  // ============================================================
  final Map<String, List<int>> idsPorOcurrencia;

  // ============================================================
  // CAMPOS DE "OMITIR RUTINA" (comodín pagado con monedas de racha)
  // ------------------------------------------------------------
  // omitida / fechaOmitida: espejo de completada / fechaCompletada,
  // pero para la ocurrencia de HOY marcada como "salteada a propósito"
  // (no como "no hecha"). Se resetea en cada cambio de día igual que
  // completada, ver _cargarRutinas en rutina_provider.dart.
  //
  // omisionesSeguidas: cuántas veces seguidas se omitió esta rutina
  // SIN una completada real de por medio. Determina el costo en
  // monedas de la PRÓXIMA omisión (costo = omisionesSeguidas + 1,
  // creciente para desalentar el abuso) y se resetea a 0 apenas se
  // completa la rutina de verdad.
  //
  // historialOmisiones: fechas (yyyy-MM-dd) de ocurrencias omitidas,
  // recortado a los últimos 60 días al escribir. Existe para que
  // _cargarRutinas pueda distinguir, al revisar si se perdió la
  // racha, un día realmente saltado (protegido con moneda, no rompe
  // racha) de un día simplemente no hecho (sí la rompe).
  // ============================================================
  final bool omitida;
  final String? fechaOmitida;
  final int omisionesSeguidas;
  final List<String> historialOmisiones;

  // ============================================================
  // rachaPagadaHasta — hito de racha más alto ya pagado con moneda
  // ------------------------------------------------------------
  // Antes, el otorgamiento de moneda en toggleCompletada solo miraba
  // "¿racha es múltiplo de 7?", recalculado desde cero en cada toggle.
  // Como desmarcar resta 1 a la racha sin revertir la moneda, marcar/
  // desmarcar/marcar sobre el mismo múltiplo de 7 pagaba una moneda
  // nueva cada vez, sin límite. Este campo registra hasta qué racha ya
  // se pagó, así el mismo hito nunca vuelve a cobrar dos veces — ver
  // el chequeo en toggleCompletada.
  //
  // Al desmarcar NO se revierte (decisión de producto: la moneda ya
  // ganada se conserva), así que este campo tampoco retrocede.
  // ============================================================
  final int rachaPagadaHasta;

  // ============================================================
  // omisionesSeguidasAntesDeMarcar — "escrow" de un día, para BUG 2
  // ------------------------------------------------------------
  // -1 = sin valor guardado (estado normal). Al marcar completada
  // (toggleCompletada), justo antes de resetear omisionesSeguidas a 0,
  // se guarda acá el valor que tenía — para poder restaurarlo si el
  // usuario desmarca ESE MISMO DÍA (deshacer un marcado no debería
  // "condonar" omisiones que ya se habían acumulado antes de marcar).
  // Al desmarcar, si este campo tiene un valor (!= -1), se restaura
  // omisionesSeguidas y este campo vuelve a -1.
  //
  // Nunca sobrevive más de un día: _cargarRutinas lo limpia a -1 en el
  // mismo rollover que resetea completada, así que si el usuario NUNCA
  // desmarca (la completada "se sostiene" hasta el cambio de día), el
  // valor guardado queda descartado para siempre — correcto, porque en
  // ese caso la completada fue real y omisionesSeguidas=0 ya es el
  // valor correcto y definitivo.
  //
  // Es un int no-nullable (no int?) a propósito: el patrón de copyWith
  // de este archivo usa "parámetro null = sin cambios" (ver
  // notificacionesActivas/idsPorOcurrencia), así que un campo que
  // necesita poder LIMPIARSE explícitamente no puede ser nullable sin
  // ese mismo copyWith absorbiendo el null como "no tocar" en vez de
  // "vaciar" (es lo que le pasa hoy a fechaCompletada al desmarcar,
  // sin relación con este campo). Con -1 como sentinel evitamos ese
  // problema: limpiar es pasar el literal -1, nunca null.
  // ============================================================
  final int omisionesSeguidasAntesDeMarcar;

  Rutina({
    required this.id,
    required this.titulo,
    this.descripcion,
    required this.horarios,
    required this.iconoCode,
    this.activa = true,
    this.racha = 0,
    this.completada = false,
    this.fechaCompletada,
    this.esFlexible = false,
    this.notificacionesActivas = const [], // Por defecto, ninguna notificación programada aún
    this.ultimaFechaProgramada,
    this.idsPorOcurrencia = const {},
    this.omitida = false,
    this.fechaOmitida,
    this.omisionesSeguidas = 0,
    this.historialOmisiones = const [],
    this.rachaPagadaHasta = 0,
    this.omisionesSeguidasAntesDeMarcar = -1,
  });

  Rutina copyWith({
    String? id,
    String? titulo,
    String? descripcion,
    Map<int, TimeOfDay>? horarios,
    int? iconoCode,
    bool? activa,
    int? racha,
    bool? completada,
    String? fechaCompletada,
    bool? esFlexible,
    List<int>? notificacionesActivas,
    DateTime? ultimaFechaProgramada,
    Map<String, List<int>>? idsPorOcurrencia,
    bool? omitida,
    String? fechaOmitida,
    int? omisionesSeguidas,
    List<String>? historialOmisiones,
    int? rachaPagadaHasta,
    int? omisionesSeguidasAntesDeMarcar,
    // Excepción al patrón "parámetro null = sin cambios" de este copyWith:
    // descripcion es el único campo editable desde el formulario que es a la
    // vez nullable y limpiable por el usuario (borrar el texto = guardar
    // null), así que un `descripcion: null` normal sería indistinguible de
    // "no lo toques" y la descripción vieja quedaría pegada para siempre.
    // Este flag separa ambos casos sin recurrir a un valor centinela.
    bool limpiarDescripcion = false,
  }) {
    return Rutina(
      id: id ?? this.id,
      titulo: titulo ?? this.titulo,
      descripcion: limpiarDescripcion ? null : (descripcion ?? this.descripcion),
      horarios: horarios ?? this.horarios,
      iconoCode: iconoCode ?? this.iconoCode,
      activa: activa ?? this.activa,
      racha: racha ?? this.racha,
      completada: completada ?? this.completada,
      fechaCompletada: fechaCompletada ?? this.fechaCompletada,
      esFlexible: esFlexible ?? this.esFlexible,
      notificacionesActivas: notificacionesActivas ?? this.notificacionesActivas,
      ultimaFechaProgramada: ultimaFechaProgramada ?? this.ultimaFechaProgramada,
      idsPorOcurrencia: idsPorOcurrencia ?? this.idsPorOcurrencia,
      omitida: omitida ?? this.omitida,
      fechaOmitida: fechaOmitida ?? this.fechaOmitida,
      omisionesSeguidas: omisionesSeguidas ?? this.omisionesSeguidas,
      historialOmisiones: historialOmisiones ?? this.historialOmisiones,
      rachaPagadaHasta: rachaPagadaHasta ?? this.rachaPagadaHasta,
      omisionesSeguidasAntesDeMarcar: omisionesSeguidasAntesDeMarcar ?? this.omisionesSeguidasAntesDeMarcar,
    );
  }

  Map<String, dynamic> toJson() {
    final horariosJson = horarios.map((key, value) => MapEntry(key.toString(), {'hour': value.hour, 'minute': value.minute}));
    
    return {
      'id': id,
      'titulo': titulo,
      'descripcion': descripcion,
      'horarios': horariosJson,
      'iconoCode': iconoCode,
      'activa': activa,
      'racha': racha,
      'completada': completada,
      'fechaCompletada': fechaCompletada,
      'esFlexible': esFlexible,
      // Guardamos la lista de IDs reales para poder recuperarla al reabrir la app
      'notificacionesActivas': notificacionesActivas,
      'ultimaFechaProgramada': ultimaFechaProgramada?.toIso8601String(),
      'idsPorOcurrencia': idsPorOcurrencia,
      'omitida': omitida,
      'fechaOmitida': fechaOmitida,
      'omisionesSeguidas': omisionesSeguidas,
      'historialOmisiones': historialOmisiones,
      'rachaPagadaHasta': rachaPagadaHasta,
      'omisionesSeguidasAntesDeMarcar': omisionesSeguidasAntesDeMarcar,
    };
  }

  factory Rutina.fromJson(Map<String, dynamic> json) {
    Map<int, TimeOfDay> horariosParsados = {};

    if (json.containsKey('horarios') && json['horarios'] != null) {
      final Map<String, dynamic> hMap = json['horarios'];
      hMap.forEach((k, v) {
        horariosParsados[int.parse(k)] = TimeOfDay(hour: v['hour'], minute: v['minute']);
      });
    } 
    else if (json.containsKey('diasSemana')) {
      List<bool> viejosDias = List<bool>.from(json['diasSemana']);
      TimeOfDay viejaHora = TimeOfDay(hour: json['hora'] as int, minute: json['minuto'] as int);
      for(int i=0; i<viejosDias.length; i++) {
        if (viejosDias[i]) horariosParsados[i] = viejaHora;
      }
    }

    return Rutina(
      id: json['id'] as String,
      titulo: json['titulo'] as String,
      descripcion: json['descripcion'] as String?,
      horarios: horariosParsados,
      iconoCode: json['iconoCode'] as int,
      activa: json['activa'] as bool,
      racha: json['racha'] as int? ?? 0,
      completada: json['completada'] as bool? ?? false,
      fechaCompletada: json['fechaCompletada'] as String?,
      esFlexible: json['esFlexible'] as bool? ?? false, 
      // Rutinas guardadas ANTES de este cambio no tendrán este campo:
      // les asignamos lista vacía (no rompe nada, simplemente no habrá
      // nada que cancelar de forma "recordada" hasta que se reprogramen
      // por primera vez con el nuevo sistema).
      notificacionesActivas: (json['notificacionesActivas'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          const [],
      // Rutinas guardadas ANTES de este campo (o restauradas de un respaldo
      // de otro dispositivo) no lo tendrán: usamos tryParse para que un
      // valor ausente o corrupto se convierta en null en vez de crashear,
      // y null fuerza el reset completo que "siembra" el campo de nuevo.
      ultimaFechaProgramada: json['ultimaFechaProgramada'] != null
          ? DateTime.tryParse(json['ultimaFechaProgramada'] as String)
          : null,
      // Rutinas guardadas ANTES de este campo no lo tendrán: mapa vacío
      // fuerza (ver _rellenarColchonSiHaceFalta) un reset completo único
      // que lo siembra, igual que con ultimaFechaProgramada.
      idsPorOcurrencia: (json['idsPorOcurrencia'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, (v as List<dynamic>).map((e) => e as int).toList())) ??
          const {},
      // Rutinas guardadas antes de la función "omitir" no tendrán estos
      // campos: los valores por defecto (sin omitir, sin historial) son
      // seguros y no requieren ninguna migración especial.
      omitida: json['omitida'] as bool? ?? false,
      fechaOmitida: json['fechaOmitida'] as String?,
      omisionesSeguidas: json['omisionesSeguidas'] as int? ?? 0,
      historialOmisiones: (json['historialOmisiones'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      // Rutinas guardadas ANTES de este campo (fix de monedas infinitas):
      // si falta, se siembra con la racha actual de esa misma rutina, NO
      // con 0. Con 0, un tester que ya llegó a una racha alta bajo el
      // código viejo podría cobrar de nuevo el mismo hito con solo
      // desmarcar y volver a marcar tras actualizar. Sembrar con la racha
      // actual bloquea ese re-cobro puntual sin afectar los hitos futuros
      // (la comparación en toggleCompletada es contra múltiplos de 7 POR
      // ENCIMA de este valor, así que sembrar con un valor que no es en
      // sí mismo múltiplo de 7 no cambia cuándo se paga el próximo hito).
      rachaPagadaHasta: json['rachaPagadaHasta'] as int? ?? (json['racha'] as int? ?? 0),
      // Rutinas guardadas ANTES de este campo: -1 (sin valor guardado) es
      // el mismo default que una rutina nueva, seguro sin migración especial.
      omisionesSeguidasAntesDeMarcar: json['omisionesSeguidasAntesDeMarcar'] as int? ?? -1,
    );
  }
}
