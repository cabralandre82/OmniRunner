import 'package:flutter/material.dart';

import 'package:omni_runner/presentation/screens/athlete_dashboard_screen.dart';
import 'package:omni_runner/presentation/screens/history_screen.dart';
import 'package:omni_runner/presentation/screens/more_screen.dart';
import 'package:omni_runner/presentation/screens/staff_dashboard_screen.dart';
import 'package:omni_runner/presentation/screens/tracking_screen.dart';
import 'package:omni_runner/presentation/widgets/no_connection_banner.dart';

/// Root navigation shell with bottom tab bar.
///
/// Athlete tabs: Início, Correr, Histórico, Mais
/// Staff tabs: Início, Mais (no running / history)
class HomeScreen extends StatefulWidget {
  final String? userRole;

  const HomeScreen({super.key, this.userRole});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  bool get _isStaff => widget.userRole == 'ASSESSORIA_STAFF';

  @override
  Widget build(BuildContext context) {
    if (_isStaff) return _buildStaffShell();
    return _buildAthleteShell();
  }

  Widget _buildAthleteShell() {
    return Scaffold(
      body: NoConnectionBanner(
        child: IndexedStack(index: _tab, children: [
        const AthleteDashboardScreen(),
        const TrackingScreen(),
        HistoryScreen(isVisible: _tab == 2),
        const MoreScreen(userRole: 'ATLETA'),
      ]),
      ),
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

  Widget _buildStaffShell() {
    return Scaffold(
      body: NoConnectionBanner(
        child: IndexedStack(index: _tab, children: const [
        StaffDashboardScreen(),
        MoreScreen(userRole: 'ASSESSORIA_STAFF'),
      ]),
      ),
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
            icon: Icon(Icons.menu_outlined),
            selectedIcon: Icon(Icons.menu),
            label: 'Mais',
          ),
        ],
      ),
    );
  }
}
