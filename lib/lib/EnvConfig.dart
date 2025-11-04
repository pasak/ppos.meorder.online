// ในไฟล์ main.dart หรือสร้างไฟล์ใหม่ชื่อ env_config.dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

class EnvConfig {
  final String appTitle;
  final String apiUrl;
  final String apiToken;
  final bool isFileExists; // สถานะการมีอยู่ของไฟล์ kitchen.txt
  final String? terminalId; 
  final DateTime? expireDate; // ใช้ DateTime เพื่อให้จัดการได้ง่าย

  EnvConfig({
    required this.appTitle,
    required this.apiUrl,
    required this.apiToken,
    required this.isFileExists,
    this.terminalId, 
    this.expireDate,
  });
// 💡 สร้างเมธอด .copyWith() สำหรับการสร้าง config ตัวใหม่ที่มีการเปลี่ยนแปลงบางส่วน
  EnvConfig copyWith({
    String? terminalId,
    DateTime? expireDate,
  }) {
    return EnvConfig(
      appTitle: appTitle,
      apiUrl: apiUrl,
      apiToken: apiToken,
      isFileExists: isFileExists,
      terminalId: terminalId ?? this.terminalId, // ถ้าไม่ได้ส่งค่ามา ให้ใช้ค่าเดิม
      expireDate: expireDate ?? this.expireDate, // ถ้าไม่ได้ส่งค่ามา ให้ใช้ค่าเดิม
    );
  }
  // สร้าง factory method สำหรับโหลดและรวมข้อมูลทั้งหมด
  static Future<EnvConfig> load(bool fileExists) async {
    // โหลด Env (ถ้ายังไม่ได้โหลด)
    await dotenv.load(fileName: ".env");

    return EnvConfig(
      appTitle: dotenv.env['APP_TITLE'] ?? 'MeOrder Kitchen',
      apiUrl: dotenv.env['API_URL'] ?? '',
      apiToken: dotenv.env['API_TOKEN'] ?? '',
      isFileExists: fileExists,
    );
  }
}