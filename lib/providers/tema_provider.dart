import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Definición central de tus temas. Como tu HomeScreen ya lo importa,
// reconocerá automáticamente las opciones.
// Medianoche se agrega al final para no romper el índice numérico que
// tema_seleccionado persiste en SharedPreferences para los 4 temas previos.
enum TemaApp { clasico, zenClasico, brisaMarina, atardecerMinimalista, medianoche }

// Fuente única de verdad para los colores/degradados asociados a cada tema.
// Antes estaban repetidos como métodos privados en HomeScreen, SettingsScreen
// y PantallaAlarma; ahora todas esas pantallas consumen estos getters.
extension TemaColores on TemaApp {
  Color get colorPrincipal {
    if (this == TemaApp.clasico) return Colors.black87;
    if (this == TemaApp.brisaMarina) return const Color(0xFF1E3A8A);
    if (this == TemaApp.atardecerMinimalista) return const Color(0xFFC05621);
    if (this == TemaApp.medianoche) return const Color(0xFF93C5FD);
    return const Color(0xFF276749); // Zen Clásico
  }

  // Color de texto/ícono a usar sobre superficies rellenas con colorPrincipal
  // (FAB, AppBar de pantallas secundarias). En los temas claros colorPrincipal
  // ya es oscuro, así que blanco funciona. Medianoche invierte colorPrincipal
  // a un tono claro para que se lea sobre su fondo oscuro, así que ahí
  // necesita texto/ícono oscuro en vez de blanco.
  Color get colorSobrePrincipal {
    if (this == TemaApp.medianoche) return const Color(0xFF10131C);
    return Colors.white;
  }

  // Color de los títulos de grupo/carpeta en la lista de tareas. Solo
  // Medianoche lo necesita: su texto por defecto (heredado del ThemeData
  // claro global) es casi negro y se pierde contra el fondo oscuro, así
  // que aquí se fuerza un lila claro que resalte. Los demás temas
  // devuelven null para seguir heredando el estilo por defecto.
  Color? get colorTituloGrupo {
    if (this == TemaApp.medianoche) return const Color(0xFFD8B4FE);
    return null;
  }

  // Superficie tipo "tarjeta/panel" (sidebar y tarjetas compactas del layout
  // horizontal): blanco en los 4 temas claros, tintada y oscura en Medianoche
  // para no perder el contraste que ya cuida TareaCard en ese tema.
  Color get colorSuperficieCard {
    if (this == TemaApp.medianoche) return colorPrincipal.withValues(alpha: 0.08);
    return Colors.white;
  }

  // Texto/íconos por defecto sobre colorSuperficieCard. Mismo criterio que
  // colorTituloGrupo: solo Medianoche necesita invertir a un tono claro.
  Color get colorTextoSuperficie {
    if (this == TemaApp.medianoche) return const Color(0xFFF1F5F9);
    return Colors.black87;
  }

  Color get colorFondo {
    if (this == TemaApp.clasico) return Colors.white;
    if (this == TemaApp.brisaMarina) return const Color(0xFFF0F8FF);
    if (this == TemaApp.atardecerMinimalista) return const Color(0xFFFFF9F5);
    if (this == TemaApp.medianoche) return const Color(0xFF10131C);
    return const Color(0xFFF2F7F2); // Zen Clásico
  }

  Gradient get degradadoFondo {
    if (this == TemaApp.clasico) return const LinearGradient(colors: [Colors.white, Colors.white]);
    if (this == TemaApp.brisaMarina) return const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF0F8FF), Color(0xFF9FB8D0)]);
    if (this == TemaApp.atardecerMinimalista) return const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF9F5), Color(0xFFE5B270)]);
    if (this == TemaApp.medianoche) return const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF10131C), Color(0xFF262A4E)]);
    return const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF2F7F2), Color(0xFF8BA888)]);
  }

  // --- Paleta específica de la pantalla de alarma (PantallaAlarma) ---
  Color get colorFondoAlarma {
    switch (this) {
      case TemaApp.zenClasico: return const Color(0xFFF4F1EA);
      case TemaApp.brisaMarina: return const Color(0xFFE8F1F5);
      case TemaApp.atardecerMinimalista: return const Color(0xFFFFF5E6);
      case TemaApp.medianoche: return const Color(0xFF0D0F1A);
      case TemaApp.clasico: return Colors.white;
    }
  }

  Color get colorTextoAlarma {
    switch (this) {
      case TemaApp.zenClasico: return const Color(0xFF4A4A4A);
      case TemaApp.brisaMarina: return const Color(0xFF2C3E50);
      case TemaApp.atardecerMinimalista: return const Color(0xFF5C4A3D);
      case TemaApp.medianoche: return const Color(0xFFE8EAF6);
      case TemaApp.clasico: return Colors.black87;
    }
  }

  Color get colorAcentoAlarma {
    switch (this) {
      case TemaApp.zenClasico: return const Color(0xFF7B9E87);
      case TemaApp.brisaMarina: return const Color(0xFF5D9B9B);
      case TemaApp.atardecerMinimalista: return const Color(0xFFE07A5F);
      case TemaApp.medianoche: return const Color(0xFF6D5DF6);
      case TemaApp.clasico: return Colors.teal;
    }
  }

  Color get colorPosponerAlarma {
    switch (this) {
      case TemaApp.zenClasico: return const Color(0xFF5A7A65);
      case TemaApp.brisaMarina: return const Color(0xFF1B4965);
      case TemaApp.atardecerMinimalista: return const Color(0xFFAC6B53);
      case TemaApp.medianoche: return const Color(0xFF4338CA);
      case TemaApp.clasico: return Colors.teal.shade700;
    }
  }
}

class TemaNotifier extends Notifier<TemaApp> {
  static const String _temaKey = 'tema_seleccionado';

  @override
  TemaApp build() {
    // Al abrir la app, inicia con el clásico, pero inmediatamente 
    // manda a buscar a la memoria si el usuario había guardado otro.
    _cargarTemaGuardado();
    return TemaApp.clasico; 
  }

  // --- LEER DE LA MEMORIA ---
  Future<void> _cargarTemaGuardado() async {
    final prefs = await SharedPreferences.getInstance();
    // Lee el número guardado (0, 1, 2 o 3)
    final index = prefs.getInt(_temaKey);
    
    // Si encontró un número válido, actualiza la pantalla automáticamente
    if (index != null && index < TemaApp.values.length) {
      state = TemaApp.values[index];
    }
  }

  // Fuerza una relectura completa desde SharedPreferences. Se usa tras
  // restaurar un respaldo.
  Future<void> recargarDesdeDisco() async {
    await _cargarTemaGuardado();
  }

  // --- GUARDAR EN LA MEMORIA ---
  // Este es el método que tu HomeScreen ya está llamando en el PopupMenuButton
  Future<void> cambiarTema(TemaApp nuevoTema) async {
    // 1. Cambia el color en pantalla
    state = nuevoTema; 
    
    // 2. Lo guarda en el disco duro del teléfono
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_temaKey, nuevoTema.index);
  }
}

// El proveedor que Riverpod utiliza para distribuir el estado
final temaProvider = NotifierProvider<TemaNotifier, TemaApp>(() {
  return TemaNotifier();
});

// --- BADGE "NUEVO" DE MEDIANOCHE (se muestra solo hasta que el usuario
// abre el selector de temas por primera vez) ---
class BadgeMedianocheNotifier extends Notifier<bool> {
  static const String _key = 'medianoche_badge_visto';

  @override
  bool build() {
    _cargarEstado();
    return true; // Se asume visible hasta confirmar que ya se mostró antes
  }

  Future<void> _cargarEstado() async {
    final prefs = await SharedPreferences.getInstance();
    final yaVisto = prefs.getBool(_key) ?? false;
    if (yaVisto) state = false;
  }

  // Se llama al abrir el selector de temas: oculta el badge desde ahora
  // y persiste que ya se mostró para que no vuelva a aparecer.
  Future<void> marcarComoVisto() async {
    state = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }
}

final medianocheBadgeProvider = NotifierProvider<BadgeMedianocheNotifier, bool>(() {
  return BadgeMedianocheNotifier();
});