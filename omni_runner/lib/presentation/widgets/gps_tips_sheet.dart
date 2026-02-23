import 'package:flutter/material.dart';

/// Bottom sheet with practical GPS tips to help users avoid
/// invalidated runs. All text in friendly PT-BR.
class GpsTipsSheet extends StatelessWidget {
  const GpsTipsSheet._();

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const GpsTipsSheet._(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 16, bottom: pad + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.satellite_alt_rounded,
                  size: 24, color: Colors.blue.shade700),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Dicas para melhorar o GPS',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _Tip(
            icon: Icons.visibility_rounded,
            title: 'Espere o sinal estabilizar',
            body: 'Antes de começar, fique parado ao ar livre por '
                '15–30 segundos até o app captar GPS.',
          ),
          const _Tip(
            icon: Icons.forest_rounded,
            title: 'Evite locais fechados',
            body: 'Túneis, prédios altos e árvores densas '
                'podem enfraquecer o sinal de GPS.',
          ),
          const _Tip(
            icon: Icons.phone_android_rounded,
            title: 'Mantenha o celular firme',
            body: 'Leve o celular no braço ou no bolso. '
                'Movimentos bruscos podem gerar leituras erradas.',
          ),
          const _Tip(
            icon: Icons.wifi_off_rounded,
            title: 'Ative Wi-Fi e Bluetooth',
            body: 'Mesmo sem usar internet, Wi-Fi e Bluetooth '
                'ajudam o sistema de localização.',
          ),
          const _Tip(
            icon: Icons.battery_charging_full_rounded,
            title: 'Bateria e modo econômico',
            body: 'O modo de economia de energia pode reduzir '
                'a precisão do GPS. Desative durante a corrida.',
          ),
          const _Tip(
            icon: Icons.update_rounded,
            title: 'Atualize o app e o sistema',
            body: 'Versões antigas podem ter problemas de '
                'compatibilidade com o sensor GPS.',
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Entendi'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _Tip({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: Colors.blue.shade700),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
