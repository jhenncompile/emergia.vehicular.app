import 'package:flutter/material.dart';
import '../../services/calificacion_service.dart';
import '../../theme/colors.dart';

class CalificacionScreen extends StatefulWidget {
  final int incidenteId;
  final String? nombreTaller;

  const CalificacionScreen({
    super.key,
    required this.incidenteId,
    this.nombreTaller,
  });

  @override
  State<CalificacionScreen> createState() => _CalificacionScreenState();
}

class _CalificacionScreenState extends State<CalificacionScreen>
    with SingleTickerProviderStateMixin {
  final CalificacionService _service = CalificacionService();
  final TextEditingController _comentarioCtrl = TextEditingController();

  int _puntuacion = 0; // 0 = sin seleccionar
  bool _enviando = false;
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeIn);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _comentarioCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_puntuacion == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona una puntuación antes de enviar.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _enviando = true);

    try {
      await _service.enviarCalificacion(
        incidenteId: widget.incidenteId,
        puntuacion: _puntuacion,
        comentario: _comentarioCtrl.text.trim().isEmpty
            ? null
            : _comentarioCtrl.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('¡Gracias por tu calificación!'),
            ],
          ),
          backgroundColor: Colors.green.shade600,
          duration: const Duration(seconds: 3),
        ),
      );
      Navigator.of(context).pop(true); // devuelve true para indicar que se calificó
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Widget _buildEstrella(int index) {
    final selected = index <= _puntuacion;
    return GestureDetector(
      onTap: () => setState(() => _puntuacion = index),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, anim) =>
            ScaleTransition(scale: anim, child: child),
        child: Icon(
          selected ? Icons.star_rounded : Icons.star_outline_rounded,
          key: ValueKey('star_${index}_$selected'),
          size: 52,
          color: selected ? const Color(0xFFFFC107) : Colors.grey.shade400,
        ),
      ),
    );
  }

  String get _labelPuntuacion {
    switch (_puntuacion) {
      case 1:
        return 'Muy malo 😞';
      case 2:
        return 'Malo 😕';
      case 3:
        return 'Regular 😐';
      case 4:
        return 'Bueno 😊';
      case 5:
        return 'Excelente ⭐';
      default:
        return 'Toca una estrella';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Calificar Servicio'),
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 16),

              // Icono principal
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primaryColor,
                      AppColors.primaryColor.withValues(alpha: 0.6),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryColor.withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.garage_rounded,
                  size: 44,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),

              Text(
                '¿Cómo fue el servicio?',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),

              if (widget.nombreTaller != null)
                Text(
                  widget.nombreTaller!,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 32),

              // Estrellas
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) => _buildEstrella(i + 1)),
              ),
              const SizedBox(height: 10),
              Text(
                _labelPuntuacion,
                style: TextStyle(
                  color: _puntuacion > 0
                      ? const Color(0xFFFFC107)
                      : Colors.grey.shade500,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 32),

              // Campo comentario
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: TextField(
                  controller: _comentarioCtrl,
                  maxLines: 4,
                  maxLength: 300,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.transparent,
                    hintText: 'Escribe un comentario (opcional)...',
                    hintStyle:
                        TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                    counterStyle:
                        TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Botón Enviar
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _enviando ? null : _enviar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 4,
                  ),
                  child: _enviando
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child:
                              CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text(
                          'Enviar Calificación',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
              const SizedBox(height: 12),

              // Botón Omitir
              TextButton(
                onPressed: _enviando
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: Text(
                  'Omitir por ahora',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
