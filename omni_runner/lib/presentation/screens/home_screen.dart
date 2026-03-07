import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/router/app_router.dart';
import 'package:omni_runner/core/theme/design_tokens.dart';
import 'package:omni_runner/presentation/screens/athlete_dashboard_screen.dart';
import 'package:omni_runner/presentation/screens/history_screen.dart';
import 'package:omni_runner/presentation/screens/more_screen.dart';
import 'package:omni_runner/presentation/screens/staff_dashboard_screen.dart';
import 'package:omni_runner/presentation/screens/today_screen.dart';
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
  late int _tab = _isStaff ? 0 : 1;

  bool get _isStaff => widget.userRole == 'ASSESSORIA_STAFF';

  @override
  Widget build(BuildContext context) {
    if (_isStaff) return _buildStaffShell();
    return _buildAthleteShell();
  }

  void _exitDemoMode() {
    AppConfig.demoMode = false;
    context.go(AppRoutes.root);
  }

  Widget _buildAthleteShell() {
    final scaffold = Scaffold(
      body: NoConnectionBanner(
        child: Column(
          children: [
            if (AppConfig.demoMode) const _DemoModeBanner(),
            if (!AppConfig.demoMode && AppConfig.backendMode == 'mock') _MockModeBanner(),
            Expanded(
              child: IndexedStack(index: _tab, children: [
                AthleteDashboardScreen(isVisible: _tab == 0),
                TodayScreen(isVisible: _tab == 1),
                HistoryScreen(isVisible: _tab == 2),
                const MoreScreen(userRole: 'ATLETA'),
              ]),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? DesignTokens.bgSecondary
            : null,
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
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Hoje',
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

    if (AppConfig.demoMode) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _exitDemoMode();
        },
        child: scaffold,
      );
    }
    return scaffold;
  }

  Widget _buildStaffShell() {
    return Scaffold(
      body: NoConnectionBanner(
        child: Column(
          children: [
            if (AppConfig.demoMode) const _DemoModeBanner(),
            if (!AppConfig.demoMode && AppConfig.backendMode == 'mock') _MockModeBanner(),
            Expanded(
              child: IndexedStack(index: _tab, children: const [
                StaffDashboardScreen(),
                MoreScreen(userRole: 'ASSESSORIA_STAFF'),
              ]),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? DesignTokens.bgSecondary
            : null,
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

class _DemoModeBanner extends StatelessWidget {
  const _DemoModeBanner();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        AppConfig.demoMode = false;
        context.go(AppRoutes.root);
      },
      child: Material(
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 4,
            bottom: 6,
            left: DesignTokens.spacingMd,
            right: DesignTokens.spacingMd,
          ),
          color: DesignTokens.info,
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.explore_outlined, size: 16, color: Colors.white),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Modo exploração — Toque para criar conta',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: 8),
              Icon(Icons.arrow_forward_ios, size: 12, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}

class _MockModeBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Material(
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 4,
          bottom: 6,
          left: DesignTokens.spacingMd,
          right: DesignTokens.spacingMd,
        ),
        color: DesignTokens.warning,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.science_outlined, size: 16, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'Modo demonstração — dados não serão salvos',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
