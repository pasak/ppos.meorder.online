import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:meorder_product/lib/EnvConfig.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:meorder_product/screen/ProductPackScreen.dart';

class ProductItemScreen extends StatefulWidget {
  final EnvConfig config;
  final Map<String, dynamic> group;

  const ProductItemScreen({super.key, required this.config, required this.group});

  @override
  State<ProductItemScreen> createState() => _ProductItemScreenState();
}

class _ProductItemScreenState extends State<ProductItemScreen> {
  bool _isLoading = false;
  List<dynamic> _productItems = [];
  List<String> _unitNameList = [];
  String _parentName = '';
  String _error = '';

  @override
  void initState() {
    super.initState();
    _fetchProductItems();
  }

  Future<void> _fetchProductItems() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    final uri = Uri.parse('${widget.config.apiUrl}api/product-item/list');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${widget.config.apiToken}',
    };
    final body = jsonEncode({
      'shop_ID': widget.config.id,
      'product_group_ID': widget.group['ID'],
    });

    try {
      final response = await http.post(uri, headers: headers, body: body);
      if (response.statusCode == 200) {
        final Map<String, dynamic> responseJson = jsonDecode(response.body);
        if (responseJson['message'] == 'success') {
          final items = responseJson['ProductItemList'] ?? [];
          
          final Set<String> units = {};
          for (var item in items) {
            if (item['UnitName'] != null && item['UnitName'].toString().trim().isNotEmpty) {
              units.add(item['UnitName'].toString().trim());
            }
          }

          setState(() {
            _productItems = items;
            _parentName = responseJson['parentName'] ?? widget.group['GroupName'] ?? 'สินค้า';
            _unitNameList = ['ขวด', 'ซอง', 'กล่อง', 'กระป๋อง', 'ชิ้น'];
          });
        } else {
          setState(() {
            _error = responseJson['message'] ?? 'Error loading data';
          });
        }
      } else {
        setState(() {
          _error = 'API Error ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Network Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveProductItem(Map<String, dynamic> payload) async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    final uri = Uri.parse('${widget.config.apiUrl}api/product-item/save');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${widget.config.apiToken}',
    };

    try {
      final response = await http.post(uri, headers: headers, body: jsonEncode(payload));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['message'] == 'success' || data['ID'] != null) {
          await _fetchProductItems();
        } else {
          setState(() { _error = data['message'] ?? 'Save failed'; });
        }
      } else {
        setState(() { _error = 'API Error ${response.statusCode}'; });
      }
    } catch (e) {
      setState(() { _error = 'Network Error: $e'; });
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  Future<void> _deleteProductItem(var id) async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    final uri = Uri.parse('${widget.config.apiUrl}api/product-item/delete');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${widget.config.apiToken}',
    };

    try {
      final response = await http.post(uri, headers: headers, body: jsonEncode({'ID': id}));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['message'] == 'success') {
          await _fetchProductItems();
        } else {
          setState(() { _error = data['message'] ?? 'Delete failed'; });
        }
      } else {
        setState(() { _error = 'API Error ${response.statusCode}'; });
      }
    } catch (e) {
      setState(() { _error = 'Network Error: $e'; });
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  void _confirmDelete(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('ยืนยันการลบ'),
          content: Text('คุณต้องการลบสินค้า "${item['ProductName'] ?? item['ID']}" ใช่หรือไม่?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _deleteProductItem(item['ID']);
              },
              child: const Text('ลบ', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveMedia(Map<String, dynamic> item, String filePath, StateSetter setStateDialog) async {
    setState(() { _isLoading = true; });
    
    final uri = Uri.parse('${widget.config.apiUrl}api/product-item/save-media');
    var request = http.MultipartRequest('POST', uri);
    request.headers.addAll({
      'Authorization': 'Bearer ${widget.config.apiToken}',
    });
    
    request.fields['ParentID'] = item['ID'].toString();
    request.files.add(await http.MultipartFile.fromPath('PictureFile', filePath));

    try {
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['message'] == 'success') {
          setStateDialog(() {
            final mediaList = List<dynamic>.from(item['Media'] ?? []);
            mediaList.add(data['data']);
            item['Media'] = mediaList;
          });
          _fetchProductItems();
        } else {
          setState(() { _error = data['message'] ?? 'Save media failed'; });
        }
      } else {
        setState(() { _error = 'API Error ${response.statusCode}'; });
      }
    } catch (e) {
      setState(() { _error = 'Network Error: $e'; });
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  Future<void> _deleteMedia(Map<String, dynamic> media, Map<String, dynamic> item, StateSetter setStateDialog) async {
    setState(() { _isLoading = true; _error = ''; });

    final uri = Uri.parse('${widget.config.apiUrl}api/product-item/delete-media');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${widget.config.apiToken}',
    };

    try {
      final response = await http.post(uri, headers: headers, body: jsonEncode({'ID': media['ID']}));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['message'] == 'success') {
          setStateDialog(() {
            final mediaList = List<dynamic>.from(item['Media'] ?? []);
            mediaList.removeWhere((m) => m['ID'] == media['ID']);
            item['Media'] = mediaList;
          });
          _fetchProductItems();
        } else {
          setState(() { _error = data['message'] ?? 'Delete media failed'; });
        }
      } else {
        setState(() { _error = 'API Error ${response.statusCode}'; });
      }
    } catch (e) {
      setState(() { _error = 'Network Error: $e'; });
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  void _confirmDeleteMedia(Map<String, dynamic> media, Map<String, dynamic> item, StateSetter setStateDialog) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('ยืนยันการลบรูปภาพ'),
          content: const Text('คุณต้องการลบรูปภาพนี้ใช่หรือไม่?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _deleteMedia(media, item, setStateDialog);
              },
              child: const Text('ลบ', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  void _showMediaDialog(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final mediaList = List<dynamic>.from(item['Media'] ?? []);

            return AlertDialog(
              title: Text('รูปภาพ: ${item['ProductName'] ?? item['ID']}'),
              content: SizedBox(
                width: double.maxFinite,
                child: mediaList.isEmpty
                    ? const Center(heightFactor: 4, child: Text('ไม่มีรูปภาพ', style: TextStyle(fontSize: 16)))
                    : GridView.builder(
                        shrinkWrap: true,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: mediaList.length,
                        itemBuilder: (context, index) {
                          final media = Map<String, dynamic>.from(mediaList[index]);
                          final imageUrl = '${widget.config.apiUrl}uploads/${media['FileName']}';

                          return Stack(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    imageUrl,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                    errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.broken_image, size: 40, color: Colors.grey)),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: Colors.white70,
                                  child: IconButton(
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                    onPressed: () => _confirmDeleteMedia(media, item, setStateDialog),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('ปิด'),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('เพิ่มรูปภาพ'),
                  onPressed: () async {
                    final ImagePicker picker = ImagePicker();
                    final XFile? image = await picker.pickImage(source: ImageSource.camera);
                    if (image != null) {
                      await _saveMedia(item, image.path, setStateDialog);
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _openScanner({required Function(String) onScan}) {
    final MobileScannerController scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              AppBar(
                title: const Text('สแกนบาร์โค้ด'),
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Expanded(
                child: MobileScanner(
                  controller: scannerController,
                  onDetect: (capture) {
                    final List<Barcode> barcodes = capture.barcodes;
                    if (barcodes.isNotEmpty) {
                      final String code = barcodes.first.rawValue ?? "";
                      if (code.isNotEmpty) {
                        onScan(code);
                        Navigator.pop(context); // Close scanner
                      }
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    ).then((_) {
      scannerController.dispose();
    });
  }

  void _showEditDialog({Map<String, dynamic>? item}) {
    final bool isAdd = item == null;
    
    final TextEditingController idController = TextEditingController(text: item?['ID']?.toString() ?? '');
    final TextEditingController barcodeController = TextEditingController(text: item?['Barcode']?.toString() ?? '');
    final TextEditingController nameController = TextEditingController(text: item?['ProductName']?.toString() ?? _parentName);
    final TextEditingController priceController = TextEditingController(text: item?['Price']?.toString() ?? '');
    final TextEditingController unitController = TextEditingController(text: item?['UnitName']?.toString() ?? '');
    
    bool isTax = item?['Tax'] != 'N'; // default checked = V

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {

            return AlertDialog(
              title: Text(isAdd ? 'เพิ่มสินค้า' : 'แก้ไขสินค้า'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: idController,
                      decoration: const InputDecoration(
                        labelText: 'รหัสสินค้า',
                      ),
                      readOnly: !isAdd,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: barcodeController,
                            decoration: const InputDecoration(
                              labelText: 'Barcode',
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.qr_code_scanner),
                          color: Colors.blue,
                          onPressed: () {
                            _openScanner(onScan: (code) {
                              setStateDialog(() {
                                barcodeController.text = code;
                              });
                            });
                          },
                        ),
                      ],
                    ),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'ชื่อสินค้า (ไม่บังคับ)',
                      ),
                    ),
                    TextField(
                      controller: priceController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'ราคา',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: unitController,
                            decoration: const InputDecoration(
                              labelText: 'หน่วยนับ',
                            ),
                          ),
                        ),
                        if (_unitNameList.isNotEmpty)
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.arrow_drop_down),
                            onSelected: (String value) {
                              setStateDialog(() {
                                unitController.text = value;
                              });
                            },
                            itemBuilder: (BuildContext context) {
                              return _unitNameList.map((String unit) {
                                return PopupMenuItem<String>(
                                  value: unit,
                                  child: Text(unit),
                                );
                              }).toList();
                            },
                          ),
                      ],
                    ),
                    CheckboxListTile(
                      title: const Text('ภาษี'),
                      value: isTax,
                      onChanged: (bool? value) {
                        setStateDialog(() {
                          isTax = value ?? true;
                        });
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('ยกเลิก'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final taxValue = isTax ? 'V' : 'N';
                    final payload = {
                      'ID': idController.text,
                      'Barcode': barcodeController.text,
                      'product_group_ID': widget.group['ID'],
                      'ProductName': nameController.text,
                      'Price': num.tryParse(priceController.text) ?? 0,
                      'UnitName': unitController.text,
                      'Tax': taxValue,
                    };
                    _saveProductItem(payload);
                    Navigator.pop(context);
                  },
                  child: const Text('บันทึก'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_parentName.isNotEmpty ? _parentName : 'สินค้า'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchProductItems,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showEditDialog(),
            tooltip: 'เพิ่มสินค้า',
          ),
        ],
      ),
      body: _isLoading && _productItems.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(_error, style: const TextStyle(color: Colors.red)),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _fetchProductItems,
                    child: _productItems.isEmpty
                        ? ListView(
                            children: const [
                              Padding(
                                padding: EdgeInsets.all(32.0),
                                child: Center(child: Text('ไม่มีข้อมูลสินค้า')),
                              )
                            ],
                          )
                        : ListView.builder(
                            itemCount: _productItems.length,
                            itemBuilder: (context, index) {
                              final item = Map<String, dynamic>.from(_productItems[index]);
                              final mediaList = List<dynamic>.from(item['Media'] ?? []);
                              
                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(12.0),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(item['ProductName'] ?? '-', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                                const SizedBox(height: 4),
                                                Text('Barcode: ${item['Barcode']}'),
                                              ],
                                            ),
                                          ),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text('${item['Price']} : ${item['UnitName']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),

                                              if (item['StockCount'] != null && item['StockCount'] > 0) ...[
                                                const SizedBox(height: 4),
                                                Text('สต๊อก : ${item['StockCount']}', style: const TextStyle(color: Colors.black)),
                                              ]
                                              /*
                                              if (mediaList.isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Text('รูปภาพ : ${mediaList.length} รูป', style: const TextStyle(color: Colors.blue)),
                                              ]
                                              */
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton.icon(
                                          icon: const Icon(Icons.layers, color: Colors.black),
                                          label: const Text('แพ็ค', style: TextStyle(color: Colors.black)),
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(builder: (context) => ProductPackScreen(config: widget.config, item: item)),
                                            );
                                          },
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.image, color: Colors.green),
                                          onPressed: () => _showMediaDialog(item),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.edit, color: Colors.blue),
                                          onPressed: () => _showEditDialog(item: item),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete, color: Colors.red),
                                          onPressed: () => _confirmDelete(item),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}
