import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Lista de permisos que este onboarding gestiona, en el orden en que
/// deben pedirse. NOTA: shared_preferences ya no se usa aquí a propósito:
/// antes se marcaba "ya mostrado" una sola vez para siempre, sin importar
/// si el usuario realmente concedió algo. Ahora el criterio para mostrar
/// (o no) este diálogo es el ESTADO REAL de los permisos en el sistema.
const List<Permission> _permisosGestionados = [
  Permission.notification,
  Permission.scheduleExactAlarm,
  Permission.ignoreBatteryOptimizations,
];

class OnboardingPermisos extends StatefulWidget {
  const OnboardingPermisos({super.key});

  /// Llama esto cada vez que se inicia la pantalla principal (initState).
  /// Como el criterio ya no es "¿ya se mostró alguna vez?" sino "¿falta
  /// algún permiso de verdad?", es seguro y correcto llamarlo en cada
  /// apertura de la app: si todo está concedido, no se mostrará nada.
  static Future<void> verificarYMostrar(BuildContext context) async {
    final faltantes = await _permisosFaltantes();
    if (faltantes.isNotEmpty && context.mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const OnboardingPermisos(),
      );
    }
  }

  static Future<List<Permission>> _permisosFaltantes() async {
    final faltantes = <Permission>[];
    for (final permiso in _permisosGestionados) {
      final estado = await permiso.status;
      if (!estado.isGranted) faltantes.add(permiso);
    }
    return faltantes;
  }

  @override
  State<OnboardingPermisos> createState() => _OnboardingPermisosState();
}

class _OnboardingPermisosState extends State<OnboardingPermisos>
    with WidgetsBindingObserver {
  List<Permission> _pasosPendientes = [];
  bool _cargando = true;

  // Guarda qué permiso quedó "en el aire" mientras el usuario estuvo en
  // Ajustes. Al volver (resumed), lo volvemos a chequear de verdad en vez
  // de asumir que se concedió solo porque el usuario regresó.
  Permission? _permisoEsperandoRegreso;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _inicializarPasos();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _inicializarPasos() async {
    final faltantes = await OnboardingPermisos._permisosFaltantes();
    if (!mounted) return;
    setState(() {
      _pasosPendientes = faltantes;
      _cargando = false;
    });
    if (_pasosPendientes.isEmpty) {
      Navigator.pop(context);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state != AppLifecycleState.resumed || _permisoEsperandoRegreso == null) {
      return;
    }
    final permiso = _permisoEsperandoRegreso!;
    _permisoEsperandoRegreso = null;

    // Este es el chequeo que faltaba: solo avanzamos si el permiso
    // REALMENTE quedó concedido al volver de Ajustes/diálogo del sistema.
    final estado = await permiso.status;
    if (!mounted) return;

    if (estado.isGranted) {
      _avanzar();
    } else {
      // Sigue sin concederse: nos quedamos en el mismo paso para que
      // el usuario pueda reintentar o saltarlo con "Ahora no".
      setState(() {});
    }
  }

  void _avanzar() {
    if (_pasosPendientes.isEmpty) return;
    setState(() {
      _pasosPendientes.removeAt(0);
    });
    if (_pasosPendientes.isEmpty) {
      Navigator.pop(context);
    }
  }

  Future<void> _manejarPermiso(Permission permiso) async {
    final estadoActual = await permiso.status;

    if (estadoActual.isPermanentlyDenied) {
      // El sistema ya no va a mostrar ningún diálogo para este permiso
      // (el usuario lo rechazó antes de forma permanente, o es de los
      // que solo se activan desde Ajustes). Sin esto, tocar "Permitir"
      // no hacía absolutamente nada visible: por eso se sentía "de
      // trámite". La única salida real es ir a los Ajustes de la app.
      _permisoEsperandoRegreso = permiso;
      await openAppSettings();
      return;
    }

    if (permiso == Permission.notification) {
      // Es el único permiso de este grupo con diálogo nativo fiable en
      // Android (13+) cuyo resultado se puede leer de forma síncrona.
      final resultado = await permiso.request();
      if (resultado.isGranted || resultado.isDenied) {
        _avanzar();
      } else if (resultado.isPermanentlyDenied) {
        _permisoEsperandoRegreso = permiso;
        await openAppSettings();
      }
      return;
    }

    // scheduleExactAlarm, ignoreBatteryOptimizations:
    // Android no tiene diálogo nativo para estos, permission_handler abre
    // la pantalla de Ajustes correspondiente. El Future de aquí puede
    // resolverse ANTES de que el usuario termine de activar el switch,
    // así que NO avanzamos en este punto: esperamos a que la app vuelva
    // a primer plano (didChangeAppLifecycleState) y ahí sí verificamos
    // el estado real.
    _permisoEsperandoRegreso = permiso;
    await permiso.request();
  }

  void _saltarPaso() {
    // Cierra el diálogo por esta sesión. Como ya no dependemos de un
    // flag de "visto", volverá a aparecer en el próximo inicio si el
    // permiso sigue faltando.
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const AlertDialog(
        content: SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final totalPendientes = _pasosPendientes.length;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(Icons.settings_suggest_rounded,
              color: Colors.blueAccent, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Configuración inicial ($totalPendientes pendiente${totalPendientes == 1 ? '' : 's'})',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
      content: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _construirContenidoPaso(),
      ),
    );
  }

  Widget _construirContenidoPaso() {
    if (_pasosPendientes.isEmpty) {
      return const SizedBox.shrink();
    }
    final permisoActual = _pasosPendientes.first;

    if (permisoActual == Permission.notification) {
      return _PasoContenido(
        key: const ValueKey('notification'),
        icono: Icons.notifications_active_rounded,
        titulo: 'Notificaciones',
        descripcion:
            'Para avisarte de tus hábitos, necesitamos enviarte notificaciones.',
        textoBoton: 'Permitir',
        onPressed: () => _manejarPermiso(permisoActual),
        onSaltar: _saltarPaso,
      );
    } else if (permisoActual == Permission.scheduleExactAlarm) {
      return _PasoContenido(
        key: const ValueKey('exactAlarm'),
        icono: Icons.timer_rounded,
        titulo: 'Alarmas exactas',
        descripcion:
            'Para que las alarmas suenen a la hora exacta, el sistema necesita permiso para programar alarmas exactas.',
        textoBoton: 'Ir a Ajustes',
        onPressed: () => _manejarPermiso(permisoActual),
        onSaltar: _saltarPaso,
      );
    } else {
      // ignoreBatteryOptimizations
      return _PasoContenido(
        key: const ValueKey('battery'),
        icono: Icons.battery_saver_rounded,
        titulo: 'Ahorro de batería',
        descripcion:
            'Desactiva el ahorro de batería para esta app para que las alarmas no se retrasen ni se cancelen.',
        textoBoton: 'Ir a Ajustes',
        onPressed: () => _manejarPermiso(permisoActual),
        onSaltar: _saltarPaso,
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
  final VoidCallback onSaltar;

  const _PasoContenido({
    super.key,
    required this.icono,
    required this.titulo,
    required this.descripcion,
    required this.textoBoton,
    required this.onPressed,
    required this.onSaltar,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 60, color: Colors.black54),
        const SizedBox(height: 16),
        Text(titulo,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 12),
        Text(descripcion,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, height: 1.4)),
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
        ),
        TextButton(
          onPressed: onSaltar,
          child: const Text('Ahora no'),
        ),
      ],
    );
  }
}