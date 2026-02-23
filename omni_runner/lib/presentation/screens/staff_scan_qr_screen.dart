import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:omni_runner/domain/entities/token_intent_entity.dart';
import 'package:omni_runner/presentation/blocs/staff_qr/staff_qr_bloc.dart';
import 'package:omni_runner/presentation/blocs/staff_qr/staff_qr_event.dart';
import 'package:omni_runner/presentation/blocs/staff_qr/staff_qr_state.dart';

/// Camera-based QR scanner that reads and consumes a token intent.
///
/// Used by athletes scanning a staff-generated QR, or by staff assisting
/// an athlete. The scanned payload is validated client-side for expiry,
/// then sent to the backend for consumption.
class StaffScanQrScreen extends StatefulWidget {
  const StaffScanQrScreen({super.key});

  @override
  State<StaffScanQrScreen> createState() => _StaffScanQrScreenState();
}

class _StaffScanQrScreenState extends State<StaffScanQrScreen> {
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
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear QR')),
      body: BlocConsumer<StaffQrBloc, StaffQrState>(
        listener: (context, state) {
          if (state is StaffQrConsumed) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_successMessage(state.type)),
                backgroundColor: Colors.green,
              ),
            );
            Navigator.of(context).pop();
          }
          if (state is StaffQrError) {
            setState(() => _hasScanned = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: theme.colorScheme.error,
              ),
            );
          }
        },
        builder: (context, state) {
          if (state is StaffQrConsuming) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text('Processando...', style: theme.textTheme.bodyLarge),
                ],
              ),
            );
          }

          return Column(
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
                            .read<StaffQrBloc>()
                            .add(ConsumeScannedQr(raw));
                      },
                    ),
                    // Viewfinder overlay
                    Container(
                      width: 250,
                      height: 250,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: theme.colorScheme.primary,
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
                color: theme.colorScheme.surfaceContainerHighest,
                child: Column(
                  children: [
                    Icon(Icons.qr_code_scanner,
                        size: 32, color: theme.colorScheme.primary),
                    const SizedBox(height: 8),
                    Text(
                      'Aponte a câmera para o QR Code\ngerado pelo staff da assessoria',
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
          );
        },
      ),
    );
  }

  static String _successMessage(TokenIntentType t) => switch (t) {
        TokenIntentType.issueToAthlete => 'OmniCoins recebidos com sucesso!',
        TokenIntentType.burnFromAthlete => 'OmniCoins devolvidos com sucesso!',
        TokenIntentType.champBadgeActivate =>
          'Badge de campeonato ativado com sucesso!',
      };
}
