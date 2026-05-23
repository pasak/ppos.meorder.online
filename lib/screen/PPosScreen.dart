import 'dart:io';
import 'package:flutter/material.dart';

import 'package:meorder_ppos/lib/EnvConfig.dart';
import 'package:meorder_ppos/screen/FoodMenuScreen.dart';
import 'package:meorder_ppos/screen/ReceiptScreen.dart';
import 'package:isar/isar.dart';
import 'package:meorder_ppos/database/IsarModels.dart';
import 'package:meorder_ppos/screen/PaymentScreen.dart' show DisplayOrderItem;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:image/image.dart' as img;
import 'package:flutter_usb_printer/flutter_usb_printer.dart';
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

class PPosScreen extends StatefulWidget {
  final EnvConfig config;
  const PPosScreen({super.key, required this.config});

  @override
  State<PPosScreen> createState() => _PPosScreenState();
}

class _PPosScreenState extends State<PPosScreen> {

  bool _isExpired = false;
  Isar isar = Isar.getInstance()!;
  List<FoodOrder> activeOrders = [];
  Map<String, List<DisplayOrderItem>> orderItemsMap = {};
  bool isLoading = false;
  FlutterUsbPrinter flutterUsbPrinter = FlutterUsbPrinter();

  @override
  void initState() {
    super.initState();
    _checkExpiration();
    refreshFoodOrder();
  }

  void _checkExpiration() {
    if (widget.config.ExpireDate != null && widget.config.ExpireDate!.isNotEmpty) {
      try {
        DateTime expireDate = DateTime.parse(widget.config.ExpireDate!);
        if (DateTime.now().isAfter(expireDate)) {
          _isExpired = true;
        }
      } catch (e) {
        print("Error parsing ExpireDate: $e");
      }
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    Map<String, String> labels = getLabels(widget.config.language ?? 'th');

    return Scaffold(
      appBar: AppBar(
        title: const Text('PPOS'),
        actions: [
          if (!_isExpired) ...[
            IconButton(
              icon: const Icon(Icons.list),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ReceiptScreen(config: widget.config),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: refreshFoodOrder,
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => FoodMenuScreen(
                      config: widget.config,
                      shop_open_table_ID: '0',
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
      body: _isExpired 
        ? Center(
            child: Text(
              labels['ServiceExpirePlsPayFee'] ?? 'Service Expired Please Pay Fee',
              style: const TextStyle(fontSize: 20, color: Colors.red, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          )
        : isLoading 
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: refreshFoodOrder,
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: activeOrders.length,
                itemBuilder: (context, index) {
                  final fo = activeOrders[index];
                  final items = orderItemsMap[fo.id] ?? [];
                  
                  String prefix = fo.serveType == 'ServeTable' ? 'T' : 'H';
                  String titleText = '$prefix${fo.number ?? ''}';

                  return Card(
                    elevation: 3,
                    margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(titleText, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.print, color: Colors.blue),
                                    onPressed: () => rePrintCookingOrder(fo.id!),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.check, color: Colors.green),
                                    onPressed: () => servedOrder(fo.id!),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => cancelOrder(fo.id!),
                                  ),
                                ],
                              )
                            ],
                          ),
                          const Divider(),
                          ...items.map((di) {
                             String desc = '${di.item.quantity ?? 0}x ${di.itemName}';
                             if (di.sizeName.isNotEmpty) desc += ' ${di.sizeName}';
                             if (di.choiceName.isNotEmpty) desc += ' ${di.choiceName}';
                             return Padding(
                               padding: const EdgeInsets.symmetric(vertical: 4),
                               child: Text(desc, style: const TextStyle(fontSize: 16)),
                             );
                          }),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  Future<void> refreshFoodOrder() async {
    setState(() {
      isLoading = true;
    });

    try {
      DateTime now = DateTime.now();
      String todayStr = DateTime(now.year, now.month, now.day).toIso8601String();
      
      final orders = await isar.foodOrderList.where()
          .filter()
          .anyOf(['OrderFood', 'KitchenPrinted'], (q, String s) => q.statusEqualTo(s))
          .and()
          .createdAtGreaterThan(todayStr)
          .findAll();

      Map<String, List<DisplayOrderItem>> newItemsMap = {};

      for (var order in orders) {
        final items = await isar.foodOrderItemList.where()
            .filter()
            .food_order_IDEqualTo(order.id)
            .findAll();

        List<DisplayOrderItem> displayList = [];
        for (var item in items) {
          String itemName = '';
          String kitchenItemName = '';
          if (item.food_item_ID != null) {
            final foodItem = await isar.foodItemList.where()
                .filter()
                .idEqualTo(item.food_item_ID!)
                .findFirst();
            if (foodItem != null) {
              itemName = (widget.config.language == 'th') ? (foodItem.thaiName ?? '') : (foodItem.englishName ?? '');
              kitchenItemName = foodItem.kitchenName ?? itemName;
            }
          }

          String sizeName = '';
          String kitchenSizeName = '';
          if (item.food_size_ID != null && item.food_size_ID!.isNotEmpty) {
            final foodSize = await isar.foodSizeList.where()
                .filter()
                .idEqualTo(item.food_size_ID!)
                .findFirst();
            if (foodSize != null) {
              sizeName = (widget.config.language == 'th') ? (foodSize.thaiName ?? '') : (foodSize.englishName ?? '');
              kitchenSizeName = foodSize.kitchenName ?? sizeName;
            }
          }

          String choiceName = '';
          String kitchenChoiceName = '';
          if (item.choiceIDList != null && item.choiceIDList!.isNotEmpty) {
            List<String> choiceIDs = item.choiceIDList!.split(',');
            List<String> choiceNames = [];
            List<String> kitchenChoiceNames = [];
            for (var cID in choiceIDs) {
              if (cID.trim().isNotEmpty) {
                final choice = await isar.foodChoiceList.where()
                    .filter()
                    .idEqualTo(cID.trim())
                    .findFirst();
                if (choice != null) {
                  String cName = (widget.config.language == 'th') ? (choice.thaiName ?? '') : (choice.englishName ?? '');
                  choiceNames.add(cName);
                  kitchenChoiceNames.add(choice.kitchenName ?? cName);
                }
              }
            }
            choiceName = choiceNames.join(', ');
            kitchenChoiceName = kitchenChoiceNames.join(', ');
          }

          displayList.add(DisplayOrderItem(
            item: item,
            itemName: itemName,
            sizeName: sizeName,
            choiceName: choiceName,
            kitchenItemName: kitchenItemName,
            kitchenSizeName: kitchenSizeName,
            kitchenChoiceName: kitchenChoiceName,
          ));
        }
        newItemsMap[order.id!] = displayList;
      }

      setState(() {
        activeOrders = orders;
        orderItemsMap = newItemsMap;
      });
    } catch (e) {
      debugPrint("Error refreshFoodOrder: $e");
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void servedOrder(String id) async {
    final order = await isar.foodOrderList.where().filter().idEqualTo(id).findFirst();
    if (order != null) {
      await isar.writeTxn(() async {
        order.status = 'Served';
        order.lastUpdated = DateTime.now().toIso8601String();
        order.isDirty = true;
        await isar.foodOrderList.put(order);
      });
      refreshFoodOrder();
    }
  }

  void cancelOrder(String id) {
    showDialog(
      context: context,
      builder: (context) {
        bool isThai = widget.config.language == 'th';
        return AlertDialog(
          title: Text(isThai ? 'ยืนยันการยกเลิก' : 'Confirm Cancel'),
          content: Text(isThai ? 'คุณต้องการยกเลิกรายการนี้ใช่หรือไม่?' : 'Do you want to cancel this order?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(isThai ? 'ไม่' : 'No', style: const TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(context);
                final order = await isar.foodOrderList.where().filter().idEqualTo(id).findFirst();
                if (order != null) {
                  await isar.writeTxn(() async {
                    order.status = 'Cancel';
                    order.lastUpdated = DateTime.now().toIso8601String();
                    order.isDirty = true;
                    await isar.foodOrderList.put(order);

                    if (order.parentType == 'receipt' && order.parentID != null) {
                      final receipt = await isar.receiptList.where().filter().idEqualTo(order.parentID!).findFirst();
                      if (receipt != null) {
                        receipt.status = 'Cancel';
                        receipt.lastUpdated = DateTime.now().toIso8601String();
                        receipt.isDirty = true;
                        await isar.receiptList.put(receipt);
                      }
                    }
                  });
                  refreshFoodOrder();
                }
              },
              child: Text(isThai ? 'ใช่, ยกเลิก' : 'Yes, Cancel'),
            ),
          ],
        );
      }
    );
  }

  void rePrintCookingOrder(String id) async {
    final order = await isar.foodOrderList.where().filter().idEqualTo(id).findFirst();
    if (order != null) {
      await _printCookingOrder([order]);
    }
  }

  Future<void> _printCookingOrder(List<FoodOrder> foodOrders) async {
    final templates = await isar.documentTemplateList
        .where()
        .filter()
        .printTextContains('FoodOrder.Number')
        .findAll();

    if (widget.config.PrinterModel == 'Sunmi V series') {
      for (var order in foodOrders) {
        final orderItems = orderItemsMap[order.id] ?? [];
        if (orderItems.isEmpty) continue;

        for (var dt in templates) {
           await SunmiPrinter.printText(
             order.number?.toString() ?? '',
             style: SunmiTextStyle(align: _getAlign(dt.alignment), fontSize: dt.fontSize ?? 24, bold: true),
           );
        }
        for (var di in orderItems) {
           String desc = '${di.item.quantity ?? 0}x ${di.kitchenItemName}';
           if (di.kitchenSizeName.isNotEmpty) desc += ' ${di.kitchenSizeName}';
           if (di.kitchenChoiceName.isNotEmpty) desc += ' ${di.kitchenChoiceName}';
           
           double amount = (di.item.quantity ?? 0) * (di.item.itemPrice ?? 0.0);
           await SunmiPrinter.printRow(cols: [
             SunmiColumn(text: desc, width: 20, style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
             SunmiColumn(text: amount.toStringAsFixed(2), width: 10, style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
           ]);
        }
        await SunmiPrinter.lineWrap(2);
      }
    } else {
      List<int> bytes = [];
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      bytes += generator.reset();

      for (var order in foodOrders) {
        final orderItems = orderItemsMap[order.id] ?? [];
        if (orderItems.isEmpty) continue;

        for (var dt in templates) {
          final imageToPrint = await _textToImage(order.number?.toString() ?? '', dt.fontSize ?? 24, dt.alignment, isBold: true);
          bytes += generator.imageRaster(imageToPrint);
        }
        for (var di in orderItems) {
           String desc = '${di.item.quantity ?? 0}x ${di.kitchenItemName}';
           if (di.kitchenSizeName.isNotEmpty) desc += ' ${di.kitchenSizeName}';
           if (di.kitchenChoiceName.isNotEmpty) desc += ' ${di.kitchenChoiceName}';
           
           double amount = (di.item.quantity ?? 0) * (di.item.itemPrice ?? 0.0);
           final image = await _rowToImage(desc, amount.toStringAsFixed(2), 24);
           bytes += generator.imageRaster(image);
        }
        bytes += generator.imageRaster(await _dividerImage());
      }
      bytes += generator.cut();
      await _executePrint(bytes);
    }
  }

  Future<void> _executePrint(List<int> bytes) async {
    String address = widget.config.PrinterAddress ?? '';
    if (address.isEmpty) return;

    if (widget.config.ConnectType == 'LAN') {
      try {
        final socket = await Socket.connect(address, 9100, timeout: const Duration(seconds: 5));
        socket.add(bytes);
        await socket.flush();
        socket.destroy();
      } catch (e) {
        debugPrint("Error printing via LAN: $e");
      }
    } else if (widget.config.ConnectType == 'USB') {
      try {
        List<Map<String, dynamic>> results = await FlutterUsbPrinter.getUSBDeviceList();
        if (results.isNotEmpty) {
           for (var device in results) {
             if (device['vendorId'] == address || device['vendorId'].toString() == address) {
                await flutterUsbPrinter.connect(int.parse(device['vendorId'].toString()), int.parse(device['productId'].toString()));
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

  SunmiPrintAlign _getAlign(String? alignment) {
    if (alignment == null) return SunmiPrintAlign.LEFT;
    switch (alignment.toLowerCase()) {
      case 'center': return SunmiPrintAlign.CENTER;
      case 'right': return SunmiPrintAlign.RIGHT;
      case 'left':
      default: return SunmiPrintAlign.LEFT;
    }
  }

  Future<img.Image> _textToImage(String text, int fontSize, String? alignment, {bool isBold = false}) async {
    TextAlign textAlign = TextAlign.left;
    if (alignment?.toLowerCase() == 'center') {
      textAlign = TextAlign.center;
    } else if (alignment?.toLowerCase() == 'right') {
      textAlign = TextAlign.right;
    }

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

  Future<img.Image> _rowToImage(String leftText, String rightText, int fontSize, {bool isBold = false}) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final style = TextStyle(color: Colors.black, fontSize: fontSize.toDouble(), fontWeight: isBold ? FontWeight.bold : FontWeight.normal);
    
    final leftSpan = TextSpan(text: leftText, style: style);
    final leftPainter = TextPainter(text: leftSpan, textDirection: TextDirection.ltr, textAlign: TextAlign.left);
    leftPainter.layout(minWidth: 400, maxWidth: 400); 

    final rightSpan = TextSpan(text: rightText, style: style);
    final rightPainter = TextPainter(text: rightSpan, textDirection: TextDirection.ltr, textAlign: TextAlign.right);
    rightPainter.layout(minWidth: 176, maxWidth: 176); 
    
    double maxHeight = leftPainter.height > rightPainter.height ? leftPainter.height : rightPainter.height;

    final paint = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(0, 0, 576, maxHeight), paint);
    
    leftPainter.paint(canvas, const Offset(0, 0));
    rightPainter.paint(canvas, Offset(400, 0));
    
    final picture = recorder.endRecording();
    final uiImage = await picture.toImage(576, maxHeight.toInt());
    final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
    return img.decodeImage(byteData!.buffer.asUint8List())!;
  }

  Future<img.Image> _dividerImage() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = Colors.white;
    canvas.drawRect(const Rect.fromLTWH(0, 0, 576, 30), paint);
    
    final textSpan = const TextSpan(text: '------------------------------------------------', style: TextStyle(color: Colors.black, fontSize: 24));
    final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr, textAlign: TextAlign.center);
    textPainter.layout(minWidth: 576, maxWidth: 576);
    textPainter.paint(canvas, const Offset(0, 0));
    
    final picture = recorder.endRecording();
    final uiImage = await picture.toImage(576, 30);
    final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
    return img.decodeImage(byteData!.buffer.asUint8List())!;
  }
}

Map<String, String> getLabels(String langCode) {
  if (langCode == 'th') {
    return {
      'ServiceExpirePlsPayFee': 'บริการหมดอายุ กรุณาชำระค่าบริการ',
    };
  } else { // langCode == 'en'
    return {
      'ServiceExpirePlsPayFee': 'Service Expired Please Pay Fee',
    };
  }
}
