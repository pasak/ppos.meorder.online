// ในไฟล์ main.dart หรือสร้างไฟล์ใหม่ชื่อ env_config.dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

class EnvConfig {
  final String appTitle;
  final String apiUrl;
  final String apiToken;
  final bool isFileExists; // สถานะการมีอยู่ของไฟล์ store.json
  final String? shop_ID;
  final String? ShopName;
  final String? shop_branch_ID;
  final String? service_module_ID;
  final String? BranchName;
  final String? Address;
  final String? Telephone;
  final bool? isActive;  
  final String? language;
  final String? printerMacAddress;
  final bool? isKitchen;
  final String? UserID;
  final String? UserRole;
  final String? PrinterModel;
  final String? ConnectType;
  final String? PrinterAddress;
  final String? ExpireDate;
  final String? LastUpdated;

  EnvConfig({
    required this.appTitle,
    required this.apiUrl,
    required this.apiToken,
    required this.isFileExists,
    this.shop_ID,
    this.ShopName,
    this.shop_branch_ID,
    this.service_module_ID,
    this.BranchName,
    this.Address,
    this.Telephone,
    this.isActive,
    this.language,
    this.printerMacAddress,
    this.isKitchen,
    this.UserID,
    this.UserRole,
    this.PrinterModel,
    this.ConnectType,
    this.PrinterAddress,
    this.ExpireDate,
    this.LastUpdated,
  });

  // 💡 สร้างเมธอด .copyWith() สำหรับการสร้าง config ตัวใหม่ที่มีการเปลี่ยนแปลงบางส่วน
  EnvConfig copyWith({
    String? shop_ID,
    String? ShopName,
    String? shop_branch_ID,
    String? service_module_ID,
    String? BranchName,
    String? Address,
    String? Telephone,
    bool? isActive,
    String? language,
    String? printerMacAddress,
    bool? isKitchen,
    String? UserID,
    String? UserRole,
    String? PrinterModel,
    String? ConnectType,
    String? PrinterAddress,
    String? ExpireDate,
    String? LastUpdated,
  }) {
    return EnvConfig(
      appTitle: appTitle,
      apiUrl: apiUrl,
      apiToken: apiToken,
      isFileExists: isFileExists,
      shop_ID: shop_ID ?? this.shop_ID,
      ShopName: ShopName ?? this.ShopName, 
      shop_branch_ID: shop_branch_ID ?? this.shop_branch_ID,
      service_module_ID: service_module_ID ?? this.service_module_ID,
      BranchName: BranchName ?? this.BranchName,
      Address: Address ?? this.Address,
      Telephone: Telephone ?? this.Telephone,
      isActive: isActive ?? this.isActive,
      language: language ?? this.language,
      printerMacAddress: printerMacAddress ?? this.printerMacAddress,
      isKitchen: isKitchen ?? this.isKitchen,
      UserID: UserID ?? this.UserID,
      UserRole: UserRole ?? this.UserRole,
      PrinterModel: PrinterModel ?? this.PrinterModel,
      ConnectType: ConnectType ?? this.ConnectType,
      PrinterAddress: PrinterAddress ?? this.PrinterAddress,
      ExpireDate: ExpireDate ?? this.ExpireDate,
      LastUpdated: LastUpdated ?? this.LastUpdated,
    );
  }
  
  // สร้าง factory method สำหรับโหลดและรวมข้อมูลทั้งหมด
  static Future<EnvConfig> load(bool fileExists) async {
    // โหลด Env (ถ้ายังไม่ได้โหลด)
    await dotenv.load(fileName: ".env");

    return EnvConfig(
      appTitle: dotenv.env['APP_TITLE'] ?? 'MeOrder PPos',
      apiUrl: dotenv.env['API_URL'] ?? '',
      apiToken: dotenv.env['API_TOKEN'] ?? '',
      isFileExists: fileExists,
    );
  }
}
