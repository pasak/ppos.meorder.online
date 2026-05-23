import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'package:flutter_usb_printer/flutter_usb_printer.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

import 'package:meorder_ppos/lib/EnvConfig.dart';

class PPosScreen extends StatefulWidget {
  final EnvConfig config;
  const PPosScreen({super.key, required this.config});

  @override
  State<PPosScreen> createState() => _PPosScreenState();
}

class _PPosScreenState extends State<PPosScreen> {
  // USB Properties
  FlutterUsbPrinter flutterUsbPrinter = FlutterUsbPrinter();
  List<Map<String, dynamic>> devices = [];
  bool connected = false;
  Map<String, dynamic>? connectedDevice;

  // LAN Properties
  final TextEditingController _ipController = TextEditingController(text: "192.168.1.100");
  final TextEditingController _textController = TextEditingController(text: "Sample Restaurant");
  bool isPrintingLan = false;
  String errorMessage = "";

  @override
  void initState() {
    super.initState();
    _getDevicelist();
  }

  @override
  void dispose() {
    _ipController.dispose();
    _textController.dispose();
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

  Future<img.Image> _textToImage(String text) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final textSpan = TextSpan(
      text: text,
      style: const TextStyle(color: Colors.black, fontSize: 40, fontWeight: FontWeight.bold),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    textPainter.layout(minWidth: 576, maxWidth: 576); // 80mm printer width
    
    // Draw white background
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

    // Convert text to image to bypass code page limitations
    final imageToPrint = await _textToImage(_textController.text);
    bytes += generator.imageRaster(imageToPrint, align: PosAlign.center);

    bytes += generator.feed(2);
    bytes += generator.cut();

    return bytes;
  }

  void _printReceiptUSB() async {
    if (!connected) return;

    try {
      List<int> bytes = await _generateReceiptBytes();
      await flutterUsbPrinter.write(Uint8List.fromList(bytes));
      
      setState(() { errorMessage = ""; });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Printed via USB successfully')),
      );
    } catch (e) {
      debugPrint("Error printing via USB: $e");
      setState(() { errorMessage = e.toString(); });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error printing via USB: $e')),
      );
    }
  }

  void _printReceiptLAN() async {
    if (_ipController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter Printer IP Address')),
      );
      return;
    }

    setState(() {
      isPrintingLan = true;
    });

    try {
      List<int> bytes = await _generateReceiptBytes();
      
      // Connect to the printer's IP on default raw printing port 9100
      Socket socket = await Socket.connect(_ipController.text, 9100, timeout: const Duration(seconds: 5));
      
      socket.add(bytes);
      await socket.flush();
      await socket.close();

      if (!mounted) return;
      setState(() { errorMessage = ""; });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Printed via LAN successfully')),
      );
    } catch (e) {
      debugPrint("Error printing via LAN: $e");
      if (!mounted) return;
      setState(() { errorMessage = e.toString(); });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error printing via LAN: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isPrintingLan = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PPOS Setup'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _getDevicelist,
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- LAN Section ---
              const Text(
                'LAN / Network Printer',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _ipController,
                decoration: const InputDecoration(
                  labelText: 'Printer IP Address',
                  hintText: 'e.g. 192.168.1.100',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _textController,
                decoration: const InputDecoration(
                  labelText: 'Text to Print',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              if (errorMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Text(
                    errorMessage,
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 55),
                ),
                onPressed: isPrintingLan ? null : _printReceiptLAN,
                child: isPrintingLan
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Test Print (LAN)', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 16),

              // --- USB Section ---
              const Text(
                'USB OTG Printer (Alternative)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
              if (connected)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    onPressed: _printReceiptUSB,
                    child: const Text('Test Print (USB)'),
                  ),
                ),
              
              const SizedBox(height: 48),
              
              // --- Proceed Button ---
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 55),
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  // Navigator.pushReplacement(
                  //   context,
                  //   MaterialPageRoute(builder: (context) => HomeScreen(config: widget.config)),
                  // );
                },
                child: const Text('Proceed to Home Screen', style: TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
