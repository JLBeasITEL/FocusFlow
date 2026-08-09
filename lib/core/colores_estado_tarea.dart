import 'package:flutter/material.dart';
import '../providers/tema_provider.dart';

// Color de urgencia por nivel (1-4), específico de cada tema visual.
// Compartido entre TareaCard (portrait) y TareaLandscapeCard para que
// "urgencia 3 en Brisa Marina" signifique siempre el mismo color.
Color colorUrgenciaTarea(int urgencia, TemaApp tema) {
  if (tema == TemaApp.clasico) {
    switch (urgencia) { case 1: return Colors.teal; case 2: return Colors.blue; case 3: return Colors.orange; case 4: return Colors.red; default: return Colors.grey; }
  } else if (tema == TemaApp.zenClasico) {
    switch (urgencia) { case 1: return const Color(0xFFA5C4A6); case 2: return const Color(0xFF80A681); case 3: return const Color(0xFF5A855C); case 4: return const Color(0xFF3B633D); default: return Colors.grey; }
  } else if (tema == TemaApp.brisaMarina) {
    switch (urgencia) { case 1: return const Color(0xFF90CDF4); case 2: return const Color(0xFF63B3ED); case 3: return const Color(0xFF3182CE); case 4: return const Color(0xFF2B6CB0); default: return Colors.grey; }
  } else if (tema == TemaApp.medianoche) {
    // Escala morada (violeta claro -> violeta intenso), pensada para actuar
    // como TEXTO sobre una tarjeta oscura, no como relleno claro: necesita
    // alta luminancia para mantener ≥4.5:1 de contraste.
    switch (urgencia) { case 1: return const Color(0xFFDDD6FE); case 2: return const Color(0xFFC4B5FD); case 3: return const Color(0xFFA78BFA); case 4: return const Color(0xFF8B5CF6); default: return Colors.grey.shade400; }
  } else {
    switch (urgencia) { case 1: return const Color(0xFFFBD38D); case 2: return const Color(0xFFF6AD55); case 3: return const Color(0xFFDD6B20); case 4: return const Color(0xFFC05621); default: return Colors.grey; }
  }
}

String labelUrgenciaTarea(int urgencia) {
  switch (urgencia) { case 1: return 'BAJO'; case 2: return 'MEDIO'; case 3: return 'ALTO'; case 4: return 'MUY ALTO'; default: return '???'; }
}
