import 'package:isar/isar.dart';
import 'package:meorder_ppos/database/IsarModels.dart';
import 'package:flutter/foundation.dart';

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
