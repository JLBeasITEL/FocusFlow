import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/tema_provider.dart';
import '../../providers/configuracion_provider.dart';
import '../widgets/feedback_modal.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Escuchamos activamente los estados de audio y apariencia
    final temaActual = ref.watch(temaProvider);
    final sonidos = ref.watch(sonidoProvider);
    
    // Obtenemos la paleta de colores correspondiente al tema activo
    final colorPrincipal = _getColorPrincipal(temaActual);
    final colorFondo = _getColorFondo(temaActual);
    final esOscuro = temaActual == TemaApp.atardecerMinimalista; 

    // Estilo de texto adaptativo para los títulos
    final estiloTitulo = TextStyle(
      fontWeight: FontWeight.bold,
      color: esOscuro ? Colors.orange.shade900 : colorPrincipal,
    );

    return Scaffold(
      backgroundColor: colorFondo,
      appBar: AppBar(
        title: Text('Configuraciones', style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: colorPrincipal,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          _SectionHeader(title: 'Apariencia', color: colorPrincipal),
          ListTile(
            leading: Icon(Icons.palette_outlined, color: colorPrincipal),
            title: Text('Tema Visual', style: TextStyle(color: colorPrincipal, fontWeight: FontWeight.w600)),
            subtitle: Text(_getTemaName(temaActual), style: TextStyle(color: colorPrincipal.withValues(alpha: 0.7))),
            trailing: Icon(Icons.chevron_right, color: colorPrincipal.withValues(alpha: 0.5)),
            onTap: () => _showThemeDialog(context, ref, colorPrincipal, estiloTitulo),
          ),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
            child: Divider(color: colorPrincipal.withValues(alpha: 0.2)),
          ),
          
          _SectionHeader(title: 'Sonidos y Alertas', color: colorPrincipal),
          ListTile(
            leading: Icon(Icons.notifications_none_rounded, color: colorPrincipal),
            title: Text('Sonido de Notificación', style: TextStyle(color: colorPrincipal, fontWeight: FontWeight.w600)),
            subtitle: Text(_formatSoundName(sonidos.sonidoNotificacion), style: TextStyle(color: colorPrincipal.withValues(alpha: 0.7))),
            trailing: Icon(Icons.chevron_right, color: colorPrincipal.withValues(alpha: 0.5)),
            onTap: () => _showSoundDialog(context, ref, true, colorPrincipal, estiloTitulo),
          ),
          ListTile(
            leading: Icon(Icons.warning_amber_rounded, color: colorPrincipal),
            title: Text('Alarma Urgente', style: TextStyle(color: colorPrincipal, fontWeight: FontWeight.w600)),
            subtitle: Text(_formatSoundName(sonidos.sonidoAlarma), style: TextStyle(color: colorPrincipal.withValues(alpha: 0.7))),
            trailing: Icon(Icons.chevron_right, color: colorPrincipal.withValues(alpha: 0.5)),
            onTap: () => _showSoundDialog(context, ref, false, colorPrincipal, estiloTitulo),
          ),

          // === NUEVA SECCIÓN DE SOPORTE ===
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
            child: Divider(color: colorPrincipal.withValues(alpha: 0.2)),
          ),
          
          _SectionHeader(title: 'Soporte', color: colorPrincipal),
          ListTile(
            leading: Icon(Icons.rate_review_outlined, color: colorPrincipal),
            title: Text('Enviar feedback', style: TextStyle(color: colorPrincipal, fontWeight: FontWeight.w600)),
            subtitle: Text('Reporta un error o sugiere mejoras', style: TextStyle(color: colorPrincipal.withValues(alpha: 0.7))),
            trailing: Icon(Icons.chevron_right, color: colorPrincipal.withValues(alpha: 0.5)),
            onTap: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true, // Importante para que el modal suba con el teclado
                backgroundColor: Colors.transparent,
                builder: (context) => const FeedbackModal(),
              );
            },
          ),
          
          // === DERECHOS DE AUTOR ===
          Padding(
            padding: const EdgeInsets.only(top: 48.0, bottom: 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'FocusFlow v1.9.3',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: colorPrincipal.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '© 2026 Juan Luis Beas Vázquez.',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorPrincipal.withValues(alpha: 0.4),
                  ),
                ),
                Text(
                  'Todos los derechos reservados.',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorPrincipal.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Mapeo de Colores del Sistema ---
  Color _getColorPrincipal(TemaApp tema) {
    if (tema == TemaApp.clasico) return Colors.black87; 
    if (tema == TemaApp.brisaMarina) return const Color(0xFF1E3A8A); 
    if (tema == TemaApp.atardecerMinimalista) return const Color(0xFFC05621); 
    return const Color(0xFF276749); // Zen Clásico
  }

  Color _getColorFondo(TemaApp tema) {
    if (tema == TemaApp.clasico) return Colors.white;
    if (tema == TemaApp.brisaMarina) return const Color(0xFFF0F8FF);
    if (tema == TemaApp.atardecerMinimalista) return const Color(0xFFFFF9F5);
    return const Color(0xFFF2F7F2); // Zen Clásico
  }

  String _getTemaName(TemaApp tema) {
    switch (tema) {
      case TemaApp.clasico: return 'Original (Blanco)';
      case TemaApp.zenClasico: return 'Zen Clásico (Verde)';
      case TemaApp.brisaMarina: return 'Brisa Marina (Azul)';
      case TemaApp.atardecerMinimalista: return 'Atardecer Minimalista';
    }
  }

  String _formatSoundName(String rawName) {
    switch (rawName) {
      case 'default_nota': return 'Piano Eco (Por defecto)';
      case 'campana_zen': return 'Campana Zen Clara';
      case 'burbuja_ui': return 'Burbuja Digital Corta';
      case 'default_alarma': return 'Progresión Clásica (Por defecto)';
      case 'marimba_alerta': return 'Ritmo Marimba Insistente';
      case 'sintetizador_pulso': return 'Sintetizador';
      default: return rawName;
    }
  }

  // --- Diálogos Estilizados ---
  void _showThemeDialog(BuildContext context, WidgetRef ref, Color colorPrincipal, TextStyle estiloTitulo) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Seleccionar Tema', style: estiloTitulo),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: TemaApp.values.map((t) => ListTile(
            title: Text(_getTemaName(t), style: TextStyle(color: colorPrincipal)),
            trailing: ref.read(temaProvider) == t ? Icon(Icons.check_circle, color: colorPrincipal) : null,
            onTap: () {
              ref.read(temaProvider.notifier).cambiarTema(t);
              Navigator.pop(context);
            },
          )).toList(),
        ),
      ),
    );
  }

  void _showSoundDialog(BuildContext context, WidgetRef ref, bool isNota, Color colorPrincipal, TextStyle estiloTitulo) {
    final options = isNota 
      ? ['default_nota', 'campana_zen', 'burbuja_ui']
      : ['default_alarma', 'marimba_alerta', 'sintetizador_pulso'];

    final sonidoSeleccionado = isNota 
      ? ref.read(sonidoProvider).sonidoNotificacion 
      : ref.read(sonidoProvider).sonidoAlarma;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isNota ? 'Sonido de Notificación' : 'Sonido de Alarma', style: estiloTitulo),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((s) => ListTile(
            title: Text(_formatSoundName(s), style: TextStyle(color: colorPrincipal)),
            trailing: sonidoSeleccionado == s ? Icon(Icons.radio_button_checked, color: colorPrincipal) : Icon(Icons.radio_button_off, color: colorPrincipal.withValues(alpha: 0.3)),
            onTap: () async {
              if (isNota) {
                await ref.read(sonidoProvider.notifier).cambiarSonidoNotificacion(s);
              } else {
                await ref.read(sonidoProvider.notifier).cambiarSonidoAlarma(s);
              }
              
              if (context.mounted) {
                 Navigator.pop(context);
                 ScaffoldMessenger.of(context).showSnackBar(
                   SnackBar(
                     content: Text(isNota ? '🔔 Canal de notificación actualizado a $s' : '🔥 Alarma principal configurada'), 
                     behavior: SnackBarBehavior.floating
                   ),
                 );
              }
            },
          )).toList(),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;
  const _SectionHeader({required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(), 
        style: TextStyle(
          fontSize: 12, 
          fontWeight: FontWeight.bold, 
          color: color.withValues(alpha: 0.6), 
          letterSpacing: 1.3
        ),
      ),
    );
  }
}