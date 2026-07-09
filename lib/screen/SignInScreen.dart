import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:meorder_ppos/lib/EnvConfig.dart';
import 'package:path_provider/path_provider.dart';
import 'package:isar/isar.dart';
import 'package:meorder_ppos/database/IsarModels.dart';
import 'package:meorder_ppos/screen/PPosScreen.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SignInScreen extends StatefulWidget {
  final EnvConfig config; 
  const SignInScreen({super.key, required this.config});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  String _currentLang = 'th';
  String _error = '';
  String _debug = '';

  late Map<String, String> _labels;

  final TextEditingController _controller = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  bool _obscurePassword = true;
  bool _isButtonEnabled = false;
  late EnvConfig _currentConfig;

  @override
  void initState() {
    super.initState();
    _labels = getLabels(_currentLang);
    _controller.addListener(_validateInput);
    _passwordController.addListener(_validateInput);
    _currentConfig = widget.config;
  }

  @override
  void dispose() {
    _controller.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _toggleLanguage() {
    final newLang = _currentLang == 'th' ? 'en' : 'th';
    setState(() {
      _currentLang = newLang;
      _labels = getLabels(_currentLang);
    });
  }

  void _validateInput() {
    final isValid = _controller.text.isNotEmpty && _passwordController.text.isNotEmpty;
    if (_isButtonEnabled != isValid) {
      setState(() {
        _isButtonEnabled = isValid;
      });
    }
  }
  
  void _submitUserNamePassword() async {
    final userName = _controller.text;
    final password = _passwordController.text;
    
    try {
      final isar = Isar.getInstance()!;
      final user = await isar.userList.filter().userNameEqualTo(userName).findFirst();

      if (user != null) {
         final isMatch = BCrypt.checkpw(password, user.passwordHash ?? '');
         if (isMatch) {
            const storage = FlutterSecureStorage();
            final branchStr = await storage.read(key: 'branch');
            Map<String, dynamic> branchData = {};
            if (branchStr != null) {
              branchData = jsonDecode(branchStr);
              branchData['UserID'] = user.id.toString();
              branchData['UserRole'] = user.role_ID;
              branchData['language'] = user.language;
              
              await storage.write(key: 'branch', value: jsonEncode(branchData));
            }

            final updatedConfig = _currentConfig.copyWith(
              shop_ID: branchData['shop_ID']?.toString(),
              ShopName: branchData['ShopName'],
              TaxID: branchData['TaxID'],
              shop_branch_ID: branchData['shop_branch_ID']?.toString(),
              service_module_ID: branchData['service_module_ID'],
              shop_branch_service_ID: branchData['shop_branch_service_ID'],
              IntervalType: branchData['IntervalType'],
              BranchName: branchData['BranchName'],
              Address: branchData['Address'],
              Telephone: branchData['Telephone'],
              isActive: (branchData['IsActive'] == 'Y' || branchData['isActive'] == true) ? true : false,
              language: user.language,
              printerMacAddress: branchData['printerMacAddress'],
              isKitchen: branchData['isKitchen'],
              PrinterModel: branchData['PrinterModel'],
              ConnectType: branchData['ConnectType'],
              PrinterAddress: branchData['PrinterAddress'],
              ExpireDate: branchData['ExpireDate'],
              LastUpdated: branchData['LastUpdated'],
              PosID: branchData['PosID']?.toString(),
              isExpired: branchData['isExpired'],
              UserID: user.id.toString(),
              UserRole: user.role_ID,
            );

            if (mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (context) => PPosScreen(config: updatedConfig),
                ),
              );
            }
         } else {
            setState(() { _error = _labels['PasswordIncorrect']!; });
         }
      } else {
         setState(() { _error = _labels['NotFoundThisUserName']!; });
      }
    } catch (e) {
      setState(() { _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar( title: Text(widget.config.appTitle) ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Image.asset('assets/images/meorder-online-logo.png', height: 40, width: 40, ),
              const SizedBox(height: 10), 

              Text(_labels['PleaseEntryUserName']!, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 10),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40), 
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.text,
                  style: const TextStyle(fontSize: 30),
                  decoration: const InputDecoration(
                    labelText: 'ชื่อผู้ใช้ (User Name)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40), 
                child: TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  keyboardType: TextInputType.text,
                  style: const TextStyle(fontSize: 30),
                  decoration: InputDecoration(
                    labelText: 'รหัสผ่าน (Password)',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                        size: 30,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: _isButtonEnabled ? _submitUserNamePassword : null,
                child: Text(_labels['SignIn']!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue, 
                  foregroundColor: Colors.white, 
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                ),
              ),
              const SizedBox(height: 10),

              ElevatedButton(
                onPressed: _toggleLanguage,
                child: Text(_labels['ChangeLangButton']!),
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 10),

              Text(_error, style: const TextStyle(fontSize: 14, color: Colors.red)),
              Text(_debug, style: const TextStyle(fontSize: 12, color: Colors.black)),
            ],
          ),
        ),
      ),
    );
  }
}

Map<String, String> getLabels(String langCode) {
  if (langCode == 'th') {
    return {
      'PleaseEntryUserName': 'กรุณาป้อนชื่อผู้ใช้',
      'SignIn': 'เข้าสู่ระบบ',
      'ChangeLangButton': 'Change to English',
      'PasswordIncorrect': 'รหัสผ่านไม่ถูกต้อง',
      'NotFoundThisUserName': 'ไม่พบชื่อผู้ใช้นี้ในระบบ',
    };
  } else { // langCode == 'en'
    return {
      'PleaseEntryUserName': 'Please enter User Name',
      'SignIn': 'Sign In',
      'ChangeLangButton': 'เปลี่ยนเป็นภาษาไทย',
      'PasswordIncorrect': 'Password incorrect',
      'NotFoundThisUserName': 'User Name not found',
    };
  }
}
