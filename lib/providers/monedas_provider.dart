import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================
// MonedasNotifier — "monedas de racha"
// ------------------------------------------------------------
// Moneda global (no por rutina) que se gana al alcanzar un hito de
// racha semanal en CUALQUIER rutina (ver el otorgamiento en
// toggleCompletada, rutina_provider.dart) y se gasta al omitir una
// ocurrencia de hoy sin romper la racha (ver toggleOmitida, mismo
// archivo). Al atar la ganancia a la constancia real, el propio
// costo de "hacer trampa" queda limitado por qué tan consistente ha
// sido el usuario, sin necesitar un tope artificial aparte.
// ============================================================
class MonedasNotifier extends Notifier<int> {
  static const String _storageKey = 'monedas_racha_v1';

  // Regalo de bienvenida para que un usuario nuevo pueda probar la función
  // de omitir sin tener que esperar a cumplir su primera racha de 7.
  static const int _monedasBienvenida = 3;

  @override
  int build() {
    _cargarMonedas();
    return 0;
  }

  Future<void> _cargarMonedas() async {
    final prefs = await SharedPreferences.getInstance();
    // containsKey (no getInt == null): la clave solo falta si NUNCA se
    // guardó nada acá, es decir, un usuario nuevo (o una reinstalación).
    // Un usuario que ya gastó todas sus monedas hasta 0 sí tiene la clave
    // escrita (con valor 0) y no debe volver a recibir el regalo.
    if (!prefs.containsKey(_storageKey)) {
      state = _monedasBienvenida;
      await _guardarMonedas();
      return;
    }
    state = prefs.getInt(_storageKey) ?? 0;
  }

  Future<void> _guardarMonedas() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_storageKey, state);
  }

  // Fuerza una relectura completa desde SharedPreferences. Se usa tras
  // restaurar un respaldo.
  Future<void> recargarDesdeDisco() async {
    await _cargarMonedas();
  }

  Future<void> agregar(int cantidad) async {
    if (cantidad <= 0) return;
    state = state + cantidad;
    await _guardarMonedas();
  }

  // Devuelve false (sin cambiar nada) si no alcanzan las monedas.
  Future<bool> gastar(int cantidad) async {
    if (cantidad <= 0) return true;
    if (state < cantidad) return false;
    state = state - cantidad;
    await _guardarMonedas();
    return true;
  }
}

final monedasProvider = NotifierProvider<MonedasNotifier, int>(() {
  return MonedasNotifier();
});
