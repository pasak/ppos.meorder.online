import 'package:isar/isar.dart';
import 'package:meorder_ppos/database/IsarModels.dart';

class RolePermissionServices {
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
}
