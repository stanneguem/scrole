import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.update, size: 80, color: Colors.blue),
              const SizedBox(height: 24),
              Text(
                'update_required_title'.tr,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'update_required_message'.tr,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () {
                  // Rediriger vers le store
                  // launchUrl(Uri.parse('https://play.google.com/store/apps/details?id=com.scrole.app'));
                },
                child: Text('update_button'.tr),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
