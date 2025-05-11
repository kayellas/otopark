import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _parkingData = [];
  
  // Sıralama için parametreler
  String _sortColumn = 'OTOPARK_ADI';
  bool _sortAscending = true;
  
  // Arama metni için controller
  final TextEditingController _searchController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _fetchParkingData();
    _loadFavoriteParkings(); // Kayıtlı otoparkları yükle
  }
  
  // Favorileri yükleme
  Future<void> _loadFavoriteParkings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedFavorites = prefs.getStringList('adminFavorites') ?? [];
      
      if (savedFavorites.isNotEmpty) {
        // Her bir favori ID'sini kullanarak tam veriyi bul
        for (String favoriteId in savedFavorites) {
          debugPrint('Saved favorite found: $favoriteId');
        }
      }
    } catch (e) {
      debugPrint('Error loading favorites: $e');
    }
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  
  // Otopark verilerini çekme
  Future<void> _fetchParkingData() async {
    setState(() {
      _isLoading = true;
    });
    
    const url = 'https://acikveri.bizizmir.com/api/3/action/datastore_search?resource_id=a982c5d9-931d-4a75-a61d-23127d8ddad2&limit=100';
    
    try {
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List records = data['result']['records'];
        
        setState(() {
          _parkingData = List<Map<String, dynamic>>.from(records.map((record) => 
            Map<String, dynamic>.from(record)
          ));
          _isLoading = false;
        });
      } else {
        throw Exception('API hatası: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Veri çekme hatası: $e');
      setState(() {
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Veriler çekilirken hata oluştu: $e')),
      );
    }
  }
  
  // Verileri sıralama
  void _sort<T>(String column, Comparable<T> Function(Map<String, dynamic>) getField) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
      
      _parkingData.sort((a, b) {
        final aValue = getField(a);
        final bValue = getField(b);
        
        return _sortAscending ? Comparable.compare(aValue, bValue) : Comparable.compare(bValue, aValue);
      });
    });
  }
  
  // Arama filtresi
  List<Map<String, dynamic>> _getFilteredData() {
    final searchTerm = _searchController.text.toLowerCase();
    
    if (searchTerm.isEmpty) {
      return _parkingData;
    }
    
    return _parkingData.where((parking) {
      final parkingId = parking['_id']?.toString().toLowerCase() ?? '';
      final parkingName = parking['OTOPARK_ADI']?.toString().toLowerCase() ?? '';
      final district = parking['ILCE']?.toString().toLowerCase() ?? '';
      
      return parkingId.contains(searchTerm) || 
             parkingName.contains(searchTerm) || 
             district.contains(searchTerm);
    }).toList();
  }
  
  // Otopark bilgisini düzenleme
  void _editParkingInfo(Map<String, dynamic> parking) {
    final TextEditingController nameController = TextEditingController(text: parking['OTOPARK_ADI']);
    final TextEditingController capacityController = TextEditingController(text: parking['KAPASITE']?.toString() ?? '');
    final TextEditingController feeController = TextEditingController(text: parking['UCRET_DURUMU']);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Otopark Bilgilerini Düzenle'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Otopark Adı'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: capacityController,
                decoration: const InputDecoration(labelText: 'Kapasite'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: feeController,
                decoration: const InputDecoration(labelText: 'Ücret Durumu'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              // Verileri güncelle - API'ye gerçek bir POST isteği atılacak
              setState(() {
                final index = _parkingData.indexOf(parking);
                if (index != -1) {
                  // API'ye gerçek istek burada yapılacak
                  // Şu an için sadece yerel veriyi güncelliyoruz
                  _parkingData[index]['OTOPARK_ADI'] = nameController.text;
                  _parkingData[index]['KAPASITE'] = capacityController.text;
                  _parkingData[index]['UCRET_DURUMU'] = feeController.text;
                }
              });
              
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Otopark bilgileri güncellendi')),
              );
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }
  
  // Otopark silme
  void _deleteParkingInfo(Map<String, dynamic> parking) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Otopark Kaydını Sil'),
        content: Text('${parking['OTOPARK_ADI']} otoparkını silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              // API'ye DELETE isteği gönderilecek
              setState(() {
                _parkingData.remove(parking);
              });
              
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Otopark kaydı silindi')),
              );
            },
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }
  
  // Yeni otopark ekleme
  void _addNewParking() {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController capacityController = TextEditingController();
    final TextEditingController feeController = TextEditingController();
    final TextEditingController districtController = TextEditingController();
    final TextEditingController addressController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yeni Otopark Ekle'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Otopark Adı *'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: capacityController,
                decoration: const InputDecoration(labelText: 'Kapasite *'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: feeController,
                decoration: const InputDecoration(labelText: 'Ücret Durumu *'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: districtController,
                decoration: const InputDecoration(labelText: 'İlçe'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(labelText: 'Adres'),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              // Gerekli alanların kontrolü
              if (nameController.text.isEmpty || 
                  capacityController.text.isEmpty || 
                  feeController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Lütfen zorunlu alanları doldurun')),
                );
                return;
              }
              
              // API'ye POST isteği atılacak
              final newParking = {
                '_id': (_parkingData.length + 1).toString(),
                'OTOPARK_ADI': nameController.text,
                'KAPASITE': capacityController.text,
                'UCRET_DURUMU': feeController.text,
                'ILCE': districtController.text,
                'ADRES': addressController.text,
                // Diğer alanlar varsayılan değerlerle doldurulabilir
              };
              
              setState(() {
                _parkingData.add(newParking);
              });
              
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Yeni otopark kaydı eklendi')),
              );
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }
  
  // Excel raporu oluşturma (örnek gösterim - gerçek implementasyon için paketler gerekir)
  void _generateExcelReport() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Excel rapor oluşturuluyor...')),
    );
    
    // Excel oluşturma işlemi burada gerçekleştirilecek
    // Gerçek uygulamada excel veya csv paketleri kullanılmalı
    
    Future.delayed(const Duration(seconds: 2), () {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rapor başarıyla oluşturuldu ve indirildi')),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final filteredData = _getFilteredData();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF246AFB),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _fetchParkingData,
            tooltip: 'Verileri Yenile',
          ),
          IconButton(
            icon: const Icon(Icons.file_download, color: Colors.white),
            onPressed: _generateExcelReport,
            tooltip: 'Excel Raporu İndir',
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () {
              Navigator.of(context).pop(); // Admin panelinden çıkış
            },
            tooltip: 'Çıkış Yap',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF246AFB),
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: _addNewParking,
        tooltip: 'Yeni Otopark Ekle',
      ),
      body: Column(
        children: [
          // İstatistik kartları
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildStatCard(
                  'Toplam Otopark', 
                  _parkingData.length.toString(), 
                  Icons.local_parking,
                  const Color(0xFF246AFB),
                ),
                const SizedBox(width: 10),
                _buildStatCard(
                  'Toplam Kapasite', 
                  _calculateTotalCapacity(), 
                  Icons.directions_car,
                  Colors.green,
                ),
                const SizedBox(width: 10),
                _buildStatCard(
                  'Ücretsiz Otoparklar', 
                  _calculateFreeParking(), 
                  Icons.monetization_on_outlined,
                  Colors.orange,
                ),
              ],
            ),
          ),
          
          // Arama kutusu
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Otopark Ara...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  // Arama sonuçlarını güncellemek için setState çağrılır
                });
              },
            ),
          ),
          
          // Tablo başlığı
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Toplam ${filteredData.length} kayıt gösteriliyor',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          
          // Tablo
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        sortColumnIndex: _sortColumn == 'OTOPARK_ADI' ? 1 : 
                                        _sortColumn == 'KAPASITE' ? 2 : 
                                        _sortColumn == 'UCRET_DURUMU' ? 3 : null,
                        sortAscending: _sortAscending,
                        columns: [
                          const DataColumn(
                            label: Text('ID'),
                          ),
                          DataColumn(
                            label: const Text('Otopark Adı'),
                            onSort: (_, __) {
                              _sort<String>('OTOPARK_ADI', (parking) => 
                                parking['OTOPARK_ADI']?.toString() ?? '');
                            },
                          ),
                          DataColumn(
                            label: const Text('Kapasite'),
                            numeric: true,
                            onSort: (_, __) {
                              _sort<num>('KAPASITE', (parking) {
                                final capacity = parking['KAPASITE']?.toString() ?? '0';
                                return int.tryParse(capacity) ?? 0;
                              });
                            },
                          ),
                          DataColumn(
                            label: const Text('Ücret Durumu'),
                            onSort: (_, __) {
                              _sort<String>('UCRET_DURUMU', (parking) => 
                                parking['UCRET_DURUMU']?.toString() ?? '');
                            },
                          ),
                          const DataColumn(
                            label: Text('İlçe'),
                          ),
                          const DataColumn(
                            label: Text('İşlemler'),
                          ),
                        ],
                        rows: filteredData.map((parking) {
                          return DataRow(
                            cells: [
                              DataCell(Text(parking['_id']?.toString() ?? '')),
                              DataCell(Text(parking['OTOPARK_ADI'] ?? '')),
                              DataCell(Text(parking['KAPASITE']?.toString() ?? '')),
                              DataCell(Text(parking['UCRET_DURUMU'] ?? '')),
                              DataCell(Text(parking['ILCE'] ?? '')),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit, color: Colors.blue),
                                      onPressed: () => _editParkingInfo(parking),
                                      tooltip: 'Düzenle',
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => _deleteParkingInfo(parking),
                                      tooltip: 'Sil',
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
  
  // İstatistik kartı widget'ı
  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Toplam kapasite hesaplama
  String _calculateTotalCapacity() {
    int total = 0;
    
    for (var parking in _parkingData) {
      final capacity = parking['KAPASITE']?.toString() ?? '0';
      total += int.tryParse(capacity) ?? 0;
    }
    
    return total.toString();
  }
  
  // Ücretsiz otopark sayısı hesaplama
  String _calculateFreeParking() {
    int count = 0;
    
    for (var parking in _parkingData) {
      final fee = (parking['UCRET_DURUMU'] ?? '').toString();
      if (fee.toLowerCase().contains('ucretsiz') || fee.toLowerCase().contains('ücretsiz')) {
        count++;
      }
    }
    
    return count.toString();
  }
}