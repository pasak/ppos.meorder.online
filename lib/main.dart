import 'dart:io'; 
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:meorder_kitchen/lib/EnvConfig.dart'; 

import 'screen/HomeScreen.dart'; 
import 'screen/SignInScreen.dart'; 

// ฟังก์ชันสำหรับรวมการตรวจสอบไฟล์และการโหลด Env
Future<EnvConfig> initializeApp() async {
  // ตรวจสอบให้แน่ใจว่า Flutter Binding พร้อมใช้งานก่อนเรียกใช้ PathProvider
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. โหลด Env ก่อน
  await dotenv.load(fileName: ".env");
  
  // 2. ตรวจสอบไฟล์ kitchen.txt
  bool fileExists = false;
  try {
    final directory = await getApplicationDocumentsDirectory();
    const String fileName = 'kitchen.txt';
    final filePath = '${directory.path}/$fileName';
    fileExists = await File(filePath).exists();
  } catch (e) {
    // พิมพ์ข้อผิดพลาด แต่ถือว่าไม่พบไฟล์ เพื่อไปหน้า SignInScreen
    print('Error checking file existence: $e');
  }

  // 3. สร้าง EnvConfig object พร้อมสถานะไฟล์
  return EnvConfig.load(fileExists); 
}

void main() {
  // รันแอป
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // FutureBuilder จะเรียก initializeApp() และรอผลลัพธ์
    return FutureBuilder<EnvConfig>(
      future: initializeApp(),
      builder: (BuildContext context, AsyncSnapshot<EnvConfig> snapshot) {
        
        // 1. แสดง Loading Screen ในขณะที่รอ Future
        if (snapshot.connectionState == ConnectionState.waiting) {
          return MaterialApp(
            home: Scaffold(
              body: Center(
                // 1. ใช้ Center เพื่อให้ Column อยู่กึ่งกลางหน้าจอ
                child: Column(
                  // 2. จัดให้ Column อยู่กึ่งกลางแนวตั้ง (Main Axis) และแนวนอน (Cross Axis)
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
            
                  children: <Widget>[
                    // 3. Image (โลโก้)
                    Image.asset(
                    'assets/images/meorder-online-logo.png', height: 200, width: 200, ),
                    // 4. Widget เพื่อสร้างช่องว่างระหว่าง Image กับ Indicator
                    SizedBox(height: 30), 

                    // 5. CircularProgressIndicator (ตัวหมุนโหลด)
                    CircularProgressIndicator(),
                  ],              
                ),
              ),
            ),
          );
        }

        // 2. เมื่อโหลดสำเร็จ (มีข้อมูล EnvConfig)
        if (snapshot.hasData) {
          final EnvConfig config = snapshot.data!;

          // **เงื่อนไขการนำทางตามสถานะไฟล์**
          final Widget initialScreen = config.isFileExists 
              ? HomeScreen(config: config) // ส่ง config ไปยัง HomeScreen
              : SignInScreen(config: config); // ส่ง config ไปยัง SignInScreen

          return MaterialApp(
            title: config.appTitle,
            debugShowCheckedModeBanner: false,
            theme: ThemeData(primarySwatch: Colors.blue),
            home: initialScreen, // ใช้หน้าจอเริ่มต้นตามเงื่อนไข
          );
        } 

        // 3. กรณีมีข้อผิดพลาดร้ายแรง (เช่น โหลด Env ไม่ได้เลย)
        return const MaterialApp(
          home: Scaffold(
            body: Center(
              child: Text('Failed to load application configuration. Check .env file.'),
            ),
          ),
        );
      },
    ); 
  } 
}
