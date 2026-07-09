import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:meorder_ppos/database/IsarModels.dart';
import 'package:meorder_ppos/lib/EnvConfig.dart';
import 'package:meorder_ppos/services/GeneralServices.dart';
import 'package:uuid/uuid.dart';

class InventoryServices {
  static Future<void> sellDecreaseStock(
    EnvConfig config,
    String roleID,
    List<ReceiptItem> receiptItemList,
  ) async {
    final isar = Isar.getInstance()!;
    final foTransferStock = await GeneralServices.getRoleTransactionPermissionList(roleID, 'FO_TRANSFER_STOCK');

    final bool isDebug = true;

    if (isDebug) { debugPrint('sellDecreaseStock PermissionLevel: ${foTransferStock?['PermissionLevel']}'); }

    for (var ri in receiptItemList) {
      String stockType = (ri.merchandise_pack_ID == null || ri.merchandise_pack_ID!.isEmpty)
          ? 'merchandise_item'
          : 'merchandise_pack';
      String stockID = (ri.merchandise_pack_ID == null || ri.merchandise_pack_ID!.isEmpty)
          ? ri.merchandise_item_ID!
          : ri.merchandise_pack_ID!;

      var msList = await isar.merchandiseStockList
          .where()
          .filter()
          .storeTypeEqualTo('shop_branch')
          .and()
          .storeIDEqualTo(int.tryParse(config.shop_branch_ID ?? '0') ?? 0)
          .and()
          .stockTypeEqualTo(stockType)
          .and()
          .stockIDEqualTo(stockID)
          .sortByCreatedAt()
          .findAll();

      if (isDebug) { 
        debugPrint('sellDecreaseStock search MerchandiseStock list length: ${msList.length}'); 
      }

      if (msList.isEmpty) {
        var ms = MerchandiseStock()
          ..id = const Uuid().v4()
          ..storeType = 'shop_branch'
          ..storeID = int.tryParse(config.shop_branch_ID ?? '0') ?? 0
          ..stockType = stockType
          ..stockID = stockID
          ..currentQuantity = 0.0
          ..availableQuantity = 0.0
          ..unitCost = 0.0
          ..createdAt = DateTime.now().toIso8601String()
          ..lastUpdated = DateTime.now().toIso8601String()
          ..isDirty = true;

        await isar.writeTxn(() async {
          await isar.merchandiseStockList.put(ms);
        });

        msList = [ms];

        if (isDebug) { 
          debugPrint('sellDecreaseStock create MerchandiseStock id: ${ms.id}, storeType: ${ms.storeType}, storeID: ${ms.storeID}, stockType: ${ms.stockType}, stockID: ${ms.stockID}, current: ${ms.currentQuantity}, available: ${ms.availableQuantity}, isDirty: ${ms.isDirty}'); 
        }
      }

      double sumAvailableQuantity = msList.fold(0.0, (sum, ms) => sum + (ms.availableQuantity ?? 0.0));

      if (isDebug) { debugPrint('sellDecreaseStock sumAvailableQuantity: ${sumAvailableQuantity} ri.quantity: ${ri.quantity}'); }

      if (sumAvailableQuantity < (ri.quantity ?? 0.0)) {
        if (foTransferStock != null &&
            (foTransferStock['PermissionLevel'] == 'Full' || foTransferStock['PermissionLevel'] == 'Unpack')) {

          bool unpacked = await getNextLevelMerchandiseStockList(config, ri.receipt_ID ?? '', stockType, stockID);

          if (isDebug) { debugPrint('sellDecreaseStock unpacked: $unpacked'); }

          if (unpacked) {
            msList = await isar.merchandiseStockList
                .where()
                .filter()
                .storeTypeEqualTo('shop_branch')
                .and()
                .storeIDEqualTo(int.tryParse(config.shop_branch_ID ?? '0') ?? 0)
                .and()
                .stockTypeEqualTo(stockType)
                .and()
                .stockIDEqualTo(stockID)
                .sortByCreatedAt()
                .findAll();

            if (isDebug) { debugPrint('sellDecreaseStock unpack MerchandiseStock reloaded list stockType: $stockType, stockID: $stockID, length: ${msList.length}'); }
          }
        }
      }

      if (msList.isNotEmpty) {
        double decreaseQuantity = (ri.quantity ?? 0).toDouble();
        double sumCost = 0.0;
        await isar.writeTxn(() async {
          for (var ms in msList) {
            if (decreaseQuantity <= 0) break;

            if ((ms.availableQuantity ?? 0.0) > 0) {
              if (isDebug) { debugPrint('sellDecreaseStock ms.availableQuantity: ${ms.availableQuantity}, decreaseQuantity: $decreaseQuantity'); }

              if ((ms.availableQuantity ?? 0.0) >= decreaseQuantity) {
                sumCost += decreaseQuantity * (ms.unitCost ?? 0.0);
                
                ms.currentQuantity = (ms.currentQuantity ?? 0.0) - decreaseQuantity;
                ms.availableQuantity = (ms.availableQuantity ?? 0.0) - decreaseQuantity;
                ms.lastUpdated = DateTime.now().toIso8601String();
                ms.isDirty = true;
                await isar.merchandiseStockList.put(ms);
                
                if (isDebug) { debugPrint('sellDecreaseStock after decrease MerchandiseStock id: ${ms.id}, current: ${ms.currentQuantity}, available: ${ms.availableQuantity}, isDirty: ${ms.isDirty}'); }
                decreaseQuantity = 0;
              } else {
                double available = ms.availableQuantity ?? 0.0;
                sumCost += available * (ms.unitCost ?? 0.0);
                decreaseQuantity -= available;

                ms.currentQuantity = (ms.currentQuantity ?? 0.0) - available;
                ms.availableQuantity = (ms.availableQuantity ?? 0.0) - available;
                ms.lastUpdated = DateTime.now().toIso8601String();
                ms.isDirty = true;
                await isar.merchandiseStockList.put(ms);
                
                if (isDebug) { debugPrint('sellDecreaseStock after decrease (available $available < decrease $decreaseQuantity) MerchandiseStock id: ${ms.id}, current: ${ms.currentQuantity}, available: ${ms.availableQuantity}, isDirty: ${ms.isDirty}'); }
              }
            }
          }

          // หากหักจากทุก lot ที่เป็นค่าบวกจนหมดแล้ว แต่ยังต้องหักอีก (ยอมให้สต๊อคติดลบ) โค้ดจะนำยอดที่เหลือไปหักจาก stock ลอตล่าสุดในลิสต์
          if (decreaseQuantity > 0) {
            var ms = msList.last;
            sumCost += decreaseQuantity * (ms.unitCost ?? 0.0);
            ms.currentQuantity = (ms.currentQuantity ?? 0.0) - decreaseQuantity;
            ms.availableQuantity = (ms.availableQuantity ?? 0.0) - decreaseQuantity;
            ms.lastUpdated = DateTime.now().toIso8601String();
            ms.isDirty = true;
            await isar.merchandiseStockList.put(ms);

            if (isDebug) { debugPrint('sellDecreaseStock update MerchandiseStock (negative) id: ${ms.id}, current: ${ms.currentQuantity}, available: ${ms.availableQuantity}, isDirty: ${ms.isDirty}'); }
          }
          
          if ((ri.quantity ?? 0) > 0) {
            ri.unitCost = (msList.length > 1) ? sumCost / ri.quantity! : (msList.first.unitCost ?? 0.0);
            ri.lastUpdated = DateTime.now().toIso8601String();
            ri.isDirty = true;
            await isar.receiptItemList.put(ri);

            if (isDebug) { debugPrint('sellDecreaseStock update ReceiptItem id: ${ri.id}, unitCost: ${ri.unitCost}'); }
          }
        });
      }
    }
  }

  static Future<bool> getNextLevelMerchandiseStockList(
    EnvConfig config,
    String receiptID,
    String stockType,
    String stockID,
  ) async {
    final isDebug = true;

    final isar = Isar.getInstance()!;

    if (stockType == 'merchandise_item') {
      var packL1List = await isar.merchandisePackList
          .where()
          .filter()
          .merchandise_item_IDEqualTo(stockID)
          .and()
          .levelEqualTo(1)
          .findAll();

      for (var pack in packL1List) {
        if (isDebug) { debugPrint('getNextLevelMerchandiseStockList pack.id: ${pack.id}'); }

        var packStock = await isar.merchandiseStockList
            .where()
            .filter()
            .storeTypeEqualTo('shop_branch')
            .and()
            .storeIDEqualTo(int.tryParse(config.shop_branch_ID ?? '0') ?? 0)
            .and()
            .stockTypeEqualTo('merchandise_pack')
            .and()
            .stockIDEqualTo(pack.id)
            .findFirst();

        if (packStock != null && (packStock.availableQuantity ?? 0.0) > 0.0) {
          if (isDebug) { debugPrint('getNextLevelMerchandiseStockList packStock.id: ${packStock.id}'); }

          var itemStock = await isar.merchandiseStockList
              .where()
              .filter()
              .storeTypeEqualTo('shop_branch')
              .and()
              .storeIDEqualTo(int.tryParse(config.shop_branch_ID ?? '0') ?? 0)
              .and()
              .stockTypeEqualTo('merchandise_item')
              .and()
              .stockIDEqualTo(stockID)
              .findFirst();

          if (itemStock == null) { // ถ้ายังไม่มี สร้าง item stock เพื่อรับการ unpack
            itemStock = MerchandiseStock()
              ..id = const Uuid().v4()
              ..storeType = 'shop_branch'
              ..storeID = int.tryParse(config.shop_branch_ID ?? '0') ?? 0
              ..stockType = 'merchandise_item'
              ..stockID = stockID
              ..currentQuantity = 0.0
              ..availableQuantity = 0.0
              ..unitCost = 0.0
              ..lastUpdated = DateTime.now().toIso8601String()
              ..isDirty = true;
              
            await isar.writeTxn(() async {
              await isar.merchandiseStockList.put(itemStock!);
            });
          }

          if (isDebug) { debugPrint('getNextLevelMerchandiseStockList unpack receiptID: ${receiptID}, packStock.id: ${packStock.id}, itemStock.id: ${itemStock.id}'); }

          await unpackStock(receiptID, packStock.id!, itemStock.id!);

          if (isDebug) { debugPrint('getNextLevelMerchandiseStockList unpack success'); }

          return true;
        } else {
          bool unpacked = await getNextLevelMerchandiseStockList(config, receiptID, 'merchandise_pack', pack.id!);
          if (unpacked) {
            var refreshedPackStock = await isar.merchandiseStockList
                .where()
                .filter()
                .storeTypeEqualTo('shop_branch')
                .and()
                .storeIDEqualTo(int.tryParse(config.shop_branch_ID ?? '0') ?? 0)
                .and()
                .stockTypeEqualTo('merchandise_pack')
                .and()
                .stockIDEqualTo(pack.id)
                .findFirst();

            var itemStock = await isar.merchandiseStockList
                .where()
                .filter()
                .storeTypeEqualTo('shop_branch')
                .and()
                .storeIDEqualTo(int.tryParse(config.shop_branch_ID ?? '0') ?? 0)
                .and()
                .stockTypeEqualTo('merchandise_item')
                .and()
                .stockIDEqualTo(stockID)
                .findFirst();

            if (itemStock == null) {
              itemStock = MerchandiseStock()
                ..id = const Uuid().v4()
                ..storeType = 'shop_branch'
                ..storeID = int.tryParse(config.shop_branch_ID ?? '0') ?? 0
                ..stockType = 'merchandise_item'
                ..stockID = stockID
                ..currentQuantity = 0.0
                ..availableQuantity = 0.0
                ..lastUpdated = DateTime.now().toIso8601String()
                ..isDirty = true;

              await isar.writeTxn(() async {
                await isar.merchandiseStockList.put(itemStock!);
              });
            }
            if (refreshedPackStock != null) {
              await unpackStock(receiptID, refreshedPackStock.id!, itemStock.id!);
            }
            return true;
          }
        }
      }
    } else if (stockType == 'merchandise_pack') {
      var currentPack = await isar.merchandisePackList
          .where()
          .filter()
          .idEqualTo(stockID)
          .findFirst();

      if (currentPack != null) {
        int currentLevel = currentPack.level ?? 1;
        var nextLevelPacks = await isar.merchandisePackList
            .where()
            .filter()
            .merchandise_item_IDEqualTo(currentPack.merchandise_item_ID)
            .and()
            .levelEqualTo(currentLevel + 1)
            .findAll();

        for (var nextPack in nextLevelPacks) {
          var nextPackStock = await isar.merchandiseStockList
              .where()
              .filter()
              .storeTypeEqualTo('shop_branch')
              .and()
              .storeIDEqualTo(int.tryParse(config.shop_branch_ID ?? '0') ?? 0)
              .and()
              .stockTypeEqualTo('merchandise_pack')
              .and()
              .stockIDEqualTo(nextPack.id)
              .findFirst();

          if (nextPackStock != null && (nextPackStock.availableQuantity ?? 0.0) > 0.0) {
            var currentStock = await isar.merchandiseStockList
                .where()
                .filter()
                .storeTypeEqualTo('shop_branch')
                .and()
                .storeIDEqualTo(int.tryParse(config.shop_branch_ID ?? '0') ?? 0)
                .and()
                .stockTypeEqualTo('merchandise_pack')
                .and()
                .stockIDEqualTo(stockID)
                .findFirst();

            if (currentStock == null) {
              currentStock = MerchandiseStock()
                ..id = const Uuid().v4()
                ..storeType = 'shop_branch'
                ..storeID = int.tryParse(config.shop_branch_ID ?? '0') ?? 0
                ..stockType = 'merchandise_pack'
                ..stockID = stockID
                ..currentQuantity = 0.0
                ..availableQuantity = 0.0
                ..unitCost = 0.0
                ..createdAt = DateTime.now().toIso8601String()
                ..lastUpdated = DateTime.now().toIso8601String()
                ..isDirty = true;
                
              await isar.writeTxn(() async {
                await isar.merchandiseStockList.put(currentStock!);
              });
            }
            await unpackStock(receiptID, nextPackStock.id!, currentStock.id!);
            return true;
          } else {
            bool unpacked = await getNextLevelMerchandiseStockList(config, receiptID, 'merchandise_pack', nextPack.id!);
            if (unpacked) {
              var refreshedNextPackStock = await isar.merchandiseStockList
                  .where()
                  .filter()
                  .storeTypeEqualTo('shop_branch')
                  .and()
                  .storeIDEqualTo(int.tryParse(config.shop_branch_ID ?? '0') ?? 0)
                  .and()
                  .stockTypeEqualTo('merchandise_pack')
                  .and()
                  .stockIDEqualTo(nextPack.id)
                  .findFirst();

              var currentStock = await isar.merchandiseStockList
                  .where()
                  .filter()
                  .storeTypeEqualTo('shop_branch')
                  .and()
                  .storeIDEqualTo(int.tryParse(config.shop_branch_ID ?? '0') ?? 0)
                  .and()
                  .stockTypeEqualTo('merchandise_pack')
                  .and()
                  .stockIDEqualTo(stockID)
                  .findFirst();

              if (currentStock == null) {
                currentStock = MerchandiseStock()
                  ..id = const Uuid().v4()
                  ..storeType = 'shop_branch'
                  ..storeID = int.tryParse(config.shop_branch_ID ?? '0') ?? 0
                  ..stockType = 'merchandise_pack'
                  ..stockID = stockID
                  ..currentQuantity = 0.0
                  ..availableQuantity = 0.0
                  ..unitCost = 0.0
                  ..createdAt = DateTime.now().toIso8601String()
                  ..lastUpdated = DateTime.now().toIso8601String()
                  ..isDirty = true;
              }
              if (currentStock.id == null) {
                await isar.writeTxn(() async {
                  await isar.merchandiseStockList.put(currentStock!);
                });
              }

              if (refreshedNextPackStock != null) {
                await unpackStock(receiptID, refreshedNextPackStock.id!, currentStock.id!);
              }
              return true;
            }
          }
        }
      }
    }

    return false;
  }

  static Future<void> unpackStock(
    String receiptID,
    String from_merchandise_stock_ID,
    String to_merchandise_stock_ID,
  ) async {
    final isDebug = true;

    final isar = Isar.getInstance()!;

    var fms = await isar.merchandiseStockList
        .where()
        .filter()
        .idEqualTo(from_merchandise_stock_ID)
        .findFirst();
    if (fms == null) return;

    var fmp = await isar.merchandisePackList
        .where()
        .filter()
        .idEqualTo(fms.stockID ?? '')
        .findFirst();
    if (fmp == null) return;

    var tms = await isar.merchandiseStockList
        .where()
        .filter()
        .idEqualTo(to_merchandise_stock_ID)
        .findFirst();
    if (tms == null) return;

    await isar.writeTxn(() async {
      var transfer = TransferStock()
        ..id = const Uuid().v4()
        ..byType = 'receipt'
        ..byID = receiptID
        ..transferType = 'UnPack'
        ..from_merchandise_stock_ID = from_merchandise_stock_ID
        ..fromQuantity = 1.0
        ..to_merchandise_stock_ID = to_merchandise_stock_ID
        ..toQuantity = (fmp.quantity ?? 1).toDouble()
        ..lastUpdated = DateTime.now().toIso8601String()
        ..isDirty = true;

      if (isDebug) { 
        debugPrint('unpackStock from_merchandise_stock_ID: ${from_merchandise_stock_ID}, to_merchandise_stock_ID: ${to_merchandise_stock_ID} '
                    'fromQuantity: ${transfer.fromQuantity}, toQuantity: ${transfer.toQuantity}');
      }

      await isar.transferStockList.put(transfer);

      fms.currentQuantity = (fms.currentQuantity ?? 0.0) - 1.0;
      fms.availableQuantity = (fms.availableQuantity ?? 0.0) - 1.0;
      fms.lastUpdated = DateTime.now().toIso8601String();
      fms.isDirty = true;
      await isar.merchandiseStockList.put(fms);

      tms.currentQuantity = (tms.currentQuantity ?? 0.0) + (fmp.quantity ?? 1).toDouble();
      tms.availableQuantity = (tms.availableQuantity ?? 0.0) + (fmp.quantity ?? 1).toDouble();
      tms.unitCost = (fms.unitCost ?? 0.0) / (fmp.quantity ?? 1).toDouble();
      tms.lastUpdated = DateTime.now().toIso8601String();
      tms.isDirty = true;
      await isar.merchandiseStockList.put(tms);
    });
  }

  static Future<void> receivedPoIncreaseStock(String poID) async {
    bool isDebug = true;

    final isar = Isar.getInstance()!;
    final po = await isar.purchaseOrderList.where().filter().idEqualTo(poID).findFirst();
    if (po == null) return;

    final poItemList = await isar.purchaseOrderItemList
        .where()
        .filter()
        .purchase_order_IDEqualTo(poID)
        .findAll();

    final settings = await isar.settingValueList
        .where()
        .filter()
        .setting_IDEqualTo('FOC_CALC_UNIT_COST')
        .findFirst();

    String calcUnitCost = settings?.value ?? 'Average';
    
    if (isDebug) { debugPrint('receivedPoIncreaseStock calcUnitCost: $calcUnitCost'); }

    for (var item in poItemList) {
      if (calcUnitCost == 'Average') {
        var ms = await isar.merchandiseStockList
            .where()
            .filter()
            .storeTypeEqualTo(po.storeType)
            .and()
            .storeIDEqualTo(int.tryParse(po.storeID ?? '0') ?? 0)
            .and()
            .stockTypeEqualTo(item.stockType)
            .and()
            .stockIDEqualTo(item.stockID)
            .findFirst();
    
        if (isDebug) { debugPrint('receivedPoIncreaseStock search existing ms.currentQuantity: ${ms?.currentQuantity}'); }

        if (ms != null) {
          double newQuantity = (ms.currentQuantity ?? 0.0) + (item.receivedQuantity ?? 0.0);
          
          if ((ms.currentQuantity ?? 0.0) > 0.0) {
            double stockValue = ((ms.currentQuantity ?? 0.0) * (ms.unitCost ?? 0.0)) + 
                               ((item.receivedQuantity ?? 0.0) * (item.unitCost ?? 0.0));
            ms.unitCost = newQuantity > 0 ? stockValue / newQuantity : item.unitCost;
          } else { // สต็อคติดลบอยู่แล้ว ให้ใช้ต้นทุนใหม่เลย
            ms.unitCost = item.unitCost;
          }

          ms.currentQuantity = newQuantity;
          ms.availableQuantity = (ms.availableQuantity ?? 0.0) + (item.receivedQuantity ?? 0.0);
          ms.lastUpdated = DateTime.now().toIso8601String();
          ms.isDirty = true;
          
          await isar.writeTxn(() async {
            await isar.merchandiseStockList.put(ms);
          });
    
          if (isDebug) { debugPrint('receivedPoIncreaseStock update ms.currentQuantity: ${ms?.currentQuantity}'); }
        } else {
          var newMs = MerchandiseStock()
            ..id = const Uuid().v4()
            ..storeType = po.storeType
            ..storeID = int.tryParse(po.storeID ?? '0') ?? 0
            ..stockType = item.stockType
            ..stockID = item.stockID
            ..currentQuantity = item.receivedQuantity ?? 0.0
            ..availableQuantity = item.receivedQuantity ?? 0.0
            ..unitCost = item.unitCost
            ..createdAt = DateTime.now().toIso8601String()
            ..lastUpdated = DateTime.now().toIso8601String()
            ..isDirty = true;
            
          await isar.writeTxn(() async {
            await isar.merchandiseStockList.put(newMs);
          });
    
          if (isDebug) { debugPrint('receivedPoIncreaseStock insert newMs.currentQuantity: ${newMs.currentQuantity}'); }
        }      
      } else { // FIFO ปกติจะสร้าง ms แยกแต่ละครั้งที่ซื้อ เพื่อตัดสต๊อคตามลำดับ 
        // ยกเว้นกรณีขายโดยสต๊อกติดลบ ให้อัพเดท ms ที่ติดลบ
        var ms = await isar.merchandiseStockList
            .where()
            .filter()
            .storeTypeEqualTo(po.storeType)
            .and()
            .storeIDEqualTo(int.tryParse(po.storeID ?? '0') ?? 0)
            .and()
            .stockTypeEqualTo(item.stockType)
            .and()
            .stockIDEqualTo(item.stockID)
            .and()
            .currentQuantityLessThan(0.0)
            .findFirst();
    
        if (isDebug) { debugPrint('receivedPoIncreaseStock search existing ms.currentQuantity: ${ms?.currentQuantity}'); }

        if (ms != null) {
          // เช่น ขาย 5 -> ms ติดลบ 5 -> ซื้อ 10 -> อัพเดท ms -> currentQuantity เป็น 5 และใช้ต้นทุนใหม่
          ms.currentQuantity = (ms.currentQuantity ?? 0.0) + (item.receivedQuantity ?? 0.0);
          ms.availableQuantity = (ms.availableQuantity ?? 0.0) + (item.receivedQuantity ?? 0.0);
          ms.unitCost = item.unitCost;
          ms.lastUpdated = DateTime.now().toIso8601String();
          ms.isDirty = true;

          await isar.writeTxn(() async {
            await isar.merchandiseStockList.put(ms);
          });
    
          if (isDebug) { debugPrint('receivedPoIncreaseStock update ms.currentQuantity: ${ms?.currentQuantity}'); }

          // update receiptItem.unitCost ที่ขายโดยสต๊อคติดลบ เพราะตอนขายยังไม่มี unitCost
          var risList = await isar.receiptItemStockList
              .where()
              .filter()
              .merchandise_stock_IDEqualTo(ms.id)
              .findAll();

          for (var ris in risList) {
            var riList = await isar.receiptItemList
                .where()
                .filter()
                .idEqualTo(ris.receipt_item_ID ?? '')
                .and()
                .unitCostEqualTo(0.0)
                .findAll();
    
            if (isDebug) { debugPrint('receivedPoIncreaseStock search receiptItem.unitCost ที่ขายโดยสต๊อคติดลบ: ${riList?.length}'); }

            for (var ri in riList) {
              ri.unitCost = item.unitCost;
              ri.lastUpdated = DateTime.now().toIso8601String();
              ri.isDirty = true;
              await isar.writeTxn(() async {
                await isar.receiptItemList.put(ri);
              });
    
              if (isDebug) { debugPrint('receivedPoIncreaseStock update receiptItem.unitCost: ${ri.unitCost}'); }
            }
          }
        } else {
          var newMs = MerchandiseStock()
            ..id = const Uuid().v4()
            ..storeType = po.storeType
            ..storeID = int.tryParse(po.storeID ?? '0') ?? 0
            ..stockType = item.stockType
            ..stockID = item.stockID
            ..currentQuantity = item.receivedQuantity ?? 0.0
            ..availableQuantity = item.receivedQuantity ?? 0.0
            ..unitCost = item.unitCost
            ..createdAt = DateTime.now().toIso8601String()
            ..lastUpdated = DateTime.now().toIso8601String()
            ..isDirty = true;
            
          await isar.writeTxn(() async {
            await isar.merchandiseStockList.put(newMs);
          });
    
          if (isDebug) { debugPrint('receivedPoIncreaseStock insert newMs.currentQuantity: ${newMs.currentQuantity}'); }
        }
      }

      item.status = 'Received';
      item.lastUpdated = DateTime.now().toIso8601String();
      item.isDirty = true;
      await isar.writeTxn(() async {
        await isar.purchaseOrderItemList.put(item);
      });
    }
  }
}
