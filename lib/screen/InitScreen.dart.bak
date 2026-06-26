import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:meorder_ppos/lib/EnvConfig.dart';
import 'package:meorder_ppos/screen/SetPrinterScreen.dart';
import 'package:path_provider/path_provider.dart';
import 'package:isar/isar.dart';
import 'package:meorder_ppos/database/IsarModels.dart';

class InitScreen extends StatefulWidget {
  final EnvConfig config;
  const InitScreen({super.key, required this.config});

  @override
  State<InitScreen> createState() => _InitScreenState();
}

class _InitScreenState extends State<InitScreen> {
  String _currentLang = 'th';
  String _error = '';
  String _debug = '';

  late Map<String, String> _labels;
  final TextEditingController _controller = TextEditingController();
  bool _isButtonEnabled = false;
  bool _isLoading = false;

  late EnvConfig _currentConfig;

  @override
  void initState() {
    super.initState();
    _labels = getLabels(_currentLang);
    _controller.addListener(_validateInput);
    _currentConfig = widget.config;
  }

  @override
  void dispose() {
    _controller.dispose();
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
    final text = _controller.text;
    final isValid = text.length == 6 && int.tryParse(text) != null;
    
    if (_isButtonEnabled != isValid) {
      setState(() {
        _isButtonEnabled = isValid;
      });
    }
  }
  
  void _submitCode() async {
    final serviceCode = _controller.text;
    final uri = Uri.parse('${widget.config.apiUrl}api/pos/pull-master'); 

    setState(() { 
      _isLoading = true;
      _error = '';
      _debug = 'Connecting...';
    });

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${widget.config.apiToken}',
    };

    final body = jsonEncode({
      'shop_branch_service_ID': serviceCode,
      'Language': _currentLang
    });

    try {
      final response = await http.post(uri, headers: headers, body: body);
      
      if (response.statusCode == 200) {
        setState(() { _debug = 'Processing data...'; });
        
        final responseData = jsonDecode(response.body);
        
        // 1. Process Branch Data
        final branchData = responseData['Branch'];
        branchData['UserID'] = null;
        branchData['UserRole'] = null;
        branchData['PrinterModel'] = null;
        branchData['ConnectType'] = null;
        branchData['PrinterAddress'] = null;
        branchData['isKitchen'] = true;

        final directory = await getApplicationDocumentsDirectory();
        final filePath = '${directory.path}/branch.json';
        await File(filePath).writeAsString(jsonEncode(branchData));

        final updatedConfig = _currentConfig.copyWith(
          shop_ID: branchData['shop_ID']?.toString(),
          ShopName: branchData['ShopName'],
          TaxID: branchData['TaxID'],
          shop_branch_ID: branchData['shop_branch_ID']?.toString(),
          service_module_ID: branchData['service_module_ID'],
          BranchName: branchData['BranchName'],
          Address: branchData['Address'],
          Telephone: branchData['Telephone'],
          isActive: (branchData['IsActive'] == 'Y') ? true : false, 
          ExpireDate: branchData['ExpireDate'],
          LastUpdated: branchData['LastUpdated'],
          PosID: branchData['PosID']?.toString(),
        );

        setState(() { _debug = 'updatedConfig success'; });

        // 2. Process Isar Data
        final isar = Isar.getInstance()!;

        await isar.writeTxn(() async {
          // Clear existing data
          await isar.userList.clear();
          await isar.roleList.clear();
          await isar.roleTransactionPermissionList.clear();
          await isar.shopCustomerList.clear();
          await isar.shopTableList.clear();
          await isar.settingValueList.clear();
          await isar.documentCodeList.clear();
          await isar.documentTypeList.clear();
          await isar.documentTemplateList.clear();
          await isar.foodCategoryList.clear();
          await isar.foodSizeList.clear();
          await isar.foodItemList.clear();
          await isar.foodItemSizeList.clear();
          await isar.foodOptionList.clear();
          await isar.foodChoiceList.clear();
          await isar.foodChoiceSizeList.clear();
          await isar.receiptList.clear();
          await isar.shopOpenTableList.clear();
          await isar.foodOrderList.clear();
          await isar.foodOrderItemList.clear();
          await isar.paymentList.clear();
          await isar.paymentValueList.clear();
          await isar.merchandiseCategoryList.clear();
          await isar.merchandiseItemList.clear();
          await isar.merchandisePackList.clear();
          await isar.receiptItemList.clear();
          await isar.lastSyncList.clear();

          // LastSync
          final String currentTime = DateTime.now().toIso8601String();
          final lastSync = LastSync()
            ..id = 1
            ..master = currentTime
            ..receipt = currentTime;
          await isar.lastSyncList.put(lastSync);

          // User
          final userListRaw = responseData['UserList'] as List<dynamic>? ?? [];
          final user = userListRaw.map((e) => User()
            ..id = e['ID']
            ..name = e['Name']
            ..userName = e['UserName']
            ..passwordHash = e['PasswordHash']
            ..role_ID = e['role_ID']
            ..language = e['Language']
            ..isActive = e['IsActive']
            ..lastUpdated = e['LastUpdated']
            ..isDirty = false
          ).toList();
          await isar.userList.putAll(user);

          setState(() { _debug = 'putAll User success'; });

          // Role
          final roleListRaw = responseData['RoleList'] as List<dynamic>? ?? [];
          final roles = roleListRaw.map((e) => Role()
            ..id = e['ID']
            ..thaiName = e['ThaiName']
            ..englishName = e['EnglishName']
            ..isActive = e['IsActive']
            ..lastUpdated = e['LastUpdated']
            ..isDirty = false
          ).toList();
          await isar.roleList.putAll(roles);

          setState(() { _debug = 'putAll Role success'; });

          // RoleTransactionPermission
          final roleTransactionPermissionListRaw = responseData['RoleTransactionPermissionList'] as List<dynamic>? ?? [];
          final roleTransactionPermissions = roleTransactionPermissionListRaw.map((e) => RoleTransactionPermission()
            ..id = e['ID']
            ..role_ID = e['role_ID']
            ..transaction_permission_ID = e['transaction_permission_ID']
            ..permissionLevel = e['PermissionLevel']
            ..partialPercent = e['PartialPercent']?.toString()
            ..partialAmount = e['PartialAmount']?.toString()
            ..lastUpdated = e['LastUpdated']
            ..isDirty = false
          ).toList();
          await isar.roleTransactionPermissionList.putAll(roleTransactionPermissions);

          setState(() { _debug = 'putAll RoleTransactionPermission success'; });

          // ShopCustomer
          final shopCustomerListRaw = responseData['ShopCustomerList'] as List<dynamic>? ?? [];
          final shopCustomer = shopCustomerListRaw.map((e) => ShopCustomer()
            ..id = e['ID']
            ..firstName = e['FirstName']
            ..lastName = e['LastName']
            ..loginType = e['LoginType']
            ..loginID = e['LoginID']
            ..email = e['Email']
            ..passwordHash = e['PasswordHash']
            ..language = e['Language']
            ..picture = e['Picture']
            ..telephone = e['Telephone']
            ..isActive = e['IsActive']
            ..lastUpdated = e['LastUpdated']
            ..isDirty = false
          ).toList();
          await isar.shopCustomerList.putAll(shopCustomer);

          setState(() { _debug = 'putAll ShopCustomer success'; });

          // ShopTable
          final shopTableListRaw = responseData['ShopTableList'] as List<dynamic>? ?? [];
          final shopTable = shopTableListRaw.map((e) => ShopTable()
            ..id = e['ID']
            ..code = e['Code']
            ..tableNumber = e['TableNumber']
            ..numberOfSeat = e['NumberOfSeat']
            ..status = e['Status']
            ..lastUpdated = e['LastUpdated']
            ..isDirty = false
          ).toList();
          await isar.shopTableList.putAll(shopTable);

          setState(() { _debug = 'putAll ShopTable success'; });

          // SettingValue
          final settingValueListRaw = responseData['SettingValueList'] as List<dynamic>? ?? [];
          final settingValue = settingValueListRaw.map((e) => SettingValue()
            ..id = e['ID']
            ..setting_ID = e['setting_ID']
            ..name = e['Name']
            ..value = e['Value']
            ..type = e['Type']
            ..list = e['List']
            ..lastUpdated = e['LastUpdated']
            ..isDirty = false
          ).toList();
          await isar.settingValueList.putAll(settingValue);

          setState(() { _debug = 'putAll SettingValue success'; });

          // DocumentCode
          final documentCodeListRaw = responseData['DocumentCodeList'] as List<dynamic>? ?? [];
          final documentCode = documentCodeListRaw.map((e) => DocumentCode()
            ..id = e['ID']
            ..seq = e['Seq']
            ..name = e['Name']
            ..value = e['Value']
            ..seperator = e['Seperator']
            ..isActive = e['IsActive']
            ..lastUpdated = e['LastUpdated']
            ..isDirty = false
          ).toList();
          await isar.documentCodeList.putAll(documentCode);

          setState(() { _debug = 'putAll DocumentCode success'; });

          // DocumentType
          final documentTypeListRaw = responseData['DocumentTypeList'] as List<dynamic>? ?? [];
          final documentType = documentTypeListRaw.map((e) => DocumentType()
            ..id = e['ID']
            ..printerModel = e['PrinterModel']
            ..lastUpdated = e['LastUpdated']
            ..isDirty = false
          ).toList();
          await isar.documentTypeList.putAll(documentType);

          setState(() { _debug = 'putAll DocumentType success'; });

          // DocumentTemplate
          final documentTemplateListRaw = responseData['DocumentTemplateList'] as List<dynamic>? ?? [];
          final documentTemplate = documentTemplateListRaw.map((e) => DocumentTemplate()
            ..id = e['ID']
            ..document_type_ID = e['document_type_ID']
            ..seq = e['Seq']
            ..printText = e['PrintText']
            ..alignment = e['Alignment']
            ..fontSize = e['FontSize']
            ..isActive = e['IsActive']
            ..lastUpdated = e['LastUpdated']
            ..isDirty = false
          ).toList();
          await isar.documentTemplateList.putAll(documentTemplate);

          setState(() { _debug = 'putAll DocumentTemplate success'; });

          // FoodCategory
          final foodCategoryListRaw = responseData['FoodCategoryList'] as List<dynamic>? ?? [];
          final foodCategory = foodCategoryListRaw.map((e) => FoodCategory()
            ..id = e['ID']
            ..parentType = e['ParentType']
            ..parentID = e['ParentID']
            ..seq = e['Seq']
            ..thaiName = e['ThaiName']
            ..englishName = e['EnglishName']
            ..isActive = e['IsActive']
            ..lastUpdated = e['LastUpdated']
            ..isDirty = false
          ).toList();
          await isar.foodCategoryList.putAll(foodCategory);

          setState(() { _debug = 'putAll FoodCategory success'; });

          // FoodSize
          final foodSizeListRaw = responseData['FoodSizeList'] as List<dynamic>? ?? [];
          final foodSize = foodSizeListRaw.map((e) => FoodSize()
            ..id = e['ID']
            ..parentType = e['ParentType']
            ..parentID = e['ParentID']
            ..seq = e['Seq']
            ..thaiName = e['ThaiName']
            ..englishName = e['EnglishName']
            ..kitchenName = e['KitchenName']
            ..isActive = e['IsActive']
            ..lastUpdated = e['LastUpdated']
            ..isDirty = false
          ).toList();
          await isar.foodSizeList.putAll(foodSize);

          setState(() { _debug = 'putAll FoodSize success'; });

          // FoodItem
          final foodItemListRaw = responseData['FoodItemList'] as List<dynamic>? ?? [];
          final appDocDir = await getApplicationDocumentsDirectory();
          
          List<FoodItem> foodItem = [];
          for (var e in foodItemListRaw) {
             final item = FoodItem()
               ..id = e['ID']
               ..food_category_ID = e['food_category_ID']
               ..seq = e['Seq']
               ..thaiName = e['ThaiName']
               ..englishName = e['EnglishName']
               ..kitchenName = e['KitchenName']
               ..price = (e['Price'] as num?)?.toDouble()
               ..currency_ID = e['currency_ID']
               ..picture = e['Picture']
               ..isRecommend = e['IsRecommend']
               ..isServeTable = e['IsServeTable']
               ..isTakeAway = e['IsTakeAway']
               ..isDelivery = e['IsDelivery']
               ..isActive = e['IsActive']
               ..lastUpdated = e['LastUpdated']
               ..isDirty = false;
               
             if (item.picture != null && item.picture!.isNotEmpty) {
                 final url = widget.config.apiUrl + item.picture!;
                 try {
                     final picResponse = await http.get(Uri.parse(url));
                     if (picResponse.statusCode == 200) {
                         final filename = item.picture!.split('/').last;
                         final localFile = File('${appDocDir.path}/$filename');
                         await localFile.writeAsBytes(picResponse.bodyBytes);
                         item.localPicture = localFile.path;
                     }
                 } catch (err) {
                     debugPrint("Error downloading picture for food item ${item.id}: $err");
                 }
             }
             foodItem.add(item);
          }
          await isar.foodItemList.putAll(foodItem);

          setState(() { _debug = 'putAll FoodItem success'; });

          // FoodItemSize
          final foodItemSizeListRaw = responseData['FoodItemSizeList'] as List<dynamic>? ?? [];
          final foodItemSize = foodItemSizeListRaw.map((e) => FoodItemSize()
            ..id = e['ID']
            ..food_item_ID = e['food_item_ID']
            ..food_size_ID = e['food_size_ID']
            ..price = (e['Price'] as num?)?.toDouble()
            ..isActive = e['IsActive']
            ..lastUpdated = e['LastUpdated']
            ..isDirty = false
          ).toList();
          await isar.foodItemSizeList.putAll(foodItemSize);

          setState(() { _debug = 'putAll FoodItemSize success'; });

          // FoodOption
          final foodOptionListRaw = responseData['FoodOptionList'] as List<dynamic>? ?? [];
          final foodOption = foodOptionListRaw.map((e) => FoodOption()
            ..id = e['ID']
            ..food_item_ID = e['food_item_ID']
            ..seq = e['Seq']
            ..thaiName = e['ThaiName']
            ..englishName = e['EnglishName']
            ..isActive = e['IsActive']
            ..lastUpdated = e['LastUpdated']
            ..isDirty = false
          ).toList();
          await isar.foodOptionList.putAll(foodOption);

          setState(() { _debug = 'putAll FoodOption success'; });

          // FoodChoice
          final foodChoiceListRaw = responseData['FoodChoiceList'] as List<dynamic>? ?? [];
          final foodChoice = foodChoiceListRaw.map((e) => FoodChoice()
            ..id = e['ID']
            ..parentType = e['ParentType']
            ..parentID = e['ParentID']
            ..seq = e['Seq']
            ..thaiName = e['ThaiName']
            ..englishName = e['EnglishName']
            ..kitchenName = e['KitchenName']
            ..price = (e['Price'] as num?)?.toDouble()
            ..currency_ID = e['currency_ID']
            ..picture = e['Picture']
            ..isServeTable = e['IsServeTable']
            ..isTakeAway = e['IsTakeAway']
            ..isDelivery = e['IsDelivery']
            ..isActive = e['IsActive']
            ..lastUpdated = e['LastUpdated']
            ..isDirty = false
          ).toList();
          await isar.foodChoiceList.putAll(foodChoice);

          setState(() { _debug = 'putAll FoodChoice success'; });

          // FoodChoiceSize
          final foodChoiceSizeListRaw = responseData['FoodChoiceSizeList'] as List<dynamic>? ?? [];
          final foodChoiceSize = foodChoiceSizeListRaw.map((e) => FoodChoiceSize()
            ..id = e['ID']
            ..food_choice_ID = e['food_choice_ID']
            ..food_size_ID = e['food_size_ID']
            ..price = (e['Price'] as num?)?.toDouble()
            ..isActive = e['IsActive']
            ..lastUpdated = e['LastUpdated']
            ..isDirty = false
          ).toList();
          await isar.foodChoiceSizeList.putAll(foodChoiceSize);

          setState(() { _debug = 'putAll FoodChoiceSize success'; });

          // Payment
          final paymentListRaw = responseData['PaymentList'] as List<dynamic>? ?? [];
          final payment = paymentListRaw.map((e) => Payment()
            ..id = e['ID']
            ..payment_channel_ID = e['payment_channel_ID']
            ..feePercent = (e['FeePercent'] as num?)?.toDouble()
            ..mode = e['Mode']
            ..isActive = e['IsActive']
            ..lastUpdated = e['LastUpdated']
            ..name = e['Name']
            ..isDirty = false
          ).toList();
          await isar.paymentList.putAll(payment);

          setState(() { _debug = 'putAll Payment success'; });

          // PaymentValue
          final paymentValueListRaw = responseData['PaymentValueList'] as List<dynamic>? ?? [];
          
          List<PaymentValue> paymentValue = [];
          for (var e in paymentValueListRaw) {
             final item = PaymentValue()
               ..id = e['ID']
               ..payment_ID = e['payment_ID']
               ..payment_parameter_ID = e['payment_parameter_ID']
               ..value = e['Value']
               ..lastUpdated = e['LastUpdated']
               ..name = e['Name']
               ..type = e['Type']
               ..isDirty = false;
               
             if (item.type == 'P' && item.value != null && item.value!.isNotEmpty) {
                 final url = widget.config.apiUrl + item.value!;
                 try {
                     final filename = item.value!.split('/').last;
                     final localFile = File('${appDocDir.path}/$filename');
                     
                     if (await localFile.exists()) {
                         await localFile.delete();
                     }

                     final picResponse = await http.get(Uri.parse(url));
                     if (picResponse.statusCode == 200) {
                         await localFile.writeAsBytes(picResponse.bodyBytes);
                         item.localPicture = localFile.path;
                     } else {
                         throw Exception('Failed to download payment image (Status: ${picResponse.statusCode})');
                     }
                 } catch (err) {
                     throw Exception('Error downloading payment image: $err');
                 }
             }
             paymentValue.add(item);
          }
          await isar.paymentValueList.putAll(paymentValue);

          setState(() { _debug = 'putAll PaymentValue success'; });

          // MerchandiseCategory
          final merchandiseCategoryListRaw = responseData['MerchandiseCategoryList'] as List<dynamic>? ?? [];
          final merchandiseCategory = merchandiseCategoryListRaw.map((e) => MerchandiseCategory()
            ..id = e['ID']
            ..parentType = e['ParentType']
            ..parentID = e['ParentID']
            ..categoryName = e['CategoryName']
            ..isActive = e['IsActive']
            ..lastUpdated = e['LastUpdated']
            ..isDirty = false
          ).toList();
          await isar.merchandiseCategoryList.putAll(merchandiseCategory);

          setState(() { _debug = 'putAll MerchandiseCategory success'; });

          // MerchandiseItem
          final merchandiseItemListRaw = responseData['MerchandiseItemList'] as List<dynamic>? ?? [];
          final merchandiseItem = merchandiseItemListRaw.map((e) => MerchandiseItem()
            ..id = e['ID']
            ..barcode = e['Barcode']
            ..merchandise_category_ID = e['merchandise_category_ID']
            ..productName = e['ProductName']
            ..price = double.tryParse(e['Price']?.toString() ?? '')
            ..unitName = e['UnitName']
            ..tax = e['Tax']
            ..isActive = e['IsActive']
            ..lastUpdated = e['LastUpdated']
            ..isDirty = false
          ).toList();
          await isar.merchandiseItemList.putAll(merchandiseItem);

          setState(() { _debug = 'putAll MerchandiseItem success'; });

          // MerchandisePack
          final merchandisePackListRaw = responseData['MerchandisePackList'] as List<dynamic>? ?? [];
          final merchandisePack = merchandisePackListRaw.map((e) => MerchandisePack()
            ..id = e['ID']
            ..barcode = e['Barcode']
            ..merchandise_item_ID = e['merchandise_item_ID']
            ..level = int.tryParse(e['Level']?.toString() ?? '')
            ..quantity = int.tryParse(e['Quantity']?.toString() ?? '')
            ..packName = e['PackName']
            ..price = double.tryParse(e['Price']?.toString() ?? '')
            ..isActive = e['IsActive']
            ..lastUpdated = e['LastUpdated']
            ..isDirty = false
          ).toList();
          await isar.merchandisePackList.putAll(merchandisePack);

          setState(() { _debug = 'putAll MerchandisePack success'; });
        });

        setState(() { _isLoading = false; });

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => SetPrinterScreen(config: updatedConfig),
          ),
        );

      } else {
        setState(() { 
          _isLoading = false;
          _error = 'API Error ${response.statusCode}: ${response.body}'; 
        });
      }
    } catch (e) {
      setState(() { 
        _isLoading = false;
        _error = 'Network/Connection Error: $e'; 
      });
    }    
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar( title: Text(widget.config.appTitle) ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Image.asset('assets/images/meorder-online-logo.png', height: 40, width: 40, ),
            const SizedBox(height: 10), 

            Text(_labels['PleaseEntryServiceCode']!, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 10),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40), 
              child: TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 50, letterSpacing: 5,),
                decoration: InputDecoration(
                  labelText: _labels['ServiceCodeLabel']!,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 10),

            ElevatedButton(
              onPressed: _isButtonEnabled && !_isLoading ? _submitCode : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue, 
                foregroundColor: Colors.white, 
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _isLoading 
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white))
                : Text(_labels['Submit']!),
            ),
            const SizedBox(height: 10),

            ElevatedButton(
              onPressed: _isLoading ? null : _toggleLanguage,
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(_labels['ChangeLangButton']!),
            ),
            const SizedBox(height: 10),

            if (_error.isNotEmpty) Text(_error, style: const TextStyle(fontSize: 12, color: Colors.red)),
            if (_debug.isNotEmpty) Text(_debug, style: const TextStyle(fontSize: 12, color: Colors.black)),
          ],
        ),
      ),
    );
  }
}

Map<String, String> getLabels(String langCode) {
  if (langCode == 'th') {
    return {
      'PleaseEntryServiceCode': 'กรุณาป้อนรหัสบริการ เป็นตัวเลข 6 หลัก',
      'Submit': 'ตกลง',
      'ChangeLangButton': 'Change to English',
      'ServiceCodeLabel': 'รหัสบริการ',
    };
  } else { 
    return {
      'PleaseEntryServiceCode': 'Please entry Service Code as 6-digit number',
      'Submit': 'Submit',
      'ChangeLangButton': 'เปลี่ยนเป็นภาษาไทย',
      'ServiceCodeLabel': 'Service Code',
    };
  }
}
