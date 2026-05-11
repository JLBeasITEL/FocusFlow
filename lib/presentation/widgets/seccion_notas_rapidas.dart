import 'package:flutter/material.dart';

class SeccionNotasRapidas extends StatefulWidget {
  final Color textColor;
  final Color accentColor;

  const SeccionNotasRapidas({
    super.key, 
    required this.textColor, 
    required this.accentColor,
  });

  @override
  State<SeccionNotasRapidas> createState() => _SeccionNotasRapidasState();
}

class _SeccionNotasRapidasState extends State<SeccionNotasRapidas> {
  final TextEditingController _notasController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Aquí puedes cargar la nota desde tu base de datos al iniciar
    // _notasController.text = ...
  }

  @override
  void dispose() {
    _notasController.dispose();
    super.dispose();
  }

  void _guardarNota(String texto) {
    // Para guardar el texto de forma persistente y que no se pierda al cerrar la app, 
    // puedes conectar este método directamente a tu base de datos en Firebase.
    print('Guardando en backend: $texto');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.textColor.withValues(alpha: 0.05), // Fondo muy sutil
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: widget.textColor.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note_rounded, color: widget.accentColor, size: 24),
              const SizedBox(width: 8),
              Text(
                'Notas Rápidas',
                style: TextStyle(
                  fontSize: 18, 
                  fontWeight: FontWeight.bold, 
                  color: widget.textColor
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notasController,
            maxLines: 5, // Límite máximo antes de hacer scroll interno
            minLines: 2, // Tamaño mínimo inicial
            style: TextStyle(color: widget.textColor, fontSize: 16),
            decoration: InputDecoration(
              hintText: 'Escribe ideas, recados o pendientes rápidos aquí...',
              hintStyle: TextStyle(color: widget.textColor.withValues(alpha: 0.4), fontSize: 14),
              border: InputBorder.none, // Sin línea inferior para un look más limpio
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (valor) {
              // Guarda automáticamente conforme el usuario escribe
              _guardarNota(valor);
            },
          ),
        ],
      ),
    );
  }
}