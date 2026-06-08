import 'api_service.dart';

/// Servicio de pagos para el movil.
/// Nota: el backend actual expone endpoints de pagos para rol admin de taller.
class PagoService {
  final ApiService apiService;

  PagoService({required this.apiService});

  Future<List<Map<String, dynamic>>> obtenerMisHistorialPagos({
    required int usuarioId,
  }) async {
    final response = await apiService.get('/api/v1/pagos/cliente/historial');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> obtenerFacturasPendientes({
    required int usuarioId,
  }) async {
    final response = await apiService.get('/api/v1/pagos/cliente/pendientes');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> obtenerDetallePago({required int pagoId}) async {
    throw Exception(
      'Detalle de pago no disponible para rol movil en backend actual.',
    );
  }

  Future<Map<String, dynamic>> registrarPago({
    required int incidenteId,
    required int usuarioId,
    required int tallerId,
    required double monto,
    required String metodoPago,
    String? referencia,
  }) async {
    throw Exception(
      'Registro de pago desde movil aun no disponible en backend actual.',
    );
  }

  Future<String> descargarComprobante({required int pagoId}) async {
    throw Exception(
      'Comprobante no disponible para rol movil en backend actual.',
    );
  }

  Future<Map<String, dynamic>> crearPaymentIntent(int pagoId) async {
    final response = await apiService.post('/api/v1/pagos/intent/$pagoId', body: {});
    if (response['paymentIntent'] != null) {
      return response;
    } else {
      throw Exception('No se pudo obtener el intent de pago');
    }
  }

  Future<void> confirmarPagoCliente(int pagoId) async {
    await apiService.post('/api/v1/pagos/cliente/$pagoId/confirmar?metodo_pago=Tarjeta', body: {});
  }
}
