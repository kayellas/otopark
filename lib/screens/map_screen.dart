import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';


class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  final TextEditingController _searchController = TextEditingController();

  // Filtreleme seçenekleri
  bool _showEmptyParkingSpots = false;
  bool _showFreeParking = false;
  bool _show24HourParking = false;
  bool _showTrafficCondition = false;

  // Filtre butonu pozisyonu
  Offset _filterButtonPosition = const Offset(20, 300);
  
  // İzmir merkez koordinatları
  final LatLng _izmir = const LatLng(38.4192, 27.1287);
  
  // Kullanıcı konumu
  LatLng? _userLocation;

  // İşaretçiler kümesi
  Set<Marker> _markers = {};
  
  // Tüm otopark verileri
  List<Map<String, dynamic>> _allParkingData = [];
    
  final List<Map<String, dynamic>> _favoriteParkingSpots = [];
    // API URL'leri
  final Map<String, String> _apiUrls = {
    'AÇIK OTOPARK': 'https://acikveri.bizizmir.com/api/3/action/datastore_search?resource_id=959c08c4-3e62-4e20-9e45-c334b0df31b1&',
    'KAPALI OTOPARK': 'https://acikveri.bizizmir.com/api/3/action/datastore_search?resource_id=6ad4ad67-5923-49ec-8725-3f44f6f72aec&',
    'YOL KENARI': 'https://acikveri.bizizmir.com/api/3/action/datastore_search?resource_id=a982c5d9-931d-4a75-a61d-23127d8ddad2&',
    'TARIFE': 'https://acikveri.bizizmir.com/api/3/action/datastore_search?resource_id=8dca3fb5-b7fe-4f16-91af-d8248da59f87',
    'SERVİS' : 'https://ulasav.csb.gov.tr/api/3/action/datastore_search?resource_id=8b183e98-9f93-4b88-81c5-424e08b8428f'
  };

  bool _isFavoriteParking(Map<String, dynamic> parking) {
    final parkingId = parking['OTOPARK_ADI']?.toString() ?? '';
    return _favoriteParkingSpots.any((favParking) => 
      favParking['OTOPARK_ADI']?.toString() == parkingId);
  }
  // Yükleniyor durumu
  bool _isLoading = true;
  StreamSubscription<Position>? _positionStreamSubscription;

  @override
void _toggleFavorite(Map<String, dynamic> parking) {
  setState(() {
    if (_isFavoriteParking(parking)) {
      _favoriteParkingSpots.removeWhere((favParking) => 
        favParking['OTOPARK_ADI'] == parking['OTOPARK_ADI']);
    } else {
      _favoriteParkingSpots.add(parking);
    }
  });
}
  void _showFavoritesDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Favori Otoparklar'),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: _favoriteParkingSpots.isEmpty
              ? const Center(
                  child: Text('Henüz favori otopark eklenmedi',
                      textAlign: TextAlign.center),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _favoriteParkingSpots.length,
                  itemBuilder: (context, index) {
                    final parking = _favoriteParkingSpots[index];
                    return ListTile(
                      title: Text(parking['OTOPARK_ADI'] ?? 'Bilinmeyen'),
                      subtitle: Text(parking['ADRES'] ?? 'Adres yok'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        Navigator.pop(context);
                        
                        // Navigate to the parking spot on the map
                        final lat = double.tryParse(parking['ENLEM']?.toString() ?? '') ?? 0;
                        final lng = double.tryParse(parking['BOYLAM']?.toString() ?? '') ?? 0;
                        
                        if (lat != 0 && lng != 0) {
                          _mapController?.animateCamera(
                            CameraUpdate.newLatLngZoom(LatLng(lat, lng), 16),
                          );
                          
                          // Show detail bottom sheet
                          _showParkingDetailsBottomSheet(parking);
                        }
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }
  @override
  void initState() {
    super.initState();
    
    _getCurrentLocation();
    _listenToLocationChanges();
    _fetchAndSetParkingMarkers(); // İlk veriler yüklenirken çağır
  }

  void _listenToLocationChanges() {
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // 10 metre arayla güncelleme
    );
    
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      setState(() {
        _userLocation = LatLng(position.latitude, position.longitude);
        // Debug bilgisi yazdır
        debugPrint('Konum güncellendi: ${position.latitude}, ${position.longitude}');
      });
    });
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _mapController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // Kullanıcı konumunu alma
  Future<void> _getCurrentLocation() async {
    try {
      // Konum iznini kontrol et ve gerekirse iste
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          if (!mounted) return; // mounted kontrolü
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Konum izni olmadan konumunuzu gösteremiyoruz')),
          );
          return;
        }
      }

      // Konum servisinin açık olup olmadığını kontrol et
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return; // mounted kontrolü
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen konum servisini açınız')),
        );
        // Kullanıcıdan konum servisini açmasını isteme
        await Geolocator.openLocationSettings();
        return;
      }

      // Konumu al
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Debug için konum bilgilerini yazdır
      debugPrint('Alınan konum: ${position.latitude}, ${position.longitude}');

      if (!mounted) return; // mounted kontrolü

      setState(() {
        _userLocation = LatLng(position.latitude, position.longitude);
      });

      if (_mapController != null && _userLocation != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(_userLocation!, 14),
        );
      }
    } catch (e) {
      debugPrint('Konum alma hatası: $e');
      if (!mounted) return; // mounted kontrolü
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Konum alınamadı: $e')),
      );
    }
  }

  // Tüm API'lerden otopark verilerini çekme
  Future<void> _fetchAndSetParkingMarkers() async {
    setState(() {
      _isLoading = true;
      _allParkingData = []; // Önceki verileri temizle
    });

    try {
      // Her API için ayrı ayrı veri çek
      for (final entry in _apiUrls.entries) {
        final parkingType = entry.key;
        final url = entry.value;
        
        debugPrint('Fetching data from API: $parkingType');
        
        final data = await _fetchParkingData(url, parkingType);
        if (data.isNotEmpty) {
          _allParkingData.addAll(data);
        }
      }

      debugPrint('Total parking data fetched: ${_allParkingData.length}');
      
      // Filtreleme olmadan tüm işaretçileri ayarlama
      _applyFilters();
      
    } catch (e) {
      debugPrint('Veri çekme hatası: $e');
      if (!mounted) return; // mounted kontrolü
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Veriler çekilirken hata oluştu: $e')),
      );
    } finally {
      if (mounted) { // mounted kontrolü
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
    // Tek bir API'den veri çekme
  Future<List<Map<String, dynamic>>> _fetchParkingData(String url, String parkingType) async {
    try {
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List records = data['result']['records'];
        
        // Her kayda otopark tipini ekle
        return List<Map<String, dynamic>>.from(records.map((record) {
          final map = Map<String, dynamic>.from(record);
          map['OTOPARK_TIPI'] = parkingType; // Otopark tipini ekle
          return map;
        }));
      } else {
        debugPrint('API hatası: ${response.statusCode} for $parkingType');
        return [];
      }
    } catch (e) {
      debugPrint('Veri çekme hatası ($parkingType): $e');
      return [];
    }
  }

  // Özel işaretçi simgesi oluşturma (farklı durumlar için farklı renkler)
  Future<BitmapDescriptor> _getMarkerIcon(String type, String parkingType) async {


    // Diğer otopark türleri için mevcut kod
    final Map<String, double> parkingTypeHues = {
      'AÇIK OTOPARK': BitmapDescriptor.hueBlue,
      'KAPALI OTOPARK': BitmapDescriptor.hueOrange,
      'YOL KENARI': BitmapDescriptor.hueCyan,
      'SERVİS': BitmapDescriptor.hueRed,
    };
      
    // Ücrete göre hue değerleri
    switch (type) {
      case 'KAPALI':
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
      case 'UCRETLI':
        return BitmapDescriptor.defaultMarkerWithHue(parkingTypeHues[parkingType] ?? BitmapDescriptor.hueViolet);
      case 'UCRETSIZ':
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
      default:
        return BitmapDescriptor.defaultMarkerWithHue(parkingTypeHues[parkingType] ?? BitmapDescriptor.hueBlue);
    }
  }

  // Filtreleri uygulama
  void _applyFilters() async {
    debugPrint('Applying filters to ${_allParkingData.length} parking data items');
    
    // Filtreleme kriterleri
    List<Map<String, dynamic>> filteredData = List.from(_allParkingData);

    if (_showEmptyParkingSpots) {
      filteredData = filteredData.where((parking) {
        final capacity = int.tryParse(parking['KAPASITE']?.toString() ?? '0') ?? 0;
        final estimatedUsage = (capacity * 0.7).toInt(); // Tahmini kullanım
        return capacity > estimatedUsage; // %70'ten az doluluk
      }).toList();
    }

    if (_showFreeParking) {
      filteredData = filteredData.where((parking) {
        final parkType = parking['UCRET_DURUMU']?.toString() ?? '';
        return parkType.toUpperCase().contains('UCRETSIZ');
      }).toList();
    }

    if (_show24HourParking) {
      filteredData = filteredData.where((parking) {
        final opening = parking['ACILIS_SAATI']?.toString().toUpperCase() ?? '';
        final closing = parking['KAPANIS_SAATI']?.toString().toUpperCase() ?? '';
        final workHours = '$opening - $closing';
        return workHours.contains('24') || workHours.contains('24 SAAT');
      }).toList();
    }

    debugPrint('After filtering: ${filteredData.length} parking spots remain');

    // İşaretçileri oluştur
    final Set<Marker> newMarkers = {};
    int validCoordinates = 0;
    
    for (var parking in filteredData) {
      final lat = double.tryParse(parking['ENLEM']?.toString() ?? '') ?? 0;
      final lng = double.tryParse(parking['BOYLAM']?.toString() ?? '') ?? 0;
      
      // Geçersiz koordinatları kontrol et
      if (lat == 0 || lng == 0 || lat < 30 || lat > 45 || lng < 20 || lng > 35) {
        debugPrint('Invalid coordinates for ${parking['OTOPARK_ADI']}: $lat, $lng');
        continue;
      }
      
      validCoordinates++;
      final name = parking['OTOPARK_ADI'] ?? 'Bilinmeyen';
      final capacity = parking['KAPASITE'] ?? 'Bilinmiyor';
      final parkingType = parking['UCRET_DURUMU'] ?? 'Bilinmiyor';
      final workHours = (parking['ACILIS_SAATI'] != null && parking['KAPANIS_SAATI'] != null)
    ? '${parking['ACILIS_SAATI']} - ${parking['KAPANIS_SAATI']}'
    : 'Bilinmiyor';

      
      // Park tipi belirleme
      String parkType = 'NORMAL';
      if (parkingType.toString().toUpperCase().contains('UCRETSIZ')) {
        parkType = 'UCRETSIZ';
      } else if (parkingType.toString().toUpperCase().contains('UCRETLI')) {
        parkType = 'UCRETLI';
      } else if (parkingType.toString().toUpperCase().contains('KAPALI')) {
        parkType = 'KAPALI';
      }
      
      try {
        final icon = await _getMarkerIcon(parkType, parking['OTOPARK_TIPI'] ?? 'AÇIK OTOPARK');
        
        newMarkers.add(
          Marker(
            markerId: MarkerId(name),
            position: LatLng(lat, lng),
            infoWindow: InfoWindow(
              title: name,
              snippet: 'Kapasite: $capacity\nÇalışma Saatleri: $workHours\nÜcret: $parkingType',
            ),
            icon: icon,
            onTap: () {
              _showParkingDetailsBottomSheet(parking);
            },
          ),
        );
      } catch (e) {
        debugPrint('Error creating marker for $name: $e');
      }
    }

    debugPrint('Created ${newMarkers.length} markers from $validCoordinates valid coordinates');

    if (!mounted) return; // mounted kontrolü
    
    setState(() {
      _markers = newMarkers;
    });
  }
    // Bilgi satırı oluşturucu widget
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }


  // Otopark detaylarını gösteren alt sayfa
// Otopark detaylarını gösteren alt sayfa
// Otopark detaylarını gösteren alt sayfa
// Otopark detaylarını gösteren alt sayfa
void _showParkingDetailsBottomSheet(Map<String, dynamic> parking) {
  // Otoparkın boş yer sayısını hesapla (örnek olarak - gerçek API'den gelecek)
  final capacity = int.tryParse(parking['KAPASITE']?.toString() ?? '0') ?? 0;
  final estimatedUsage = (capacity * 0.7).toInt(); // Tahmini kullanım
  final emptySpaces = capacity - estimatedUsage;
  final parkingType = parking['OTOPARK_TIPI'] ?? 'AÇIK OTOPARK';
  
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      // Favorilere eklenip eklenmediğini kontrol etmek için bir değişken
      // StatefulBuilder içinde tanımlandı
      bool isFavorite = _isFavoriteParking(parking);
      
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.4,
            maxChildSize: 0.8,
            expand: false,
            builder: (context, scrollController) {
              return SingleChildScrollView(
                controller: scrollController,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 5,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      
                      // Başlık ve favorileme butonu
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  parking['OTOPARK_ADI'] ?? 'Bilinmeyen Otopark',
                                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  parkingType,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              isFavorite ? Icons.favorite : Icons.favorite_border,
                              color: isFavorite ? Colors.red : Colors.grey,
                            ),
                            onPressed: () {
                              setModalState(() {
                                isFavorite = !isFavorite;
                                _toggleFavorite(parking); // <-- Add this
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(isFavorite 
                                        ? 'Favorilere eklendi' 
                                        : 'Favorilerden çıkarıldı'),
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                              });
                            },

                          ),
                        ],
                      ),
                      
                      const Divider(height: 24),
                      
                      // Boş yer bilgisi
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: emptySpaces > 0 ? Colors.green[50] : Colors.red[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: emptySpaces > 0 ? Colors.green : Colors.red,
                            width: 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              emptySpaces > 0 
                                ? '$emptySpaces Boş Yer Mevcut' 
                                : 'Boş Yer Yok',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: emptySpaces > 0 ? Colors.green[800] : Colors.red[800],
                              ),
                            ),
                            Text(
                              'Toplam Kapasite: ${parking['KAPASITE'] ?? 'Bilinmiyor'}',
                              style: TextStyle(
                                color: Colors.grey[800],
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Otopark bilgileri
                      _buildInfoRow('İlçe', parking['ILCE'] ?? 'Bilinmiyor'),
                      _buildInfoRow('Adres', parking['ADRES'] ?? 'Adres bilgisi yok'),
                      _buildInfoRow(
                        'Çalışma Saatleri',
                        '${parking['ACILIS_SAATI'] ?? 'Bilinmiyor'} - ${parking['KAPANIS_SAATI'] ?? 'Bilinmiyor'}',
                      ),
                      _buildInfoRow('Ücret Durumu', parking['UCRET_DURUMU'] ?? 'Bilinmiyor'),
                      _buildInfoRow('Ücretsiz Park Süresi', parking['UCRETSIZ_PARK_SURESI'] ?? 'Bilgi yok'),
                      _buildInfoRow('Tarife', parking['otopark_ucretleri'] ?? 'Bilgi yok'),
                      
                      const SizedBox(height: 24),
                      
                      // Butonlar
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.directions),
                              label: const Text('Yol Tarifi Al'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF246AFB),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: () async {
                                Navigator.pop(context);
                                final lat = double.tryParse(parking['ENLEM']?.toString() ?? '') ?? 0;
                                final lng = double.tryParse(parking['BOYLAM']?.toString() ?? '') ?? 0;
                                
                                if (lat != 0 && lng != 0) {
                                  // Haritada göster
                                  _mapController?.animateCamera(
                                    CameraUpdate.newLatLngZoom(LatLng(lat, lng), 16),
                                  );
                                  
                                  // Yol tarifi için harici uygulamayı aç
                                  final String destination = '$lat,$lng';
                                  final String parkingName = Uri.encodeComponent(parking['OTOPARK_ADI'] ?? 'Otopark');
                                  
                                  // Kullanıcı konumu varsa, onu başlangıç noktası olarak kullan
                                  String origin = '';
                                  if (_userLocation != null) {
                                    origin = '&origin=${_userLocation!.latitude},${_userLocation!.longitude}';
                                  }
                                  
                                  // Google Maps URL'i oluştur
                                  final url = 'https://www.google.com/maps/dir/?api=1$origin&destination=$destination&destination_place_id=$parkingName&travelmode=driving';
                                  
                                  final Uri uri = Uri.parse(url);
                                  if (await canLaunchUrl(uri)) {
                                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                                  } else {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Harita uygulaması açılamadı')),
                                      );
                                    }
                                  }
                                } else {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Bu otopark için konum bilgisi bulunamadı')),
                                    );
                                  }
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        }
      );
    },
  );
}

  // Bilgi satırı widget'ı
  Widget _buildDetailInfoRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$title:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  void _searchLocation() {
    final searchText = _searchController.text.toLowerCase();
    if (searchText.isEmpty) return;

    // İsme göre otopark arama
    final matchingParking = _allParkingData.firstWhere(
      (parking) => (parking['OTOPARK_ADI'] ?? '').toString().toLowerCase().contains(searchText) || 
                   (parking['ADRES'] ?? '').toString().toLowerCase().contains(searchText) ||
                   (parking['ILCE'] ?? '').toString().toLowerCase().contains(searchText),
      orElse: () => <String, dynamic>{},
    );

    if (matchingParking.isNotEmpty) {
      final lat = double.tryParse(matchingParking['ENLEM']?.toString() ?? '') ?? 0;
      final lng = double.tryParse(matchingParking['BOYLAM']?.toString() ?? '') ?? 0;
      
      if (lat != 0 && lng != 0) {
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(lat, lng), 15),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${matchingParking['OTOPARK_ADI']} bulundu')),
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$searchText" ile eşleşen otopark bulunamadı')),
        );
      }
    }
  }

  void _toggleFilterPanel() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return Padding(
              padding: MediaQuery.of(context).viewInsets,
              child: _buildFilterPanel(setState),
            );
          }
        );
      },
    );
  }

  Widget _buildFilterPanel(StateSetter setModalState) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        children: [
          Center(
            child: Container(
              width: 40,
              height: 5,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const Text(
            'Filtreler',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          _buildFilterOption(
            'Boş Park Yerleri', 
            _showEmptyParkingSpots, 
            (value) {
              setModalState(() => _showEmptyParkingSpots = value);
              setState(() => _showEmptyParkingSpots = value);
            },
          ),
          _buildFilterOption(
            'Ücretsiz Otoparklar', 
            _showFreeParking, 
            (value) {
              setModalState(() => _showFreeParking = value);
              setState(() => _showFreeParking = value);
            },
          ),
          _buildFilterOption(
            '24 Saat Açık Olanlar', 
            _show24HourParking, 
            (value) {
              setModalState(() => _show24HourParking = value);
              setState(() => _show24HourParking = value);
            },
          ),
          _buildFilterOption(
            'Trafik Durumunu Göster', 
            _showTrafficCondition, 
            (value) {
              setModalState(() => _showTrafficCondition = value);
              setState(() => _showTrafficCondition = value);
              // Not: GoogleMapController sınıfında setTrafficEnabled metodu yok
              // Trafik durumu GoogleMap widget'ında trafficEnabled özelliği ile kontrol edilir
            },
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                _applyFilters();
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text('Uygula'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EgeParkGo', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF246AFB),
        actions: [
          // Add this button to the AppBar
          IconButton(
            icon: const Icon(Icons.favorite, color: Colors.white),
            onPressed: _showFavoritesDialog,
            tooltip: 'Favoriler',
          ),
        ],
      ),
      body: Stack(
        children: [
          // Google Harita
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _izmir,
              zoom: 12,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: true,
            compassEnabled: true,
            mapToolbarEnabled: true,
            trafficEnabled: _showTrafficCondition,
            onMapCreated: (controller) {
              setState(() {
                _mapController = controller;
                _getCurrentLocation();
              });
            },
            markers: _markers,
          ),
          
          // Yükleniyor göstergesi
          if (_isLoading)
            Container(
              color: Colors.black.withAlpha(128),
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF246AFB)),
                ),
              ),
            ),
          
          // Arama kutusu
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(51),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Otopark ara...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => _searchController.clear(),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                ),
                onSubmitted: (_) => _searchLocation(),
              ),
            ),
          ),
          
          // Filtre butonu
          Positioned(
            left: _filterButtonPosition.dx,
            top: _filterButtonPosition.dy,
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  _filterButtonPosition += details.delta;
                });
              },
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF246AFB),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(51),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: const Icon(Icons.filter_list, color: Colors.white),
                  onPressed: _toggleFilterPanel,
                  iconSize: 24,
                ),
              ),
            ),
          ),
          
          // Lejant (işaretçi tipleri açıklaması)
          Positioned(
            bottom: 80,
            right: 10,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(51),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),

            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "refreshButton",
            backgroundColor: const Color(0xFF246AFB),
            mini: true,
            onPressed: _fetchAndSetParkingMarkers,
            child: const Icon(Icons.refresh, color: Colors.white),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: "locationButton",
            backgroundColor: const Color(0xFF246AFB),
            onPressed: () {
              if (_userLocation != null) {
                _mapController?.animateCamera(
                  CameraUpdate.newLatLngZoom(_userLocation!, 15),
                );
              } else {
                _getCurrentLocation();
              }
            },
            child: const Icon(Icons.my_location, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterOption(String title, bool value, Function(bool) onChanged) {
    // Zengin renk paleti
    final primaryColor = const Color(0xFF2E7D32);    // Koyu yeşil
    final secondaryColor = const Color(0xFFE3F2FD);  // Açık yeşil arka plan
    final accentColor = const Color(0xFF4CAF50);     // Orta ton yeşil
   
   
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF246AFB),
          ),
        ],
      ),
    );
  }
  
  Widget _buildLegendItem(double hue, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: HSLColor.fromAHSL(1.0, hue, 1.0, 0.5).toColor(),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}