import 'package:flutter/material.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';

class FeedbackModal extends StatefulWidget {
  const FeedbackModal({super.key});

  @override
  State<FeedbackModal> createState() => _FeedbackModalState();
}

class _FeedbackModalState extends State<FeedbackModal> {
  final TextEditingController _mensajeController = TextEditingController();
  String _tipoFeedback = 'Sugerencia'; // Opción por defecto


  Future<void> _enviarFeedback() async {
    final texto = _mensajeController.text.trim();
    if (texto.isEmpty) return;

    // Construimos el objeto del correo usando el nuevo paquete
    final Email email = Email(
      body: 'Categoría: $_tipoFeedback\n\nDetalles del mensaje:\n$texto\n\n--- \nEnviado desde FocusFlow App',
      subject: 'Feedback App de Tareas - $_tipoFeedback',
      recipients: ['jl.beas_itel@outlook.com'], 
      isHTML: false,
    );

    try {
      // Esta función fuerza internamente la creación de un "App Chooser" en Android
      await FlutterEmailSender.send(email);
      
      if (mounted) {
        Navigator.pop(context); 
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir el menú de correos.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _mensajeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorTema = Theme.of(context).primaryColor;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 24, right: 24, top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- BARRA SUPERIOR (Mango para deslizar) ---
            Center(
              child: Container(
                width: 40, height: 4, margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            
            // --- TÍTULO ---
            const Text(
              'Enviar Comentarios',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Ayúdanos a mejorar. ¿Qué te gustaría compartirnos?',
              style: TextStyle(color: Colors.grey, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // --- SELECTOR DE CATEGORÍA ---
            const Text('Categoría', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Sugerencia', label: Text('Sugerencia', style: TextStyle(fontSize: 12))),
                ButtonSegment(value: 'Error/Bug', label: Text('Error/Bug', style: TextStyle(fontSize: 12))),
                ButtonSegment(value: 'Otro', label: Text('Otro', style: TextStyle(fontSize: 12))),
              ],
              selected: {_tipoFeedback},
              onSelectionChanged: (Set<String> sel) => setState(() => _tipoFeedback = sel.first),
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith<Color>(
                  (Set<WidgetState> states) {
                    if (states.contains(WidgetState.selected)) {
                      return colorTema.withOpacity(0.2); // Color dinámico
                    }
                    return Colors.transparent;
                  },
                ),
              ),
            ),
            
            const SizedBox(height: 24),

            // --- ÁREA DE TEXTO ---
            TextField(
              controller: _mensajeController,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Escribe tus comentarios, ideas o reporta un problema aquí...',
                filled: true, fillColor: Colors.grey.shade50,
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: colorTema, width: 1.5)),
              ),
            ),
            
            const SizedBox(height: 32),

            // --- BOTÓN DE ENVÍO ---
            ElevatedButton.icon(
              onPressed: _enviarFeedback,
              style: ElevatedButton.styleFrom(
                backgroundColor: colorTema, 
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.send_rounded, size: 20),
              label: const Text('Enviar mensaje', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}