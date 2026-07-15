import 'package:isar/isar.dart';
import 'package:meorder_ppos/database/IsarModels.dart';
import 'package:meorder_ppos/lib/EnvConfig.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:meorder_ppos/screen/MerchandiseCategoryScreen.dart';
import 'package:meorder_ppos/screen/SettingValueScreen.dart';
import 'package:meorder_ppos/screen/DocumentTypeScreen.dart';

class GeneralServices {
  static Future<Map<String, String?>?> getRoleTransactionPermissionList(
      String roleID, String transactionPermissionID) async {
    final isar = Isar.getInstance()!;
    final data = await isar.roleTransactionPermissionList
        .filter()
        .role_IDEqualTo(roleID)
        .and()
        .transaction_permission_IDEqualTo(transactionPermissionID)
        .findFirst();

    if (data == null) {
      return null;
    }

    return {
      'PermissionLevel': data.permissionLevel,
      'PartialPercent': data.partialPercent,
      'PartialAmount': data.partialAmount,
    };
  }

  static Future<RoleMasterPermission?> getRoleMasterPermission(
      String roleID, String masterPermissionID) async {
    final isar = Isar.getInstance()!;
    return await isar.roleMasterPermissionList
        .filter()
        .role_IDEqualTo(roleID)
        .and()
        .master_permission_IDEqualTo(masterPermissionID)
        .findFirst();
  }

  static Future<List<RoleMasterPermission>> getAdminMenuList(
      String roleID, EnvConfig config) async {
    List<RoleMasterPermission> adminMenuList = [];

    List<String> masterPermissionIDList = []

    if (config.service_module_ID == 'FOA' || config.service_module_ID == 'FOB') {
      masterPermissionIDList = [
        'FO_SUPPLIER',
        'FO_FOOD_CATEGORY',
        'FO_MERCHANDISE_CATEGORY',
        'FO_SHOP_CUSTOMER',
        'FO_SHOP_ZONE',
        'FO_SHOP_TABLE',
        'FO_DOCUMENT_CODE',
        'FO_DOCUMENT_TYPE',
        'FO_KITCHEN',
        'FO_POS',
        'FO_SHOP',
        'FO_SHOP_BRANCH',
        'FO_ROLE',
        'FO_SHOP_USER',
        'FO_SETTING_VALUE',
        'FO_PAYMENT'
      ];
    } else {
      masterPermissionIDList = [
        'FO_SUPPLIER',
        'FO_FOOD_CATEGORY',
        'FO_MERCHANDISE_CATEGORY',
        'FO_SHOP_CUSTOMER',
        'FO_DOCUMENT_CODE',
        'FO_DOCUMENT_TYPE',
        'FO_KITCHEN',
        'FO_POS',
        'FO_SHOP',
        'FO_SHOP_BRANCH',
        'FO_ROLE',
        'FO_SHOP_USER',
        'FO_SETTING_VALUE',
        'FO_PAYMENT'
      ];
    }

    // debugPrint('getRoleMasterPermission masterPermissionIDList: $masterPermissionIDList');

    for (var mpID in masterPermissionIDList) {
      final mp = await getRoleMasterPermission(roleID, mpID);
    
      // debugPrint('getRoleMasterPermission roleID: $roleID, mpID: $mpID, mp: $mp');

      if (mp != null && mp.canRead == 'Y') {
        adminMenuList.add(mp);
      }
    }

    return adminMenuList;
  }

  static Widget? _getScreen(String id, EnvConfig config) {
    switch (id) {
      case 'FO_MERCHANDISE_CATEGORY':
        return MerchandiseCategoryScreen(config: config);
      case 'FO_SETTING_VALUE':
        return SettingValueScreen(config: config);
      case 'FO_DOCUMENT_TYPE':
        return DocumentTypeScreen(config: config);
      // NOTE: Other screens map to null for now as they are not imported or implemented yet
      default:
        return null;
    }
  }

  static Widget getAdminPopupMenuButton(BuildContext context, EnvConfig config, List<RoleMasterPermission> adminMenuList, bool isThai) {
    if (adminMenuList.isEmpty) return const SizedBox.shrink();

    return PopupMenuButton<String>(
      icon: const Icon(Icons.menu, color: Colors.black),
      onSelected: (value) {
        final screen = _getScreen(value, config);
        if (screen != null) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(isThai ? 'ยังไม่พร้อมใช้งาน' : 'Under Construction')),
          );
        }
      },
      itemBuilder: (context) {
        return adminMenuList.map((am) {
          return PopupMenuItem<String>(
            value: am.master_permission_ID,
            child: Text(isThai ? (am.thaiName ?? '') : (am.englishName ?? '')),
          );
        }).toList();
      },
    );
  }

  static Future<String> getDocumentCode(String documentType, {String? posID}) async {
    final isDebug = true;

    final isar = Isar.getInstance()!;
    String code = '';
    int seqNumber = 0;
    final docCodeList = await isar.documentCodeList.filter().documentTypeEqualTo(documentType).findAll();
    docCodeList.sort((a, b) => (a.seq ?? 0).compareTo(b.seq ?? 0));
    var numberCode;
    DateTime now = DateTime.now();

    for (var docCode in docCodeList) {
      switch (docCode.name) {
        case 'POSID':
          code += (posID ?? '') + (docCode.seperator ?? '');
          break;
        case 'PREFIX':
          if (docCode.value != null) {
            code += docCode.value! + (docCode.seperator ?? '');
          }
          break;
        case 'YEAR':
          if (docCode.value != null && docCode.value!.isNotEmpty) {
            int y = now.year;
            if (docCode.value!.startsWith('BE')) y += 543;
            if (docCode.value!.contains('2')) y = y % 100;
            code += '$y${docCode.seperator ?? ''}';
          }
          break;
        case 'MONTH':
          String m = now.month.toString().padLeft(2, '0');
          code += '$m${docCode.seperator ?? ''}';
          break;
        case 'DAY':
          String d = now.day.toString().padLeft(2, '0');
          code += '$d${docCode.seperator ?? ''}';
          break;
        case 'NUMBER':
          numberCode = docCode;
          break;
      }

      if (isDebug) { debugPrint('getDocumentCode docCode.name: ${docCode.name}, docCode.seperator: ${docCode.seperator}, docCode.value: ${docCode.value} code: ${code}'); }
    } // end for
      
    String codePrefix = code;
    int digit = 4;
    if (numberCode != null) {
      digit = int.tryParse(numberCode.seperator ?? '4') ?? 4;
      if (numberCode.value == 'SEQUENCE') {
        final existingCount = await isar.receiptList
            .where()
            .filter()
            .codeStartsWith(codePrefix)
            .count();
        seqNumber = existingCount + 1;
        code += seqNumber.toString().padLeft(digit, '0');
      } else {
        seqNumber = now.millisecondsSinceEpoch % 10000;
        code += seqNumber.toString().padLeft(digit, '0');
      }
    } else {
      seqNumber = now.millisecondsSinceEpoch % 10000;
      code += seqNumber.toString().padLeft(digit, '0');
    }

    if (isDebug) { debugPrint('getDocumentCode numberCode: ${numberCode}, code: ${code}'); }
    
    return code;
  }
}
