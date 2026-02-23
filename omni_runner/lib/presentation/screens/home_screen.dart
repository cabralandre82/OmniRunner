import 'package:flutter/material.dart';

import 'package:omni_runner/presentation/screens/athlete_dashboard_screen.dart';
import 'package:omni_runner/presentation/screens/history_screen.dart';
import 'package:omni_runner/presentation/screens/more_screen.dart';
import 'package:omni_runner/presentation/screens/staff_dashboard_screen.dart';
import 'package:omni_runner/presentation/screens/tracking_screen.dart';

/// Root navigation shell with bottom tab bar.
///
/// Tab 0 shows [AthleteDashboardScreen] or [StaffDashboardScreen]
/// depending on [userRole] (passed from [AuthGate]).
///
/// Tabs:
///   0 — Início (role-aware dashboard)
///   1 — Correr (GPS tracking, map, ghost runner)
///   2 — Histórico (past sessions, sync)
///   3 — Mais (coaching, social, integrations, settings)
class HomeScreen extends StatefulWidget {
  final String? userRole;

  const HomeScreen({super.key, this.userRole});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  late final List<Widget> _tabs = [
    widget.userRole == 'ASSESSORIA_STAFF'
        ? const StaffDashboardScreen()
        : const AthleteDashboardScreen(),
    const TrackingScreen(),
    const HistoryScreen(),
    const MoreScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 64,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Início',
          ),
          NavigationDestination(
            icon: Icon(Icons.directions_run_outlined),
            selectedIcon: Icon(Icons.directions_run),
            label: 'Correr',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'Histórico',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_outlined),
            selectedIcon: Icon(Icons.menu),
            label: 'Mais',
          ),
        ],
      ),
    );
  }
}
