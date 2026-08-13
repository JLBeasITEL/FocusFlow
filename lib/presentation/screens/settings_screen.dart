import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../providers/tema_provider.dart';
import '../../providers/configuracion_provider.dart';
import '../widgets/feedback_modal.dart';
import '../../services/backup_service.dart';
import '../../services/notificaciones_service.dart';
import '../../providers/rutina_provider.dart';
import '../../providers/tarea_provider.dart';

/// Expone la versión y el build number leídos directamente del build
/// actual (lo que Flutter generó a partir de `version:` en pubspec.yaml),
/// para que lo mostrado en Ajustes nunca se desincronice del build real.
final packageInfoProvider = FutureProvider<PackageInfo>((ref) {
  return PackageInfo.fromPlatform();
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Escuchamos activamente los estados de audio y apariencia
    final temaActual = ref.watch(temaProvider);
    final sonidos = ref.watch(sonidoProvider);
    final infoPaquete = ref.watch(packageInfoProvider);
    
    // Obtenemos la paleta de colores correspondiente al tema activo
    final colorPrincipal = temaActual.colorPrincipal;
    final colorFondo = temaActual.colorFondo;
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
      body: SafeArea(
        top: false,
        child: ListView(
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

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
            child: Divider(color: colorPrincipal.withValues(alpha: 0.2)),
          ),

          _SectionHeader(title: 'Respaldo', color: colorPrincipal),
          ListTile(
            leading: Icon(Icons.upload_file_outlined, color: colorPrincipal),
            title: Text('Exportar respaldo', style: TextStyle(color: colorPrincipal, fontWeight: FontWeight.w600)),
            subtitle: Text('Guarda todas tus tareas, rutinas y notas en un archivo', style: TextStyle(color: colorPrincipal.withValues(alpha: 0.7))),
            trailing: Icon(Icons.chevron_right, color: colorPrincipal.withValues(alpha: 0.5)),
            onTap: () => _exportarRespaldo(context, colorPrincipal),
          ),
          ListTile(
            leading: Icon(Icons.download_outlined, color: colorPrincipal),
            title: Text('Importar respaldo', style: TextStyle(color: colorPrincipal, fontWeight: FontWeight.w600)),
            subtitle: Text('Restaura tus datos desde un archivo de respaldo', style: TextStyle(color: colorPrincipal.withValues(alpha: 0.7))),
            trailing: Icon(Icons.chevron_right, color: colorPrincipal.withValues(alpha: 0.5)),
            onTap: () => _confirmarImportarRespaldo(context, ref, colorPrincipal, estiloTitulo),
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
          ListTile(
            leading: Icon(Icons.cleaning_services_outlined, color: colorPrincipal),
            title: Text('Reparar notificaciones', style: TextStyle(color: colorPrincipal, fontWeight: FontWeight.w600)),
            subtitle: Text('Limpia y reprograma todas las alarmas', style: TextStyle(color: colorPrincipal.withValues(alpha: 0.7))),
            trailing: Icon(Icons.chevron_right, color: colorPrincipal.withValues(alpha: 0.5)),
            onTap: () => _confirmarLimpiezaAlarmas(context, ref, colorPrincipal, estiloTitulo),
          ),
          
          
          // === DERECHOS DE AUTOR ===
          Padding(
            padding: const EdgeInsets.only(top: 48.0, bottom: 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  infoPaquete.when(
                    data: (info) => 'FocusFlow v${info.version}',
                    loading: () => 'FocusFlow',
                    error: (_, __) => 'FocusFlow',
                  ),
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
      ),
    );
  }

  String _getTemaName(TemaApp tema) {
    switch (tema) {
      case TemaApp.clasico: return 'Original (Blanco)';
      case TemaApp.zenClasico: return 'Zen Clásico (Verde)';
      case TemaApp.brisaMarina: return 'Brisa Marina (Azul)';
      case TemaApp.atardecerMinimalista: return 'Atardecer Minimalista';
      case TemaApp.medianoche: return 'Medianoche (Oscuro)';
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
    // Se captura una sola vez al abrir: así el badge no desaparece de golpe
    // mientras el usuario todavía tiene el diálogo abierto viéndolo.
    final mostrarBadgeNuevo = ref.read(medianocheBadgeProvider);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Seleccionar Tema', style: estiloTitulo),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: TemaApp.values.map((t) => ListTile(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_getTemaName(t), style: TextStyle(color: colorPrincipal)),
                if (t == TemaApp.medianoche && mostrarBadgeNuevo) ...[
                  const SizedBox(width: 8),
                  const _BadgeNuevo(),
                ],
              ],
            ),
            trailing: ref.read(temaProvider) == t ? Icon(Icons.check_circle, color: colorPrincipal) : null,
            onTap: () {
              ref.read(temaProvider.notifier).cambiarTema(t);
              Navigator.pop(context);
            },
          )).toList(),
        ),
      ),
    );

    if (mostrarBadgeNuevo) {
      ref.read(medianocheBadgeProvider.notifier).marcarComoVisto();
    }
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
        content: _SoundOptionsList(
          options: options,
          sonidoSeleccionado: sonidoSeleccionado,
          colorPrincipal: colorPrincipal,
          formatSoundName: _formatSoundName,
          onSeleccionar: (s) async {
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
        ),
      ),
    );
  }

  void _confirmarLimpiezaAlarmas(BuildContext context, WidgetRef ref, Color colorPrincipal, TextStyle estiloTitulo) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Reparar notificaciones?', style: estiloTitulo),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Text(
          'Esto cancelará todas las alarmas pendientes del sistema y las volverá a programar desde cero, basándose en tus rutinas actuales. Úsalo si notas notificaciones duplicadas o que no coinciden con el estado real de tus rutinas.',
          style: TextStyle(color: colorPrincipal.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context); // Cerramos el diálogo de confirmación

              // 1. Cancelamos TODO lo que haya en el sistema, sin excepción
              await NotificacionesService().limpiarTodasLasAlarmasDelSistema();

              // 2. Reprogramamos desde cero basándonos en el estado real guardado.
              // Las dos: cancelAll() no distingue entre alarmas de rutinas y de
              // tareas, así que si solo reprogramáramos rutinas, las tareas
              // quedarían sin ninguna alerta programada.
              await ref.read(rutinaProvider.notifier).resincronizarTodasLasAlarmas();
              await ref.read(tareaProvider.notifier).resincronizarTodasLasAlarmas();

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Notificaciones reparadas y reprogramadas'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: Text('Reparar', style: TextStyle(color: colorPrincipal, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _mostrarCargando(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
  }

  void _mostrarSnackBar(BuildContext context, String mensaje, {bool esError = false}) {
    _mostrarSnackBarConMessenger(ScaffoldMessenger.of(context), mensaje, esError: esError);
  }

  // Variante que recibe el ScaffoldMessengerState ya capturado en vez de un
  // BuildContext. Necesaria para casos como _importarRespaldo, donde el
  // context puede desmontarse mientras hay un selector nativo en primer
  // plano (ver FASE D/E): ScaffoldMessenger.of(context) fallaría en ese
  // punto, pero un ScaffoldMessengerState capturado ANTES sigue siendo
  // válido.
  void _mostrarSnackBarConMessenger(ScaffoldMessengerState messenger, String mensaje, {bool esError = false}) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(mensaje),
        behavior: SnackBarBehavior.floating,
        backgroundColor: esError ? Colors.red.shade700 : null,
      ),
    );
  }

  Future<void> _exportarRespaldo(BuildContext context, Color colorPrincipal) async {
    _mostrarCargando(context);
    try {
      await BackupService().exportarYCompartirBackup();
      if (context.mounted) Navigator.pop(context); // Cierra el diálogo de carga
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        _mostrarSnackBar(
          context,
          e is BackupException ? '❌ ${e.mensaje}' : '❌ No se pudo exportar el respaldo.',
          esError: true,
        );
      }
    }
  }

  void _confirmarImportarRespaldo(BuildContext context, WidgetRef ref, Color colorPrincipal, TextStyle estiloTitulo) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Importar respaldo?', style: estiloTitulo),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Text(
          'Esto reemplazará todos tus datos actuales (tareas, rutinas y notas) con los del archivo de respaldo. Esta acción no se puede deshacer. ¿Continuar?',
          style: TextStyle(color: colorPrincipal.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Cerramos el diálogo de confirmación
              _importarRespaldo(context, ref);
            },
            child: Text('Continuar', style: TextStyle(color: colorPrincipal, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _importarRespaldo(BuildContext context, WidgetRef ref) async {
    // Catch de último recurso: nada en este método debe poder morir en
    // silencio. Cualquier excepción no prevista por los try/catch internos
    // de abajo cae aquí y se logea igual, sin condicionar a context.mounted
    // ni a ninguna otra cosa.
    try {
      await _importarRespaldoInterno(context, ref);
    } catch (e, st) {
      debugPrint('BackupImport: fallo inesperado no manejado en _importarRespaldo -> $e\n$st');
    }
  }

  Future<void> _importarRespaldoInterno(BuildContext context, WidgetRef ref) async {
    // Capturamos ScaffoldMessenger y Navigator ANTES de abrir el selector,
    // mientras el context todavía está montado. FASE D confirmó que el
    // context vuelve desmontado tras cerrar el selector nativo de archivos
    // (aunque la pantalla sigue viva); un ScaffoldMessengerState/
    // NavigatorState ya capturado sigue siendo válido para mostrar un
    // SnackBar o cerrar el diálogo de carga aunque eso pase.
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);

    // pickFiles (en vez del atajo pickFile) para poder distinguir la
    // cancelación real del usuario (resultado nulo) de un archivo elegido
    // cuyo contenido no se pudo leer. withData:true pide los bytes
    // directamente: en Android, elegir un archivo desde un proveedor SAF
    // (p. ej. Descargas) puede devolver PlatformFile.path == null aunque
    // el usuario sí seleccionó un archivo válido, así que no podemos
    // depender solo de path.
    debugPrint('BackupImport: abriendo selector de archivos.');
    final FilePickerResult? resultado = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      // ignore: deprecated_member_use
      allowMultiple: false, // evita un StateError si el picker permitiera selección múltiple
      // ignore: deprecated_member_use
      withData: true, // requerido para leer bytes en vez de depender de path (ver comentario arriba)
    );
    debugPrint('BackupImport: selector de archivos retornó.');

    if (resultado == null) {
      debugPrint('BackupImport: selección cancelada por el usuario.');
      return;
    }

    final PlatformFile seleccionado = resultado.files.single;
    File? archivoParaImportar;
    File? temporalCreado;

    try {
      // ignore: deprecated_member_use
      final bytes = seleccionado.bytes; // necesitamos el valor nullable para el fallback a path
      if (bytes != null) {
        debugPrint('BackupImport: bytes disponibles (${bytes.length} bytes).');

        debugPrint('BackupImport: antes de getTemporaryDirectory().');
        final directorio = await getTemporaryDirectory();
        debugPrint('BackupImport: después de getTemporaryDirectory() -> ${directorio.path}');

        temporalCreado = File('${directorio.path}/focusflow_import_temp.json');

        // writeAsBytes directo: los bytes ya son el contenido exacto del
        // archivo, no hace falta decodificar a String con utf8 y volver a
        // codificar al escribir — un paso menos y sin FormatException
        // posible por un archivo que no fuera UTF-8 válido.
        debugPrint('BackupImport: antes de writeAsBytes() -> ${temporalCreado.path}');
        await temporalCreado.writeAsBytes(bytes);
        debugPrint('BackupImport: después de writeAsBytes().');

        archivoParaImportar = temporalCreado;
      } else if (seleccionado.path != null) {
        debugPrint('BackupImport: bytes nulo, usando fallback a path=${seleccionado.path}');
        archivoParaImportar = File(seleccionado.path!);
      } else {
        debugPrint('BackupImport: bytes y path nulos, no se puede leer el archivo seleccionado.');
      }
    } catch (e, st) {
      debugPrint('BackupImport: fallo al leer el archivo seleccionado -> $e\n$st');
      archivoParaImportar = null;
    }

    if (archivoParaImportar == null) {
      debugPrint('BackupImport: sin archivo legible, mostrando snackbar de error.');
      // Usamos el messenger capturado al principio, no context: FASE D
      // mostró que el context puede llegar desmontado hasta aquí, pero el
      // messenger capturado antes del selector sigue siendo válido.
      _mostrarSnackBarConMessenger(
        messenger,
        '❌ No se pudo leer el archivo seleccionado. Intenta elegirlo de nuevo.',
        esError: true,
      );
      return;
    }

    // A partir de aquí YA tenemos un archivo válido: importarBackup() recibe
    // un File y un WidgetRef, no un BuildContext, así que debe ejecutarse
    // siempre, sin importar si la pantalla de Ajustes sigue montada. El
    // diálogo de carga sí necesita un context válido para abrirse (se omite
    // si no lo hay), pero cerrarlo y mostrar el resultado usan navigator y
    // messenger capturados arriba, así que no dependen de si el context
    // sigue montado en ese momento.
    bool dialogoCargandoMostrado = false;
    if (context.mounted) {
      _mostrarCargando(context);
      dialogoCargandoMostrado = true;
    } else {
      debugPrint('BackupImport: context no montado antes de importar, se omite diálogo de carga pero SÍ se importa.');
    }
    try {
      debugPrint('BackupImport: antes de importarBackup().');
      await BackupService().importarBackup(archivoParaImportar, ref);
      debugPrint('BackupImport: después de importarBackup(), completó sin lanzar.');
      if (dialogoCargandoMostrado) navigator.pop(); // Cierra el diálogo de carga
      _mostrarSnackBarConMessenger(messenger, '✅ Respaldo importado correctamente');
    } catch (e, st) {
      debugPrint('BackupImport: fallo al importar -> $e\n$st');
      if (dialogoCargandoMostrado) navigator.pop();
      _mostrarSnackBarConMessenger(
        messenger,
        e is BackupException ? '❌ ${e.mensaje}' : '❌ No se pudo importar el respaldo.',
        esError: true,
      );
    } finally {
      if (temporalCreado != null && await temporalCreado.exists()) {
        debugPrint('BackupImport: borrando archivo temporal ${temporalCreado.path}');
        await temporalCreado.delete();
      }
    }
  }
}

class _SoundOptionsList extends StatefulWidget {
  final List<String> options;
  final String sonidoSeleccionado;
  final Color colorPrincipal;
  final String Function(String) formatSoundName;
  final void Function(String) onSeleccionar;

  const _SoundOptionsList({
    required this.options,
    required this.sonidoSeleccionado,
    required this.colorPrincipal,
    required this.formatSoundName,
    required this.onSeleccionar,
  });

  @override
  State<_SoundOptionsList> createState() => _SoundOptionsListState();
}

class _SoundOptionsListState extends State<_SoundOptionsList> {
  final AudioPlayer _reproductor = AudioPlayer();
  String? _sonidoReproduciendo;

  @override
  void dispose() {
    _reproductor.stop();
    _reproductor.dispose();
    super.dispose();
  }

  Future<void> _alternarPreview(String sonido) async {
    if (_sonidoReproduciendo == sonido) {
      await _reproductor.stop();
      setState(() => _sonidoReproduciendo = null);
      return;
    }

    await _reproductor.stop();
    setState(() => _sonidoReproduciendo = sonido);
    await _reproductor.play(AssetSource('sounds/$sonido.mp3'));
    _reproductor.onPlayerComplete.first.then((_) {
      if (mounted && _sonidoReproduciendo == sonido) {
        setState(() => _sonidoReproduciendo = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: widget.options.map((s) {
        final estaReproduciendo = _sonidoReproduciendo == s;
        return ListTile(
          leading: IconButton(
            icon: Icon(
              estaReproduciendo ? Icons.stop_circle : Icons.play_circle_outline,
              color: widget.colorPrincipal,
            ),
            tooltip: estaReproduciendo ? 'Detener' : 'Escuchar',
            onPressed: () => _alternarPreview(s),
          ),
          title: Text(widget.formatSoundName(s), style: TextStyle(color: widget.colorPrincipal)),
          trailing: widget.sonidoSeleccionado == s
              ? Icon(Icons.radio_button_checked, color: widget.colorPrincipal)
              : Icon(Icons.radio_button_off, color: widget.colorPrincipal.withValues(alpha: 0.3)),
          onTap: () => widget.onSeleccionar(s),
        );
      }).toList(),
    );
  }
}

class _BadgeNuevo extends StatelessWidget {
  const _BadgeNuevo();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF6D5DF6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'NUEVO',
        style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5),
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