import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:meorder_ppos/lib/EnvConfig.dart';
import 'package:meorder_ppos/database/IsarModels.dart';
import 'package:meorder_ppos/screen/PPosScreen.dart';
import 'package:meorder_ppos/screen/FoodMenuScreen.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:image/image.dart' as img;
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';
import 'package:flutter_usb_printer/flutter_usb_printer.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

class DisplayOrderItem {
  final FoodOrderItem item;
  final String itemName;
  final String sizeName;
  final String choiceName;
  final String kitchenItemName;
  final String kitchenSizeName;
  final String kitchenChoiceName;

  DisplayOrderItem({
    required this.item,
    required this.itemName,
    required this.sizeName,
    required this.choiceName,
    required this.kitchenItemName,
    required this.kitchenSizeName,
    required this.kitchenChoiceName,
  });
}

class PaymentScreen extends StatefulWidget {
  final EnvConfig config;
  final String receiptID;

  const PaymentScreen({
    super.key,
    required this.config,
    required this.receiptID,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  late Isar isar;
  bool isLoading = true;

  Receipt? receipt;
  List<DisplayOrderItem> displayItems = [];

  String selectedMethod = 'Cash';
  double receiveAmount = 0.0;
  double changeAmount = 0.0;
  double tipAmount = 0.0;

  final TextEditingController receiveAmountController = TextEditingController(text: '0');
  final TextEditingController changeAmountController = TextEditingController(text: '0');
  final TextEditingController tipAmountController = TextEditingController(text: '0');

  bool get isThai => widget.config.language == 'th';

  @override
  void initState() {
    super.initState();
    isar = Isar.getInstance()!;
    _loadData();
  }

  @override
  void dispose() {
    receiveAmountController.dispose();
    changeAmountController.dispose();
    tipAmountController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      receipt = await isar.receiptList.where().filter().idEqualTo(widget.receiptID).findFirst();

      if (receipt != null) {
        final foodOrders = await isar.foodOrderList.where()
            .filter()
            .parentIDEqualTo(receipt!.id)
            .and()
            .parentTypeEqualTo('receipt')
            .findAll();

        List<DisplayOrderItem> tempDisplayItems = [];

        for (var order in foodOrders) {
          final items = await isar.foodOrderItemList.where()
              .filter()
              .food_order_IDEqualTo(order.id)
              .findAll();

          for (var item in items) {
            String itemName = '';
            String kitchenItemName = '';
            if (item.food_item_ID != null) {
              final foodItem = await isar.foodItemList.where()
                  .filter()
                  .idEqualTo(item.food_item_ID!)
                  .findFirst();
              if (foodItem != null) {
                itemName = isThai ? (foodItem.thaiName ?? '') : (foodItem.englishName ?? '');
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
                sizeName = isThai ? (foodSize.thaiName ?? '') : (foodSize.englishName ?? '');
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
                     choiceNames.add(isThai ? (choice.thaiName ?? '') : (choice.englishName ?? ''));
                     kitchenChoiceNames.add(choice.kitchenName ?? (isThai ? (choice.thaiName ?? '') : (choice.englishName ?? '')));
                  }
                }
              }
              choiceName = choiceNames.join(', ');
              kitchenChoiceName = kitchenChoiceNames.join(', ');
            }

            tempDisplayItems.add(DisplayOrderItem(
              item: item,
              itemName: itemName,
              sizeName: sizeName,
              choiceName: choiceName,
              kitchenItemName: kitchenItemName,
              kitchenSizeName: kitchenSizeName,
              kitchenChoiceName: kitchenChoiceName,
            ));
          }
        }
        
        displayItems = tempDisplayItems;
      }
    } catch (e) {
      debugPrint("Error loading PaymentScreen data: $e");
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  void _handleAmount(String _) {
    double rAmount = double.tryParse(receiveAmountController.text) ?? 0.0;
    double tAmount = double.tryParse(tipAmountController.text) ?? 0.0;
    double total = receipt?.totalAmount ?? 0.0;
    
    double change = rAmount - total - tAmount;
    
    setState(() {
      receiveAmount = rAmount;
      tipAmount = tAmount;
      changeAmount = change;
      changeAmountController.text = change.toStringAsFixed(2);
    });
  }

  void _change2Tip() {
    setState(() {
      tipAmount += changeAmount;
      changeAmount = 0.0;
      tipAmountController.text = tipAmount.toStringAsFixed(2);
      changeAmountController.text = changeAmount.toStringAsFixed(2);
    });
  }

  void _addAmount(double amount) {
    setState(() {
      receiveAmount += amount;
      receiveAmountController.text = receiveAmount.toStringAsFixed(0);
    });
    _handleAmount('');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => FoodMenuScreen(
              config: widget.config,
              receiptID: widget.receiptID,
            ),
          ),
        );
      },
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          title: Text(isThai ? 'ชำระเงิน' : 'Payment'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => FoodMenuScreen(
                    config: widget.config,
                    receiptID: widget.receiptID,
                  ),
                ),
              );
            },
          ),
        ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSection1(),
                    const SizedBox(height: 24),
                    _buildSection2(),
                    const SizedBox(height: 24),
                    if (selectedMethod == 'Cash') _buildSection3(),
                  ],
                ),
              ),
            ),
      ),
    );
  }

  Widget _buildSection1() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isThai ? 'รายละเอียดสินค้า' : 'Order Details',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...displayItems.map((di) {
              String desc = '${di.item.quantity ?? 0}x ${di.itemName}';
              if (di.sizeName.isNotEmpty) desc += ' ${di.sizeName}';
              if (di.choiceName.isNotEmpty) desc += ' ${di.choiceName}';
              
              double amount = (di.item.quantity ?? 0) * (di.item.itemPrice ?? 0.0);

              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(desc, style: const TextStyle(fontSize: 16)),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        amount.toStringAsFixed(2),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 16),
            const Divider(thickness: 1, color: Colors.black26),
            const SizedBox(height: 16),
            Text(
              isThai ? 'รายละเอียดการชำระเงิน' : 'Payment Details',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildAmountRow(
              isThai ? 'ยอดรวม' : 'Subtotal',
              receipt?.sumAmount ?? 0.0,
              isBold: false,
            ),
            const SizedBox(height: 8),
            _buildAmountRow(
              isThai ? 'ส่วนลด' : 'Discount',
              receipt?.discountAmount ?? 0.0,
              isBold: false,
            ),
            const SizedBox(height: 8),
            _buildAmountRow(
              isThai ? 'ยอดรวมทั้งหมด' : 'Total Amount',
              receipt?.totalAmount ?? 0.0,
              isBold: true,
              fontSize: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountRow(String label, double amount, {bool isBold = false, double fontSize = 16}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          amount.toStringAsFixed(2),
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildSection2() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildMethodButton(
                    'Cash',
                    isThai ? 'เงินสด' : 'Cash',
                    isEnabled: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMethodButton(
                    'Transfer',
                    isThai ? 'โอน' : 'Transfer',
                    isEnabled: false,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMethodButton(
                    'Online',
                    isThai ? 'ออนไลน์' : 'Online',
                    isEnabled: false,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  (receipt?.totalAmount ?? 0.0).toStringAsFixed(2),
                  style: const TextStyle(
                    fontSize: 50,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMethodButton(String methodId, String label, {required bool isEnabled}) {
    bool isSelected = selectedMethod == methodId;
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? Colors.blue : (isEnabled ? Colors.grey[200] : Colors.grey[100]),
        foregroundColor: isSelected ? Colors.white : (isEnabled ? Colors.black87 : Colors.black38),
        elevation: isSelected ? 2 : 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: isEnabled
          ? () {
              setState(() {
                selectedMethod = methodId;
              });
            }
          : null,
      child: Text(label),
    );
  }

  Widget _buildSection3() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: receiveAmountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: _handleAmount,
                    decoration: InputDecoration(
                      labelText: isThai ? 'จำนวนเงินที่ได้รับ' : 'Receive Amount',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: changeAmountController,
                    readOnly: true,
                    style: TextStyle(
                      color: changeAmount < 0 ? Colors.red : Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      labelText: isThai ? 'จำนวนเงินทอน' : 'Change Amount',
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: tipAmountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: _handleAmount,
                    decoration: InputDecoration(
                      labelText: isThai ? 'จำนวนเงินทิป' : 'Tip Amount',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: changeAmount > 0 ? _change2Tip : null,
                    child: Text(isThai ? 'ไม่รับเงินทอน ให้เป็นทิป' : 'Change to Tip'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildBanknoteButton(10),
                _buildBanknoteButton(20),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildBanknoteButton(50),
                _buildBanknoteButton(100),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildBanknoteButton(500),
                _buildBanknoteButton(1000),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _processPayment,
                child: Text(
                  isThai ? 'เก็บเงิน' : 'Pay',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBanknoteButton(double value) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue[50],
            foregroundColor: Colors.blue[900],
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.blue[200]!),
            ),
          ),
          onPressed: () => _addAmount(value),
          child: Text('${value.toStringAsFixed(0)}'),
        ),
      ),
    );
  }

  void _processPayment() async {
    if (receipt == null) return;
    
    receipt!.paidAmount = (receipt!.totalAmount ?? 0.0) + tipAmount;
    receipt!.status = 'Paid';
    receipt!.paymentType = 'Cash'; 
    
    final foodOrders = await isar.foodOrderList.where()
        .filter()
        .parentIDEqualTo(receipt!.id)
        .and()
        .parentTypeEqualTo('receipt')
        .findAll();

    await isar.writeTxn(() async {
      await isar.receiptList.put(receipt!);
      for (var order in foodOrders) {
        order.status = 'OrderFood';
        await isar.foodOrderList.put(order);
      }
    });

    final settings = await isar.settingValueList.where()
      .filter()
      .anyOf(['FOC_PRN_RCP_CSH', 'FOC_PRN_COK', 'FOC_PAUSE_PRN_COK'], (q, String id) => q.setting_IDEqualTo(id))
      .findAll();

    Map<String, bool> settingValue = {
      'FOC_PRN_RCP_CSH': true, 
      'FOC_PRN_COK': true, 
      'FOC_PAUSE_PRN_COK': false
    };

    for (var sv in settings) {
      if (sv.setting_ID != null) {
        settingValue[sv.setting_ID!] = (sv.value == 'Y');
      }
    }

    if (widget.config.PrinterModel == 'Xprinter N160ii') {
      settingValue['FOC_PAUSE_PRN_COK'] = false;
    }

    if (settingValue['FOC_PRN_RCP_CSH'] == true) {
      await _printReceipt(foodOrders);
    }

    if (settingValue['FOC_PRN_COK'] == true) {
      if (settingValue['FOC_PAUSE_PRN_COK'] == true) {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return AlertDialog(
              content: Text(isThai ? 'ฉีกใบเสร็จรับเงินให้ลูกค้า แล้วกดปุ่มเพื่อพิมพ์ใบสั่งอาหาร' : 'Tear off the receipt and press to print cooking order.'),
              actions: [
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _printCookingOrder(foodOrders);
                    _navigateBack();
                  },
                  child: Text(isThai ? 'พิมพ์ใบสั่งอาหาร' : 'Print Cooking Order'),
                )
              ],
            );
          }
        );
        return; 
      } else {
        await _printCookingOrder(foodOrders);
      }
    }

    _navigateBack();
  }

  void _navigateBack() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => PPosScreen(config: widget.config)),
      (route) => false,
    );
  }

  Future<void> _printReceipt(List<FoodOrder> foodOrders) async {
    final templates = await isar.documentTemplateList
        .where()
        .filter()
        .isActiveEqualTo('Y')
        .sortBySeq()
        .findAll();
    
    if (widget.config.PrinterModel == 'Sunmi V series') {
      for (var dt in templates) {
        String rawText = dt.printText ?? '';
        if (!_shouldPrintTemplate(rawText)) continue;
        
        if (rawText.contains('[ReceiptItem]')) {
          await SunmiPrinter.lineWrap(2);
          await _printReceiptItemsSunmi();
          await SunmiPrinter.lineWrap(2);
        } else {
          String textToPrint = _replaceVariables(rawText, widget.config, foodOrders);
          if (textToPrint.isNotEmpty) {
            await SunmiPrinter.printText(
              textToPrint,
              style: SunmiTextStyle(align: _getAlign(dt.alignment), fontSize: dt.fontSize ?? 24),
            );
          }
        }
      }
      await SunmiPrinter.lineWrap(2); 
    } else {
      List<int> bytes = [];
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      bytes += generator.reset();

      for (var dt in templates) {
        String rawText = dt.printText ?? '';
        if (!_shouldPrintTemplate(rawText)) continue;
        
        if (rawText.contains('[ReceiptItem]')) {
          bytes += generator.feed(2);
          for (var di in displayItems) {
            String desc = '${di.item.quantity ?? 0}x ${di.itemName}';
            if (di.sizeName.isNotEmpty) desc += ' ${di.sizeName}';
            if (di.choiceName.isNotEmpty) desc += ' ${di.choiceName}';
            double amount = (di.item.quantity ?? 0) * (di.item.itemPrice ?? 0.0);
            
            final image = await _rowToImage(desc, amount.toStringAsFixed(2), 24);
            bytes += generator.imageRaster(image);
          }
          bytes += generator.imageRaster(await _dividerImage());
          
          bytes += generator.imageRaster(await _rowToImage(isThai ? 'ยอดรวม' : 'Sum Amount', (receipt?.sumAmount ?? 0.0).toStringAsFixed(2), 24));
          bytes += generator.imageRaster(await _rowToImage(isThai ? 'ส่วนลด' : 'Discount', (receipt?.discountAmount ?? 0.0).toStringAsFixed(2), 24));
          bytes += generator.imageRaster(await _rowToImage(isThai ? 'ยอดรวมทั้งหมด' : 'Total Amount', (receipt?.totalAmount ?? 0.0).toStringAsFixed(2), 28, isBold: true));
          
          bytes += generator.imageRaster(await _dividerImage());
          String pt = (receipt?.paymentType == 'Cash') ? (isThai ? 'เงินสด' : 'Cash') : (receipt?.paymentType ?? '');
          bytes += generator.imageRaster(await _rowToImage(pt, (receipt?.paidAmount ?? 0.0).toStringAsFixed(2), 24));
          bytes += generator.feed(2);
        } else {
          String textToPrint = _replaceVariables(rawText, widget.config, foodOrders);
          if (textToPrint.isNotEmpty) {
            final imageToPrint = await _textToImage(textToPrint, dt.fontSize ?? 24, dt.alignment);
            bytes += generator.imageRaster(imageToPrint);
          }
        }
      }
      bytes += generator.feed(2);
      bytes += generator.cut();
      await _executePrint(bytes);
    }
  }

  Future<void> _printReceiptItemsSunmi() async {
    for (var di in displayItems) {
       String desc = '${di.item.quantity ?? 0}x ${di.itemName}';
       if (di.sizeName.isNotEmpty) desc += ' ${di.sizeName}';
       if (di.choiceName.isNotEmpty) desc += ' ${di.choiceName}';
       
       double amount = (di.item.quantity ?? 0) * (di.item.itemPrice ?? 0.0);
       await SunmiPrinter.printRow(cols: [
         SunmiColumn(text: desc, width: 20, style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
         SunmiColumn(text: amount.toStringAsFixed(2), width: 10, style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
       ]);
    }
    await SunmiPrinter.line();
    await SunmiPrinter.printRow(cols: [
      SunmiColumn(text: isThai ? 'ยอดรวม' : 'Sum Amount', width: 20, style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
      SunmiColumn(text: (receipt?.sumAmount ?? 0.0).toStringAsFixed(2), width: 10, style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
    ]);
    await SunmiPrinter.printRow(cols: [
      SunmiColumn(text: isThai ? 'ส่วนลด' : 'Discount', width: 20, style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
      SunmiColumn(text: (receipt?.discountAmount ?? 0.0).toStringAsFixed(2), width: 10, style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
    ]);
    await SunmiPrinter.printRow(cols: [
      SunmiColumn(text: isThai ? 'ยอดรวมทั้งหมด' : 'Total Amount', width: 15, style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
      SunmiColumn(text: (receipt?.totalAmount ?? 0.0).toStringAsFixed(2), width: 15, style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
    ]);
    await SunmiPrinter.line();
    
    String pt = (receipt?.paymentType == 'Cash') ? (isThai ? 'เงินสด' : 'Cash') : (receipt?.paymentType ?? '');
    await SunmiPrinter.printRow(cols: [
      SunmiColumn(text: pt, width: 15, style: SunmiTextStyle(align: SunmiPrintAlign.LEFT)),
      SunmiColumn(text: (receipt?.paidAmount ?? 0.0).toStringAsFixed(2), width: 15, style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT)),
    ]);
  }

  Future<void> _printCookingOrder(List<FoodOrder> foodOrders) async {
    final templates = await isar.documentTemplateList
        .where()
        .filter()
        .printTextContains('FoodOrder.Number')
        .findAll();

    if (widget.config.PrinterModel == 'Sunmi V series') {
      for (var order in foodOrders) {
        final orderItems = displayItems.where((di) => di.item.food_order_ID == order.id).toList();
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
        final orderItems = displayItems.where((di) => di.item.food_order_ID == order.id).toList();
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
        bytes += generator.feed(2);
      }
      bytes += generator.cut();
      await _executePrint(bytes);
    }
  }

  Future<void> _executePrint(List<int> bytes) async {
    if (widget.config.ConnectType == 'LAN') {
      try {
        final ip = widget.config.PrinterAddress ?? '';
        if (ip.isNotEmpty) {
          Socket socket = await Socket.connect(ip, 9100, timeout: const Duration(seconds: 5));
          socket.add(bytes);
          await socket.flush();
          await socket.close();
        }
      } catch (e) {
        debugPrint("Error printing via LAN: $e");
      }
    } else if (widget.config.ConnectType == 'USB') {
      try {
        FlutterUsbPrinter flutterUsbPrinter = FlutterUsbPrinter();
        // Here we assume the device is already matched or we connect if we stored vendorId 
        // For simplicity, attempt connection if config stores printerMacAddress or PrinterAddress
        // In SetPrinterScreen, vendorId is saved to PrinterAddress for USB
        final address = widget.config.PrinterAddress ?? '';
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

  String _replaceVariables(String template, EnvConfig config, [List<FoodOrder>? foodOrders]) {
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
    };
    configMap.forEach((key, value) {
      result = result.replaceAll('[config.$key]', value);
    });
    
    if (foodOrders != null && result.contains('[FoodOrder.Number]')) {
      final numbers = foodOrders.map((e) => e.number?.toString() ?? '').where((e) => e.isNotEmpty).join(', ');
      result = result.replaceAll('[FoodOrder.Number]', numbers);
    }
    
    return result;
  }

  bool _shouldPrintTemplate(String text) {
    if (!text.contains('[')) return true;
    if (text.contains('[ReceiptItem]') || text.contains('[FoodOrder.Number]')) return true;
    
    final matches = RegExp(r'\[(.*?)\]').allMatches(text);
    for (final match in matches) {
      String inner = match.group(1) ?? '';
      if (!inner.startsWith('config.') && inner != 'ReceiptItem' && inner != 'FoodOrder.Number') {
        return false;
      }
    }
    return true;
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

  Future<img.Image> _dividerImage() async {
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
}
