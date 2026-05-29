import 'dart:async';

import 'package:flutter/material.dart';

class DiagnosticoIAScreen extends StatefulWidget {
  const DiagnosticoIAScreen({
    super.key,
    required this.incidente,
    required this.onCompleted,
  });

  final Map<String, dynamic> incidente;
  final VoidCallback onCompleted;

  @override
  State<DiagnosticoIAScreen> createState() => _DiagnosticoIAScreenState();
}

class _DiagnosticoIAScreenState extends State<DiagnosticoIAScreen> {
  int _progress = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 220), (timer) {
      if (!mounted) return;
      setState(() {
        _progress += 10;
      });

      if (_progress >= 100) {
        timer.cancel();
        Future.delayed(const Duration(milliseconds: 350), () {
          if (!mounted) return;
          Navigator.of(context).pop();
          widget.onCompleted();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostico IA')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.psychology_alt, size: 76, color: Colors.blue),
                const SizedBox(height: 14),
                const Text(
                  'Analizando reporte con IA',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Modulo solo maquetado por ahora',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(value: _progress / 100),
                const SizedBox(height: 10),
                Text('$_progress% completado'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
