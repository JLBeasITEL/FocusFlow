import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/rutina.dart';
import '../../providers/rutina_provider.dart';

class AlarmaScreen extends ConsumerWidget {
  final Rutina rutina;

  const AlarmaScreen({super.key, required this.rutina});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1A1A), Colors.black],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('ES HORA DE TU RUTINA', style: TextStyle(color: Colors.white70, letterSpacing: 3)),
              const SizedBox(height: 40),
              Icon(IconData(rutina.iconoCode, fontFamily: 'MaterialIcons'), size: 100, color: Colors.white),
              const SizedBox(height: 20),
              Text(rutina.titulo, style: const TextStyle(fontSize: 32, color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 80),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orangeAccent,
                    minimumSize: const Size(double.infinity, 60),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  onPressed: () {
                    ref.read(rutinaProvider.notifier).incrementarRacha(rutina.id);
                    Navigator.pop(context);
                  },
                  child: const Text('COMPLETAR (+1 🔥)', style: TextStyle(fontSize: 18, color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Posponer', style: TextStyle(color: Colors.white60)),
              )
            ],
          ),
        ),
      ),
    );
  }
}