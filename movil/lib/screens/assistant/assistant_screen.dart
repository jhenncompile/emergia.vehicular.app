import 'package:flutter/material.dart';

import '../../services/assistant_service.dart';
import '../../theme/colors.dart';

/// Chatbot auxiliar para el cliente.
///
/// Muestra recomendaciones basicas de seguridad mientras el cliente espera la
/// asistencia. Es independiente del flujo de incidentes: solo consume el
/// endpoint stateless `/assistant/chat` y no altera ningun estado de la app.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _MensajeChat {
  _MensajeChat({required this.texto, required this.esBot});
  final String texto;
  final bool esBot;
}

class _AssistantScreenState extends State<AssistantScreen> {
  final AssistantService _service = AssistantService();
  final ScrollController _scrollController = ScrollController();

  final List<_MensajeChat> _mensajes = [];
  List<Map<String, dynamic>> _opciones = [];
  String? _nodoActual;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _iniciar() async {
    await _enviar(nodo: null, opcion: null);
  }

  Future<void> _enviar({String? nodo, String? opcion, String? textoUsuario}) async {
    setState(() {
      if (textoUsuario != null) {
        _mensajes.add(_MensajeChat(texto: textoUsuario, esBot: false));
      }
      _opciones = [];
      _cargando = true;
    });
    _bajarScroll();

    try {
      final resp = await _service.chat(nodo: nodo, opcion: opcion);
      if (!mounted) return;
      setState(() {
        _nodoActual = resp['nodo'] as String?;
        _mensajes.add(_MensajeChat(texto: resp['mensaje'] as String, esBot: true));
        _opciones = List<Map<String, dynamic>>.from(resp['opciones'] ?? []);
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mensajes.add(_MensajeChat(
          texto: 'No pude responder en este momento. Intenta nuevamente.',
          esBot: true,
        ));
        _cargando = false;
      });
    }
    _bajarScroll();
  }

  void _bajarScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(title: const Text('Chatbot Auxiliar')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _mensajes.length,
              itemBuilder: (context, index) => _burbuja(_mensajes[index]),
            ),
          ),
          if (_cargando)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (!_cargando && _opciones.isNotEmpty)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: _opciones.map(_botonOpcion).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _botonOpcion(Map<String, dynamic> opcion) {
    return ElevatedButton(
      onPressed: () => _enviar(
        nodo: _nodoActual,
        opcion: opcion['id'] as String,
        textoUsuario: opcion['texto'] as String,
      ),
      child: Text(opcion['texto'] as String),
    );
  }

  Widget _burbuja(_MensajeChat mensaje) {
    final esBot = mensaje.esBot;

    final burbuja = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.72,
      ),
      decoration: BoxDecoration(
        color: esBot ? Colors.white : AppColors.primaryColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(esBot ? 4 : 16),
          bottomRight: Radius.circular(esBot ? 16 : 4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        mensaje.texto,
        style: TextStyle(
          color: esBot ? AppColors.textDark : Colors.white,
          fontSize: 14,
          height: 1.35,
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: esBot ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (esBot) ...[
            const CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.info,
              child: Icon(Icons.support_agent, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(child: burbuja),
        ],
      ),
    );
  }
}
