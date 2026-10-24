import 'package:flutter/material.dart';

class HelpCenterScreen extends StatelessWidget {
  const HelpCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Centre d\'aide')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildFaqItem(
            'Comment créer une communauté ?',
            'Allez dans l\'onglet Communautés et cliquez sur le bouton "+" en haut de l\'écran.',
          ),
          _buildFaqItem(
            'Comment changer ma photo de profil ?',
            'Allez dans vos paramètres, puis dans "Mon compte" pour modifier vos informations.',
          ),
          _buildFaqItem(
            'Qu\'est-ce que le système de rangs ?',
            'Le système de rangs récompense votre activité au sein des communautés par des badges et des points.',
          ),
          const SizedBox(height: 32),
          const Center(
            child: Text(
              'Besoin d\'aide supplémentaire ?\nContactez-nous à support@scrole.app',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFaqItem(String question, String answer) {
    return ExpansionTile(
      title: Text(question, style: const TextStyle(fontWeight: FontWeight.bold)),
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(answer),
        ),
      ],
    );
  }
}
