import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/presentation/blocs/checkin/checkin_bloc.dart';
import 'package:omni_runner/presentation/blocs/checkin/checkin_event.dart';
import 'package:omni_runner/presentation/blocs/checkin/checkin_state.dart';

/// Camera-based QR scanner for training check-in.
/// Scans athlete's check-in QR and dispatches [ConsumeCheckinQr] to [CheckinBloc].
/// On success, pops with true so the detail screen can refresh.
class StaffTrainingScanScreen extends StatefulWidget {
  final String sessionId;

  const StaffTrainingScanScreen({
    super.key,
    required this.sessionId,
  });

  @override
  State<StaffTrainingScanScreen> createState() => _StaffTrainingScanScreenState();
}

class _StaffTrainingScanScreenState extends State<StaffTrainingScanScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  bool _hasScanned = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return BlocProvider(
      create: (_) => sl<CheckinBloc>(),
      child: BlocConsumer<CheckinBloc, CheckinState>(
        listener: (context, state) {
          switch (state) {
            case CheckinSuccess(:final status):
              HapticFeedback.mediumImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    status == 'already_present'
                        ? 'Presença já registrada'
                        : 'Presença registrada com sucesso',
                  ),
                  backgroundColor: Colors.green,
                ),
              );
              Navigator.of(context).pop(true);
            case CheckinError(:final message):
              setState(() => _hasScanned = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(message),
                  backgroundColor: cs.error,
                ),
              );
            case CheckinInitial() ||
                CheckinGenerating() ||
                CheckinQrReady() ||
                CheckinConsuming():
              break;
          }
        },
        builder: (context, state) {
          if (state is CheckinConsuming) {
            return Scaffold(
              appBar: AppBar(title: const Text('Escanear QR')),
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Processando...',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            );
          }

          return Scaffold(
            appBar: AppBar(title: const Text('Escanear QR')),
            body: Column(
              children: [
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      MobileScanner(
                        controller: _scannerController,
                        onDetect: (capture) {
                          if (_hasScanned) return;
                          final barcodes = capture.barcodes;
                          if (barcodes.isEmpty) return;
                          final raw = barcodes.first.rawValue;
                          if (raw == null || raw.isEmpty) return;
                          setState(() => _hasScanned = true);
                          context
                              .read<CheckinBloc>()
                              .add(ConsumeCheckinQr(rawPayload: raw));
                        },
                      ),
                      Container(
                        width: 250,
                        height: 250,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: cs.primary,
                            width: 3,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  color: cs.surfaceContainerHighest,
                  child: Column(
                    children: [
                      Icon(
                        Icons.qr_code_scanner,
                        size: 32,
                        color: cs.primary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Aponte a câmera para o QR Code\ndo atleta para registrar presença',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'O QR possui validade limitada',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.orange.shade700,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
