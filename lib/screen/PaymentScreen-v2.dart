import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:meorder_ppos/lib/EnvConfig.dart';
import 'package:meorder_ppos/database/IsarModels.dart';
import 'package:meorder_ppos/screen/FoodMenuScreen.dart';
import 'package:meorder_ppos/screen/ReceiptScreen.dart';
import 'package:meorder_ppos/screen/PPosScreen.dart';
import 'package:meorder_ppos/services/SyncService.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';
import 'package:flutter_usb_printer/flutter_usb_printer.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

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
  bool hasMT = false;
  bool hasPP = false;
  bool hasOnline = false;
  List<PaymentValue> mtValues = [];
  List<PaymentValue> ppValues = [];
  String? _ppQrBase64;
  bool _isGeneratingPP = false;

  String selectedMethod = 'Cash';
  String _debugText = '';
  bool isDebug = false;
  double receiveAmount = 0.0;
  double changeAmount = 0.0;
  double tipAmount = 0.0;

  final TextEditingController receiveAmountController = TextEditingController(
    text: '0',
  );
  final TextEditingController changeAmountController = TextEditingController(
    text: '0',
  );
  final TextEditingController tipAmountController = TextEditingController(
    text: '0',
  );

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
      receipt = await isar.receiptList
          .where()
          .filter()
          .idEqualTo(widget.receiptID)
          .findFirst();

      if (receipt != null) {
        final foodOrders = await isar.foodOrderList
            .where()
            .filter()
            .parentIDEqualTo(receipt!.id)
            .and()
            .parentTypeEqualTo('receipt')
            .findAll();

        List<DisplayOrderItem> tempDisplayItems = [];

        for (var order in foodOrders) {
          final items = await isar.foodOrderItemList
              .where()
              .filter()
              .food_order_IDEqualTo(order.id)
              .findAll();

          for (var item in items) {
            String itemName = '';
            String kitchenItemName = '';
            if (item.food_item_ID != null) {
              final foodItem = await isar.foodItemList
                  .where()
                  .filter()
                  .idEqualTo(item.food_item_ID!)
                  .findFirst();
              if (foodItem != null) {
                itemName = isThai
                    ? (foodItem.thaiName ?? '')
                    : (foodItem.englishName ?? '');
                kitchenItemName = foodItem.kitchenName ?? itemName;
              }
            }

            String sizeName = '';
            String kitchenSizeName = '';
            if (item.food_size_ID != null && item.food_size_ID!.isNotEmpty) {
              final foodSize = await isar.foodSizeList
                  .where()
                  .filter()
                  .idEqualTo(item.food_size_ID!)
                  .findFirst();
              if (foodSize != null) {
                sizeName = isThai
                    ? (foodSize.thaiName ?? '')
                    : (foodSize.englishName ?? '');
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
                  final choice = await isar.foodChoiceList
                      .where()
                      .filter()
                      .idEqualTo(cID.trim())
                      .findFirst();
                  if (choice != null) {
                    choiceNames.add(
                      isThai
                          ? (choice.thaiName ?? '')
                          : (choice.englishName ?? ''),
                    );
                    kitchenChoiceNames.add(
                      choice.kitchenName ??
                          (isThai
                              ? (choice.thaiName ?? '')
                              : (choice.englishName ?? '')),
                    );
                  }
                }
              }
              choiceName = choiceNames.join(', ');
              kitchenChoiceName = kitchenChoiceNames.join(', ');
            }

            tempDisplayItems.add(
              DisplayOrderItem(
                item: item,
                itemName: itemName,
                sizeName: sizeName,
                choiceName: choiceName,
                kitchenItemName: kitchenItemName,
                kitchenSizeName: kitchenSizeName,
                kitchenChoiceName: kitchenChoiceName,
              ),
            );
          }
        }

        displayItems = tempDisplayItems;

        final mtPayment = await isar.paymentList
            .where()
            .filter()
            .payment_channel_IDEqualTo('MT')
            .isActiveEqualTo('Y')
            .findFirst();
        if (mtPayment != null) {
          hasMT = true;
          mtValues = await isar.paymentValueList
              .where()
              .filter()
              .payment_IDEqualTo(mtPayment.id!)
              .findAll();
        }

        final ppPayment = await isar.paymentList
            .where()
            .filter()
            .payment_channel_IDEqualTo('PP')
            .isActiveEqualTo('Y')
            .findFirst();
        if (ppPayment != null) {
          hasPP = true;
          ppValues = await isar.paymentValueList
              .where()
              .filter()
              .payment_IDEqualTo(ppPayment.id!)
              .findAll();
        }

        final onlinePayment = await isar.paymentList
            .where()
            .filter()
            .payment_channel_IDEqualTo('ONLINE')
            .isActiveEqualTo('Y')
            .findFirst();
        if (onlinePayment != null) {
          hasOnline = true;
        }
      }
    } catch (e) {
      debugPrint("Error loading PaymentScreen data: $e");
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> syncReceipt() async {
    await SyncService.syncReceipt(widget.config);
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
          actions: [
            IconButton(
              icon: const Icon(Icons.list),
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ReceiptScreen(config: widget.config),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        FoodMenuScreen(config: widget.config, receiptID: null),
                  ),
                );
              },
            ),
          ],
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
                      if (selectedMethod == 'Transfer') _buildMTSection(),
                      if (selectedMethod == 'PromptPay') _buildPPSection(),
                      if (_debugText.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16.0),
                          child: Text(
                            _debugText,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 14,
                            ),
                          ),
                        ),
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

              double amount =
                  (di.item.quantity ?? 0) * (di.item.itemPrice ?? 0.0);

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

  Widget _buildAmountRow(
    String label,
    double amount, {
    bool isBold = false,
    double fontSize = 16,
  }) {
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
                if (hasMT) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMethodButton(
                      'Transfer',
                      isThai ? 'โอน' : 'Transfer',
                      isEnabled: true,
                    ),
                  ),
                ],
                if (hasPP) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMethodButton(
                      'PromptPay',
                      isThai ? 'พร้อมเพย์' : 'PromptPay',
                      isEnabled: true,
                    ),
                  ),
                ],
                if (hasOnline) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMethodButton(
                      'Online',
                      isThai ? 'ออนไลน์' : 'Online',
                      isEnabled: true,
                    ),
                  ),
                ],
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

  Widget _buildMethodButton(
    String methodId,
    String label, {
    required bool isEnabled,
  }) {
    bool isSelected = selectedMethod == methodId;
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected
            ? Colors.blue
            : (isEnabled ? Colors.grey[200] : Colors.grey[100]),
        foregroundColor: isSelected
            ? Colors.white
            : (isEnabled ? Colors.black87 : Colors.black38),
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
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: _handleAmount,
                    decoration: InputDecoration(
                      labelText: isThai
                          ? 'จำนวนเงินที่ได้รับ'
                          : 'Receive Amount',
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
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
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
                    child: Text(
                      isThai ? 'ไม่รับเงินทอน ให้เป็นทิป' : 'Change to Tip',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [_buildBanknoteButton(10), _buildBanknoteButton(20), _buildBanknoteButton(50) ],
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [_buildBanknoteButton(100), _buildBanknoteButton(500), _buildBanknoteButton(1000)],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 60,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _confirmCancel,
                      child: Text(
                        isThai ? 'ยกเลิก' : 'Cancel',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 60,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _processPayment,
                      child: Text(
                        isThai ? 'เก็บเงิน' : 'Pay',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
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

  Widget _buildMTSection() {
    List<String> requiredParams = [
      "MT_BANK_CODE",
      "MT_ACCOUNT_NAME",
      "MT_ACCOUNT_NUMBER",
      "MT_THAI_MEDIA",
    ];
    List<PaymentValue> displayValues = mtValues
        .where((pv) => requiredParams.contains(pv.payment_parameter_ID))
        .toList();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...displayValues.map((pv) {
              if (pv.type == 'T') {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          pv.name ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Expanded(flex: 3, child: Text(pv.value ?? '')),
                    ],
                  ),
                );
              } else if (pv.type == 'P') {
                Widget imageWidget;
                if (pv.localPicture != null &&
                    pv.localPicture!.isNotEmpty &&
                    File(pv.localPicture!).existsSync()) {
                  imageWidget = Image.file(
                    File(pv.localPicture!),
                    height: 100,
                    fit: BoxFit.contain,
                  );
                } else if (pv.value != null && pv.value!.isNotEmpty) {
                  imageWidget = Image.network(
                    widget.config.apiUrl + pv.value!,
                    height: 100,
                    fit: BoxFit.contain,
                  );
                } else {
                  return const SizedBox();
                }

                return GestureDetector(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => Dialog(
                        child:
                            pv.localPicture != null &&
                                pv.localPicture!.isNotEmpty &&
                                File(pv.localPicture!).existsSync()
                            ? Image.file(
                                File(pv.localPicture!),
                                fit: BoxFit.contain,
                              )
                            : Image.network(
                                widget.config.apiUrl + pv.value!,
                                fit: BoxFit.contain,
                              ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: imageWidget,
                    ),
                  ),
                );
              }
              return const SizedBox();
            }).toList(),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: receiveAmountController
                      ..text =
                          (receiveAmountController.text == '0' ||
                              receiveAmountController.text.isEmpty)
                          ? (receipt?.totalAmount ?? 0.0).toStringAsFixed(2)
                          : receiveAmountController.text,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: _handleAmount,
                    decoration: InputDecoration(
                      labelText: isThai
                          ? 'จำนวนเงินที่ได้รับ'
                          : 'Receive Amount',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (receipt?.slipFileName != null &&
                receipt!.slipFileName!.isNotEmpty)
              FutureBuilder<Directory>(
                future: getApplicationDocumentsDirectory(),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    final file = File(
                      '${snapshot.data!.path}/${receipt!.slipFileName}',
                    );
                    if (file.existsSync()) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 24.0),
                        child: Center(
                          child: Image.file(
                            file,
                            height: 100,
                            fit: BoxFit.contain,
                          ),
                        ),
                      );
                    }
                  }
                  return const SizedBox();
                },
              ),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: _takePhoto,
                    child: Text(isThai ? 'ถ่ายรูป' : 'Take Photo'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: _printPaymentInfo,
                    child: Text(isThai ? 'พิมพ์' : 'Print'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: _processMTPayment,
                    child: Text(isThai ? 'เก็บเงิน' : 'Pay'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);
    if (pickedFile != null && receipt != null) {
      final docDir = await getApplicationDocumentsDirectory();
      final newFileName = '${const Uuid().v4()}.jpg';
      final newFilePath = '${docDir.path}/$newFileName';
      await File(pickedFile.path).copy(newFilePath);

      setState(() {
        receipt!.slipFileName = newFileName;
        receipt!.isDirty = true;
      });
      await isar.writeTxn(() async {
        await isar.receiptList.put(receipt!);
      });
    }
  }

  void _confirmCancel() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isThai ? 'ยืนยันการยกเลิก' : 'Confirm Cancel'),
          content: Text(
            isThai
                ? 'คุณต้องการยกเลิกการชำระเงินใช่หรือไม่?'
                : 'Do you want to cancel this payment?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                isThai ? 'ไม่' : 'No',
                style: const TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.pop(context);
                await _processCancel();
              },
              child: Text(isThai ? 'ใช่, ยกเลิก' : 'Yes, Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _processCancel() async {
    if (receipt != null) {
      await isar.writeTxn(() async {
        receipt!.status = 'Cancel';
        receipt!.lastUpdated = DateTime.now().toIso8601String();
        receipt!.isDirty = true;
        await isar.receiptList.put(receipt!);
      });
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => PPosScreen(config: widget.config),
      ),
      (route) => false,
    );
  }

  void _processPayment() async {
    if (isDebug) { setState(() => _debugText = 'processPayment'); }
    if (receipt == null) return;

    receipt!.paidAmount = (receipt!.totalAmount ?? 0.0) + tipAmount;
    receipt!.status = 'Paid';
    receipt!.paymentType = 'Cash';

    final foodOrders = await isar.foodOrderList
        .where()
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

    if (widget.config.PrinterModel == 'Xprinter N160ii') {
      settingValue['FOC_PAUSE_PRN_COK'] = false;
    }

    if (settingValue['FOC_PRN_RCP_CSH'] == true) {
      await _printReceipt(foodOrders);
      if (isDebug) { setState(() => _debugText = '_printReceipt'); }
    }

    if (settingValue['FOC_PRN_COK'] == true &&
        widget.config.isKitchen == true) {
      if (settingValue['FOC_PAUSE_PRN_COK'] == true) {
        if (!mounted) return;
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
                    await _printCookingOrder(foodOrders);
                    await syncReceipt();
                    _navigateBack();
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
        await _printCookingOrder(foodOrders);
        if (isDebug) { setState(() => _debugText = '_printCookingOrder'); }
      }
    }

    if (isDebug) { setState(() => _debugText = 'call syncReceipt'); }

    await syncReceipt();
    // _navigateBack(); 
  }

  void _processMTPayment() async {
    if (isDebug) { setState(() => _debugText = 'processMTPayment'); }
    if (receipt == null) return;

    receipt!.paidAmount = (receipt!.totalAmount ?? 0.0) + tipAmount;
    receipt!.status = 'Paid';
    receipt!.paymentType = 'MoneyTransfer';

    final foodOrders = await isar.foodOrderList
        .where()
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

    if (widget.config.PrinterModel == 'Xprinter N160ii') {
      settingValue['FOC_PAUSE_PRN_COK'] = false;
    }

    if (settingValue['FOC_PRN_RCP_CSH'] == true) {
      await _printReceipt(foodOrders, isMT: true);
      if (isDebug) { setState(() => _debugText = '_printReceipt'); }
    }

    if (settingValue['FOC_PRN_COK'] == true &&
        widget.config.isKitchen == true) {
      if (settingValue['FOC_PAUSE_PRN_COK'] == true) {
        if (!mounted) return;
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
                    await _printCookingOrder(foodOrders);
                    await syncReceipt();
                    _navigateBack();
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
        await _printCookingOrder(foodOrders);
        if (isDebug) { setState(() => _debugText = '_printCookingOrder done'); }
      }
    }

    if (isDebug) { setState(() => _debugText = 'call syncReceipt'); }

    await syncReceipt();
    // _navigateBack(); 
  }

  void _navigateBack() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => PPosScreen(config: widget.config),
      ),
      (route) => false,
    );
  }

  Future<void> _printReceipt(
    List<FoodOrder> foodOrders, {
    bool isMT = false,
  }) async {
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

        if (rawText.contains('[KitchenItem]')) continue;

        if (rawText.contains('[ReceiptItem]')) {
          await SunmiPrinter.lineWrap(2);
          await _printReceiptItemsSunmi(isMT: isMT);
          await SunmiPrinter.lineWrap(2);
        } else {
          String textToPrint = _replaceVariables(
            rawText,
            widget.config,
            foodOrders,
          );
          if (textToPrint.isNotEmpty) {
            await SunmiPrinter.printText(
              textToPrint,
              style: SunmiTextStyle(
                align: _getAlign(dt.alignment),
                fontSize: dt.fontSize ?? 24,
              ),
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

        if (rawText.contains('[KitchenItem]')) continue;

        if (rawText.contains('[ReceiptItem]')) {
          bytes += generator.feed(2);
          for (var di in displayItems) {
            String desc = '${di.item.quantity ?? 0}x ${di.itemName}';
            if (di.sizeName.isNotEmpty) desc += ' ${di.sizeName}';
            if (di.choiceName.isNotEmpty) desc += ' ${di.choiceName}';
            double amount =
                (di.item.quantity ?? 0) * (di.item.itemPrice ?? 0.0);

            final image = await _rowToImage(
              desc,
              amount.toStringAsFixed(2),
              24,
            );
            bytes += generator.imageRaster(image);
          }
          bytes += generator.imageRaster(await _dividerImage());

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
            await _rowToImage(
              pt,
              (receipt?.paidAmount ?? 0.0).toStringAsFixed(2),
              24,
            ),
          );
          bytes += generator.feed(2);
        } else {
          String textToPrint = _replaceVariables(
            rawText,
            widget.config,
            foodOrders,
          );
          if (textToPrint.isNotEmpty) {
            final imageToPrint = await _textToImage(
              textToPrint,
              dt.fontSize ?? 24,
              dt.alignment,
            );
            bytes += generator.imageRaster(imageToPrint);
          }
        }
      }
      bytes += generator.feed(2);
      bytes += generator.cut();
      await _executePrint(bytes);
    }
  }

  Future<void> _printReceiptItemsSunmi({bool isMT = false}) async {
    for (var di in displayItems) {
      String desc = '${di.item.quantity ?? 0}x ${di.itemName}';
      if (di.sizeName.isNotEmpty) desc += ' ${di.sizeName}';
      if (di.choiceName.isNotEmpty) desc += ' ${di.choiceName}';

      double amount = (di.item.quantity ?? 0) * (di.item.itemPrice ?? 0.0);
      await SunmiPrinter.printRow(
        cols: [
          SunmiColumn(
            text: desc,
            width: 20,
            style: SunmiTextStyle(align: SunmiPrintAlign.LEFT),
          ),
          SunmiColumn(
            text: amount.toStringAsFixed(2),
            width: 10,
            style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT),
          ),
        ],
      );
    }
    await SunmiPrinter.line();
    await SunmiPrinter.printRow(
      cols: [
        SunmiColumn(
          text: isThai ? 'ยอดรวม' : 'Sum Amount',
          width: 20,
          style: SunmiTextStyle(align: SunmiPrintAlign.LEFT),
        ),
        SunmiColumn(
          text: (receipt?.sumAmount ?? 0.0).toStringAsFixed(2),
          width: 10,
          style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT),
        ),
      ],
    );
    await SunmiPrinter.printRow(
      cols: [
        SunmiColumn(
          text: isThai ? 'ส่วนลด' : 'Discount',
          width: 20,
          style: SunmiTextStyle(align: SunmiPrintAlign.LEFT),
        ),
        SunmiColumn(
          text: (receipt?.discountAmount ?? 0.0).toStringAsFixed(2),
          width: 10,
          style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT),
        ),
      ],
    );
    await SunmiPrinter.printRow(
      cols: [
        SunmiColumn(
          text: isThai ? 'ยอดรวมทั้งหมด' : 'Total Amount',
          width: 15,
          style: SunmiTextStyle(align: SunmiPrintAlign.LEFT),
        ),
        SunmiColumn(
          text: (receipt?.totalAmount ?? 0.0).toStringAsFixed(2),
          width: 15,
          style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT),
        ),
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
        SunmiColumn(
          text: pt,
          width: 15,
          style: SunmiTextStyle(align: SunmiPrintAlign.LEFT),
        ),
        SunmiColumn(
          text: (receipt?.paidAmount ?? 0.0).toStringAsFixed(2),
          width: 15,
          style: SunmiTextStyle(align: SunmiPrintAlign.RIGHT),
        ),
      ],
    );
  }

  Future<void> _printCookingOrder(List<FoodOrder> foodOrders) async {
    if (isDebug) { setState(() => _debugText = 'start _printCookingOrder'); }

    final templates = await isar.documentTemplateList
        .where()
        .filter()
        .printTextContains('FoodOrder.Number')
        .findAll();

    final kitchenTemplates = await isar.documentTemplateList
        .where()
        .filter()
        .printTextContains('[KitchenItem]')
        .findAll();
    final dtKitchen = kitchenTemplates.isNotEmpty ? kitchenTemplates.first : null;
    final int kFontSize = dtKitchen?.fontSize ?? 24;
    final String kAlign = dtKitchen?.alignment ?? 'Left';

    if (isDebug) { setState(() => _debugText = '_printCookingOrder kFontSize:$kFontSize kAlign:$kAlign'); }

    if (widget.config.PrinterModel == 'Sunmi V series') {
      for (var order in foodOrders) {
        final orderItems = displayItems
            .where((di) => di.item.food_order_ID == order.id)
            .toList();
        if (orderItems.isEmpty) continue;

        for (var dt in templates) {
          await SunmiPrinter.printText(
            order.number?.toString() ?? '',
            style: SunmiTextStyle(
              align: _getAlign(dt.alignment),
              fontSize: dt.fontSize ?? 24,
              bold: true,
            ),
          );
        }
        for (var di in orderItems) {
          String desc = '${di.item.quantity ?? 0}x ${di.kitchenItemName}';
          if (di.kitchenSizeName.isNotEmpty) desc += ' ${di.kitchenSizeName}';
          if (di.kitchenChoiceName.isNotEmpty)
            desc += ' ${di.kitchenChoiceName}';

          await SunmiPrinter.printText(
            desc,
            style: SunmiTextStyle(
              align: _getAlign(kAlign),
              fontSize: kFontSize,
            ),
          );
        }
        await SunmiPrinter.lineWrap(2);
      }
    } else {
      List<int> bytes = [];
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      bytes += generator.reset();

      for (var order in foodOrders) {
        final orderItems = displayItems
            .where((di) => di.item.food_order_ID == order.id)
            .toList();
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
          if (di.kitchenChoiceName.isNotEmpty)
            desc += ' ${di.kitchenChoiceName}';

          final imageToPrint = await _textToImage(
            desc,
            kFontSize,
            kAlign,
          );
          bytes += generator.imageRaster(imageToPrint);
        }
        bytes += generator.feed(2);
      }
      bytes += generator.cut();
      await _executePrint(bytes);
    }

    await isar.writeTxn(() async {
      for (var order in foodOrders) {
        order.status = 'KitchenPrinted';
        order.lastUpdated = DateTime.now().toIso8601String();
        await isar.foodOrderList.put(order);
      }
    });
  }

  Future<void> _executePrint(List<int> bytes) async {
    // เพิ่มการหน่วงเวลา 500ms (ครึ่งวินาที) เพื่อให้พรินเตอร์เคลียร์ตัวเองก่อนรับงานใหม่
    await Future.delayed(const Duration(milliseconds: 500)); 

    if (widget.config.ConnectType == 'LAN') {
      try {
        final ip = widget.config.PrinterAddress ?? '';
        if (ip.isNotEmpty) {
          Socket socket = await Socket.connect(
            ip,
            9100,
            timeout: const Duration(seconds: 5),
          );
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
          List<Map<String, dynamic>> results =
              await FlutterUsbPrinter.getUSBDeviceList();
          for (var device in results) {
            if (device['vendorId'] == address ||
                device['vendorId'].toString() == address) {
              await flutterUsbPrinter.connect(
                int.parse(device['vendorId']),
                int.parse(device['productId']),
              );
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

  Future<void> _printPaymentInfo() async {
    if (receipt == null) return;

    await syncReceipt();

    List<String> requiredParams = [
      "MT_BANK_CODE",
      "MT_ACCOUNT_NAME",
      "MT_ACCOUNT_NUMBER",
      "MT_THAI_MEDIA",
    ];
    List<PaymentValue> displayValues = mtValues
        .where((pv) => requiredParams.contains(pv.payment_parameter_ID))
        .toList();

    String qrUrl = '${widget.config.foodUrl ?? ''}inform-payment/receipt/${receipt!.id ?? ''}';

    if (widget.config.PrinterModel == 'Sunmi V series') {
      await SunmiPrinter.printText(
        isThai ? 'กรุณาโอนเงิน' : 'Please transfer',
        style: SunmiTextStyle(align: SunmiPrintAlign.CENTER, fontSize: 20),
      );
      await SunmiPrinter.printText(
        (receipt?.totalAmount ?? 0.0).toStringAsFixed(2),
        style: SunmiTextStyle(
          align: SunmiPrintAlign.CENTER,
          fontSize: 50,
          bold: true,
        ),
      );
      await SunmiPrinter.printText(
        isThai ? 'บาท เข้าบัญชีธนาคาร' : 'Baht to bank account',
        style: SunmiTextStyle(align: SunmiPrintAlign.CENTER, fontSize: 20),
      );

      await SunmiPrinter.lineWrap(1);

      for (var pv in displayValues) {
        if (pv.type == 'T') {
          await SunmiPrinter.printText(
            '${pv.name} : ${pv.value}',
            style: SunmiTextStyle(align: SunmiPrintAlign.CENTER, fontSize: 24),
          );
        } else if (pv.type == 'P') {
          Uint8List? imgBytes;
          if (pv.localPicture != null &&
              pv.localPicture!.isNotEmpty &&
              File(pv.localPicture!).existsSync()) {
            imgBytes = await File(pv.localPicture!).readAsBytes();
          } else if (pv.value != null && pv.value!.isNotEmpty) {
            try {
              final resp = await http.get(
                Uri.parse(widget.config.apiUrl + pv.value!),
              );
              if (resp.statusCode == 200) {
                imgBytes = resp.bodyBytes;
              }
            } catch (e) {
              debugPrint("Error downloading image: $e");
            }
          }
          if (imgBytes != null) {
            try {
              await SunmiPrinter.lineWrap(1);
              await SunmiPrinter.printImage(imgBytes);
            } catch (e) {
              debugPrint("Print Image Error: $e");
            }
          }
        }
      }

      await SunmiPrinter.lineWrap(1);

      await SunmiPrinter.printText(
        isThai
            ? 'เสร็จแล้ว แจ้งโอนเงิน โดยสแกน QR code'
            : 'After transfer, notify via QR code',
        style: SunmiTextStyle(align: SunmiPrintAlign.CENTER, fontSize: 20),
      );

      await SunmiPrinter.lineWrap(1);

      await SunmiPrinter.printQRCode(qrUrl);
      await SunmiPrinter.lineWrap(3);
    } else {
      List<int> bytes = [];
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      bytes += generator.reset();

      bytes += generator.imageRaster(
        await _textToImage(
          isThai ? 'กรุณาโอนเงิน' : 'Please transfer',
          20,
          'center',
        ),
      );
      bytes += generator.imageRaster(
        await _textToImage(
          (receipt?.totalAmount ?? 0.0).toStringAsFixed(2),
          50,
          'center',
          isBold: true,
        ),
      );
      bytes += generator.imageRaster(
        await _textToImage(
          isThai ? 'บาท เข้าบัญชีธนาคาร' : 'Baht to bank account',
          20,
          'center',
        ),
      );

      bytes += generator.feed(1);

      for (var pv in displayValues) {
        if (pv.type == 'T') {
          bytes += generator.imageRaster(
            await _textToImage('${pv.name} : ${pv.value}', 24, 'center'),
          );
        } else if (pv.type == 'P') {
          Uint8List? imgBytes;
          if (pv.localPicture != null &&
              pv.localPicture!.isNotEmpty &&
              File(pv.localPicture!).existsSync()) {
            imgBytes = await File(pv.localPicture!).readAsBytes();
          } else if (pv.value != null && pv.value!.isNotEmpty) {
            try {
              final resp = await http.get(
                Uri.parse(widget.config.apiUrl + pv.value!),
              );
              if (resp.statusCode == 200) {
                imgBytes = resp.bodyBytes;
              }
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
      bytes += generator.imageRaster(
        await _textToImage(
          isThai
              ? 'เสร็จแล้ว แจ้งโอนเงิน โดยสแกน QR code'
              : 'After transfer, notify via QR code',
          20,
          'center',
        ),
      );

      bytes += generator.feed(1);
      bytes += generator.qrcode(qrUrl);
      bytes += generator.feed(3);
      bytes += generator.cut();

      await _executePrint(bytes);
    }
  }

  String _replaceVariables(
    String template,
    EnvConfig config, [
    List<FoodOrder>? foodOrders,
  ]) {
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
      final numbers = foodOrders
          .map((e) => e.number?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .join(', ');
      result = result.replaceAll('[FoodOrder.Number]', numbers);
    }

    return result;
  }

  bool _shouldPrintTemplate(String text) {
    if (!text.contains('[')) return true;
    if (text.contains('[ReceiptItem]') || text.contains('[FoodOrder.Number]'))
      return true;

    final matches = RegExp(r'\[(.*?)\]').allMatches(text);
    for (final match in matches) {
      String inner = match.group(1) ?? '';
      if (!inner.startsWith('config.') &&
          inner != 'ReceiptItem' &&
          inner != 'FoodOrder.Number') {
        return false;
      }
    }
    return true;
  }

  SunmiPrintAlign _getAlign(String? alignment) {
    if (alignment == null) return SunmiPrintAlign.LEFT;
    switch (alignment.toLowerCase()) {
      case 'center':
        return SunmiPrintAlign.CENTER;
      case 'right':
        return SunmiPrintAlign.RIGHT;
      case 'left':
      default:
        return SunmiPrintAlign.LEFT;
    }
  }

  Future<img.Image> _textToImage(
    String text,
    int fontSize,
    String? alignment, {
    bool isBold = false,
  }) async {
    TextAlign textAlign = TextAlign.left;
    if (alignment?.toLowerCase() == 'center')
      textAlign = TextAlign.center;
    else if (alignment?.toLowerCase() == 'right')
      textAlign = TextAlign.right;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: Colors.black,
        fontSize: fontSize.toDouble(),
        fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      textAlign: textAlign,
    );
    textPainter.layout(minWidth: 576, maxWidth: 576);

    final paint = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(0, 0, 576, textPainter.height), paint);
    textPainter.paint(canvas, const Offset(0, 0));

    final picture = recorder.endRecording();
    final uiImage = await picture.toImage(576, textPainter.height.toInt());
    final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
    return img.decodeImage(byteData!.buffer.asUint8List())!;
  }

  Future<img.Image> _rowToImage(
    String leftText,
    String rightText,
    int fontSize, {
    bool isBold = false,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final style = TextStyle(
      color: Colors.black,
      fontSize: fontSize.toDouble(),
      fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
    );

    final leftSpan = TextSpan(text: leftText, style: style);
    final leftPainter = TextPainter(
      text: leftSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
    );
    leftPainter.layout(minWidth: 400, maxWidth: 400);

    final rightSpan = TextSpan(text: rightText, style: style);
    final rightPainter = TextPainter(
      text: rightSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.right,
    );
    rightPainter.layout(minWidth: 176, maxWidth: 176);

    double height = leftPainter.height > rightPainter.height
        ? leftPainter.height
        : rightPainter.height;
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
    final linePaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2;
    canvas.drawLine(const Offset(0, 10), const Offset(576, 10), linePaint);
    final picture = recorder.endRecording();
    final uiImage = await picture.toImage(576, 20);
    final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
    return img.decodeImage(byteData!.buffer.asUint8List())!;
  }

  Widget _buildPPSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isThai ? 'คิวอาร์พร้อมเพย์' : 'PromptPay QR',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (_isGeneratingPP)
              const Center(child: CircularProgressIndicator())
            else if (_ppQrBase64 == null)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _generatePPQr,
                child: Text(isThai ? 'สร้างคิวอาร์โค้ด' : 'Generate QR Code'),
              )
            else
              Column(
                children: [
                  Image.memory(
                    base64Decode(_ppQrBase64!),
                    height: 250,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          onPressed: _printPromptPay,
                          child: Text(isThai ? 'พิมพ์ QR' : 'Print QR'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          onPressed: _processMTPayment,
                          child: Text(isThai ? 'ตรวจสอบ & ชำระเงิน' : 'Check & Pay'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _generatePPQr() async {
    if (isDebug) { setState(() => _debugText = 'Generating PP QR'); }
    setState(() {
      _isGeneratingPP = true;
    });

    try {
      String merchantId = '';
      String apiKey = '';
      int expireMinute = 15;

      for (var pv in ppValues) {
        if (pv.payment_parameter_ID == 'PP_MERCHANT_ID') merchantId = pv.value ?? '';
        if (pv.payment_parameter_ID == 'PP_API_KEY') apiKey = pv.value ?? '';
        if (pv.payment_parameter_ID == 'PP_EXPIRE_MINUTE') expireMinute = int.tryParse(pv.value ?? '15') ?? 15;
      }

      if (merchantId.isEmpty || apiKey.isEmpty) {
        throw Exception('PP_MERCHANT_ID or PP_API_KEY is missing');
      }

      final now = DateTime.now().toUtc();
      final expiryTime = now.add(Duration(minutes: expireMinute));
      final expiryTimeStr = '${expiryTime.toIso8601String().split('.')[0]}Z';

      int amount = ((receipt?.totalAmount ?? 0.0) * 100).toInt();

      final payload = {
        "amount": amount,
        "currency": "THB",
        "paymentMethod": {
          "qrPromptPay": {
            "expiryTime": expiryTimeStr
          },
          "paymentMethodType": "QR_PROMPT_PAY"
        },
        "referenceId": receipt?.id,
        "returnUrl": "https://www.beamcheckout.com",
        "skip3dsFlow": false
      };

      String basicAuth = 'Basic ' + base64Encode(utf8.encode('$merchantId:$apiKey'));

      final response = await http.post(
        Uri.parse('https://api.beamcheckout.com/api/v1/charges'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': basicAuth,
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['encodedImage'] != null && data['encodedImage']['imageBase64Encoded'] != null) {
          await syncReceipt();

          setState(() { _ppQrBase64 = data['encodedImage']['imageBase64Encoded']; });
        } else {
          throw Exception('No QR image in response');
        }
      } else {
        throw Exception('API error: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      if (isDebug) {
        setState(() {
          _debugText = 'PP QR Error: $e';
        });
      }
      debugPrint("Error generating PP QR: $e");
    } finally {
      setState(() {
        _isGeneratingPP = false;
      });
    }
  }

  Future<void> _printPromptPay() async {
    if (_ppQrBase64 == null || receipt == null) return;
    
    String orderNo = '';
    try {
      final foodOrders = await isar.foodOrderList
          .where()
          .filter()
          .parentIDEqualTo(receipt!.id)
          .and()
          .parentTypeEqualTo('receipt')
          .findAll();
      if (foodOrders.isNotEmpty) {
        orderNo = foodOrders.first.number?.toString() ?? orderNo;
      }
    } catch (e) {
      debugPrint(e.toString());
    }

    Uint8List imgBytes = base64Decode(_ppQrBase64!);

    if (widget.config.PrinterModel == 'Sunmi V series') {
      await SunmiPrinter.printText(
        orderNo,
        style: SunmiTextStyle(align: SunmiPrintAlign.CENTER, fontSize: 36, bold: true),
      );
      await SunmiPrinter.lineWrap(1);
      await SunmiPrinter.printImage(imgBytes);
      await SunmiPrinter.lineWrap(2);
    } else {
      List<int> bytes = [];
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      bytes += generator.reset();

      final imageToPrint = await _textToImage(
        orderNo,
        50,
        'Center',
        isBold: true,
      );
      bytes += generator.imageRaster(imageToPrint);
      bytes += generator.feed(1);

      final qrImage = await _qrToImage(imgBytes);
      bytes += generator.imageRaster(qrImage);

      bytes += generator.feed(2);
      bytes += generator.cut();
      await _executePrint(bytes);
    }
  }

  Future<img.Image> _qrToImage(Uint8List bytes) async {
    // 40 mm * 8 dots/mm = 320 dots
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 320, targetHeight: 320);
    final frame = await codec.getNextFrame();
    final uiImage = frame.image;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    
    // Fill white background for 576 width (standard 80mm printer)
    final bgPaint = Paint()..color = Colors.white;
    canvas.drawRect(const Rect.fromLTWH(0, 0, 576, 320), bgPaint);

    // Center the 320x320 image on the 576 width canvas
    // (576 - 320) / 2 = 128
    canvas.drawImage(uiImage, const Offset(128, 0), Paint());

    final picture = recorder.endRecording();
    final finalImage = await picture.toImage(576, 320);
    final byteData = await finalImage.toByteData(format: ui.ImageByteFormat.png);
    return img.decodeImage(byteData!.buffer.asUint8List())!;
  }
}
