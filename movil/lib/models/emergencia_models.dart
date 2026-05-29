/// Domain models for emergency reporting functionality.
///
/// This file contains all data structures needed for the emergency report flow:
/// - Request models (validation)
/// - Response models (API responses)
/// - Result wrapper (Success/Failure pattern)
library;

// ============================================================================
// EXCEPTIONS
// ============================================================================

/// Base exception for emergency service errors.
class EmergenciaException implements Exception {
  final String message;
  final dynamic originalError;
  final StackTrace? stackTrace;

  EmergenciaException({
    required this.message,
    this.originalError,
    this.stackTrace,
  });

  @override
  String toString() => 'EmergenciaException: $message';
}

/// Exception thrown when file size exceeds limits.
class FileSizeException extends EmergenciaException {
  final String fileName;
  final int fileSize;
  final int maxSize;

  FileSizeException({
    required this.fileName,
    required this.fileSize,
    required this.maxSize,
  }) : super(
         message:
             'File "$fileName" exceeds maximum size. '
             'Size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB, '
             'Max: ${(maxSize / 1024 / 1024).toStringAsFixed(2)}MB',
       );
}

/// Exception thrown when file MIME type is invalid.
class FileTypeException extends EmergenciaException {
  final String fileName;
  final String fileType;
  final List<String> allowedTypes;

  FileTypeException({
    required this.fileName,
    required this.fileType,
    required this.allowedTypes,
  }) : super(
         message:
             'Invalid file type for "$fileName". '
             'Got: $fileType, Allowed: ${allowedTypes.join(', ')}',
       );
}

/// Exception thrown when no internet connection is available.
class NoInternetException extends EmergenciaException {
  NoInternetException()
    : super(
        message:
            'No internet connection. Please check your network and try again.',
      );
}

/// Exception thrown when API request times out.
class TimeoutException extends EmergenciaException {
  final Duration timeout;

  TimeoutException({required this.timeout})
    : super(
        message:
            'Request timed out after ${timeout.inSeconds} seconds. '
            'Please check your internet connection and try again.',
      );
}

/// Exception thrown when server returns HTTP error.
class HttpException extends EmergenciaException {
  final int statusCode;
  final String? responseBody;

  HttpException({
    required this.statusCode,
    required super.message,
    this.responseBody,
  });

  /// User-friendly error message based on status code.
  String get userFriendlyMessage {
    switch (statusCode) {
      case 400:
        return 'Invalid request. Please check your files and try again.';
      case 413:
        return 'File is too large. Please reduce the file size and try again.';
      case 500:
      case 502:
      case 503:
        return 'Server error. Please try again later.';
      default:
        return 'An error occurred. Please try again.';
    }
  }
}

// ============================================================================
// RESPONSE MODELS
// ============================================================================

/// Represents a single detected object in the image.
///
/// Example:
/// ```dart
/// var detection = Detection(
///   label: 'car',
///   score: 0.95,
///   box: {'xmin': 100, 'ymin': 50, 'xmax': 400, 'ymax': 350},
/// );
/// ```
class Detection {
  final String label;
  final double score;
  final Map<String, dynamic>? box;

  Detection({required this.label, required this.score, this.box});

  factory Detection.fromJson(Map<String, dynamic> json) {
    return Detection(
      label: json['label'] ?? 'unknown',
      score: (json['score'] ?? 0.0).toDouble(),
      box: json['box'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
    'label': label,
    'score': score,
    if (box != null) 'box': box,
  };

  @override
  String toString() => 'Detection(label: $label, score: $score)';
}

/// Emergency report response from the backend.
///
/// Contains AI analysis results including transcription, object detections,
/// and priority assessment.
///
/// Example:
/// ```dart
/// var report = EmergenciaReporte(
///   status: 'success',
///   transcription: 'There is a car accident',
///   detections: [Detection(label: 'car', score: 0.95)],
///   detectionSummary: ['car'],
///   priority: 'Alta',
///   processingStatus: 'success',
/// );
/// ```
class EmergenciaReporte {
  /// Overall processing status: "success", "partial", "error"
  final String status;

  /// Transcribed text from audio
  final String transcription;

  /// Raw detection objects from image analysis
  final List<Detection> detections;

  /// Clean list of detected object labels only
  final List<String> detectionSummary;

  /// Priority level: "Alta", "Media", "Baja"
  final String priority;

  /// AI processing status: "success", "partial", "error"
  final String processingStatus;

  /// Human-readable processing message
  final String? message;

  EmergenciaReporte({
    required this.status,
    required this.transcription,
    required this.detections,
    required this.detectionSummary,
    required this.priority,
    required this.processingStatus,
    this.message,
  });

  factory EmergenciaReporte.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? {};

    return EmergenciaReporte(
      status: json['status'] ?? 'unknown',
      transcription: data['transcription'] ?? '',
      detections:
          (data['detections'] as List?)
              ?.map((e) => Detection.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      detectionSummary: List<String>.from(data['detection_summary'] ?? []),
      priority: data['priority'] ?? 'Media',
      processingStatus: data['processing_status'] ?? 'unknown',
      message: json['message'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'status': status,
    'data': {
      'transcription': transcription,
      'detections': detections.map((e) => e.toJson()).toList(),
      'detection_summary': detectionSummary,
      'priority': priority,
      'processing_status': processingStatus,
    },
    if (message != null) 'message': message,
  };

  /// Whether this report indicates a high-priority emergency
  bool get isHighPriority => priority == 'Alta';

  /// Whether the processing completed successfully
  bool get isSuccess => status == 'success' && processingStatus == 'success';

  @override
  String toString() =>
      'EmergenciaReporte(priority: $priority, detections: ${detectionSummary.length})';
}

// ============================================================================
// RESULT WRAPPER (Success/Failure Pattern)
// ============================================================================

/// Abstract base class for Result pattern.
///
/// Represents the outcome of an operation that can either succeed or fail.
/// This pattern eliminates the need for try-catch blocks in calling code.
///
/// Example:
/// ```dart
/// final result = await emergenciaService.enviarReporte(audio, imagen);
///
/// result.when(
///   success: (reporte) => print('Priority: ${reporte.priority}'),
///   failure: (error) => print('Error: ${error.message}'),
/// );
/// ```
sealed class Result<T> {
  const Result();

  /// Execute different logic based on success or failure.
  R when<R>({
    required R Function(T data) success,
    required R Function(EmergenciaException error) failure,
  }) {
    return switch (this) {
      Success<T>(data: final data) => success(data),
      Failure<T>(error: final error) => failure(error),
    };
  }

  /// Execute side effects based on result type.
  void whenOrNull({
    void Function(T data)? success,
    void Function(EmergenciaException error)? failure,
  }) {
    switch (this) {
      case Success<T>(data: final data):
        success?.call(data);
      case Failure<T>(error: final error):
        failure?.call(error);
    }
  }

  /// Get data or null if failure.
  T? getOrNull() {
    return switch (this) {
      Success<T>(data: final data) => data,
      Failure<T>() => null,
    };
  }

  /// Get error or null if success.
  EmergenciaException? getErrorOrNull() {
    return switch (this) {
      Success<T>() => null,
      Failure<T>(error: final error) => error,
    };
  }

  /// Check if result is success.
  bool get isSuccess => this is Success<T>;

  /// Check if result is failure.
  bool get isFailure => this is Failure<T>;
}

/// Success case of Result.
///
/// Contains the result data of a successful operation.
final class Success<T> extends Result<T> {
  final T data;

  const Success(this.data);

  @override
  String toString() => 'Success(data: $data)';
}

/// Failure case of Result.
///
/// Contains the exception from a failed operation.
final class Failure<T> extends Result<T> {
  final EmergenciaException error;

  const Failure(this.error);

  @override
  String toString() => 'Failure(error: $error)';
}

// ============================================================================
// REQUEST MODELS
// ============================================================================

/// Request data for sending an emergency report.
///
/// Used to validate and prepare data before sending to backend.
class EmergenciaReporteRequest {
  /// Path to audio file (e.g., /data/user/0/com.app/cache/audio.mp3)
  final String audioPath;

  /// Path to image file (e.g., /data/user/0/com.app/cache/image.jpg)
  final String imagePath;

  /// Optional metadata or additional info
  final Map<String, dynamic>? metadata;

  /// Callback to track upload progress (0.0 - 1.0)
  final Function(double progress)? onProgress;

  EmergenciaReporteRequest({
    required this.audioPath,
    required this.imagePath,
    this.metadata,
    this.onProgress,
  });

  @override
  String toString() =>
      'EmergenciaReporteRequest('
      'audio: $audioPath, image: $imagePath)';
}
