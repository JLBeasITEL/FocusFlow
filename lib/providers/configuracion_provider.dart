import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ConfiguracionSonidos {
  final String sonidoNotificacion;
  final String sonidoAlarma;

  ConfiguracionSonidos({
    required this.sonidoNotificacion,
    required this.sonidoAlarma,
  });
}

class SonidoNotifier extends Notifier<ConfiguracionSonidos> {
  @override
  ConfiguracionSonidos build() {
    _cargarSonidos();
    // Valores por defecto estrictos
    return ConfiguracionSonidos(
      sonidoNotificacion: 'default_nota', 
      sonidoAlarma: 'default_alarma',
    );
  }

  Future<void> _cargarSonidos() async {
    final prefs = await SharedPreferences.getInstance();
    final nota = prefs.getString('sonido_notificacion') ?? 'default_nota';
    final alarma = prefs.getString('sonido_alarma') ?? 'default_alarma';
    
    state = ConfiguracionSonidos(sonidoNotificacion: nota, sonidoAlarma: alarma);
  }

  // Fuerza una relectura completa desde SharedPreferences. Se usa tras
  // restaurar un respaldo.
  Future<void> recargarDesdeDisco() async {
    await _cargarSonidos();
  }

  Future<void> cambiarSonidoNotificacion(String nuevoSonido) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sonido_notificacion', nuevoSonido);
    state = ConfiguracionSonidos(sonidoNotificacion: nuevoSonido, sonidoAlarma: state.sonidoAlarma);
  }

  Future<void> cambiarSonidoAlarma(String nuevoSonido) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sonido_alarma', nuevoSonido);
    state = ConfiguracionSonidos(sonidoNotificacion: state.sonidoNotificacion, sonidoAlarma: nuevoSonido);
  }
}

// Este es el provider que settings_screen.dart está intentando leer:
final sonidoProvider = NotifierProvider<SonidoNotifier, ConfiguracionSonidos>(() {
  return SonidoNotifier();
});

// Estilo de transición al cambiar de pestaña (Tareas/Rutinas/Notas) en el
// layout landscape de HomeScreen (portrait ya anima con el swipe nativo de
// TabBarView). Configurable desde Ajustes > Apariencia — ver
// _construirContenidoTabAnimado en home_screen.dart, que es el único lugar
// que lee este valor para decidir qué transición dibujar.
enum TransicionTab {
  // Cross-fade sin movimiento: la más simple y liviana.
  fade,
  // Fade + la pantalla nueva "flota" un poco hacia arriba al entrar.
  fadeDeslizamiento,
  // Desliza horizontalmente, entrando desde el lado hacia el que se navegó
  // (como páginas una al lado de la otra).
  horizontal,
}

class TransicionTabNotifier extends Notifier<TransicionTab> {
  static const String _key = 'transicion_tab_landscape';

  @override
  TransicionTab build() {
    _cargarGuardada();
    return TransicionTab.fade;
  }

  Future<void> _cargarGuardada() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_key);
    if (index != null && index < TransicionTab.values.length) {
      state = TransicionTab.values[index];
    }
  }

  // Fuerza una relectura completa desde SharedPreferences. Se usa tras
  // restaurar un respaldo.
  Future<void> recargarDesdeDisco() async {
    await _cargarGuardada();
  }

  Future<void> cambiar(TransicionTab nueva) async {
    state = nueva;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, nueva.index);
  }
}

final transicionTabProvider = NotifierProvider<TransicionTabNotifier, TransicionTab>(() {
  return TransicionTabNotifier();
});