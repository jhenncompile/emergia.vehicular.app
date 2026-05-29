/// Complete example of using the EmergenciaService in a Flutter application.
///
/// This file demonstrates:
/// - Service initialization
/// - File selection and validation
/// - Emergency report submission
/// - Error handling with Result pattern
/// - Progress tracking
/// - State management integration
library;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/emergencia_models.dart';
import '../services/emergencia_service.dart';

// ============================================================================
// SIMPLE EXAMPLE: Basic Usage
// ============================================================================

/// Simple example showing the basic flow of submitting an emergency report.
Future<void> basicExample() async {
  // Initialize the service
  final emergenciaService = EmergenciaService();

  // Submit report
  final result = await emergenciaService.enviarReporte(
    audioPath: '/path/to/audio.mp3',
    imagePath: '/path/to/image.jpg',
  );

  // Handle result using pattern matching
  result.when(
    success: (reporte) {
      debugPrint('✅ Report submitted successfully!');
      debugPrint('Priority: ${reporte.priority}');
      debugPrint('Transcription: ${reporte.transcription}');
      debugPrint('Detected objects: ${reporte.detectionSummary}');
    },
    failure: (error) {
      debugPrint('❌ Error: ${error.message}');
      if (error is FileSizeException) {
        debugPrint('File is too large: ${error.fileName}');
      }
    },
  );
}

// ============================================================================
// ADVANCED EXAMPLE: With Provider State Management
// ============================================================================

/// State manager for emergency report submission.
///
/// Integrates with Provider package for state management.
/// Usage:
/// ```dart
/// final provider = Provider<EmergenciaProvider>(
///   create: (_) => EmergenciaProvider(),
/// );
/// ```
class EmergenciaProvider extends ChangeNotifier {
  final EmergenciaService _service = EmergenciaService();

  // State variables
  bool _isLoading = false;
  double _uploadProgress = 0.0;
  EmergenciaReporte? _lastReport;
  String? _errorMessage;

  // Getters
  bool get isLoading => _isLoading;
  double get uploadProgress => _uploadProgress;
  EmergenciaReporte? get lastReport => _lastReport;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;

  /// Submit emergency report with full state management.
  ///
  /// Tracks loading, progress, and errors.
  /// Updates UI automatically via notifyListeners().
  Future<void> submitEmergencyReport({
    required String audioPath,
    required String imagePath,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      _uploadProgress = 0.0;
      notifyListeners();

      // Call service with progress callback
      final result = await _service.enviarReporte(
        audioPath: audioPath,
        imagePath: imagePath,
        onProgress: (progress) {
          _uploadProgress = progress;
          notifyListeners();
        },
      );

      // Handle result
      result.when(
        success: (reporte) {
          _lastReport = reporte;
          _uploadProgress = 1.0;
        },
        failure: (error) {
          _errorMessage = error.message;
        },
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Clear error message.
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Reset state for new submission.
  void reset() {
    _isLoading = false;
    _uploadProgress = 0.0;
    _lastReport = null;
    _errorMessage = null;
    notifyListeners();
  }
}

// ============================================================================
// UI EXAMPLE: Emergency Report Screen
// ============================================================================

/// UI screen for submitting emergency reports.
///
/// Demonstrates:
/// - File picking
/// - Form validation
/// - Progress tracking
/// - Error display
/// - Result presentation
class EmergenciaReporteScreen extends StatefulWidget {
  const EmergenciaReporteScreen({super.key});

  @override
  State<EmergenciaReporteScreen> createState() =>
      _EmergenciaReporteScreenState();
}

class _EmergenciaReporteScreenState extends State<EmergenciaReporteScreen> {
  final ImagePicker _picker = ImagePicker();

  String? _selectedAudioPath;
  String? _selectedImagePath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reportar Emergencia')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Audio Selection Section
            _buildFileSelector(
              title: 'Grabación de Audio',
              subtitle: _selectedAudioPath != null
                  ? _selectedAudioPath!.split('/').last
                  : 'Seleccionar archivo de audio',
              icon: Icons.mic,
              onTap: _pickAudioFile,
              maxSize: '25 MB',
            ),
            const SizedBox(height: 16),

            // Image Selection Section
            _buildFileSelector(
              title: 'Foto del Incidente',
              subtitle: _selectedImagePath != null
                  ? _selectedImagePath!.split('/').last
                  : 'Seleccionar foto',
              icon: Icons.image,
              onTap: _pickImageFile,
              maxSize: '10 MB',
            ),
            const SizedBox(height: 24),

            // Submit Button and Progress
            Consumer<EmergenciaProvider>(
              builder: (context, provider, _) {
                if (provider.isLoading) {
                  return _buildProgressIndicator(provider.uploadProgress);
                }

                return ElevatedButton(
                  onPressed:
                      _selectedAudioPath != null && _selectedImagePath != null
                      ? () => _submitReport(context)
                      : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.red,
                  ),
                  child: const Text(
                    'ENVIAR REPORTE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // Error Display
            Consumer<EmergenciaProvider>(
              builder: (context, provider, _) {
                if (provider.hasError) {
                  return _buildErrorCard(provider.errorMessage!);
                }
                return const SizedBox.shrink();
              },
            ),

            // Success Display
            Consumer<EmergenciaProvider>(
              builder: (context, provider, _) {
                if (provider.lastReport != null) {
                  return _buildSuccessCard(provider.lastReport!);
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Build file selector card.
  Widget _buildFileSelector({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    required String maxSize,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon, size: 32, color: Colors.blue),
        title: Text(title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle),
            Text(
              'Máximo: $maxSize',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        trailing: const Icon(Icons.arrow_forward),
        onTap: onTap,
      ),
    );
  }

  /// Build progress indicator.
  Widget _buildProgressIndicator(double progress) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Subiendo... ${(progress * 100).toStringAsFixed(0)}%',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: progress, minHeight: 8),
      ],
    );
  }

  /// Build error card.
  Widget _buildErrorCard(String errorMessage) {
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error, color: Colors.red.shade700),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Error',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(errorMessage),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () {
                context.read<EmergenciaProvider>().clearError();
              },
              child: const Text('Descartar'),
            ),
          ],
        ),
      ),
    );
  }

  /// Build success card showing report results.
  Widget _buildSuccessCard(EmergenciaReporte report) {
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade700),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '¡Reporte Enviado!',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildReportDetail('Prioridad', report.priority),
            _buildReportDetail('Estado', report.processingStatus),
            if (report.transcription.isNotEmpty)
              _buildReportDetail('Audio', report.transcription),
            if (report.detectionSummary.isNotEmpty)
              _buildReportDetail(
                'Objetos Detectados',
                report.detectionSummary.join(', '),
              ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                context.read<EmergenciaProvider>().reset();
                setState(() {
                  _selectedAudioPath = null;
                  _selectedImagePath = null;
                });
              },
              child: const Text('Enviar Otro Reporte'),
            ),
          ],
        ),
      ),
    );
  }

  /// Build detail row in success card.
  Widget _buildReportDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  /// Pick audio file from device storage.
  Future<void> _pickAudioFile() async {
    try {
      final file = await _picker.pickMedia(requestFullMetadata: false);

      if (file != null) {
        setState(() {
          _selectedAudioPath = file.path;
        });
      }
    } catch (e) {
      _showError('Error al seleccionar archivo de audio: $e');
    }
  }

  /// Pick image file from device camera or gallery.
  Future<void> _pickImageFile() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      );

      if (file != null) {
        setState(() {
          _selectedImagePath = file.path;
        });
      }
    } catch (e) {
      _showError('Error al seleccionar imagen: $e');
    }
  }

  /// Submit emergency report.
  Future<void> _submitReport(BuildContext context) async {
    if (_selectedAudioPath == null || _selectedImagePath == null) {
      _showError('Por favor selecciona ambos archivos');
      return;
    }

    final provider = context.read<EmergenciaProvider>();
    await provider.submitEmergencyReport(
      audioPath: _selectedAudioPath!,
      imagePath: _selectedImagePath!,
    );
  }

  /// Show error snackbar.
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }
}

// ============================================================================
// MAIN APP WITH PROVIDER
// ============================================================================

/// Example app setup with Provider.
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => EmergenciaProvider())],
      child: MaterialApp(
        title: 'VialIA - Emergency Reports',
        theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
        home: const EmergenciaReporteScreen(),
      ),
    );
  }
}
