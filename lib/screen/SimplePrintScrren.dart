import 'package:flutter/material.dart';
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';

// This is the standalone screen widget moved from main.dart
class SimplePrintScreen extends StatefulWidget {
  const SimplePrintScreen({super.key});

  @override
  State<SimplePrintScreen> createState() => _SimplePrintScreenState();
}

class _SimplePrintScreenState extends State<SimplePrintScreen> {
  // Initial status displayed to the user
  String _status = 'Printer ready';

  @override
  void initState() {
    super.initState();
    // You might want to initialize SunmiPrinter connection here in a real app
    // e.g., SunmiPrinter.initService();
  }

  // Function to handle the actual printing logic
  Future<void> _printTest() async {
    try {
      // Basic text printing
      await SunmiPrinter.printText('Simple raw text');
      
      // Bold and centered text
      await SunmiPrinter.printText(
        'Bold text centered',
        style: SunmiTextStyle(bold: true, align: SunmiPrintAlign.CENTER),
      );

      await SunmiPrinter.lineWrap(2); // Jump 2 lines
      
      // Large font size text
      await SunmiPrinter.printText(
        'Very Large font!',
        style: SunmiTextStyle(fontSize: 80),
      );

      // Custom font size text
      await SunmiPrinter.printText(
        'Custom font size!!!',
        style: SunmiTextStyle(fontSize: 32),
      );

      // Print a QR code
      await SunmiPrinter.printQRCode(
        'https://github.com/brasizza/sunmi_printer',
        style: SunmiQrcodeStyle(
          qrcodeSize: 3,
          errorLevel: SunmiQrcodeLevel.LEVEL_H,
        ),
      ); 
      
      // Final feed and cut
      await SunmiPrinter.lineWrap(4); // Extra lines to push receipt out
      await SunmiPrinter.cut(); // Cut the receipt

      setState(() {
        _status = 'Print successful!';
      });
    } catch (e) {
      setState(() {
        _status = 'Printing failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sunmi V2s Test')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // Display the printer status
            Text(_status, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 30),
            // Button to trigger the print function
            ElevatedButton(
              onPressed: _printTest,
              child: const Text('Print Test Receipt'),
            ),
          ],
        ),
      ),
    );
  }
}
