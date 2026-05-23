import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:meorder_ppos/lib/EnvConfig.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:path_provider/path_provider.dart';

class PrintScreen extends StatefulWidget {
  final EnvConfig config;
  const PrintScreen({super.key, required this.config});

  @override
  State<PrintScreen> createState() => _PrintScreenState();
}

class _PrintScreenState extends State<PrintScreen> {
  String _error = '';
  late EnvConfig _config;
  bool _isLoading = false;
  
  String _printMode = 'Barcode';
  List<Map<String, dynamic>> _printableBarcodeList = [];
  List<Map<String, dynamic>> _printablePriceList = [];
  Set<String> _checkedBarcodes = {};

  BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;
  bool _connected = false;
  List<BluetoothDevice> _devices = [];

  @override
  void initState() {
    super.initState();
    _config = widget.config;
    _fetchProducts();
    _initPrinter();
  }

  Future<void> _initPrinter() async {
    try {
      _devices = await bluetooth.getBondedDevices();
    } catch (e) {
      print('Error getting bonded devices: $e');
    }

    if (_config.printerMacAddress != null && _config.printerMacAddress!.isNotEmpty) {
      _reconnectPrinter(_config.printerMacAddress!);
    }
  }

  Future<void> _reconnectPrinter(String macAddress) async {
    try {
      BluetoothDevice? deviceToConnect;
      for (var device in _devices) {
        if (device.address == macAddress) {
          deviceToConnect = device;
          break;
        }
      }
      
      if (deviceToConnect != null) {
        bool? isConnected = await bluetooth.isConnected;
        if (isConnected != true) {
          await bluetooth.connect(deviceToConnect);
        }
        setState(() {
          _connected = true;
        });
      }
    } catch (e) {
      setState(() {
        _connected = false;
      });
      print('Reconnect error: $e');
    }
  }

  Future<void> _saveMacAddress(String macAddress) async {
    _config = _config.copyWith(printerMacAddress: macAddress);
    
    try {
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/store.json';
      final file = File(filePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final Map<String, dynamic> storeMap = jsonDecode(content);
        storeMap['PrinterMacAddress'] = macAddress;
        await file.writeAsString(jsonEncode(storeMap));
      }
    } catch (e) {
      print('Error saving mac address to store.json: $e');
    }
  }

  void _onPrinterIconPressed() async {
    if (_config.printerMacAddress != null && _config.printerMacAddress!.isNotEmpty) {
      await _reconnectPrinter(_config.printerMacAddress!);
    } else {
      _showBluetoothDevicesDialog();
    }
  }

  void _showBluetoothDevicesDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return ListView.builder(
          itemCount: _devices.length,
          itemBuilder: (context, index) {
            final device = _devices[index];
            return ListTile(
              title: Text(device.name ?? 'Unknown Device'),
              subtitle: Text(device.address ?? ''),
              onTap: () async {
                Navigator.pop(context);
                if (device.address != null) {
                  await _saveMacAddress(device.address!);
                  await _reconnectPrinter(device.address!);
                }
              },
            );
          },
        );
      },
    );
  }

  Future<void> _fetchProducts() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });
    final uri = Uri.parse(_config.apiUrl + 'api/store/fetch-product');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${_config.apiToken}',
    };
    final body = jsonEncode({'shop_ID': _config.id});

    try {
      final response = await http.post(uri, headers: headers, body: body);
      if (response.statusCode == 200) {
        final Map<String, dynamic> responseJson = jsonDecode(response.body);
        final box = Hive.box('meOrderBox');
        await box.put('ProductList', responseJson['ProductList']);
        _buildPrintableList();
      } else {
        setState(() { _error = 'API Error ${response.statusCode}'; });
      }
    } catch (e) {
      setState(() { _error = 'Network Error: $e'; });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _buildPrintableList() {
    final box = Hive.box('meOrderBox');
    final savedProducts = box.get('ProductList');
    if (savedProducts == null) return;

    List<Map<String, dynamic>> barcodeList = [];
    List<Map<String, dynamic>> priceList = [];
    List<dynamic> products = List<dynamic>.from(savedProducts);

    for (var p in products) {
      Map<String, dynamic> product = Map<String, dynamic>.from(p);
      String prodBarcode = product['Barcode']?.toString() ?? '';
      int prodStockCount = product['StockCount'] is int ? product['StockCount'] : int.tryParse(product['StockCount']?.toString() ?? '0') ?? 0;
      
      Map<String, dynamic> prodItem = {
        'isProduct': true,
        'ProductName': product['ProductName'] ?? '',
        'Barcode': prodBarcode,
        'StockCount': prodStockCount,
        'product': product,
      };

      if (prodBarcode.startsWith('2') && prodStockCount > 0) {
        barcodeList.add(prodItem);
      }
      if (prodBarcode.isNotEmpty && prodStockCount > 0) {
        priceList.add(prodItem);
      }

      List<dynamic> packs = List<dynamic>.from(product['Pack'] ?? []);
      for (int i = 0; i < packs.length; i++) {
        Map<String, dynamic> pack = Map<String, dynamic>.from(packs[i]);
        String packBarcode = pack['Barcode']?.toString() ?? '';
        int packStockCount = pack['StockCount'] is int ? pack['StockCount'] : int.tryParse(pack['StockCount']?.toString() ?? '0') ?? 0;
        
        int currentLevel = pack['Level'] is int ? pack['Level'] : int.tryParse(pack['Level']?.toString() ?? '1') ?? 1;
        String unitName = product['UnitName']?.toString() ?? '';

        if (currentLevel > 1) {
          try {
            final prevPack = packs.firstWhere((pck) {
              final pkMap = Map<String, dynamic>.from(pck);
              final pLevel = pkMap['Level'] is int ? pkMap['Level'] : int.tryParse(pkMap['Level']?.toString() ?? '1') ?? 1;
              return pLevel == currentLevel - 1;
            });
            unitName = Map<String, dynamic>.from(prevPack)['PackName']?.toString() ?? '';
          } catch (e) {
            if (i > 0) {
              unitName = Map<String, dynamic>.from(packs[i - 1])['PackName']?.toString() ?? '';
            }
          }
        }

        Map<String, dynamic> packItem = {
          'isProduct': false,
          'ProductName': product['ProductName'] ?? '',
          'PackName': pack['PackName'] ?? '',
          'Quantity': pack['Quantity'] ?? 1,
          'UnitName': unitName,
          'Barcode': packBarcode,
          'StockCount': packStockCount,
          'pack': pack,
          'product': product,
        };

        if (packBarcode.startsWith('2') && packStockCount > 0) {
          barcodeList.add(packItem);
        }
        if (packBarcode.isNotEmpty && packStockCount > 0) {
          priceList.add(packItem);
        }
      }
    }

    setState(() {
      _printableBarcodeList = barcodeList;
      _printablePriceList = priceList;
      
      if (_printMode == 'Barcode') {
        _checkedBarcodes = _printableBarcodeList.map((e) => e['Barcode'] as String).toSet();
      } else {
        _checkedBarcodes = _printablePriceList.map((e) => e['Barcode'] as String).toSet();
      }
    });
  }

  void _setMode(String mode) {
    setState(() {
      _printMode = mode;
      if (_printMode == 'Barcode') {
        _checkedBarcodes = _printableBarcodeList.map((e) => e['Barcode'] as String).toSet();
      } else {
        _checkedBarcodes = _printablePriceList.map((e) => e['Barcode'] as String).toSet();
      }
    });
  }

  void _checkAll() {
    setState(() {
      if (_printMode == 'Barcode') {
        _checkedBarcodes = _printableBarcodeList.map((e) => e['Barcode'] as String).toSet();
      } else {
        _checkedBarcodes = _printablePriceList.map((e) => e['Barcode'] as String).toSet();
      }
    });
  }

  void _uncheckAll() {
    setState(() {
      _checkedBarcodes.clear();
    });
  }

  Future<Uint8List> _textToTsplBitmap(String text, int x, int y, double fontSize) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final textSpan = TextSpan(
      text: text,
      style: TextStyle(color: Colors.black, fontSize: fontSize, fontWeight: FontWeight.bold),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    
    textPainter.paint(canvas, Offset.zero);
    final picture = recorder.endRecording();
    final img = await picture.toImage(textPainter.width.ceil(), textPainter.height.ceil());
    
    final ByteData? byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return Uint8List(0);

    int width = img.width;
    int height = img.height;
    int widthBytes = (width + 7) ~/ 8;
    
    List<int> bitmapData = List.filled(widthBytes * height, 0xFF); // 1 = White
    
    for (int yPos = 0; yPos < height; yPos++) {
      for (int xPos = 0; xPos < width; xPos++) {
        int offset = (yPos * width + xPos) * 4;
        int a = byteData.getUint8(offset + 3);
        
        // Text is drawn black on transparent. Check alpha threshold.
        if (a > 128) {
          int byteIndex = yPos * widthBytes + (xPos ~/ 8);
          int bitIndex = 7 - (xPos % 8);
          bitmapData[byteIndex] &= ~(1 << bitIndex); // 0 = Black
        }
      }
    }

    String header = "BITMAP $x,$y,$widthBytes,$height,0,";
    List<int> command = [];
    command.addAll(header.codeUnits);
    command.addAll(bitmapData);
    command.addAll("\r\n".codeUnits);
    
    return Uint8List.fromList(command);
  }

  Future<void> _printBarcode() async {
    if (!_connected) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ไม่ได้เชื่อมต่อปริ้นเตอร์'),
          content: const Text('กรุณาเดินเข้าใกล้ และกดปุ่ม Printer'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ตกลง'),
            ),
          ],
        ),
      );
      return;
    }

    try {
      for (var item in _printableBarcodeList) {
        if (_checkedBarcodes.contains(item['Barcode'])) {
          int count = item['StockCount'] ?? 1;
          
          String title = item['ProductName'];

          String packString = '';
          if (item['isProduct'] == false) {
            packString = '${item['PackName']} ${item['Quantity']} ${item['UnitName']}';
          }
          
          String price = item['isProduct'] == true 
              ? (item['product']['Price']?.toString() ?? '') 
              : (item['pack']['Price']?.toString() ?? '');

          String barcode = item['Barcode'];

          List<int> bytes = [];

          void addString(String str) {
            bytes.addAll(str.codeUnits);
          }

          addString("SIZE 50 mm,30 mm\r\n");
          addString("GAP 2 mm,0 mm\r\n");
          addString("CLS\r\n");
          
          // Use Flutter TextPainter to generate BITMAP for Thai text
          Uint8List titleBitmap = await _textToTsplBitmap(title, 30, 20, 26);
          bytes.addAll(titleBitmap);

          Uint8List priceBitmap = await _textToTsplBitmap("$packString  $price บาท", 30, 60, 26);
          bytes.addAll(priceBitmap);

          addString("BARCODE 30,100,\"EAN13\",80,1,0,3,3,\"$barcode\"\r\n");
          addString("PRINT $count,1\r\n");

          bluetooth.writeBytes(Uint8List.fromList(bytes));
          
          // Add a small delay between commands
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
    } catch (e) {
      print('Print error: $e');
    }
  }

  Future<void> _printPrice() async {
    if (!_connected) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ไม่ได้เชื่อมต่อปริ้นเตอร์'),
          content: const Text('กรุณาเดินเข้าใกล้ และกดปุ่ม Printer'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ตกลง'),
            ),
          ],
        ),
      );
      return;
    }

    try {
      for (var item in _printablePriceList) {
        if (_checkedBarcodes.contains(item['Barcode'])) {
          String title = item['ProductName'];

          String packString = '';
          if (item['isProduct'] == false) {
            packString = '${item['PackName']} ${item['Quantity']} ${item['UnitName']}';
          }
          
          String price = item['isProduct'] == true 
              ? (item['product']['Price']?.toString() ?? '') 
              : (item['pack']['Price']?.toString() ?? '');

          List<int> bytes = [];

          void addString(String str) {
            bytes.addAll(str.codeUnits);
          }

          addString("SIZE 50 mm,30 mm\r\n");
          addString("GAP 2 mm,0 mm\r\n");
          addString("CLS\r\n");
          
          Uint8List titleBitmap = await _textToTsplBitmap(title, 30, 20, 26);
          bytes.addAll(titleBitmap);

          Uint8List packBitmap = await _textToTsplBitmap("$packString", 30, 60, 26);
          bytes.addAll(packBitmap);

          Uint8List priceBitmap = await _textToTsplBitmap("$price", 30, 100, 100);
          bytes.addAll(priceBitmap);

          Uint8List bahtBitmap = await _textToTsplBitmap("บาท", 320, 164, 26);
          bytes.addAll(bahtBitmap);

          addString("PRINT 1,1\r\n");

          bluetooth.writeBytes(Uint8List.fromList(bytes));
          
          // Add a small delay between commands
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
    } catch (e) {
      print('Print error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Print Labels'),
        actions: [
          IconButton(
            icon: Icon(Icons.qr_code, color: _printMode == 'Barcode' ? Colors.blue : Colors.grey),
            tooltip: 'Barcode Mode',
            onPressed: () => _setMode('Barcode'),
          ),
          IconButton(
            icon: Icon(Icons.monetization_on, color: _printMode == 'Price' ? Colors.blue : Colors.grey),
            tooltip: 'Price Mode',
            onPressed: () => _setMode('Price'),
          ),
          IconButton(
            icon: const Icon(Icons.check_box),
            tooltip: 'Check All',
            onPressed: _checkAll,
          ),
          IconButton(
            icon: const Icon(Icons.check_box_outline_blank),
            tooltip: 'Uncheck All',
            onPressed: _uncheckAll,
          ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(_error, style: const TextStyle(color: Colors.red)),
                ),
              Expanded(
                child: (_printMode == 'Barcode' ? _printableBarcodeList : _printablePriceList).isEmpty
                  ? Center(child: Text(_printMode == 'Barcode' ? 'ไม่มีบาร์โค้ดที่ขึ้นต้นด้วย 2' : 'ไม่มีบาร์โค้ด'))
                  : ListView.builder(
                      itemCount: (_printMode == 'Barcode' ? _printableBarcodeList : _printablePriceList).length,
                      itemBuilder: (context, index) {
                        final activeList = _printMode == 'Barcode' ? _printableBarcodeList : _printablePriceList;
                        final item = activeList[index];
                        final String barcode = item['Barcode'];
                        final bool isChecked = _checkedBarcodes.contains(barcode);

                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                if (isChecked) {
                                  _checkedBarcodes.remove(barcode);
                                } else {
                                  _checkedBarcodes.add(barcode);
                                }
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (item['isProduct'] == true)
                                          Text(
                                            '${item['ProductName']}',
                                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                          )
                                        else
                                          Text(
                                            '${item['ProductName']} ${item['PackName']} ${item['Quantity']} ${item['UnitName']}',
                                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                          ),
                                        const SizedBox(height: 4),
                                        Text('Barcode: $barcode'),
                                      ],
                                    ),
                                  ),
                                  if (_printMode == 'Barcode')
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                      child: Column(
                                        children: [
                                          const Text('สต๊อก', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                          Text('${item['StockCount']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                  Checkbox(
                                    value: isChecked,
                                    onChanged: (bool? value) {
                                      setState(() {
                                        if (value == true) {
                                          _checkedBarcodes.add(barcode);
                                        } else {
                                          _checkedBarcodes.remove(barcode);
                                        }
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
              ),
            ],
          ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              IconButton(
                onPressed: _onPrinterIconPressed,
                icon: Icon(
                  Icons.print,
                  color: _connected ? Colors.green : Colors.red,
                ),
                iconSize: 32,
              ),
              const SizedBox(width: 8),
              if (_printMode == 'Barcode')
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _printBarcode,
                    icon: const Icon(Icons.qr_code),
                    label: const Text('Print Barcode'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              if (_printMode == 'Price')
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _printPrice,
                    icon: const Icon(Icons.monetization_on),
                    label: const Text('Print Price'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
