import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:meorder_kitchen/lib/EnvConfig.dart';
import 'package:meorder_kitchen/screen/HomeScreen.dart';
import 'package:path_provider/path_provider.dart';

class SignInScreen extends StatefulWidget {
  // **สำคัญ: ต้องรับ EnvConfig ผ่าน Constructor**
  final EnvConfig config; 
  const SignInScreen({super.key, required this.config});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
// 1. สถานะเริ่มต้น: ภาษาไทย ('th')
  String _currentLang = 'th';
  String _error = '';
  String _debug = '';

  // 2. สถานะ Map ข้อความเริ่มต้น
  late Map<String, String> _labels;

  // Controller สำหรับ Text Field
  final TextEditingController _controller = TextEditingController();
  
  // สถานะสำหรับควบคุมปุ่ม Submit (เริ่มต้น disable)
  bool _isButtonEnabled = false;

  // 💡 ตัวแปรสำหรับเก็บ config ที่อัปเดตแล้วใน State
  // เริ่มต้นด้วย config ที่รับมาจาก widget
  late EnvConfig _currentConfig;

  @override
  void initState() {
    super.initState();
    // โหลด Map ข้อความเริ่มต้น
    _labels = getLabels(_currentLang);
    // เพิ่ม Listener เพื่อตรวจสอบความถูกต้องของ Input ทุกครั้งที่มีการเปลี่ยนแปลง
    _controller.addListener(_validateInput);
    _currentConfig = widget.config;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // 3. ฟังก์ชันสำหรับเปลี่ยนภาษาและอัปเดต State
  void _toggleLanguage() {
    final newLang = _currentLang == 'th' ? 'en' : 'th';
    
    // ใช้งาน setState เพื่ออัปเดต UI
    setState(() {
      _currentLang = newLang;
      _labels = getLabels(_currentLang); // โหลด Map ข้อความใหม่
    });
  }

  // ตรรกะในการตรวจสอบ Input (ต้องเป็นตัวเลข 6 หลัก)
  void _validateInput() {
    final text = _controller.text;
    // ตรวจสอบว่ามี 6 ตัวอักษรพอดี และสามารถแปลงเป็นตัวเลขได้
    final isValid = text.length == 6 && int.tryParse(text) != null;
    
    // อัปเดตสถานะปุ่มหากมีการเปลี่ยนแปลง
    if (_isButtonEnabled != isValid) {
      setState(() {
        _isButtonEnabled = isValid;
      });
    }
  }
  
  // ตรรกะเมื่อกดปุ่ม Submit
  void _submitCode() async {
    final kitchenCode = _controller.text;

    final uri = Uri.parse(widget.config.apiUrl + 'sign-in'); 

    setState(() { _debug = 'Url: ${widget.config.apiUrl} Token: ${widget.config.apiToken}'; });

    // สร้าง Header
    final headers = {
      'Content-Type': 'application/json', // บอกเซิร์ฟเวอร์ว่า Body เป็น JSON
      'Authorization': 'Bearer ${widget.config.apiToken}', // สร้าง Bearer Token
    };

    // สร้าง Body
    final body = jsonEncode({'Code': kitchenCode});

    try {
      final response = await http.post(uri, headers: headers, body: body);
      
      if (response.statusCode == 200) {
        setState(() { _debug = 'Success! API Response: ${response.body}'; });
        
        final kitchen = jsonDecode(response.body);

        final DateTime expireDate = DateTime.parse(kitchen['ExpireDate']);

        final DateTime today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

        if (today.isAfter(expireDate)) {
          setState(() { _error = _labels['ServiceExpired']!; });
          return;
        } 

        final directory = await getApplicationDocumentsDirectory();
        const String fileName = 'kitchen.txt';
        final filePath = '${directory.path}/$fileName';
        await File(filePath).writeAsString(response.body);

        // 1. อัปเดต config ด้วยค่าใหม่ (TerminalID และ ExpireDate)
        final updatedConfig = _currentConfig.copyWith(
          terminalId: kitchen['TerminalID'],
          expireDate: expireDate,
        );

        // 2. อัปเดต config ใน State
        setState(() { _currentConfig = updatedConfig; });

        // 4. นำทางไปยัง HomeScreen พร้อมส่ง config ที่อัปเดตแล้ว
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => HomeScreen(config: _currentConfig), // ส่ง config ที่มี TerminalID & ExpireDate
          ),
        );
      } else {
        setState(() { _error = 'API Error ${response.statusCode}: ${response.body}'; });
      }
    } catch (e) {
      setState(() { _error = 'Network/Connection Error: $e'; });
    }    
  } // _submitCode

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar( title: Text(widget.config.appTitle) ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Image.asset('assets/images/meorder-online-logo.png', height: 40, width: 40, ),
            SizedBox(height: 10), 

            Text(_labels['PleaseEntryKitchenCode']!, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 10),

            // 1. ➡️ Wrap TextField ด้วย Padding
            Padding(
              // กำหนด Padding เฉพาะแนวนอน (ซ้ายและขวา) 
              padding: const EdgeInsets.symmetric(horizontal: 40), 
              child: TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 50, letterSpacing: 5,),
                decoration: const InputDecoration(
                  labelText: 'Kitchen Code',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 10),

            ElevatedButton(
              onPressed: _isButtonEnabled ? _submitCode : null,
              child: Text(_labels['SignIn']!),
              // ➡️ กำหนดสไตล์ปุ่ม
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue, 
                foregroundColor: Colors.white, 
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 10),

            // 5. ปุ่มสำหรับเปลี่ยนภาษา
            ElevatedButton(
              onPressed: _toggleLanguage,
              child: Text(_labels['ChangeLangButton']!),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 10),

            Text('Error: $_error', style: const TextStyle(fontSize: 12, color: Colors.red)),
            Text('Debug: $_debug', style: const TextStyle(fontSize: 12, color: Colors.black)),
          ],
        ),
      ),
    );
  }
}

// 💡 ฟังก์ชันที่ส่งคืน Map ของข้อความตามรหัสภาษา
Map<String, String> getLabels(String langCode) {
  if (langCode == 'th') {
    return {
      'PleaseEntryKitchenCode': 'กรุณาป้อน Kitchen Code เป็นตัวเลข 6 หลัก',
      'SignIn': 'เข้าสู่ระบบ',
      'ServiceExpired': 'บริการหมดอายุ',
      'ChangeLangButton': 'Change to English',
    };
  } else { // langCode == 'en'
    return {
      'PleaseEntryKitchenCode': 'Please entry Kitchen Code as 6-digit number',
      'SignIn': 'Sign In',
      'ServiceExpired': 'Service Expired',
      'ChangeLangButton': 'เปลี่ยนเป็นภาษาไทย',
    };
  }
}