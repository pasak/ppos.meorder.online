import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'package:meorder_ppos/lib/EnvConfig.dart';
import 'package:meorder_ppos/screen/SignInScreen.dart';
import 'package:isar/isar.dart';
import 'package:meorder_ppos/database/IsarModels.dart';
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_usb_printer/flutter_usb_printer.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

class SetPrinterScreen extends StatefulWidget {
  final EnvConfig config;
  const SetPrinterScreen({super.key, required this.config});

  @override
  State<SetPrinterScreen> createState() => _SetPrinterScreenState();
}

class _SetPrinterScreenState extends State<SetPrinterScreen> {
  final List<String> _printerModelList = ['Sunmi V series', 'Xprinter N160ii'];
  String? _selectedModel;
  
  final List<String> _connectTypeList = ['LAN', 'USB'];
  String? _selectedConnectType;

  bool _isPrinting = false;

  // USB Properties
  FlutterUsbPrinter flutterUsbPrinter = FlutterUsbPrinter();
  List<Map<String, dynamic>> devices = [];
  bool connected = false;
  Map<String, dynamic>? connectedDevice;

  // LAN Properties
  final TextEditingController _ipController = TextEditingController();
  String errorMessage = "";

  @override
  void initState() {
    super.initState();
    _selectedModel = widget.config.PrinterModel ?? _printerModelList.first;
    _selectedConnectType = widget.config.ConnectType ?? _connectTypeList.first;
    _ipController.text = widget.config.PrinterAddress ?? "192.168.1.100";
    
    _getDevicelist();
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  void _getDevicelist() async {
    try {
      List<Map<String, dynamic>> results = await FlutterUsbPrinter.getUSBDeviceList();
      setState(() {
        devices = results;
      });
    } catch (e) {
      debugPrint("Error getting USB devices: $e");
    }
  }

  void _connectUSB(Map<String, dynamic> device) async {
    try {
      bool? returned = await flutterUsbPrinter.connect(
          int.parse(device['vendorId']), int.parse(device['productId']));
      if (returned == true) {
        setState(() {
          connected = true;
          connectedDevice = device;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connected to USB: ${device['productName']}')),
        );
      }
    } catch (e) {
      debugPrint("Error connecting to USB device: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error connecting to USB: $e')),
      );
    }
  }

  void _disconnectUSB() async {
    try {
      await flutterUsbPrinter.close();
      setState(() {
        connected = false;
        connectedDevice = null;
      });
    } catch (e) {
      debugPrint("Error disconnecting USB device: $e");
    }
  }

  String _replaceVariables(String template, EnvConfig config) {
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

    return result;
  }

  bool _shouldPrintTemplate(String text) {
    if (!text.contains('[')) return true;
    final matches = RegExp(r'\[(.*?)\]').allMatches(text);
    for (final match in matches) {
      if (!(match.group(1) ?? '').startsWith('config.')) {
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
      default:
        return SunmiPrintAlign.LEFT;
    }
  }

  Future<img.Image> _textToImage(String text, int fontSize, String? alignment) async {
    TextAlign textAlign = TextAlign.left;
    if (alignment?.toLowerCase() == 'center') textAlign = TextAlign.center;
    else if (alignment?.toLowerCase() == 'right') textAlign = TextAlign.right;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(color: Colors.black, fontSize: fontSize.toDouble(), fontWeight: FontWeight.bold),
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
    final pngBytes = byteData!.buffer.asUint8List();
    
    return img.decodeImage(pngBytes)!;
  }

  Future<List<int>> _generateReceiptBytes() async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm80, profile);
    List<int> bytes = [];

    bytes += generator.reset();

    final isar = Isar.getInstance()!;

    final documentTypes = await isar.documentTypeList
        .where()
        .filter()
        .printerModelEqualTo(_selectedModel)
        .findAll();
    final documentType = documentTypes.isNotEmpty ? documentTypes.first : null;

    if (documentType == null) return bytes;

    final templates = await isar.documentTemplateList
        .where()
        .filter()
        .document_type_IDEqualTo(documentType.id)
        .and()
        .isActiveEqualTo('Y')
        .sortBySeq()
        .findAll();

    for (var dt in templates) {
      if (dt.alignment == 'Full') continue;
      String rawText = dt.printText ?? '';
      if (!_shouldPrintTemplate(rawText)) continue;
      
      String textToPrint = _replaceVariables(rawText, widget.config);
      
      if (textToPrint.isNotEmpty) {
         final imageToPrint = await _textToImage(textToPrint, dt.fontSize ?? 24, dt.alignment);
         bytes += generator.imageRaster(imageToPrint);
      }
    }

    bytes += generator.feed(2);
    bytes += generator.cut();

    return bytes;
  }

  void _saveConfigAndNavigate(String printerModel, String connectType, String printerAddress) async {
    final updatedConfig = widget.config.copyWith(
      PrinterModel: printerModel,
      ConnectType: connectType,
      PrinterAddress: printerAddress,
    );

    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/branch.json';
    final file = File(filePath);

    if (await file.exists()) {
      final content = await file.readAsString();
      final branchData = jsonDecode(content);
      branchData['PrinterModel'] = printerModel;
      branchData['ConnectType'] = connectType;
      branchData['PrinterAddress'] = printerAddress;
      await file.writeAsString(jsonEncode(branchData));
    }

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => SignInScreen(config: updatedConfig),
        ),
      );
    }
  }

  static Future<void> _printSunmiNewLine(int numberOfLine) async {
    for (var i = 0; i < numberOfLine; i++) {
      await SunmiPrinter.printText(' ', style: SunmiTextStyle(align: SunmiPrintAlign.LEFT, fontSize: 24));
    }
  }

  Future<void> _printTestSunmi() async {
    setState(() { _isPrinting = true; });

    try {
      final isar = Isar.getInstance()!;

      final documentTypes = await isar.documentTypeList
          .where()
          .filter()
          .printerModelEqualTo(_selectedModel)
          .findAll();
      final documentType = documentTypes.isNotEmpty ? documentTypes.first : null;

      if (documentType == null) {
        setState(() { _isPrinting = false; });
        return;
      }

      final templates = await isar.documentTemplateList
          .where()
          .filter()
          .document_type_IDEqualTo(documentType.id)
          .and()
          .isActiveEqualTo('Y')
          .sortBySeq()
          .findAll();

      for (var dt in templates) {
        if (dt.alignment == 'Full') continue;
        String rawText = dt.printText ?? '';
        if (!_shouldPrintTemplate(rawText)) continue;
        
        String textToPrint = _replaceVariables(rawText, widget.config);
        
        await SunmiPrinter.printText(
          textToPrint,
          style: SunmiTextStyle(
            align: _getAlign(dt.alignment),
            fontSize: dt.fontSize ?? 24, 
          ),
        );
      }

      await _printSunmiNewLine(3);

      setState(() { _isPrinting = false; });
      _saveConfigAndNavigate('Sunmi V series', 'Internal', '');

    } catch (e) {
      setState(() { _isPrinting = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Print failed: $e')),
      );
    }
  }

  void _printReceiptUSB() async {
    if (!connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please connect to a USB printer first')),
      );
      return;
    }

    setState(() { _isPrinting = true; });
    try {
      List<int> bytes = await _generateReceiptBytes();
      await flutterUsbPrinter.write(Uint8List.fromList(bytes));
      
      setState(() { errorMessage = ""; });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Printed via USB successfully')),
      );
      
      _saveConfigAndNavigate('Xprinter N160ii', 'USB', connectedDevice?['vendorId'] ?? '');
    } catch (e) {
      debugPrint("Error printing via USB: $e");
      setState(() { errorMessage = e.toString(); });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error printing via USB: $e')),
      );
    } finally {
      if (mounted) {
        setState(() { _isPrinting = false; });
      }
    }
  }

  void _printReceiptLAN() async {
    if (_ipController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter Printer IP Address')),
      );
      return;
    }

    setState(() { _isPrinting = true; });

    try {
      List<int> bytes = await _generateReceiptBytes();
      
      Socket socket = await Socket.connect(_ipController.text, 9100, timeout: const Duration(seconds: 5));
      
      socket.add(bytes);
      await socket.flush();
      await socket.close();

      if (!mounted) return;
      setState(() { errorMessage = ""; });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Printed via LAN successfully')),
      );

      _saveConfigAndNavigate('Xprinter N160ii', 'LAN', _ipController.text);
    } catch (e) {
      debugPrint("Error printing via LAN: $e");
      if (!mounted) return;
      setState(() { errorMessage = e.toString(); });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error printing via LAN: $e')),
      );
    } finally {
      if (mounted) {
        setState(() { _isPrinting = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ตั้งค่าเครื่องพิมพ์')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'เลือกรุ่นเครื่องพิมพ์ (Printer Model)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _selectedModel,
                items: _printerModelList.map((model) {
                  return DropdownMenuItem(
                    value: model,
                    child: Text(model),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() { _selectedModel = val; });
                },
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              
              if (_selectedModel == 'Xprinter N160ii') ...[
                const Text(
                  'ประเภทการเชื่อมต่อ (Connect Type)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _selectedConnectType,
                  items: _connectTypeList.map((type) {
                    return DropdownMenuItem(value: type, child: Text(type));
                  }).toList(),
                  onChanged: (val) {
                    setState(() { _selectedConnectType = val; });
                  },
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
                const SizedBox(height: 20),

                if (_selectedConnectType == 'LAN') ...[
                  const Text(
                    'LAN / Network Printer',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _ipController,
                    decoration: const InputDecoration(
                      labelText: 'Printer IP Address',
                      hintText: 'e.g. 192.168.1.100',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ],

                if (_selectedConnectType == 'USB') ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'USB OTG Printer',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _getDevicelist,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: devices.isEmpty
                        ? const Center(child: Text("No USB devices found.\nRefresh to scan."))
                        : ListView.builder(
                            itemCount: devices.length,
                            itemBuilder: (context, index) {
                              var device = devices[index];
                              return ListTile(
                                leading: const Icon(Icons.usb),
                                title: Text(device['manufacturer'] ?? "Unknown Vendor"),
                                subtitle: Text(device['productName'] ?? "Unknown Product"),
                                trailing: ElevatedButton(
                                  onPressed: () {
                                    if (connectedDevice == device) {
                                      _disconnectUSB();
                                    } else {
                                      _connectUSB(device);
                                    }
                                  },
                                  child: Text(connectedDevice == device ? "Disconnect" : "Connect"),
                                ),
                              );
                            },
                          ),
                  ),
                ],
                const SizedBox(height: 20),
              ],

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (context) => SignInScreen(config: widget.config),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.grey.shade300,
                        foregroundColor: Colors.black,
                      ),
                      child: const Text('ข้าม', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isPrinting ? null : () {
                        if (_selectedModel == 'Sunmi V series') {
                          _printTestSunmi();
                        } else if (_selectedModel == 'Xprinter N160ii') {
                          if (_selectedConnectType == 'LAN') {
                            _printReceiptLAN();
                          } else if (_selectedConnectType == 'USB') {
                            _printReceiptUSB();
                          }
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('ยังไม่รองรับการพิมพ์รุ่นนี้')),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      child: _isPrinting
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('ทดสอบพิมพ์', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
