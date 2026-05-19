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