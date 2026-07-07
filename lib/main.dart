import 'dart:convert';
import 'dart:io'; 
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:meorder_ppos/lib/EnvConfig.dart'; 
import 'package:meorder_ppos/screen/SignInScreen.dart'; 
import 'package:meorder_ppos/screen/POCScreen.dart';
import 'package:meorder_ppos/screen/PPosScreen.dart';
import 'package:meorder_ppos/screen/InitScreen.dart';
import 'package:isar/isar.dart';
import 'package:meorder_ppos/database/IsarModels.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() async {
  await Hive.initFlutter(); // มาจาก hive_flutter
  await Hive.openBox('meOrderBox');

  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: MainScreen(),
  ));
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late EnvConfig _config;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeAndNavigate();
  }

  Future<void> _initializeAndNavigate() async {
    WidgetsFlutterBinding.ensureInitialized();
    await dotenv.load(fileName: ".env");

    final directory = await getApplicationDocumentsDirectory();
    
    // Open Isar if not already open
    if (Isar.getInstance() == null) {
      await Isar.open(
        [
          UserSchema,
          RoleSchema,
          RoleTransactionPermissionSchema,
          ShopCustomerSchema,
          ShopTableSchema,
          SettingValueSchema,
          DocumentCodeSchema,
          DocumentTypeSchema,
          DocumentTemplateSchema,
          FoodCategorySchema,
          FoodSizeSchema,
          FoodItemSchema,
          FoodItemSizeSchema,
          FoodOptionSchema,
          FoodChoiceSchema,
          FoodChoiceSizeSchema,
          ReceiptSchema,
          ShopOpenTableSchema,
          FoodOrderSchema,
          FoodOrderItemSchema,
          PaymentSchema,
          PaymentValueSchema,
          PaymentTransactionSchema,
          MerchandiseCategorySchema,
          MerchandiseItemSchema,
          MerchandisePackSchema,
          ReceiptItemSchema,
          MerchandiseStockSchema,
          TransferStockSchema,
          LastSyncSchema,
          PurchaseOrderSchema,
          PurchaseOrderLogSchema,
          PurchaseOrderItemSchema,
          ReceiptItemStockSchema,
          SupplierSchema,
        ],
        directory: directory.path,
      );
    }

    const storage = FlutterSecureStorage();
    String? branchDataString = await storage.read(key: 'branch');
    bool fileExists = branchDataString != null;

    _config = await EnvConfig.load(fileExists);

    if (fileExists) {
      try {
        final branchData = jsonDecode(branchDataString!);

        if (branchData['LastAccess'] == null) {
            setState(() {
              _error = 'ไม่สามารถใช้งานได้เนื่องจากข้อมูลไม่ถูกต้อง \nCannot be used because the data is incorrect.';
            });
            return;
        } else {
          DateTime lastAccess = DateTime.parse(branchData['LastAccess']);
          if (lastAccess.isAfter(DateTime.now())) {
            setState(() {
              _error = 'เวลาของเครื่อง ถูกตั้งให้ย้อนกลับ The device\'s time is set to go backward';
            });
            return;
          } else {
            branchData['LastAccess'] = DateTime.now().toIso8601String();
            await storage.write(key: 'branch', value: jsonEncode(branchData));
          }
        }

        bool isExpired = false;
        if (branchData['ExpireDate'] != null && branchData['ExpireDate'].toString().isNotEmpty) {
          try {
            DateTime expireDate = DateTime.parse(branchData['ExpireDate']);
            if (DateTime.now().isAfter(expireDate)) {
              isExpired = true;
            }
          } catch (e) {
            print("Error parsing ExpireDate: $e");
          }
        }

        final updatedConfig = _config.copyWith(
          shop_ID:                branchData['shop_ID']?.toString(),
          ShopName:               branchData['ShopName'],
          shop_branch_ID:         branchData['shop_branch_ID']?.toString(),
          service_module_ID:      branchData['service_module_ID'],
          shop_branch_service_ID: branchData['shop_branch_service_ID'],
          BranchName:             branchData['BranchName'],
          Address:                branchData['Address'], 
          Telephone:              branchData['Telephone'],
          isActive:               branchData['IsActive'] == 'Y',
          language:               branchData['language'],
          ExpireDate:             branchData['ExpireDate'],
          isExpired:              isExpired,
          LastUpdated:            branchData['LastUpdated'],
          UserID:                 branchData['UserID']?.toString(),
          UserRole:               branchData['UserRole'],
          PrinterModel:           branchData['PrinterModel'],
          ConnectType:            branchData['ConnectType'],
          PrinterAddress:         branchData['PrinterAddress'],
          isKitchen:              branchData['isKitchen'] == true,
        );

        setState(() { _config = updatedConfig; });

        if (branchData['UserID'] == null) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => SignInScreen(config: _config),
            ),
          );
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => PPosScreen(config: _config),
            ),
          );
        }
      } catch (e) {
        print('Error reading branch.json: $e');
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => InitScreen(config: _config),
          ),
        );
      }
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => InitScreen(config: _config),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _error != null
            ? Text(_error!, style: const TextStyle(fontSize: 20, color: Colors.red))
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset('assets/images/meorder-online-logo.png', height: 200, width: 200),
                  const SizedBox(height: 30),
                  const CircularProgressIndicator(),
                ],
              ),
      ),
    );
  }
}


