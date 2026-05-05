import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Definición central de tus temas. Como tu HomeScreen ya lo importa, 
// reconocerá automáticamente las 4 opciones.
enum TemaApp { clasico, zenClasico, brisaMarina, atardecerMinimalista }

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