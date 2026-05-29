/// Practical integration guide for adding emergency reporting to an existing Flutter screen.
///
/// This file shows minimal, copy-paste ready code for integrating the EmergenciaService
/// into your existing screens without major refactoring.
library;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/emergencia_models.dart';
import '../services/emergencia_service.dart';

// ============================================================================
// MINIMAL INTEGRATION: Add to Existing Screen
// ============================================================================

/// Example of integrating emergency reporting into an existing incident screen.
///
/// This is the minimal code needed to add emergency reporting capability
/// to any existing Flutter screen without major refactoring.
class ExistingIncidentScreen extends StatefulWidget {
  const ExistingIncidentScreen({super.key});

  @override
  State<ExistingIncidentScreen> createState() => _ExistingIncidentScreenState();
}

class _ExistingIncidentScreenState extends State<ExistingIncidentScreen> {
  // === NEW CODE: Add these variables ===
  final EmergenciaService _emergenciaService = EmergenciaService();
  final ImagePicker _picker = ImagePicker();

  String? _audioPath;
  String? _imagePath;
  bool _isSubmitting = false;
  double _uploadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    // Initialize as needed
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reporte de Incidente')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // === EXISTING CODE: Your original content ===
            const SizedBox(height: 24),

            // === NEW CODE: Add emergency reporting section ===
            const Divider(thickness: 2),
            const SizedBox(height: 16),
            const Text(
              'Reportar Emergencia (AI Analysis)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Audio selector
            _buildSimpleButton(
              label: _audioPath != null
                  ? 'Audio: ${_audioPath!.split('/').last}'
                  : 'Seleccionar Audio',
              icon: Icons.mic,
              onPress: _pickAudio,
            ),
            const SizedBox(height: 12),

            // Image selector
            _buildSimpleButton(
              label: _imagePath != null
                  ? 'Imagen: ${_imagePath!.split('/').last}'
                  : 'Seleccionar Imagen',
              icon: Icons.image,
              onPress: _pickImage,
            ),
            const SizedBox(height: 16),

            // Submit button
            _isSubmitting
                ? Column(
                    children: [
                      LinearProgressIndicator(value: _uploadProgress),
                      const SizedBox(height: 8),
                      Text(
                        'Enviando: ${(_uploadProgress * 100).toStringAsFixed(0)}%',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  )
                : ElevatedButton(
                    onPressed: _audioPath != null && _imagePath != null
                        ? _submitEmergencyReport
                        : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: Colors.red,
                    ),
                    child: const Text(
                      'ENVIAR REPORTE',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  /// Simple button widget for file selection.
  Widget _buildSimpleButton({
    required String label,
    required IconData icon,
    required VoidCallback onPress,
  }) {
    return OutlinedButton.icon(
      onPressed: onPress,
      icon: Icon(icon),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }

  /// Pick audio file.
  Future<void> _pickAudio() async {
    try {
      final file = await _picker.pickMedia();
      if (file != null) {
        setState(() => _audioPath = file.path);
      }
    } catch (e) {
      _showSnackbar('Error: ${e.toString()}', isError: true);
    }
  }

  /// Pick image file.
  Future<void> _pickImage() async {
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery);
      if (file != null) {
        setState(() => _imagePath = file.path);
      }
    } catch (e) {
      _showSnackbar('Error: ${e.toString()}', isError: true);
    }
  }

  /// Submit emergency report to backend.
  Future<void> _submitEmergencyReport() async {
    if (_audioPath == null || _imagePath == null) {
      _showSnackbar('Selecciona ambos archivos', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // === KEY LINE: Call the service ===
      final result = await _emergenciaService.enviarReporte(
        audioPath: _audioPath!,
        imagePath: _imagePath!,
        onProgress: (progress) {
          setState(() => _uploadProgress = progress);
        },
      );

      // === Handle Result ===
      result.when(
        success: (reporte) {
          _showSnackbar('✅ Reporte enviado\nPrioridad: ${reporte.priority}');

          // Reset form
          setState(() {
            _audioPath = null;
            _imagePath = null;
          });

          // TODO: Save report data or navigate to success screen
          debugPrint('Report priority: ${reporte.priority}');
          debugPrint('Detections: ${reporte.detectionSummary}');
        },
        failure: (error) {
          String message = error.message;

          if (error is FileSizeException) {
            message = 'Archivo muy grande: ${error.fileName}';
          } else if (error is FileTypeException) {
            message = 'Formato no permitido: ${error.fileType}';
          } else if (error is NoInternetException) {
            message = 'Sin conexión a internet';
          }

          _showSnackbar('❌ Error: $message', isError: true);
        },
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// Show snackbar message.
  void _showSnackbar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }
}

// ============================================================================
// QUICK START: Copy-Paste Template
// ============================================================================

/// Minimal template for quick integration.
///
/// Usage:
/// 1. Copy this code into your screen
/// 2. Replace _audioPath and _imagePath setup
/// 3. Call _submitEmergencyReport() when user taps button
/// 4. Handle result in success/failure callbacks

class QuickStartTemplate extends StatefulWidget {
  const QuickStartTemplate({super.key});

  @override
  State<QuickStartTemplate> createState() => _QuickStartTemplateState();
}

class _QuickStartTemplateState extends State<QuickStartTemplate> {
  // Step 1: Initialize service
  final service = EmergenciaService();

  String? audioPath;
  String? imagePath;

  Future<void> submitReport() async {
    if (audioPath == null || imagePath == null) return;

    // Step 2: Call service
    final result = await service.enviarReporte(
      audioPath: audioPath!,
      imagePath: imagePath!,
      onProgress: (p) => debugPrint('${(p * 100).toStringAsFixed(0)}%'),
    );

    // Step 3: Handle result
    result.when(
      success: (reporte) {
        debugPrint('✅ Priority: ${reporte.priority}');
        // Update UI with reporte data
      },
      failure: (error) {
        debugPrint('❌ ${error.message}');
        // Show error to user
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: submitReport,
          child: const Text('Send Report'),
        ),
      ),
    );
  }
}

// ============================================================================
// ADVANCED: With State Management (Provider)
// ============================================================================

/// State management wrapper for emergency service.
///
/// Add this to your main.dart:
/// ```dart
/// providers: [
///   ChangeNotifierProvider(create: (_) => EmergenciaNotifier()),
/// ]
/// ```
class EmergenciaNotifier extends ChangeNotifier {
  final service = EmergenciaService();

  bool isLoading = false;
  double progress = 0.0;
  EmergenciaReporte? lastReport;
  EmergenciaException? error;

  Future<void> submitReport(String audio, String image) async {
    isLoading = true;
    error = null;
    notifyListeners();

    final result = await service.enviarReporte(
      audioPath: audio,
      imagePath: image,
      onProgress: (p) {
        progress = p;
        notifyListeners();
      },
    );

    result.when(success: (r) => lastReport = r, failure: (e) => error = e);

    isLoading = false;
    notifyListeners();
  }
}

/// Use in widget:
/// ```dart
/// Consumer<EmergenciaNotifier>(
///   builder: (context, notifier, _) {
///     if (notifier.isLoading) {
///       return LinearProgressIndicator(value: notifier.progress);
///     }
///     if (notifier.error != null) {
///       return Text('Error: ${notifier.error!.message}');
///     }
///     return SizedBox.shrink();
///   },
/// )
/// ```

// ============================================================================
// HELPER: Error Display Widget
// ============================================================================

/// Reusable widget to display errors beautifully.
///
/// Usage:
/// ```dart
/// if (error != null) {
///   ErrorDisplay(error: error)
/// }
/// ```
class ErrorDisplay extends StatelessWidget {
  final EmergenciaException error;
  final VoidCallback? onDismiss;

  const ErrorDisplay({super.key, required this.error, this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final color = _getColorForError(error);
    final icon = _getIconForError(error);
    final title = _getTitleForError(error);

    return Card(
      color: color.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: color),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontWeight: FontWeight.bold, color: color),
                  ),
                ),
                if (onDismiss != null)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: onDismiss,
                    iconSize: 20,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(error.message),
          ],
        ),
      ),
    );
  }

  Color _getColorForError(EmergenciaException error) {
    if (error is FileSizeException || error is FileTypeException) {
      return Colors.orange;
    } else if (error is NoInternetException) {
      return Colors.blue;
    } else if (error is TimeoutException) {
      return Colors.purple;
    } else if (error is HttpException) {
      return Colors.red;
    }
    return Colors.grey;
  }

  IconData _getIconForError(EmergenciaException error) {
    if (error is FileSizeException) return Icons.storage;
    if (error is FileTypeException) return Icons.error_outline;
    if (error is NoInternetException) return Icons.wifi_off;
    if (error is TimeoutException) return Icons.schedule;
    return Icons.warning;
  }

  String _getTitleForError(EmergenciaException error) {
    if (error is FileSizeException) return 'Archivo demasiado grande';
    if (error is FileTypeException) return 'Tipo de archivo no permitido';
    if (error is NoInternetException) return 'Sin conexión';
    if (error is TimeoutException) return 'Tiempo de espera agotado';
    if (error is HttpException) return 'Error del servidor';
    return 'Error';
  }
}

// ============================================================================
// TESTING: Mock Service for Development
// ============================================================================

/// Mock service for testing UI without backend.
///
/// Usage:
/// ```dart
/// final service = kDebugMode ? MockEmergenciaService() : EmergenciaService();
/// ```
class MockEmergenciaService extends EmergenciaService {
  @override
  Future<Result<EmergenciaReporte>> enviarReporte({
    required String audioPath,
    required String imagePath,
    Function(double progress)? onProgress,
  }) async {
    // Simulate upload progress
    for (int i = 0; i <= 10; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      onProgress?.call(i / 10);
    }

    // Return mock success
    return Success(
      EmergenciaReporte(
        status: 'success',
        transcription: 'Mock transcription: Car accident on Main Street',
        detections: [
          Detection(label: 'car', score: 0.95),
          Detection(label: 'person', score: 0.87),
        ],
        detectionSummary: ['car', 'person'],
        priority: 'Alta',
        processingStatus: 'success',
        message: 'Mock report generated successfully',
      ),
    );
  }
}
