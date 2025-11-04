import 'package:flutter/material.dart';
import 'package:meorder_kitchen/lib/EnvConfig.dart'; 

/// หน้าจอหลักที่แสดงเมื่อพบไฟล์ kitchen.txt
class HomeScreen extends StatelessWidget {
  // **สำคัญ: ต้องรับ EnvConfig ผ่าน Constructor**
  final EnvConfig config; 
  const HomeScreen({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar( title: Text(config.appTitle), backgroundColor: Colors.blue, ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 80.0),
              const SizedBox(height: 20),
              const Text(
                'พบไฟล์ kitchen.txt - เข้าสู่หน้าหลัก',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              Text('API URL: ${config.apiUrl}',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text('API Token: ${config.apiToken.substring(0, 10)}...',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
