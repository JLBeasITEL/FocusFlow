import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../../providers/tarea_provider.dart'; 

class PantallaAlarma extends ConsumerWidget {
  final int idAlarma;
  final String titulo;
  final String cuerpo;
  final int iconoCode;

  const PantallaAlarma({
    super.key,
    required this.idAlarma,
    required this.titulo,
    required this.cuerpo,
    required this.iconoCode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1. Escuchamos el tema actual configurado en la app
    final temaActual = ref.watch(temaProvider);

    // 2. Definimos las paletas de colores según el tema
    Color bgColor;
    Color textColor;
    Color accentColor;

    switch (temaActual) {
      case TemaApp.zenClasico:
        bgColor = const Color(0xFFF4F1EA); // Beige suave
        textColor = const Color(0xFF4A4A4A);
        accentColor = const Color(0xFF7B9E87); // Verde salvia
        break;
      case TemaApp.brisaMarina:
        bgColor = const Color(0xFFE8F4F8); // Azul muy claro
        textColor = const Color(0xFF1B4965);
        accentColor = const Color(0xFF62B6CB); // Azul agua
        break;
      case TemaApp.atardecerMinimalista:
        bgColor = const Color(0xFFFFF5EC); // Naranja suavizado
        textColor = const Color(0xFF5D4037);
        accentColor = const Color(0xFFE29578); // Terracota claro
        break;
      case TemaApp.clasico:
        bgColor = const Color(0xFFF8F9FA); // Gris casi blanco
        textColor = const Color(0xFF212529);
        accentColor = const Color(0xFF276749); // Tu verde original
        break;
    }

    // 3. Construimos la interfaz fluida y moderna
    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              
              // Círculo decorativo con el icono
              Container(
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accentColor.withValues(alpha: 0.15),
                ),
                // Si viene un ícono, lo armamos. Si es 0, usamos la campana genérica
                child: Icon(
                  iconoCode != 0 
                      ? IconData(iconoCode, fontFamily: 'MaterialIcons') 
                      : Icons.notifications_active_rounded,
                  size: 100,
                  color: accentColor,
                ),
              ),
              
              const SizedBox(height: 48),
              
              // Textos de la alarma
              Text(
                titulo,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                cuerpo,
                style: TextStyle(
                  fontSize: 18,
                  height: 1.4,
                  color: textColor.withValues(alpha: 0.8),
                ),
                textAlign: TextAlign.center,
              ),
              
              const Spacer(flex: 2),
              
              // Botón de acción ancho y redondeado
              SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  onPressed: () {
                    // Cierra la aplicación por completo y restaura el bloqueo
                    SystemNavigator.pop();
                  },
                  child: const Text(
                    'Entendido',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}