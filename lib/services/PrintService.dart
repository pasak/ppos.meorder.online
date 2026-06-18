import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:isar/isar.dart';
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';
import 'package:flutter_usb_printer/flutter_usb_printer.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:meorder_ppos/lib/EnvConfig.dart';
import 'package:meorder_ppos/database/IsarModels.dart';
import 'package:meorder_ppos/model/DisplayOrderItem.dart';
import 'package:meorder_ppos/services/SyncService.dart';

class PrintService {
  static Future<void> processPrintFlow({
    required BuildContext context,
    required Isar isar,
    required EnvConfig config,
    required Receipt? receipt,
    List<FoodOrder>? foodOrders,
    required List<DisplayOrderItem> displayItems,
    List<ReceiptItem>? receiptItems,
    required bool isThai,
    bool isMT = false,
    required VoidCallback onComplete,
  }) async {
    final settings = await isar.settingValueList.where().filter().anyOf([
      'FOC_PRN_RCP_CSH',
      'FOC_PRN_COK',
      'FOC_PAUSE_PRN_COK',
    ], (q, String id) => q.setting_IDEqualTo(id)).findAll();

    Map<String, bool> settingValue = {
      'FOC_PRN_RCP_CSH': true,
      'FOC_PRN_COK': true,
      'FOC_PAUSE_PRN_COK': false,
    };

    for (var sv in settings) {
      if (sv.setting_ID != null) {
        settingValue[sv.setting_ID!] = (sv.value == 'Y');
      }
    }

    if (config.PrinterModel == 'Xprinter N160ii') {
      settingValue['FOC_PAUSE_PRN_COK'] = false;
    }

    if (settingValue['FOC_PRN_RCP_CSH'] == true) {
      await printReceipt(
        isar: isar,
        config: config,
        receipt: receipt,
        foodOrders: foodOrders,
        displayItems: displayItems,
        receiptItems: receiptItems,
        isThai: isThai,
        isMT: isMT,
      );
    }

    if (foodOrders != null && foodOrders.isNotEmpty) {
      if (settingValue['FOC_PRN_COK'] == true) {
        if (settingValue['FOC_PAUSE_PRN_COK'] == true) {
        if (!context.mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return AlertDialog(
              content: Text(
                isThai
                    ? 'ฉีกใบเสร็จรับเงินให้ลูกค้า แล้วกดปุ่มเพื่อพิมพ์ใบสั่งอาหาร'
                    : 'Tear off the receipt and press to print cooking order.',
              ),
              actions: [
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await printCookingOrder(
                      isar: isar,
                      config: config,
                      foodOrders: foodOrders,
                      displayItems: displayItems,
                    );
                    onComplete();
                  },
                  child: Text(
                    isThai ? 'พิมพ์ใบสั่งอาหาร' : 'Print Cooking Order',
                  ),
                ),
              ],
            );
          },
        );
        return;
      } else {
        await printCookingOrder(
          isar: isar,
          config: config,
          foodOrders: foodOrders,
          displayItems: displayItems,
        );
      }
    }
  }

    onComplete();
  }

  static Future<void> _printSunmiNewLine(int numberOfLine) async {
    for (var i = 0; i < numberOfLine; i++) {
      await SunmiPrinter.printText(' ', style: SunmiTextStyle(align: SunmiPrintAlign.LEFT, fontSize: 24));
    }
  }

  static Future<void> printReceipt({
    required Isar isar,
    required EnvConfig config,
    required Receipt? receipt,
    List<FoodOrder>? foodOrders,
    required List<DisplayOrderItem> displayItems,
    List<ReceiptItem>? receiptItems,
    required bool isThai,
    bool isMT = false,
  }) async {
    bool isDebug = false;

    final documentTypes = await isar.documentTypeList
        .where()
        .filter()
        .printerModelEqualTo(config.PrinterModel)
        .findAll();
    final documentType = documentTypes.isNotEmpty ? documentTypes.first : null;

    if (isDebug) { 
      debugPrint('PrintService Printer Model: $config.PrinterModel');
      debugPrint('PrintService Document Type: $documentType');
    }

    if (documentType == null) return;

    final templates = await isar.documentTemplateList
        .where()
        .filter()
        .document_type_IDEqualTo(documentType.id)
        .and()
        .isActiveEqualTo('Y')
        .sortBySeq()
        .findAll();

    if (isDebug) { debugPrint('PrintService Templates: $templates'); }

    if (config.PrinterModel == 'Sunmi V series') {
      for (var dt in templates) {
        String rawText = dt.printText ?? '';
        if (!_shouldPrintTemplate(rawText)) continue;
        if (rawText.contains('[KitchenItem]')) continue;

        if (rawText.contains('[ReceiptItem]')) {
          await _printSunmiNewLine(1);
          await _printReceiptItemsSunmi(
            isar: isar,
            displayItems: displayItems,
            receiptItems: receiptItems,
            receipt: receipt,
            isThai: isThai,
            isMT: isMT,
          );
          await _printSunmiNewLine(1);
        } else {
          String textToPrint = _replaceVariables(rawText, config, foodOrders, receipt);
          if (textToPrint.isNotEmpty) {
            if (dt.alignment == 'Full' && textToPrint.contains(',')) {
              List<String> parts = textToPrint.split(',');
              String leftPart = parts.isNotEmpty ? parts[0] : '';
              String rightPart = parts.length > 1 ? parts.sublist(1).join(',') : '';
              await SunmiPrinter.printRow(
                cols: [
                  SunmiColumn(text: leftPart, width: 15, style: SunmiTextStyle(align: SunmiPrintAlign.LEFT, fontSize: (dt.fontSize ?? 24).clamp(1, 96).toInt())),
                  SunmiColumn(text: rightPart, width: 15, style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT, fontSize: (dt.fontSize ?? 24).clamp(1, 96).toInt())),
                ],
              );
            } else {
              await SunmiPrinter.printText(
                textToPrint,
                style: SunmiTextStyle(
                  align: _getAlign(dt.alignment),
                  fontSize: (dt.fontSize ?? 24).clamp(1, 96).toInt(),
                ),
              );
            }
          }
        }
      }
      await _printSunmiNewLine(3);
    } else {
      List<int> bytes = [];
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      bytes += generator.reset();

      for (var dt in templates) {
        String rawText = dt.printText ?? '';
        if (!_shouldPrintTemplate(rawText)) continue;
        if (rawText.contains('[KitchenItem]')) continue;

        if (rawText.contains('[ReceiptItem]')) {
          bytes += generator.feed(2);
          for (var di in displayItems) {
            String desc = '${di.item.quantity ?? 0}x ${di.itemName}';
            if (di.sizeName.isNotEmpty) desc += ' ${di.sizeName}';
            if (di.choiceName.isNotEmpty) desc += ' ${di.choiceName}';
            double amount = (di.item.quantity ?? 0) * (di.item.itemPrice ?? 0.0);

            if ((di.item.discountAmount ?? 0.0) > 0.0) {
              desc += ' -${di.item.discountAmount!.toStringAsFixed(2)}';
              amount -= di.item.discountAmount!;
            }

            final image = await _rowToImage(desc, amount.toStringAsFixed(2), 24);
            bytes += generator.imageRaster(image);

            if (di.item.description != null && di.item.description!.isNotEmpty) {
              final descImage = await _textToImage('  * ${di.item.description}', 24, 'Left');
              bytes += generator.imageRaster(descImage);
            }
          }
          
          for (var ri in receiptItems ?? []) {
            var mItem = await isar.merchandiseItemList.where().filter().idEqualTo(ri.merchandise_item_ID ?? '').findFirst();
            String itemName = mItem?.productName ?? '';
            String unitName = mItem?.unitName ?? '';
            
            if (ri.merchandise_pack_ID != null) {
              var mPack = await isar.merchandisePackList.where().filter().idEqualTo(ri.merchandise_pack_ID ?? '').findFirst();
              if (mPack != null) {
                final currentLevel = mPack.level ?? 1;
                if (currentLevel > 1) {
                  final allPacks = await isar.merchandisePackList.where()
                      .filter()
                      .merchandise_item_IDEqualTo(ri.merchandise_item_ID)
                      .findAll();
                  try {
                    final prevPack = allPacks.firstWhere((p) => (p.level ?? 1) == currentLevel - 1);
                    unitName = prevPack.packName ?? '';
                  } catch (e) {
                    allPacks.sort((a, b) => (a.level ?? 1).compareTo(b.level ?? 1));
                    int packIdx = allPacks.indexWhere((p) => p.id == mPack.id);
                    if (packIdx > 0) {
                      unitName = allPacks[packIdx - 1].packName ?? '';
                    }
                  }
                }
                itemName += ' ${mPack.packName ?? '-'} ${mPack.quantity ?? 1} $unitName';
              }
            }
            String desc = '${ri.quantity ?? 0}x $itemName';
            double amount = (ri.quantity ?? 0) * (ri.itemPrice ?? 0.0);
            if ((ri.discountAmount ?? 0.0) > 0.0) {
              desc += ' -${ri.discountAmount!.toStringAsFixed(2)}';
              amount -= ri.discountAmount!;
            }
            final image = await _rowToImage(desc, amount.toStringAsFixed(2), 24);
            bytes += generator.imageRaster(image);
          }
          
          bytes += generator.imageRaster(await _dividerImage());

          if ((receipt?.sumAmount ?? 0.0) != (receipt?.totalAmount ?? 0.0)) {
            bytes += generator.imageRaster(
              await _rowToImage(
                isThai ? 'ยอดรวม' : 'Sum Amount',
                (receipt?.sumAmount ?? 0.0).toStringAsFixed(2),
                24,
              ),
            );
            bytes += generator.imageRaster(
              await _rowToImage(
                isThai ? 'ส่วนลด' : 'Discount',
                (receipt?.discountAmount ?? 0.0).toStringAsFixed(2),
                24,
              ),
            );
          }
          bytes += generator.imageRaster(
            await _rowToImage(
              isThai ? 'ยอดรวมทั้งหมด' : 'Total Amount',
              (receipt?.totalAmount ?? 0.0).toStringAsFixed(2),
              28,
              isBold: true,
            ),
          );

          bytes += generator.imageRaster(await _dividerImage());
          String pt = (receipt?.paymentType == 'Cash')
              ? (isThai ? 'เงินสด' : 'Cash')
              : (isMT
                    ? (isThai ? 'โอนเงิน' : 'Money Transfer')
                    : (receipt?.paymentType ?? ''));
          bytes += generator.imageRaster(
            await _rowToImage(pt, (receipt?.paidAmount ?? 0.0).toStringAsFixed(2), 24),
          );
          bytes += generator.feed(2);
        } else {
          String textToPrint = _replaceVariables(rawText, config, foodOrders, receipt);
          if (textToPrint.isNotEmpty) {
            if (dt.alignment == 'Full' && textToPrint.contains(',')) {
              List<String> parts = textToPrint.split(',');
              String leftPart = parts.isNotEmpty ? parts[0] : '';
              String rightPart = parts.length > 1 ? parts.sublist(1).join(',') : '';
              final imageToPrint = await _rowToImage(
                leftPart, rightPart, dt.fontSize ?? 24
              );
              bytes += generator.imageRaster(imageToPrint);
            } else {
              final imageToPrint = await _textToImage(
                textToPrint,
                dt.fontSize ?? 24,
                dt.alignment,
              );
              bytes += generator.imageRaster(imageToPrint);
            }
          }
        }
      }
      bytes += generator.feed(2);
      bytes += generator.cut();
      await _executePrint(bytes, config);
    }
  }

  static Future<void> _printReceiptItemsSunmi({
    required Isar isar,
    required List<DisplayOrderItem> displayItems,
    List<ReceiptItem>? receiptItems,
    required Receipt? receipt,
    required bool isThai,
    bool isMT = false,
  }) async {
    for (var di in displayItems) {
      String desc = '${di.item.quantity ?? 0}x ${di.itemName}';
      if (di.sizeName.isNotEmpty) desc += ' ${di.sizeName}';
      if (di.choiceName.isNotEmpty) desc += ' ${di.choiceName}';

      double amount = (di.item.quantity ?? 0) * (di.item.itemPrice ?? 0.0);
      
      if ((di.item.discountAmount ?? 0.0) > 0.0) {
        desc += ' -${di.item.discountAmount!.toStringAsFixed(2)}';
        amount -= di.item.discountAmount!;
      }

      await SunmiPrinter.printRow(
        cols: [
          SunmiColumn(text: desc, width: 20, style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
          SunmiColumn(text: amount.toStringAsFixed(2), width: 10, style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
        ],
      );

      if (di.item.description != null && di.item.description!.isNotEmpty) {
        await SunmiPrinter.printText(
          '  * ${di.item.description}',
          style: SunmiTextStyle(align: SunmiPrintAlign.LEFT),
        );
      }
    }
    
    for (var ri in receiptItems ?? []) {
      var mItem = await isar.merchandiseItemList.where().filter().idEqualTo(ri.merchandise_item_ID ?? '').findFirst();
      String itemName = mItem?.productName ?? '';
      String unitName = mItem?.unitName ?? '';
      
      if (ri.merchandise_pack_ID != null) {
        var mPack = await isar.merchandisePackList.where().filter().idEqualTo(ri.merchandise_pack_ID ?? '').findFirst();
        if (mPack != null) {
          final currentLevel = mPack.level ?? 1;
          if (currentLevel > 1) {
            final allPacks = await isar.merchandisePackList.where()
                .filter()
                .merchandise_item_IDEqualTo(ri.merchandise_item_ID)
                .findAll();
            try {
              final prevPack = allPacks.firstWhere((p) => (p.level ?? 1) == currentLevel - 1);
              unitName = prevPack.packName ?? '';
            } catch (e) {
              allPacks.sort((a, b) => (a.level ?? 1).compareTo(b.level ?? 1));
              int packIdx = allPacks.indexWhere((p) => p.id == mPack.id);
              if (packIdx > 0) {
                unitName = allPacks[packIdx - 1].packName ?? '';
              }
            }
          }
          itemName += ' ${mPack.packName ?? '-'} ${mPack.quantity ?? 1} $unitName';
        }
      }
      String desc = '${ri.quantity ?? 0}x $itemName';
      double amount = (ri.quantity ?? 0) * (ri.itemPrice ?? 0.0);
      if ((ri.discountAmount ?? 0.0) > 0.0) {
        desc += ' -${ri.discountAmount!.toStringAsFixed(2)}';
        amount -= ri.discountAmount!;
      }
      await SunmiPrinter.printRow(
        cols: [
          SunmiColumn(text: desc, width: 20, style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
          SunmiColumn(text: amount.toStringAsFixed(2), width: 10, style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
        ],
      );
    }
    
    await SunmiPrinter.line();
    if ((receipt?.sumAmount ?? 0.0) != (receipt?.totalAmount ?? 0.0)) {
      await SunmiPrinter.printRow(
        cols: [
          SunmiColumn(text: isThai ? 'ยอดรวม' : 'Sum Amount', width: 20, style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
          SunmiColumn(text: (receipt?.sumAmount ?? 0.0).toStringAsFixed(2), width: 10, style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
        ],
      );
      await SunmiPrinter.printRow(
        cols: [
          SunmiColumn(text: isThai ? 'ส่วนลด' : 'Discount', width: 20, style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
          SunmiColumn(text: (receipt?.discountAmount ?? 0.0).toStringAsFixed(2), width: 10, style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
        ],
      );
    }
    await SunmiPrinter.printRow(
      cols: [
        SunmiColumn(text: isThai ? 'ยอดรวมทั้งหมด' : 'Total Amount', width: 15, style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
        SunmiColumn(text: (receipt?.totalAmount ?? 0.0).toStringAsFixed(2), width: 15, style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
      ],
    );
    await SunmiPrinter.line();

    String pt = (receipt?.paymentType == 'Cash')
        ? (isThai ? 'เงินสด' : 'Cash')
        : (isMT
              ? (isThai ? 'โอนเงิน' : 'Money Transfer')
              : (receipt?.paymentType ?? ''));
    await SunmiPrinter.printRow(
      cols: [
        SunmiColumn(text: pt, width: 15, style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
        SunmiColumn(text: (receipt?.paidAmount ?? 0.0).toStringAsFixed(2), width: 15, style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
      ],
    );
  }

  static Future<void> printCookingOrder({
    required Isar isar,
    required EnvConfig config,
    required List<FoodOrder> foodOrders,
    required List<DisplayOrderItem> displayItems,
  }) async {
    debugPrint('start printCookingOrder');

    final documentTypes = await isar.documentTypeList
        .where()
        .filter()
        .printerModelEqualTo(config.PrinterModel)
        .findAll();
    final documentType = documentTypes.isNotEmpty ? documentTypes.first : null;

    if (documentType == null) return;

    final templates = await isar.documentTemplateList
        .where()
        .filter()
        .document_type_IDEqualTo(documentType.id)
        .and()
        .printTextContains('FoodOrder.Number')
        .findAll();

    final kitchenTemplates = await isar.documentTemplateList
        .where()
        .filter()
        .document_type_IDEqualTo(documentType.id)
        .and()
        .printTextContains('[KitchenItem]')
        .findAll();
    final dtKitchen = kitchenTemplates.isNotEmpty ? kitchenTemplates.first : null;
    final int kFontSize = dtKitchen?.fontSize ?? 24;
    final String kAlign = dtKitchen?.alignment ?? 'Left';

    debugPrint('printCookingOrder kFontSize:$kFontSize kAlign:$kAlign');

    if (config.PrinterModel == 'Sunmi V series') {
      for (var order in foodOrders) {
        final orderItems = displayItems.where((di) => di.item.food_order_ID == order.id).toList();
        if (orderItems.isEmpty) continue;

        for (var dt in templates) {
          await SunmiPrinter.printText(
            order.number?.toString() ?? '',
            style: SunmiTextStyle(
              align: _getAlign(dt.alignment),
              fontSize: (dt.fontSize ?? 24).clamp(1, 96).toInt(),
              bold: true,
            ),
          );
        }
        for (var di in orderItems) {
          String desc = '${di.item.quantity ?? 0}x ${di.kitchenItemName}';
          if (di.kitchenSizeName.isNotEmpty) desc += ' ${di.kitchenSizeName}';
          if (di.kitchenChoiceName.isNotEmpty) desc += ' ${di.kitchenChoiceName}';

          await SunmiPrinter.printText(
            desc,
            style: SunmiTextStyle(align: _getAlign(kAlign), fontSize: kFontSize.clamp(1, 96).toInt()),
          );

          if (di.item.description != null && di.item.description!.isNotEmpty) {
            await SunmiPrinter.printText(
              '  * ${di.item.description}',
              style: SunmiTextStyle(align: _getAlign(kAlign), fontSize: kFontSize.clamp(1, 96).toInt()),
            );
          }
        }
        await _printSunmiNewLine(5);
      }
    } else {
      List<int> bytes = [];
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      bytes += generator.reset();

      for (var order in foodOrders) {
        final orderItems = displayItems.where((di) => di.item.food_order_ID == order.id).toList();
        if (orderItems.isEmpty) continue;

        for (var dt in templates) {
          final imageToPrint = await _textToImage(
            order.number?.toString() ?? '',
            dt.fontSize ?? 24,
            dt.alignment,
            isBold: true,
          );
          bytes += generator.imageRaster(imageToPrint);
        }
        for (var di in orderItems) {
          String desc = '${di.item.quantity ?? 0}x ${di.kitchenItemName}';
          if (di.kitchenSizeName.isNotEmpty) desc += ' ${di.kitchenSizeName}';
          if (di.kitchenChoiceName.isNotEmpty) desc += ' ${di.kitchenChoiceName}';

          final imageToPrint = await _textToImage(desc, kFontSize, kAlign);
          bytes += generator.imageRaster(imageToPrint);

          if (di.item.description != null && di.item.description!.isNotEmpty) {
            final descImage = await _textToImage('  * ${di.item.description}', kFontSize, kAlign);
            bytes += generator.imageRaster(descImage);
          }
        }
        bytes += generator.feed(2);
      }
      bytes += generator.cut();
      await _executePrint(bytes, config);
    }

    await isar.writeTxn(() async {
      for (var order in foodOrders) {
        order.status = 'KitchenPrinted';
        order.lastUpdated = DateTime.now().toIso8601String();
        await isar.foodOrderList.put(order);
      }
    });
  }

  static Future<void> _executePrint(List<int> bytes, EnvConfig config) async {
    await Future.delayed(const Duration(milliseconds: 500)); 

    if (config.ConnectType == 'LAN') {
      try {
        final ip = config.PrinterAddress ?? '';
        if (ip.isNotEmpty) {
          Socket socket = await Socket.connect(ip, 9100, timeout: const Duration(seconds: 5));
          socket.add(bytes);
          await socket.flush();
          await socket.close();
        }
      } catch (e) {
        debugPrint("Error printing via LAN: $e");
      }
    } else if (config.ConnectType == 'USB') {
      try {
        FlutterUsbPrinter flutterUsbPrinter = FlutterUsbPrinter();
        final address = config.PrinterAddress ?? '';
        if (address.isNotEmpty) {
          List<Map<String, dynamic>> results = await FlutterUsbPrinter.getUSBDeviceList();
          for (var device in results) {
            if (device['vendorId'] == address || device['vendorId'].toString() == address) {
              await flutterUsbPrinter.connect(int.parse(device['vendorId']), int.parse(device['productId']));
              await flutterUsbPrinter.write(Uint8List.fromList(bytes));
              await flutterUsbPrinter.close();
              break;
            }
          }
        }
      } catch (e) {
        debugPrint("Error printing via USB: $e");
      }
    }
  }

  static Future<void> printPaymentInfo({
    required Isar isar,
    required EnvConfig config,
    required Receipt? receipt,
    required List<PaymentValue> mtValues,
    required bool isThai,
  }) async {
    if (receipt == null) return;
    await SyncService.syncReceipt(config);

    String orderNo = '';
    try {
      final foodOrders = await isar.foodOrderList
          .where()
          .filter()
          .parentIDEqualTo(receipt.id)
          .and()
          .parentTypeEqualTo('receipt')
          .findAll();
      if (foodOrders.isNotEmpty) {
        orderNo = foodOrders.map((e) => e.number?.toString() ?? '').where((e) => e.isNotEmpty).join(', ');
      }
    } catch (e) {
      debugPrint(e.toString());
    }

    List<String> requiredParams = ["MT_BANK_CODE", "MT_ACCOUNT_NAME", "MT_ACCOUNT_NUMBER", "MT_THAI_MEDIA"];
    List<PaymentValue> displayValues = mtValues.where((pv) => requiredParams.contains(pv.payment_parameter_ID)).toList();

    String qrUrl = '${config.foodUrl ?? ''}inform-payment/receipt/${receipt.id ?? ''}';

    if (config.PrinterModel == 'Sunmi V series') {
      if (orderNo.isNotEmpty) {
        await SunmiPrinter.printText(orderNo, style: SunmiTextStyle(align: SunmiPrintAlign.CENTER, fontSize: 50, bold: true));
        await _printSunmiNewLine(1);
      }
      await SunmiPrinter.printText(isThai ? 'กรุณาโอนเงิน' : 'Please transfer', style: SunmiTextStyle(align: SunmiPrintAlign.CENTER, fontSize: 20));
      await SunmiPrinter.printText((receipt.totalAmount ?? 0.0).toStringAsFixed(2), style: SunmiTextStyle(align: SunmiPrintAlign.CENTER, fontSize: 50, bold: true));
      await SunmiPrinter.printText(isThai ? 'บาท เข้าบัญชีธนาคาร' : 'Baht to bank account', style: SunmiTextStyle(align: SunmiPrintAlign.CENTER, fontSize: 20));
      await _printSunmiNewLine(1);

      for (var pv in displayValues) {
        if (pv.type == 'T') {
          await SunmiPrinter.printText('${pv.name} : ${pv.value}', style: SunmiTextStyle(align: SunmiPrintAlign.CENTER, fontSize: 24));
        } else if (pv.type == 'P') {
          Uint8List? imgBytes;
          if (pv.localPicture != null && pv.localPicture!.isNotEmpty && File(pv.localPicture!).existsSync()) {
            imgBytes = await File(pv.localPicture!).readAsBytes();
          } else if (pv.value != null && pv.value!.isNotEmpty) {
            try {
              final resp = await http.get(Uri.parse(config.apiUrl + pv.value!));
              if (resp.statusCode == 200) imgBytes = resp.bodyBytes;
            } catch (e) {
              debugPrint("Error downloading image: $e");
            }
          }
          if (imgBytes != null) {
            try {
              img.Image? decodedImage = img.decodeImage(imgBytes);
              if (decodedImage != null) {
                img.Image resized = img.copyResize(decodedImage, width: 384);
                imgBytes = Uint8List.fromList(img.encodeJpg(resized));
              }
              await _printSunmiNewLine(1);
              await SunmiPrinter.printImage(imgBytes);
            } catch (e) {
              debugPrint("Print Image Error: $e");
            }
          }
        }
      }
      await _printSunmiNewLine(1);
      await SunmiPrinter.printText(isThai ? 'เสร็จแล้ว แจ้งโอนเงิน โดยสแกน QR code' : 'After transfer, notify via QR code', style: SunmiTextStyle(align: SunmiPrintAlign.CENTER, fontSize: 20));
      await _printSunmiNewLine(1);
      await SunmiPrinter.printQRCode(qrUrl);
      await _printSunmiNewLine(3);
    } else {
      List<int> bytes = [];
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      bytes += generator.reset();

      if (orderNo.isNotEmpty) {
        final imageToPrint = await _textToImage(orderNo, 50, 'Center', isBold: true);
        bytes += generator.imageRaster(imageToPrint);
        bytes += generator.feed(1);
      }

      bytes += generator.imageRaster(await _textToImage(isThai ? 'กรุณาโอนเงิน' : 'Please transfer', 20, 'center'));
      bytes += generator.imageRaster(await _textToImage((receipt.totalAmount ?? 0.0).toStringAsFixed(2), 50, 'center', isBold: true));
      bytes += generator.imageRaster(await _textToImage(isThai ? 'บาท เข้าบัญชีธนาคาร' : 'Baht to bank account', 20, 'center'));
      bytes += generator.feed(1);

      for (var pv in displayValues) {
        if (pv.type == 'T') {
          bytes += generator.imageRaster(await _textToImage('${pv.name} : ${pv.value}', 24, 'center'));
        } else if (pv.type == 'P') {
          Uint8List? imgBytes;
          if (pv.localPicture != null && pv.localPicture!.isNotEmpty && File(pv.localPicture!).existsSync()) {
            imgBytes = await File(pv.localPicture!).readAsBytes();
          } else if (pv.value != null && pv.value!.isNotEmpty) {
            try {
              final resp = await http.get(Uri.parse(config.apiUrl + pv.value!));
              if (resp.statusCode == 200) imgBytes = resp.bodyBytes;
            } catch (e) {}
          }
          if (imgBytes != null) {
            final decodedImg = img.decodeImage(imgBytes);
            if (decodedImg != null) {
              bytes += generator.feed(1);
              final resized = img.copyResize(decodedImg, width: 400);
              bytes += generator.imageRaster(resized, align: PosAlign.center);
            }
          }
        }
      }
      bytes += generator.feed(1);
      bytes += generator.imageRaster(await _textToImage(isThai ? 'เสร็จแล้ว แจ้งโอนเงิน โดยสแกน QR code' : 'After transfer, notify via QR code', 20, 'center'));
      bytes += generator.feed(1);
      bytes += generator.qrcode(qrUrl);
      bytes += generator.feed(3);
      bytes += generator.cut();
      await _executePrint(bytes, config);
    }
  }

  static Future<void> printPromptPay({
    required Isar isar,
    required EnvConfig config,
    required Receipt? receipt,
    required String? ppQrBase64,
  }) async {
    if (ppQrBase64 == null || receipt == null) return;
    
    String orderNo = '';
    try {
      final foodOrders = await isar.foodOrderList
          .where()
          .filter()
          .parentIDEqualTo(receipt.id)
          .and()
          .parentTypeEqualTo('receipt')
          .findAll();
      if (foodOrders.isNotEmpty) {
        orderNo = foodOrders.first.number?.toString() ?? orderNo;
      }
    } catch (e) {
      debugPrint(e.toString());
    }

    Uint8List imgBytes = base64Decode(ppQrBase64);

    if (config.PrinterModel == 'Sunmi V series') {
      await SunmiPrinter.printText(orderNo, style: SunmiTextStyle(align: SunmiPrintAlign.CENTER, fontSize: 36, bold: true));
      await _printSunmiNewLine(1);
      await SunmiPrinter.printImage(imgBytes);
      await _printSunmiNewLine(5);
    } else {
      List<int> bytes = [];
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      bytes += generator.reset();

      final imageToPrint = await _textToImage(orderNo, 50, 'Center', isBold: true);
      bytes += generator.imageRaster(imageToPrint);
      bytes += generator.feed(1);

      final qrImage = await _qrToImage(imgBytes);
      bytes += generator.imageRaster(qrImage);

      bytes += generator.feed(2);
      bytes += generator.cut();
      await _executePrint(bytes, config);
    }
  }

  static String _replaceVariables(String template, EnvConfig config, [List<FoodOrder>? foodOrders, Receipt? receipt]) {
    String result = template;
    Map<String, String> configMap = {
      'shop_ID': config.shop_ID ?? '',
      'ShopName': config.ShopName ?? '',
      'shop_branch_ID': config.shop_branch_ID ?? '',
      'BranchName': config.BranchName ?? '',
      'Address': config.Address ?? '',
      'Telephone': config.Telephone ?? '',
      'language': config.language ?? '',
      'printerMacAddress': config.printerMacAddress ?? '',
      'UserID': config.UserID ?? '',
      'UserRole': config.UserRole ?? '',
      'PrinterModel': config.PrinterModel ?? '',
      'ConnectType': config.ConnectType ?? '',
      'PrinterAddress': config.PrinterAddress ?? '',
      'ExpireDate': config.ExpireDate ?? '',
      'LastUpdated': config.LastUpdated ?? '',
      'TaxID': config.TaxID ?? '',
      'PosID': config.PosID ?? '',
    };
    configMap.forEach((key, value) {
      result = result.replaceAll('[config.$key]', value);
    });

    if (receipt != null) {
      result = result.replaceAll('[Receipt.code]', receipt.code ?? '');
      
      if (receipt.createdAt != null) {
        DateTime dt = receipt.createdAt!.toLocal();
        String D = dt.day.toString().padLeft(2, '0');
        String M = dt.month.toString().padLeft(2, '0');
        String T = (dt.year + 543).toString();
        String E = dt.year.toString();
        String H = dt.hour.toString().padLeft(2, '0');
        String Min = dt.minute.toString().padLeft(2, '0');
        String S = dt.second.toString().padLeft(2, '0');

        result = result.replaceAll('[Receipt.DMT]', '$D/$M/$T');
        result = result.replaceAll('[Receipt.DME]', '$D/$M/$E');
        result = result.replaceAll('[Receipt.TMD]', '$T-$M-$D');
        result = result.replaceAll('[Receipt.EMD]', '$E-$M-$D');
        result = result.replaceAll('[Receipt.HMS]', '$H:$Min:$S');
        result = result.replaceAll('[Receipt.HM]', '$H:$Min');
      }
    }

    if (foodOrders != null && result.contains('[FoodOrder.Number]')) {
      final numbers = foodOrders.map((e) => e.number?.toString() ?? '').where((e) => e.isNotEmpty).join(', ');
      result = result.replaceAll('[FoodOrder.Number]', numbers);
    }
    return result;
  }

  static bool _shouldPrintTemplate(String text) {
    if (!text.contains('[')) return true;
    if (text.contains('[ReceiptItem]') || text.contains('[FoodOrder.Number]')) return true;

    final matches = RegExp(r'\[(.*?)\]').allMatches(text);
    for (final match in matches) {
      String inner = match.group(1) ?? '';
      if (!inner.startsWith('config.') && !inner.startsWith('Receipt.') && inner != 'ReceiptItem' && inner != 'FoodOrder.Number') {
        return false;
      }
    }
    return true;
  }

  static SunmiPrintAlign _getAlign(String? alignment) {
    if (alignment == null) return SunmiPrintAlign.LEFT;
    switch (alignment.toLowerCase()) {
      case 'center': return SunmiPrintAlign.CENTER;
      case 'right': return SunmiPrintAlign.RIGHT;
      case 'left': default: return SunmiPrintAlign.LEFT;
    }
  }

  static Future<img.Image> _textToImage(String text, int fontSize, String? alignment, {bool isBold = false}) async {
    TextAlign textAlign = TextAlign.left;
    if (alignment?.toLowerCase() == 'center') textAlign = TextAlign.center;
    else if (alignment?.toLowerCase() == 'right') textAlign = TextAlign.right;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(color: Colors.black, fontSize: fontSize.toDouble(), fontWeight: isBold ? FontWeight.bold : FontWeight.normal),
    );
    final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr, textAlign: textAlign);
    textPainter.layout(minWidth: 576, maxWidth: 576);

    final paint = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(0, 0, 576, textPainter.height), paint);
    textPainter.paint(canvas, const Offset(0, 0));

    final picture = recorder.endRecording();
    final uiImage = await picture.toImage(576, textPainter.height.toInt());
    final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
    return img.decodeImage(byteData!.buffer.asUint8List())!;
  }

  static Future<img.Image> _rowToImage(String leftText, String rightText, int fontSize, {bool isBold = false}) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final style = TextStyle(color: Colors.black, fontSize: fontSize.toDouble(), fontWeight: isBold ? FontWeight.bold : FontWeight.normal);

    final leftSpan = TextSpan(text: leftText, style: style);
    final leftPainter = TextPainter(text: leftSpan, textDirection: TextDirection.ltr, textAlign: TextAlign.left);
    leftPainter.layout(minWidth: 400, maxWidth: 400);

    final rightSpan = TextSpan(text: rightText, style: style);
    final rightPainter = TextPainter(text: rightSpan, textDirection: TextDirection.ltr, textAlign: TextAlign.right);
    rightPainter.layout(minWidth: 176, maxWidth: 176);

    double height = leftPainter.height > rightPainter.height ? leftPainter.height : rightPainter.height;
    final paint = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(0, 0, 576, height), paint);

    leftPainter.paint(canvas, const Offset(0, 0));
    rightPainter.paint(canvas, const Offset(400, 0));

    final picture = recorder.endRecording();
    final uiImage = await picture.toImage(576, height.toInt());
    final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
    return img.decodeImage(byteData!.buffer.asUint8List())!;
  }

  static Future<img.Image> _dividerImage() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = Colors.white;
    canvas.drawRect(const Rect.fromLTWH(0, 0, 576, 20), paint);
    final linePaint = Paint()..color = Colors.black..strokeWidth = 2;
    canvas.drawLine(const Offset(0, 10), const Offset(576, 10), linePaint);
    final picture = recorder.endRecording();
    final uiImage = await picture.toImage(576, 20);
    final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
    return img.decodeImage(byteData!.buffer.asUint8List())!;
  }

  static Future<img.Image> _qrToImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 320, targetHeight: 320);
    final frame = await codec.getNextFrame();
    final uiImage = frame.image;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final bgPaint = Paint()..color = Colors.white;
    canvas.drawRect(const Rect.fromLTWH(0, 0, 576, 320), bgPaint);
    canvas.drawImage(uiImage, const Offset(128, 0), Paint());

    final picture = recorder.endRecording();
    final finalImage = await picture.toImage(576, 320);
    final byteData = await finalImage.toByteData(format: ui.ImageByteFormat.png);
    return img.decodeImage(byteData!.buffer.asUint8List())!;
  }
}
