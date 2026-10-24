import 'package:flutter/material.dart';

class WhatsNewScreen extends StatelessWidget {
  const WhatsNewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quoi de neuf ?')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.rocket_launch, size: 80, color: Colors.blue),
          const SizedBox(height: 24),
          const Text(
            'Scrole arrive bientôt !',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const Text(
            'Nous sommes ravis de vous annoncer que la sortie officielle de l\'application est prévue pour le 30 septembre 2026.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 32),
          _buildFeature('Nouvelle interface modulaire', Icons.dashboard_customize),
          _buildFeature('Synchronisation offline-first', Icons.sync),
          _buildFeature('Gestion avancée des communautés', Icons.groups),
          _buildFeature('Confidentialité renforcée', Icons.security),
        ],
      ),
    );
  }

  Widget _buildFeature(String text, IconData icon) {
    return ListTile(
      leading: Icon(icon, color: Colors.blue),
      title: Text(text),
    );
  }
}
