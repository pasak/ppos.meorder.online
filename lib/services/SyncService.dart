import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:meorder_ppos/lib/EnvConfig.dart';
import 'package:meorder_ppos/database/IsarModels.dart';

class SyncService {
  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static String? _parseString(dynamic value) {
    if (value == null) return null;
    return value.toString();
  }

  static Future<bool> syncMaster(EnvConfig config) async {
    debugPrint('syncMaster started');
    bool _isExpired = config.isExpired ?? false;

    if (_isExpired) {
      debugPrint('Sync error: Expired');
      return false;
    }

    final isar = Isar.getInstance()!;
    final lastSyncData = await isar.lastSyncList.where().findFirst();
    if (lastSyncData == null || lastSyncData.master == null) return false;

    final syncTime = lastSyncData.master!;

    final uri = Uri.parse('${config.apiUrl}api/pos/sync-master');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${config.apiToken}',
    };

    final body = jsonEncode({
      'shop_branch_service_ID': config.shop_branch_service_ID,
      'Language': config.language ?? 'th',
      'LastSync': syncTime
    });

    // debugPrint('syncMaster body: ' + body);

    try {
      final response = await http.post(uri, headers: headers, body: body);
      
      if (response.statusCode == 200) {
        final newSyncTime = DateTime.now().toIso8601String();
        final responseData = jsonDecode(response.body);

        final appDocDir = await getApplicationDocumentsDirectory();

        await isar.writeTxn(() async {
          // User
          if (responseData['UserList'] is List) {
            for (var e in responseData['UserList']) {
              final id = _parseInt(e['ID'] ?? e['id']);
              if (id != null) {
                var item = await isar.userList.where().filter().idEqualTo(id).findFirst() ?? User();
                item.id = id;
                item.name = e['Name'];
                item.userName = e['UserName'];
                item.passwordHash = e['PasswordHash'];
                item.role_ID = e['role_ID'];
                item.language = e['Language'];
                item.isActive = e['IsActive'];
                item.lastUpdated = e['LastUpdated'];
                item.isDirty = false;
                await isar.userList.put(item);
              }
            }
          }

          // Role
          if (responseData['RoleList'] is List) {
            for (var e in responseData['RoleList']) {
              final id = _parseString(e['ID']);
              if (id != null) {
                var item = await isar.roleList.where().filter().idEqualTo(id).findFirst() ?? Role();
                item.id = id;
                item.thaiName = e['ThaiName'];
                item.englishName = e['EnglishName'];
                item.isActive = e['IsActive'];
                item.lastUpdated = e['LastUpdated'];
                item.isDirty = false;
                await isar.roleList.put(item);
              }
            }
          }

          // RoleTransactionPermission
          if (responseData['RoleTransactionPermissionList'] is List) {
            for (var e in responseData['RoleTransactionPermissionList']) {
              final id = _parseString(e['ID']);
              if (id != null) {
                var item = await isar.roleTransactionPermissionList.where().filter().idEqualTo(id).findFirst() ?? RoleTransactionPermission();

                if (item != null) { debugPrint('update ' + e['transaction_permission_ID'] + ' = ' + e['PermissionLevel']);}

                item.id = id;
                item.role_ID = e['role_ID'];
                item.transaction_permission_ID = e['transaction_permission_ID'];
                item.permissionLevel = e['PermissionLevel'];
                item.partialPercent = e['PartialPercent']?.toString();
                item.partialAmount = e['PartialAmount']?.toString();
                item.lastUpdated = e['LastUpdated'];
                item.isDirty = false;
                await isar.roleTransactionPermissionList.put(item);
              }
            }
          }

          // ShopCustomer
          if (responseData['ShopCustomerList'] is List) {
            for (var e in responseData['ShopCustomerList']) {
              final id = _parseString(e['ID']);
              if (id != null) {
                var item = await isar.shopCustomerList.where().filter().idEqualTo(id).findFirst() ?? ShopCustomer();
                item.id = id;
                item.firstName = e['FirstName'];
                item.lastName = e['LastName'];
                item.loginType = e['LoginType'];
                item.loginID = e['LoginID'];
                item.email = e['Email'];
                item.passwordHash = e['PasswordHash'];
                item.language = e['Language'];
                item.picture = e['Picture'];
                item.telephone = e['Telephone'];
                item.isActive = e['IsActive'];
                item.lastUpdated = e['LastUpdated'];
                item.isDirty = false;
                await isar.shopCustomerList.put(item);
              }
            }
          }

          // ShopTable
          if (responseData['ShopTableList'] is List) {
            for (var e in responseData['ShopTableList']) {
              final id = _parseString(e['ID']);
              if (id != null) {
                var item = await isar.shopTableList.where().filter().idEqualTo(id).findFirst() ?? ShopTable();
                item.id = id;
                item.code = _parseInt(e['Code']);
                item.tableNumber = e['TableNumber'];
                item.numberOfSeat = _parseInt(e['NumberOfSeat']);
                item.status = e['Status'];
                item.lastUpdated = e['LastUpdated'];
                item.isDirty = false;
                await isar.shopTableList.put(item);
              }
            }
          }

          // SettingValue
          if (responseData['SettingValueList'] is List) {
            for (var e in responseData['SettingValueList']) {
              final id = _parseInt(e['ID']);
              if (id != null) {
                var item = await isar.settingValueList.where().filter().idEqualTo(id).findFirst() ?? SettingValue();
                item.id = id;
                item.setting_ID = e['setting_ID'];
                item.name = e['Name'];
                item.value = e['Value'];
                item.type = e['Type'];
                item.list = e['List'];
                item.lastUpdated = e['LastUpdated'];
                item.isDirty = false;
                await isar.settingValueList.put(item);
              }
            }
          }

          // DocumentCode
          if (responseData['DocumentCodeList'] is List) {
            for (var e in responseData['DocumentCodeList']) {
              final id = _parseInt(e['ID']);
              if (id != null) {
                var item = await isar.documentCodeList.where().filter().idEqualTo(id).findFirst() ?? DocumentCode();
                item.id = id;
                item.seq = _parseInt(e['Seq']);
                item.name = e['Name'];
                item.value = e['Value'];
                item.seperator = e['Seperator'];
                item.isActive = e['IsActive'];
                item.lastUpdated = e['LastUpdated'];
                item.isDirty = false;
                await isar.documentCodeList.put(item);
              }
            }
          }

          // DocumentType
          if (responseData['DocumentTypeList'] is List) {
            for (var e in responseData['DocumentTypeList']) {
              final id = _parseString(e['ID']);
              if (id != null) {
                var item = await isar.documentTypeList.where().filter().idEqualTo(id).findFirst() ?? DocumentType();
                item.id = id;
                item.printerModel = e['PrinterModel'];
                item.lastUpdated = e['LastUpdated'];
                item.isDirty = false;
                await isar.documentTypeList.put(item);
              }
            }
          }

          // DocumentTemplate
          if (responseData['DocumentTemplateList'] is List) {
            for (var e in responseData['DocumentTemplateList']) {
              final id = _parseInt(e['ID']);
              if (id != null) {
                var item = await isar.documentTemplateList.where().filter().idEqualTo(id).findFirst() ?? DocumentTemplate();
                item.id = id;
                item.document_type_ID = e['document_type_ID'];
                item.seq = _parseInt(e['Seq']);
                item.printText = e['PrintText'];
                item.alignment = e['Alignment'];
                item.fontSize = _parseInt(e['FontSize']);
                item.isActive = e['IsActive'];
                item.lastUpdated = e['LastUpdated'];
                item.isDirty = false;
                await isar.documentTemplateList.put(item);
              }
            }
          }

          // FoodCategory
          if (responseData['FoodCategoryList'] is List) {
            for (var e in responseData['FoodCategoryList']) {
              final id = _parseString(e['ID']);
              if (id != null) {
                var item = await isar.foodCategoryList.where().filter().idEqualTo(id).findFirst() ?? FoodCategory();
                item.id = id;
                item.parentType = e['ParentType'];
                item.parentID = e['ParentID'];
                item.seq = _parseInt(e['Seq']);
                item.thaiName = e['ThaiName'];
                item.englishName = e['EnglishName'];
                item.isActive = e['IsActive'];
                item.lastUpdated = e['LastUpdated'];
                item.isDirty = false;
                await isar.foodCategoryList.put(item);
              }
            }
          }

          // FoodSize
          if (responseData['FoodSizeList'] is List) {
            for (var e in responseData['FoodSizeList']) {
              final id = _parseString(e['ID']);
              if (id != null) {
                var item = await isar.foodSizeList.where().filter().idEqualTo(id).findFirst() ?? FoodSize();
                item.id = id;
                item.parentType = e['ParentType'];
                item.parentID = e['ParentID'];
                item.seq = _parseInt(e['Seq']);
                item.thaiName = e['ThaiName'];
                item.englishName = e['EnglishName'];
                item.kitchenName = e['KitchenName'];
                item.isActive = e['IsActive'];
                item.lastUpdated = e['LastUpdated'];
                item.isDirty = false;
                await isar.foodSizeList.put(item);
              }
            }
          }

          // FoodItem
          if (responseData['FoodItemList'] is List) {
            for (var e in responseData['FoodItemList']) {
              final id = _parseString(e['ID']);
              if (id != null) {
                var item = await isar.foodItemList.where().filter().idEqualTo(id).findFirst() ?? FoodItem();
                item.id = id;
                item.food_category_ID = e['food_category_ID'];
                item.seq = _parseInt(e['Seq']);
                item.thaiName = e['ThaiName'];
                item.englishName = e['EnglishName'];
                item.kitchenName = e['KitchenName'];
                item.price = _parseDouble(e['Price']);
                item.currency_ID = e['currency_ID'];
                item.picture = e['Picture'];
                item.isRecommend = e['IsRecommend'];
                item.isServeTable = e['IsServeTable'];
                item.isTakeAway = e['IsTakeAway'];
                item.isDelivery = e['IsDelivery'];
                item.isActive = e['IsActive'];
                item.lastUpdated = e['LastUpdated'];
                item.isDirty = false;

                if (item.picture != null && item.picture!.isNotEmpty) {
                  final url = config.apiUrl + item.picture!;
                  try {
                    final filename = item.picture!.split('/').last;
                    final localFile = File('${appDocDir.path}/$filename');
                    if (!await localFile.exists()) {
                      final picResponse = await http.get(Uri.parse(url));
                      if (picResponse.statusCode == 200) {
                        await localFile.writeAsBytes(picResponse.bodyBytes);
                        item.localPicture = localFile.path;
                      }
                    }
                  } catch (err) {
                    debugPrint("Error downloading picture for food item ${item.id}: $err");
                  }
                }
                
                await isar.foodItemList.put(item);
              }
            }
          }

          // FoodItemSize
          if (responseData['FoodItemSizeList'] is List) {
            for (var e in responseData['FoodItemSizeList']) {
              final id = _parseString(e['ID']);
              if (id != null) {
                var item = await isar.foodItemSizeList.where().filter().idEqualTo(id).findFirst() ?? FoodItemSize();
                item.id = id;
                item.food_item_ID = e['food_item_ID'];
                item.food_size_ID = e['food_size_ID'];
                item.price = _parseDouble(e['Price']);
                item.isActive = e['IsActive'];
                item.lastUpdated = e['LastUpdated'];
                item.isDirty = false;
                await isar.foodItemSizeList.put(item);
              }
            }
          }

          // FoodOption
          if (responseData['FoodOptionList'] is List) {
            for (var e in responseData['FoodOptionList']) {
              final id = _parseString(e['ID']);
              if (id != null) {
                var item = await isar.foodOptionList.where().filter().idEqualTo(id).findFirst() ?? FoodOption();
                item.id = id;
                item.food_item_ID = e['food_item_ID'];
                item.seq = _parseInt(e['Seq']);
                item.thaiName = e['ThaiName'];
                item.englishName = e['EnglishName'];
                item.isActive = e['IsActive'];
                item.lastUpdated = e['LastUpdated'];
                item.isDirty = false;
                await isar.foodOptionList.put(item);
              }
            }
          }

          // FoodChoice
          if (responseData['FoodChoiceList'] is List) {
            for (var e in responseData['FoodChoiceList']) {
              final id = _parseString(e['ID']);
              if (id != null) {
                var item = await isar.foodChoiceList.where().filter().idEqualTo(id).findFirst() ?? FoodChoice();
                item.id = id;
                item.parentType = e['ParentType'];
                item.parentID = e['ParentID'];
                item.seq = _parseInt(e['Seq']);
                item.thaiName = e['ThaiName'];
                item.englishName = e['EnglishName'];
                item.kitchenName = e['KitchenName'];
                item.price = _parseDouble(e['Price']);
                item.currency_ID = e['currency_ID'];
                item.picture = e['Picture'];
                item.isServeTable = e['IsServeTable'];
                item.isTakeAway = e['IsTakeAway'];
                item.isDelivery = e['IsDelivery'];
                item.isActive = e['IsActive'];
                item.lastUpdated = e['LastUpdated'];
                item.isDirty = false;
                await isar.foodChoiceList.put(item);
              }
            }
          }

          // FoodChoiceSize
          if (responseData['FoodChoiceSizeList'] is List) {
            for (var e in responseData['FoodChoiceSizeList']) {
              final id = _parseString(e['ID']);
              if (id != null) {
                var item = await isar.foodChoiceSizeList.where().filter().idEqualTo(id).findFirst() ?? FoodChoiceSize();
                item.id = id;
                item.food_choice_ID = e['food_choice_ID'];
                item.food_size_ID = e['food_size_ID'];
                item.price = _parseDouble(e['Price']);
                item.isActive = e['IsActive'];
                item.lastUpdated = e['LastUpdated'];
                item.isDirty = false;
                await isar.foodChoiceSizeList.put(item);
              }
            }
          }

          // Payment
          if (responseData['PaymentList'] is List) {
            for (var e in responseData['PaymentList']) {
              final id = _parseInt(e['ID']);
              if (id != null) {
                var item = await isar.paymentList.where().filter().idEqualTo(id).findFirst() ?? Payment();
                item.id = id;
                item.payment_channel_ID = e['payment_channel_ID'];
                item.feePercent = _parseDouble(e['FeePercent']);
                item.mode = e['Mode'];
                item.isActive = e['IsActive'];
                item.lastUpdated = e['LastUpdated'];
                item.name = e['Name'];
                item.isDirty = false;
                await isar.paymentList.put(item);
              }
            }
          }

          // PaymentValue
          if (responseData['PaymentValueList'] is List) {
            for (var e in responseData['PaymentValueList']) {
              final id = _parseInt(e['ID']);
              if (id != null) {
                var item = await isar.paymentValueList.where().filter().idEqualTo(id).findFirst() ?? PaymentValue();
                item.id = id;
                item.payment_ID = _parseInt(e['payment_ID']);
                item.payment_parameter_ID = e['payment_parameter_ID'];
                item.value = e['Value'];
                item.lastUpdated = e['LastUpdated'];
                item.name = e['Name'];
                item.type = e['Type'];
                item.isDirty = false;

                if (item.type == 'P' && item.value != null && item.value!.isNotEmpty) {
                  final url = config.apiUrl + item.value!;
                  try {
                    final filename = item.value!.split('/').last;
                    final localFile = File('${appDocDir.path}/$filename');
                    if (!await localFile.exists()) {
                      final picResponse = await http.get(Uri.parse(url));
                      if (picResponse.statusCode == 200) {
                        await localFile.writeAsBytes(picResponse.bodyBytes);
                        item.localPicture = localFile.path;
                      }
                    }
                  } catch (err) {
                    debugPrint("Error downloading payment image: $err");
                  }
                }
                
                await isar.paymentValueList.put(item);
              }
            }
          }

          // MerchandiseCategory
          if (responseData['MerchandiseCategoryList'] is List) {
            for (var e in responseData['MerchandiseCategoryList']) {
              final id = _parseString(e['ID']);
              if (id != null) {
                var item = await isar.merchandiseCategoryList.where().filter().idEqualTo(id).findFirst() ?? MerchandiseCategory();
                item.id = id;
                item.parentType = e['ParentType'];
                item.parentID = e['ParentID'];
                item.categoryName = e['CategoryName'];
                item.isActive = e['IsActive'];
                item.lastUpdated = e['LastUpdated'];
                item.isDirty = false;
                await isar.merchandiseCategoryList.put(item);
              }
            }
          }

          // MerchandiseItem
          if (responseData['MerchandiseItemList'] is List) {
            for (var e in responseData['MerchandiseItemList']) {
              final id = _parseString(e['ID']);
              if (id != null) {
                var item = await isar.merchandiseItemList.where().filter().idEqualTo(id).findFirst() ?? MerchandiseItem();
                item.id = id;
                item.barcode = e['Barcode'];
                item.sku = e['SKU'];
                item.merchandise_category_ID = e['merchandise_category_ID'];
                item.productName = e['ProductName'];
                item.price = _parseDouble(e['Price']);
                item.unitName = e['UnitName'];
                item.tax = e['Tax'];
                item.isActive = e['IsActive'];
                item.lastUpdated = e['LastUpdated'];
                item.isDirty = false;
                await isar.merchandiseItemList.put(item);
              }
            }
          }

          // MerchandisePack
          if (responseData['MerchandisePackList'] is List) {
            for (var e in responseData['MerchandisePackList']) {
              final id = _parseString(e['ID']);
              if (id != null) {
                var item = await isar.merchandisePackList.where().filter().idEqualTo(id).findFirst() ?? MerchandisePack();
                item.id = id;
                item.barcode = e['Barcode'];
                item.sku = e['SKU'];
                item.merchandise_item_ID = e['merchandise_item_ID'];
                item.level = _parseInt(e['Level']);
                item.quantity = _parseInt(e['Quantity']);
                item.packName = e['PackName'];
                item.price = _parseDouble(e['Price']);
                item.isActive = e['IsActive'];
                item.lastUpdated = e['LastUpdated'];
                item.isDirty = false;
                await isar.merchandisePackList.put(item);
              }
            }
          }

          // Supplier
          if (responseData['SupplierList'] is List) {
            for (var e in responseData['SupplierList']) {
              final id = _parseString(e['ID']);
              if (id != null) {
                var item = await isar.supplierList.where().filter().idEqualTo(id).findFirst() ?? Supplier();
                item.id = id;
                item.shop_ID = e['shop_ID'];
                item.thaiName = e['ThaiName'];
                item.englishName = e['EnglishName'];
                item.thaiAddress = e['ThaiAddress'];
                item.englishAddress = e['EnglishAddress'];
                item.sub_district_ID = e['sub_district_ID'];
                item.contactInformation = e['ContactInformation'];
                item.pictureFileName = e['PictureFileName'];
                item.telephone = e['Telephone'];
                item.email = e['Email'];
                item.taxID = e['TaxID'];
                item.language = e['Language'];
                item.isActive = e['IsActive'];
                item.lastUpdated = e['LastUpdated'];
                item.isDirty = false;
                await isar.supplierList.put(item);
              }
            }
          }

          lastSyncData.master = newSyncTime;
          await isar.lastSyncList.put(lastSyncData);
        });

        debugPrint('syncMaster finished successfully');
        return true;
      } else {
        debugPrint('syncMaster API Error ${response.statusCode}: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('syncMaster Network/Connection Error: $e');
      return false;
    }
  }

  static Future<bool> syncReceipt(EnvConfig config) async {
    debugPrint('syncReceipt started');
    bool _isExpired = config.isExpired ?? false;

    if (_isExpired) {
      debugPrint('Sync error: Expired');
      return false;
    }

    final isar = Isar.getInstance()!;
    final lastSync = await isar.lastSyncList.where().findFirst();
    if (lastSync == null || lastSync.receipt == null) return false;

    final syncTime = lastSync.receipt!;

    final receipts = await isar.receiptList
        .where()
        .filter()
        .isDirtyEqualTo(true)
        .findAll();
    final foodOrders = await isar.foodOrderList
        .where()
        .filter()
        .isDirtyEqualTo(true)
        .findAll();
    final foodOrderItems = await isar.foodOrderItemList
        .where()
        .filter()
        .isDirtyEqualTo(true)
        .findAll();
    final receiptItems = await isar.receiptItemList
        .where()
        .filter()
        .isDirtyEqualTo(true)
        .findAll();
    final merchandiseStocks = await isar.merchandiseStockList
        .where()
        .filter()
        .isDirtyEqualTo(true)
        .findAll();
    final transferStocks = await isar.transferStockList
        .where()
        .filter()
        .isDirtyEqualTo(true)
        .findAll();
    final receiptItemStocks = await isar.receiptItemStockList
        .where()
        .filter()
        .isDirtyEqualTo(true)
        .findAll();

    // Still proceed to call API even if dirty items are empty to get pullData
    // Wait, the original code had: if (receipts.isEmpty && foodOrders.isEmpty && foodOrderItems.isEmpty) return;
    // But if we want to pull data, maybe we should still call it?
    // Let's keep the return if empty for push, but the user says "when got response as pullData". 
    // Usually sync APIs are called periodically or triggered, and if there's nothing to push, it might still pull?
    // Let's remove the early return so it always pulls, or we can leave it. The original code had:
    // if (receipts.isEmpty && foodOrders.isEmpty && foodOrderItems.isEmpty) return;
    // Actually, I'll remove the early return so we can pull new data even if we don't have changes.
    // Let's send empty arrays if no dirty items.

    Map<String, dynamic> capitalizeKeys(Map<String, dynamic> json) {
      final Map<String, dynamic> result = {};
      json.forEach((key, value) {
        if (key == 'isarId' || key == 'isDirty') return;

        String newKey = key;
        if (!key.endsWith('_ID')) {
          if (key.isNotEmpty) {
            newKey = key[0].toUpperCase() + key.substring(1);
          }
        }

        if (key == 'id') newKey = 'ID';

        result[newKey] = value;
      });
      return result;
    }

    final pushData = {
      'ReceiptList': receipts.map((e) {
        final json = {
          'id': e.id,
          'pos_ID': e.pos_ID,
          'shop_user_ID': e.shop_user_ID,
          'shop_customer_ID': e.shop_customer_ID,
          'code': e.code,
          'createdAt': e.createdAt?.toIso8601String(),
          'sumAmount': e.sumAmount,
          'serviceChargeAmount': e.serviceChargeAmount,
          'discountAmount': e.discountAmount,
          'vatAmount': e.vatAmount,
          'totalAmount': e.totalAmount,
          'paidAmount': e.paidAmount,
          'status': e.status,
          'paymentType': e.paymentType,
          'slipFileName': e.slipFileName,
          'lastUpdated': e.lastUpdated,
        };
        return capitalizeKeys(json);
      }).toList(),
      'FoodOrderList': foodOrders.map((e) {
        final json = {
          'id': e.id,
          'parentType': e.parentType,
          'parentID': e.parentID,
          'number': e.number,
          'kitchen_ID': e.kitchen_ID,
          'createdAt': e.createdAt,
          'serveType': e.serveType,
          'orderAmount': e.orderAmount,
          'status': e.status,
          'lastUpdated': e.lastUpdated,
        };
        return capitalizeKeys(json);
      }).toList(),
      'FoodOrderItemList': foodOrderItems.map((e) {
        final json = {
          'id': e.id,
          'food_order_ID': e.food_order_ID,
          'food_item_ID': e.food_item_ID,
          'food_size_ID': e.food_size_ID,
          'itemPrice': e.itemPrice,
          'quantity': e.quantity,
          'choiceIDList': e.choiceIDList,
          'description': e.description,
          'lastUpdated': e.lastUpdated,
        };
        return capitalizeKeys(json);
      }).toList(),
      'ReceiptItemList': receiptItems.map((e) {
        final json = {
          'id': e.id,
          'receipt_ID': e.receipt_ID,
          'merchandise_item_ID': e.merchandise_item_ID,
          'merchandise_pack_ID': e.merchandise_pack_ID,
          'itemPrice': e.itemPrice,
          'unitCost': e.unitCost,
          'quantity': e.quantity,
          'discountPercent': e.discountPercent,
          'discountAmount': e.discountAmount,
          'lastUpdated': e.lastUpdated,
        };
        return capitalizeKeys(json);
      }).toList(),
      'MerchandiseStockList': merchandiseStocks.map((e) {
        final json = {
          'id': e.id,
          'storeType': e.storeType,
          'storeID': e.storeID,
          'stockType': e.stockType,
          'stockID': e.stockID,
          'currentQuantity': e.currentQuantity,
          'availableQuantity': e.availableQuantity,
          'unitCost': e.unitCost,
          'lastUpdated': e.lastUpdated,
        };
        return capitalizeKeys(json);
      }).toList(),
      'TransferStockList': transferStocks.map((e) {
        final json = {
          'id': e.id,
          'byType': e.byType,
          'byID': e.byID,
          'transferType': e.transferType,
          'from_merchandise_stock_ID': e.from_merchandise_stock_ID,
          'fromQuantity': e.fromQuantity,
          'to_merchandise_stock_ID': e.to_merchandise_stock_ID,
          'toQuantity': e.toQuantity,
          'lastUpdated': e.lastUpdated,
        };
        return capitalizeKeys(json);
      }).toList(),
      'ReceiptItemStockList': receiptItemStocks.map((e) {
        final json = {
          'id': e.id,
          'receipt_item_ID': e.receipt_item_ID,
          'merchandise_stock_ID': e.merchandise_stock_ID,
          'quantity': e.quantity,
        };
        return capitalizeKeys(json);
      }).toList(),
    };

    final uri = Uri.parse('${config.apiUrl}api/pos/sync-receipt');
    var request = http.MultipartRequest('POST', uri);
    request.headers.addAll({
      'Authorization': 'Bearer ${config.apiToken}',
    });

    request.fields['pos_ID'] = config.PosID.toString();
    request.fields['LastSync'] = syncTime;
    request.fields['ReceiptList'] = jsonEncode(pushData['ReceiptList']);
    request.fields['ReceiptItemList'] = jsonEncode(pushData['ReceiptItemList']);
    request.fields['FoodOrderList'] = jsonEncode(pushData['FoodOrderList']);
    request.fields['FoodOrderItemList'] = jsonEncode(pushData['FoodOrderItemList']);
    request.fields['MerchandiseStockList'] = jsonEncode(pushData['MerchandiseStockList']);
    request.fields['TransferStockList'] = jsonEncode(pushData['TransferStockList']);
    request.fields['ReceiptItemStockList'] = jsonEncode(pushData['ReceiptItemStockList']);

    final docDir = await getApplicationDocumentsDirectory();
    for (var r in receipts) {
      if (r.slipFileName != null && r.slipFileName!.isNotEmpty) {
        final filePath = '${docDir.path}/${r.slipFileName}';
        if (await File(filePath).exists()) {
          request.files.add(
            await http.MultipartFile.fromPath('SlipFile[]', filePath),
          );
        }
      }
    }

    debugPrint('syncReceipt request.fields: MerchandiseStockList ${request.fields['MerchandiseStockList']}  TransferStockList: ${request.fields['TransferStockList']}');

    try {
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('syncReceipt Sync response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final newSyncTime = DateTime.now().toIso8601String();
        
        // Parse response body for pullData
        Map<String, dynamic>? responseData;
        try {
          responseData = jsonDecode(response.body);
        } catch (e) {
          debugPrint('Error decoding JSON: $e');
        }

        await isar.writeTxn(() async {
          // Clear dirty flags for pushed items
          for (var r in receipts) {
            r.isDirty = false;
            await isar.receiptList.put(r);
          }
          for (var o in foodOrders) {
            o.isDirty = false;
            await isar.foodOrderList.put(o);
          }
          for (var i in foodOrderItems) {
            i.isDirty = false;
            await isar.foodOrderItemList.put(i);
          }
          for (var ms in merchandiseStocks) {
            ms.isDirty = false;
            await isar.merchandiseStockList.put(ms);
          }
          for (var ts in transferStocks) {
            ts.isDirty = false;
            await isar.transferStockList.put(ts);
          }
          for (var ris in receiptItemStocks) {
            ris.isDirty = false;
            await isar.receiptItemStockList.put(ris);
          }
          
          lastSync.receipt = newSyncTime;
          await isar.lastSyncList.put(lastSync);
          
          final now = DateTime.now();
          final formattedTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
          debugPrint('Last sync time $formattedTime');

          // Process pullData if available
          if (responseData != null) {
            // 1. Process ReceiptList
            if (responseData['ReceiptList'] is List) {
              for (var item in responseData['ReceiptList']) {
                final String? id = _parseString(item['ID'] ?? item['id']);
                if (id != null) {
                  var receipt = await isar.receiptList.where().filter().idEqualTo(id).findFirst() ?? Receipt();
                  receipt.id = id;
                  receipt.pos_ID = _parseInt(item['Pos_ID'] ?? item['pos_ID']);
                  receipt.shop_user_ID = _parseInt(item['Shop_user_ID'] ?? item['shop_user_ID']);
                  receipt.shop_customer_ID = _parseString(item['Shop_customer_ID'] ?? item['shop_customer_ID']);
                  receipt.code = _parseString(item['Code'] ?? item['code']);
                  receipt.createdAt = _parseDateTime(item['CreatedAt'] ?? item['createdAt']);
                  receipt.sumAmount = _parseDouble(item['SumAmount'] ?? item['sumAmount']);
                  receipt.serviceChargeAmount = _parseDouble(item['ServiceChargeAmount'] ?? item['serviceChargeAmount']);
                  receipt.discountAmount = _parseDouble(item['DiscountAmount'] ?? item['discountAmount']);
                  receipt.vatAmount = _parseDouble(item['VatAmount'] ?? item['vatAmount']);
                  receipt.totalAmount = _parseDouble(item['TotalAmount'] ?? item['totalAmount']);
                  receipt.paidAmount = _parseDouble(item['PaidAmount'] ?? item['paidAmount']);
                  receipt.status = _parseString(item['Status'] ?? item['status']);
                  receipt.paymentType = _parseString(item['PaymentType'] ?? item['paymentType']);
                  receipt.slipFileName = _parseString(item['SlipFileName'] ?? item['slipFileName']);
                  receipt.lastUpdated = _parseString(item['LastUpdated'] ?? item['lastUpdated']);
                  receipt.isDirty = false;
                  
                  await isar.receiptList.put(receipt);
                }
              }
            }

            if (responseData['PaymentTransactionList'] is List) {
              for (var item in responseData['PaymentTransactionList']) {
                final int? id = _parseInt(item['ID'] ?? item['id']);
                if (id != null) {
                  var pt = await isar.paymentTransactionList.where().filter().idEqualTo(id).findFirst() ?? PaymentTransaction();
                  pt.id = id;
                  pt.receipt_ID = _parseString(item['Receipt_ID'] ?? item['receipt_ID']);
                  pt.reponseCode = _parseString(item['ReponseCode'] ?? item['reponseCode']);
                  pt.slipFileName = _parseString(item['SlipFileName'] ?? item['slipFileName']);
                  pt.verifyReason = _parseString(item['VerifyReason'] ?? item['verifyReason']);
                  pt.lastUpdated = _parseString(item['LastUpdated'] ?? item['lastUpdated']);
                  pt.isDirty = false;
                  
                  await isar.paymentTransactionList.put(pt);
                }
              }
            }

            // 2. Process FoodOrderList
            if (responseData['FoodOrderList'] is List) {
              for (var item in responseData['FoodOrderList']) {
                final String? id = _parseString(item['ID'] ?? item['id']);
                if (id != null) {
                  var order = await isar.foodOrderList.where().filter().idEqualTo(id).findFirst() ?? FoodOrder();
                  order.id = id;
                  order.parentType = _parseString(item['ParentType'] ?? item['parentType']);
                  order.parentID = _parseString(item['ParentID'] ?? item['parentID']);
                  order.number = _parseInt(item['Number'] ?? item['number']);
                  order.kitchen_ID = _parseInt(item['Kitchen_ID'] ?? item['kitchen_ID']);
                  order.createdAt = _parseString(item['CreatedAt'] ?? item['createdAt']);
                  order.serveType = _parseString(item['ServeType'] ?? item['serveType']);
                  order.orderAmount = _parseDouble(item['OrderAmount'] ?? item['orderAmount']);
                  order.status = _parseString(item['Status'] ?? item['status']);
                  order.lastUpdated = _parseString(item['LastUpdated'] ?? item['lastUpdated']);
                  order.isDirty = false;

                  await isar.foodOrderList.put(order);
                }
              }
            }

            // 3. Process FoodOrderItemList
            if (responseData['FoodOrderItemList'] is List) {
              for (var item in responseData['FoodOrderItemList']) {
                final String? id = _parseString(item['ID'] ?? item['id']);
                if (id != null) {
                  var orderItem = await isar.foodOrderItemList.where().filter().idEqualTo(id).findFirst() ?? FoodOrderItem();
                  orderItem.id = id;
                  orderItem.food_order_ID = _parseString(item['Food_order_ID'] ?? item['food_order_ID']);
                  orderItem.food_item_ID = _parseString(item['Food_item_ID'] ?? item['food_item_ID']);
                  orderItem.food_size_ID = _parseString(item['Food_size_ID'] ?? item['food_size_ID']);
                  orderItem.itemPrice = _parseDouble(item['ItemPrice'] ?? item['itemPrice']);
                  orderItem.quantity = _parseInt(item['Quantity'] ?? item['quantity']);
                  orderItem.choiceIDList = _parseString(item['ChoiceIDList'] ?? item['choiceIDList']);
                  orderItem.description = _parseString(item['Description'] ?? item['description']);
                  orderItem.lastUpdated = _parseString(item['LastUpdated'] ?? item['lastUpdated']);
                  orderItem.isDirty = false;

                  await isar.foodOrderItemList.put(orderItem);
                }
              }
          }

          // 4. Process MerchandiseStockList
          if (responseData['MerchandiseStockList'] is List) {
            for (var item in responseData['MerchandiseStockList']) {
              final String? id = _parseString(item['ID'] ?? item['id']);
              if (id != null) {
                var stock = await isar.merchandiseStockList.where().filter().idEqualTo(id).findFirst() ?? MerchandiseStock();
                stock.id = id;
                stock.storeType = _parseString(item['StoreType'] ?? item['storeType']);
                stock.storeID = _parseInt(item['StoreID'] ?? item['storeID']);
                stock.stockType = _parseString(item['StockType'] ?? item['stockType']);
                stock.stockID = _parseString(item['StockID'] ?? item['stockID']);
                stock.currentQuantity = _parseDouble(item['CurrentQuantity'] ?? item['currentQuantity']);
                stock.availableQuantity = _parseDouble(item['AvailableQuantity'] ?? item['availableQuantity']);
                stock.lastUpdated = _parseString(item['LastUpdated'] ?? item['lastUpdated']);
                stock.isDirty = false;

                await isar.merchandiseStockList.put(stock);
              }
            }
          }

          // 5. Process TransferStockList
          if (responseData['TransferStockList'] is List) {
            for (var item in responseData['TransferStockList']) {
              final String? id = _parseString(item['ID'] ?? item['id']);
              if (id != null) {
                var transfer = await isar.transferStockList.where().filter().idEqualTo(id).findFirst() ?? TransferStock();
                transfer.id = id;
                transfer.byType = _parseString(item['ByType'] ?? item['byType']);
                transfer.byID = _parseString(item['ByID'] ?? item['byID']);
                transfer.transferType = _parseString(item['TransferType'] ?? item['transferType']);
                transfer.from_merchandise_stock_ID = _parseString(item['From_merchandise_stock_ID'] ?? item['from_merchandise_stock_ID']);
                transfer.fromQuantity = _parseDouble(item['FromQuantity'] ?? item['fromQuantity']);
                transfer.to_merchandise_stock_ID = _parseString(item['To_merchandise_stock_ID'] ?? item['to_merchandise_stock_ID']);
                transfer.toQuantity = _parseDouble(item['ToQuantity'] ?? item['toQuantity']);
                transfer.lastUpdated = _parseString(item['LastUpdated'] ?? item['lastUpdated']);
                transfer.isDirty = false;

                await isar.transferStockList.put(transfer);
              }
            }
          }
          
          // 6. Process ReceiptItemStockList
          if (responseData['ReceiptItemStockList'] is List) {
            for (var item in responseData['ReceiptItemStockList']) {
              final String? id = _parseString(item['ID'] ?? item['id']);
              if (id != null) {
                var stock = await isar.receiptItemStockList.where().filter().idEqualTo(id).findFirst() ?? ReceiptItemStock();
                stock.id = id;
                stock.receipt_item_ID = _parseString(item['Receipt_item_ID'] ?? item['receipt_item_ID']);
                stock.merchandise_stock_ID = _parseString(item['Merchandise_stock_ID'] ?? item['merchandise_stock_ID']);
                stock.quantity = _parseDouble(item['Quantity'] ?? item['quantity']);
                stock.isDirty = false;

                await isar.receiptItemStockList.put(stock);
              }
            }
          }
          }
        });
        return true;
      } else {
        debugPrint('Sync failed: ${response.statusCode} ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Sync error: $e');
      return false;
    }
  }
  
  static Future<bool> syncPurchaseOrder(EnvConfig config) async {
    debugPrint('syncPurchaseOrder started');
    bool _isExpired = config.isExpired ?? false;

    if (_isExpired) {
      debugPrint('Sync error: Expired');
      return false;
    }

    final isar = Isar.getInstance()!;
    final lastSync = await isar.lastSyncList.where().findFirst();
    if (lastSync == null) return false;
    
    final syncTime = lastSync.purchaseOrder ?? lastSync.master ?? '2000-01-01T00:00:00Z';

    final receiptItemStocks = await isar.receiptItemStockList
        .where()
        .filter()
        .isDirtyEqualTo(true)
        .findAll();
    final merchandiseStocks = await isar.merchandiseStockList
        .where()
        .filter()
        .isDirtyEqualTo(true)
        .findAll();
    final transferStocks = await isar.transferStockList
        .where()
        .filter()
        .isDirtyEqualTo(true)
        .findAll();
    final purchaseOrders = await isar.purchaseOrderList
        .where()
        .filter()
        .isDirtyEqualTo(true)
        .findAll();
    final purchaseOrderLogs = await isar.purchaseOrderLogList
        .where()
        .filter()
        .isDirtyEqualTo(true)
        .findAll();
    final purchaseOrderItems = await isar.purchaseOrderItemList
        .where()
        .filter()
        .isDirtyEqualTo(true)
        .findAll();
    final suppliers = await isar.supplierList
        .where()
        .filter()
        .isDirtyEqualTo(true)
        .findAll();

  
    Map<String, dynamic> capitalizeKeys(Map<String, dynamic> json) {
      final Map<String, dynamic> result = {};
      json.forEach((key, value) {
        if (key == 'isarId' || key == 'isDirty') return;

        String newKey = key;
        if (!key.endsWith('_ID')) {
          if (key.isNotEmpty) {
            newKey = key[0].toUpperCase() + key.substring(1);
          }
        }

        if (key == 'id') newKey = 'ID';

        result[newKey] = value;
      });
      return result;
    }

    Map<String, dynamic> pushData = {
      'ReceiptItemStockList': receiptItemStocks.map((e) {
        final json = {
          'id': e.id,
          'receipt_item_ID': e.receipt_item_ID,
          'merchandise_stock_ID': e.merchandise_stock_ID,
          'quantity': e.quantity,
          'lastUpdated': e.lastUpdated,
        };
        return capitalizeKeys(json);
      }).toList(),
      'MerchandiseStockList': merchandiseStocks.map((e) {
        final json = {
          'id': e.id,
          'storeType': e.storeType,
          'storeID': e.storeID,
          'stockType': e.stockType,
          'stockID': e.stockID,
          'currentQuantity': e.currentQuantity,
          'availableQuantity': e.availableQuantity,
          'unitCost': e.unitCost,
          'createdAt': e.createdAt,
          'lastUpdated': e.lastUpdated,
        };
        return capitalizeKeys(json);
      }).toList(),
      'TransferStockList': transferStocks.map((e) {
        final json = {
          'id': e.id,
          'byType': e.byType,
          'byID': e.byID,
          'transferType': e.transferType,
          'from_merchandise_stock_ID': e.from_merchandise_stock_ID,
          'fromQuantity': e.fromQuantity,
          'to_merchandise_stock_ID': e.to_merchandise_stock_ID,
          'toQuantity': e.toQuantity,
          'lastUpdated': e.lastUpdated,
        };
        return capitalizeKeys(json);
      }).toList(),
      'PurchaseOrderList': purchaseOrders.map((e) {
        final json = {
          'id': e.id,
          'code': e.code,
          'storeType': e.storeType,
          'storeID': e.storeID,
          'supplier_ID': e.supplier_ID,
          'supplierDocumentNumber': e.supplierDocumentNumber,
          'vatType': e.vatType,
          'sumAmount': e.sumAmount,
          'vatAmount': e.vatAmount,
          'totalAmount': e.totalAmount,
          'paidAmount': e.paidAmount,
          'status': e.status,
          'paymentType': e.paymentType,
          'lastUpdated': e.lastUpdated,
        };
        return capitalizeKeys(json);
      }).toList(),
      'PurchaseOrderLogList': purchaseOrderLogs.map((e) {
        final json = {
          'id': e.id,
          'purchase_order_ID': e.purchase_order_ID,
          'status': e.status,
          'remark': e.remark,
          'shop_user_ID': e.shop_user_ID,
          'lastUpdated': e.lastUpdated,
        };
        return capitalizeKeys(json);
      }).toList(),
      'PurchaseOrderItemList': purchaseOrderItems.map((e) {
        final json = {
          'id': e.id,
          'purchase_order_ID': e.purchase_order_ID,
          'seq': e.seq,
          'stockType': e.stockType,
          'stockID': e.stockID,
          'orderQuantity': e.orderQuantity,
          'unitPrice': e.unitPrice,
          'itemAmount': e.itemAmount,
          'receivedQuantity': e.receivedQuantity,
          'unitCost': e.unitCost,
          'status': e.status,
          'lastUpdated': e.lastUpdated,
        };
        return capitalizeKeys(json);
      }).toList(),
      'SupplierList': suppliers.map((e) {
        final json = {
          'id': e.id,
          'shop_ID': e.shop_ID,
          'thaiName': e.thaiName,
          'englishName': e.englishName,
          'thaiAddress': e.thaiAddress,
          'englishAddress': e.englishAddress,
          'sub_district_ID': e.sub_district_ID,
          'contactInformation': e.contactInformation,
          'pictureFileName': e.pictureFileName,
          'telephone': e.telephone,
          'email': e.email,
          'taxID': e.taxID,
          'language': e.language,
          'isActive': e.isActive,
          'lastUpdated': e.lastUpdated,
        };
        return capitalizeKeys(json);
      }).toList(),
    };

    final uri = Uri.parse('${config.apiUrl}api/pos/sync-purchase-order');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${config.apiToken}',
    };

    pushData['shop_branch_ID'] = config.shop_branch_ID;
    pushData['LastSync'] = syncTime;
    
    final body = jsonEncode(pushData);

    debugPrint('syncPurchaseOrder Sync pushData.shop_branch_ID: ${pushData['shop_branch_ID']} LastSync: ${pushData['LastSync']}');
    debugPrint('syncPurchaseOrder Sync pushData.ReceiptItemStockList: ${pushData['ReceiptItemStockList']}');
    debugPrint('syncPurchaseOrder Sync pushData.MerchandiseStockList: ${pushData['MerchandiseStockList']}');
    debugPrint('syncPurchaseOrder Sync pushData.TransferStockList: ${pushData['TransferStockList']}');
    debugPrint('syncPurchaseOrder Sync pushData.PurchaseOrderList: ${pushData['PurchaseOrderList']}');
    debugPrint('syncPurchaseOrder Sync pushData.PurchaseOrderLogList: ${pushData['PurchaseOrderLogList']}');
    debugPrint('syncPurchaseOrder Sync pushData.PurchaseOrderItemList: ${pushData['PurchaseOrderItemList']}');
    debugPrint('syncPurchaseOrder Sync pushData.SupplierList: ${pushData['SupplierList']}');

    try {
      final response = await http.post(uri, headers: headers, body: body);

      debugPrint('syncPurchaseOrder Sync response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final newSyncTime = DateTime.now().toIso8601String();
        
        Map<String, dynamic>? responseData;
        try {
          responseData = jsonDecode(response.body);
        } catch (e) {
          debugPrint('Error decoding JSON: $e');
        }

        await isar.writeTxn(() async {
          // Clear dirty flags
          for (var ris in receiptItemStocks) {
            ris.isDirty = false;
            await isar.receiptItemStockList.put(ris);
          }
          for (var ms in merchandiseStocks) {
            ms.isDirty = false;
            await isar.merchandiseStockList.put(ms);
          }
          for (var ts in transferStocks) {
            ts.isDirty = false;
            await isar.transferStockList.put(ts);
          }
          for (var po in purchaseOrders) {
            po.isDirty = false;
            await isar.purchaseOrderList.put(po);
          }
          for (var pol in purchaseOrderLogs) {
            pol.isDirty = false;
            await isar.purchaseOrderLogList.put(pol);
          }
          for (var poi in purchaseOrderItems) {
            poi.isDirty = false;
            await isar.purchaseOrderItemList.put(poi);
          }
          for (var s in suppliers) {
            s.isDirty = false;
            await isar.supplierList.put(s);
          }
          
          lastSync.purchaseOrder = newSyncTime;
          await isar.lastSyncList.put(lastSync);

          if (responseData != null) {
            // ReceiptItemStockList
            if (responseData['ReceiptItemStockList'] is List) {
              for (var item in responseData['ReceiptItemStockList']) {
                final String? id = _parseString(item['ID'] ?? item['id']);
                if (id != null) {
                  var stock = await isar.receiptItemStockList.where().filter().idEqualTo(id).findFirst() ?? ReceiptItemStock();
                  stock.id = id;
                  stock.receipt_item_ID = _parseString(item['Receipt_item_ID'] ?? item['receipt_item_ID']);
                  stock.merchandise_stock_ID = _parseString(item['Merchandise_stock_ID'] ?? item['merchandise_stock_ID']);
                  stock.quantity = _parseDouble(item['Quantity'] ?? item['quantity']);
                  stock.lastUpdated = _parseString(item['LastUpdated'] ?? item['lastUpdated']);
                  stock.isDirty = false;
                  await isar.receiptItemStockList.put(stock);
                }
              }
            }

            // MerchandiseStockList
            if (responseData['MerchandiseStockList'] is List) {
              for (var item in responseData['MerchandiseStockList']) {
                final String? id = _parseString(item['ID'] ?? item['id']);
                if (id != null) {
                  var stock = await isar.merchandiseStockList.where().filter().idEqualTo(id).findFirst() ?? MerchandiseStock();
                  stock.id = id;
                  stock.storeType = _parseString(item['StoreType'] ?? item['storeType']);
                  stock.storeID = _parseInt(item['StoreID'] ?? item['storeID']);
                  stock.stockType = _parseString(item['StockType'] ?? item['stockType']);
                  stock.stockID = _parseString(item['StockID'] ?? item['stockID']);
                  stock.currentQuantity = _parseDouble(item['CurrentQuantity'] ?? item['currentQuantity']);
                  stock.availableQuantity = _parseDouble(item['AvailableQuantity'] ?? item['availableQuantity']);
                  stock.unitCost = _parseDouble(item['UnitCost'] ?? item['unitCost']);
                  stock.createdAt = _parseString(item['CreatedAt'] ?? item['createdAt']);
                  stock.lastUpdated = _parseString(item['LastUpdated'] ?? item['lastUpdated']);
                  stock.isDirty = false;
                  await isar.merchandiseStockList.put(stock);
                }
              }
            }

            // TransferStockList
            if (responseData['TransferStockList'] is List) {
              for (var item in responseData['TransferStockList']) {
                final String? id = _parseString(item['ID'] ?? item['id']);
                if (id != null) {
                  var transfer = await isar.transferStockList.where().filter().idEqualTo(id).findFirst() ?? TransferStock();
                  transfer.id = id;
                  transfer.byType = _parseString(item['ByType'] ?? item['byType']);
                  transfer.byID = _parseString(item['ByID'] ?? item['byID']);
                  transfer.transferType = _parseString(item['TransferType'] ?? item['transferType']);
                  transfer.from_merchandise_stock_ID = _parseString(item['From_merchandise_stock_ID'] ?? item['from_merchandise_stock_ID']);
                  transfer.fromQuantity = _parseDouble(item['FromQuantity'] ?? item['fromQuantity']);
                  transfer.to_merchandise_stock_ID = _parseString(item['To_merchandise_stock_ID'] ?? item['to_merchandise_stock_ID']);
                  transfer.toQuantity = _parseDouble(item['ToQuantity'] ?? item['toQuantity']);
                  transfer.lastUpdated = _parseString(item['LastUpdated'] ?? item['lastUpdated']);
                  transfer.isDirty = false;
                  await isar.transferStockList.put(transfer);
                }
              }
            }

            // PurchaseOrderList
            if (responseData['PurchaseOrderList'] is List) {
              for (var item in responseData['PurchaseOrderList']) {
                final String? id = _parseString(item['ID'] ?? item['id']);
                if (id != null) {
                  var po = await isar.purchaseOrderList.where().filter().idEqualTo(id).findFirst() ?? PurchaseOrder();
                  po.id = id;
                  po.code = _parseString(item['Code'] ?? item['code']);
                  po.storeType = _parseString(item['StoreType'] ?? item['storeType']);
                  po.storeID = _parseString(item['StoreID'] ?? item['storeID']);
                  po.supplier_ID = _parseString(item['Supplier_ID'] ?? item['supplier_ID']);
                  po.supplierDocumentNumber = _parseString(item['SupplierDocumentNumber'] ?? item['supplierDocumentNumber']);
                  po.vatType = _parseString(item['VatType'] ?? item['vatType']);
                  po.sumAmount = _parseDouble(item['SumAmount'] ?? item['sumAmount']);
                  po.vatAmount = _parseDouble(item['VatAmount'] ?? item['vatAmount']);
                  po.totalAmount = _parseDouble(item['TotalAmount'] ?? item['totalAmount']);
                  po.paidAmount = _parseDouble(item['PaidAmount'] ?? item['paidAmount']);
                  po.status = _parseString(item['Status'] ?? item['status']);
                  po.paymentType = _parseString(item['PaymentType'] ?? item['paymentType']);
                  po.lastUpdated = _parseString(item['LastUpdated'] ?? item['lastUpdated']);
                  po.isDirty = false;
                  await isar.purchaseOrderList.put(po);
                }
              }
            }

            // PurchaseOrderLogList
            if (responseData['PurchaseOrderLogList'] is List) {
              for (var item in responseData['PurchaseOrderLogList']) {
                final String? id = _parseString(item['ID'] ?? item['id']);
                if (id != null) {
                  var pol = await isar.purchaseOrderLogList.where().filter().idEqualTo(id).findFirst() ?? PurchaseOrderLog();
                  pol.id = id;
                  pol.purchase_order_ID = _parseString(item['Purchase_order_ID'] ?? item['purchase_order_ID']);
                  pol.status = _parseString(item['Status'] ?? item['status']);
                  pol.remark = _parseString(item['Remark'] ?? item['remark']);
                  pol.shop_user_ID = _parseInt(item['Shop_user_ID'] ?? item['shop_user_ID']);
                  pol.lastUpdated = _parseString(item['LastUpdated'] ?? item['lastUpdated']);
                  pol.isDirty = false;
                  await isar.purchaseOrderLogList.put(pol);
                }
              }
            }

            // PurchaseOrderItemList
            if (responseData['PurchaseOrderItemList'] is List) {
              for (var item in responseData['PurchaseOrderItemList']) {
                final String? id = _parseString(item['ID'] ?? item['id']);
                if (id != null) {
                  var poi = await isar.purchaseOrderItemList.where().filter().idEqualTo(id).findFirst() ?? PurchaseOrderItem();
                  poi.id = id;
                  poi.purchase_order_ID = _parseString(item['Purchase_order_ID'] ?? item['purchase_order_ID']);
                  poi.seq = _parseInt(item['Seq'] ?? item['seq']);
                  poi.stockType = _parseString(item['StockType'] ?? item['stockType']);
                  poi.stockID = _parseString(item['StockID'] ?? item['stockID']);
                  poi.orderQuantity = _parseDouble(item['OrderQuantity'] ?? item['orderQuantity']);
                  poi.unitPrice = _parseDouble(item['UnitPrice'] ?? item['unitPrice']);
                  poi.itemAmount = _parseDouble(item['ItemAmount'] ?? item['itemAmount']);
                  poi.receivedQuantity = _parseDouble(item['ReceivedQuantity'] ?? item['receivedQuantity']);
                  poi.unitCost = _parseDouble(item['UnitCost'] ?? item['unitCost']);
                  poi.status = _parseString(item['Status'] ?? item['status']);
                  poi.lastUpdated = _parseString(item['LastUpdated'] ?? item['lastUpdated']);
                  poi.isDirty = false;
                  await isar.purchaseOrderItemList.put(poi);
                }
              }
            }

            // SupplierList
            if (responseData['SupplierList'] is List) {
              for (var item in responseData['SupplierList']) {
                final String? id = _parseString(item['ID'] ?? item['id']);
                if (id != null) {
                  var supplier = await isar.supplierList.where().filter().idEqualTo(id).findFirst() ?? Supplier();
                  supplier.id = id;
                  supplier.shop_ID = _parseString(item['Shop_ID'] ?? item['shop_ID']);
                  supplier.thaiName = _parseString(item['ThaiName'] ?? item['thaiName']);
                  supplier.englishName = _parseString(item['EnglishName'] ?? item['englishName']);
                  supplier.thaiAddress = _parseString(item['ThaiAddress'] ?? item['thaiAddress']);
                  supplier.englishAddress = _parseString(item['EnglishAddress'] ?? item['englishAddress']);
                  supplier.sub_district_ID = _parseString(item['Sub_district_ID'] ?? item['sub_district_ID']);
                  supplier.contactInformation = _parseString(item['ContactInformation'] ?? item['contactInformation']);
                  supplier.pictureFileName = _parseString(item['PictureFileName'] ?? item['pictureFileName']);
                  supplier.telephone = _parseString(item['Telephone'] ?? item['telephone']);
                  supplier.email = _parseString(item['Email'] ?? item['email']);
                  supplier.taxID = _parseString(item['TaxID'] ?? item['taxID']);
                  supplier.language = _parseString(item['Language'] ?? item['language']);
                  supplier.isActive = _parseString(item['IsActive'] ?? item['isActive']);
                  supplier.lastUpdated = _parseString(item['LastUpdated'] ?? item['lastUpdated']);
                  supplier.isDirty = false;
                  await isar.supplierList.put(supplier);
                }
              }
            }
          }
        });
        return true;
      } else {
        debugPrint('Sync failed: ${response.statusCode} ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Sync error: $e');
      return false;
    }
  } // syncPurchaseOrder
}
