import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingPermisos extends StatefulWidget {
  const OnboardingPermisos({super.key});

  // Esta función comprueba si es la primera vez y muestra el diálogo
  static Future<void> verificarYMostrar(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final bool yaMostrado = prefs.getBool('onboarding_permisos_v1') ?? false;

    if (!yaMostrado && context.mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false, // Obliga al usuario a interactuar
        builder: (context) => const OnboardingPermisos(),
      );
      // Marcamos que ya se mostró para que no vuelva a salir nunca
      await prefs.setBool('onboarding_permisos_v1', true);
    }
  }

  @override
  State<OnboardingPermisos> createState() => _OnboardingPermisosState();
}

class _OnboardingPermisosState extends State<OnboardingPermisos> {
  int _pasoActual = 1;

  void _avanzarPaso() {
    setState(() {
      _pasoActual++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(Icons.settings_suggest_rounded, color: Colors.blueAccent, size: 28),
          const SizedBox(width: 10),
          const Text('Configuración inicial'),
        ],
      ),
      content: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _construirContenidoPaso(),
      ),
    );
  }

  Widget _construirContenidoPaso() {
    // PASO 1: Notificaciones estándar
    if (_pasoActual == 1) {
      return _PasoContenido(
        key: const ValueKey(1),
        icono: Icons.notifications_active_rounded,
        titulo: 'Paso 1 de 3: Notificaciones',
        descripcion: 'Para avisarte de tus hábitos, necesitamos enviarte notificaciones.',
        textoBoton: 'Permitir',
        onPressed: () async {
          await Permission.notification.request();
          _avanzarPaso();
        },
      );
    } 
    // PASO 2: Alarmas Exactas y Batería
    else if (_pasoActual == 2) {
      return _PasoContenido(
        key: const ValueKey(2),
        icono: Icons.timer_rounded,
        titulo: 'Paso 2 de 3: Precisión',
        descripcion: 'Para que las alarmas suenen a la hora exacta, el sistema necesita permiso para programar alarmas exactas e ignorar el ahorro de batería.',
        textoBoton: 'Dar permiso',
        onPressed: () async {
          await Permission.scheduleExactAlarm.request();
          await Permission.ignoreBatteryOptimizations.request();
          _avanzarPaso();
        },
      );
    } 
    // PASO 3: Sobre otras apps (Pantalla de bloqueo Xiaomi/etc)
    else {
      return _PasoContenido(
        key: const ValueKey(3),
        icono: Icons.screen_lock_portrait_rounded,
        titulo: 'Paso 3 de 3: Pantalla de bloqueo',
        descripcion: 'Para que la alarma pueda encender tu pantalla cuando el teléfono esté bloqueado (vital en Xiaomi, Poco, etc.), activa el permiso de "Mostrar sobre otras apps".',
        textoBoton: 'Ir a Ajustes y Finalizar',
        onPressed: () async {
          await Permission.systemAlertWindow.request();
          if (mounted) Navigator.pop(context); // Cierra el diálogo y termina
        },
      );
    }
  }
}

// Widget auxiliar para mantener el código limpio
class _PasoContenido extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String descripcion;
  final String textoBoton;
  final VoidCallback onPressed;

  const _PasoContenido({
    super.key,
    required this.icono,
    required this.titulo,
    required this.descripcion,
    required this.textoBoton,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 60, color: Colors.black54),
        const SizedBox(height: 16),
        Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 12),
        Text(descripcion, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, height: 1.4)),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black87,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: onPressed,
            child: Text(textoBoton, style: const TextStyle(fontSize: 16)),
          ),
        )
      ],
    );
  }
}