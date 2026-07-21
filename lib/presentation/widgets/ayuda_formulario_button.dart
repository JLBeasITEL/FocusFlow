import 'package:flutter/material.dart';

/// Botón de ayuda ('?') para formularios. Muestra un diálogo explicando
/// los campos del formulario en el que se coloca.
class AyudaFormularioButton extends StatelessWidget {
  final String titulo;
  /// Cada elemento tiene el formato "Campo: explicación".
  final List<String> puntos;
  final Color? color;

  const AyudaFormularioButton({
    super.key,
    required this.titulo,
    required this.puntos,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.help_outline_rounded, color: color),
      tooltip: 'Ayuda',
      onPressed: () {
        showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(titulo),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: puntos.map((punto) {
                  final partes = punto.split(':');
                  final campo = partes.first;
                  final explicacion = partes.skip(1).join(':').trim();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: RichText(
                      text: TextSpan(
                        style: DefaultTextStyle.of(dialogContext).style,
                        children: [
                          TextSpan(text: '$campo: ', style: const TextStyle(fontWeight: FontWeight.bold)),
                          TextSpan(text: explicacion),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
      },
    );
  }
}
