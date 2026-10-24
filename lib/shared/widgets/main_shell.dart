import 'package:flutter/material.dart';
import '../../modules/module_evenement/interne/pages/event_screen.dart';
import '../../modules/module_profil/interne/pages/profile_screen.dart';
import 'search_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  
  // Chargement différé : seul l'onglet 0 (Accueil) est visité au démarrage
  final List<bool> _visited = [true, false, false];

  final List<Widget> _pages = const [
    SearchScreen(), // 1. Accueil (Fil d'actualité / Recherche)
    EventScreen(),   // 2. Événements
    ProfileScreen(), // 3. Profil utilisateur connecté
  ];

  void _onTabChanged(int index) {
    setState(() {
      _currentIndex = index;
      _visited[index] = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: List.generate(_pages.length, (index) {
          // Si l'onglet n'a jamais été visité, on ne le construit pas (chargement différé)
          if (!_visited[index]) {
            return const SizedBox.shrink();
          }
          return _pages[index];
        }),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTabChanged,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_outlined),
            selectedIcon: Icon(Icons.event_rounded),
            label: 'Événements',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}
