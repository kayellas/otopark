import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mysql1/mysql1.dart';

class DatabaseHelper {
  static Future<MySqlConnection> getConnection() async {
    return await MySqlConnection.connect(
      ConnectionSettings(
        host: dotenv.env['DB_HOST'] ?? 'localhost',
        port: int.tryParse(dotenv.env['DB_PORT'] ?? '3306') ?? 3306,
        user: dotenv.env['DB_USER'] ?? 'root',
        password: dotenv.env['DB_PASSWORD'] ?? '',
        db: dotenv.env['DB_NAME'] ?? 'egeparkgo',
      ),
    );
  }

  // Otopark verilerini çekmek için yeni metod
  static Future<List<Map<String, dynamic>>> getParkingData() async {
    final conn = await getConnection();
    try {
      final results = await conn.query('''
        (SELECT 
        otopark_adi AS OTOPARK_ADI,
        enlem AS ENLEM,
        boylam AS BOYLAM,
        kapasite AS KAPASITE,
        'ACIK' AS UCRET_DURUMU, // Yeni eklenen alan
        CONCAT(acilis_saati, '-', kapanis_saati) AS CALISMA_SAATLERI,
        ilce AS ILCE,
        adres AS ADRES,
        '' AS TELEFON
      FROM acik_alan_otopark)
      
      UNION ALL
      
      (SELECT 
        otopark_adi,
        enlem,
        boylam,
        kapasite,
        ucret_durumu,
        CONCAT(acilis_saati, '-', kapanis_saati),
        ilce,
        adres,
        telefon
      FROM kapali_otopark)
      
      UNION ALL
      
      (SELECT 
        otopark_adi,
        enlem,
        boylam,
        kapasite,
        'UCRETLI' AS UCRET_DURUMU,
        CONCAT(acilis_saati, '-', kapanis_saati),
        ilce,
        adres_veya_tarif AS ADRES,
        '' AS TELEFON
      FROM yol_kenari_otopark)
    ''');

      return results.map((row) {
        return {
          'OTOPARK_ADI': row[0],
          'ENLEM': row[1].toString(),
          'BOYLAM': row[2].toString(),
          'KAPASITE': row[3].toString(),
          'UCRET_DURUMU': row[4],
          'CALISMA_SAATLERI': row[5],
          'ILCE': row[6],
          'ADRES': row[7],
          'UCRETSIZ_PARK_SURESI': row[8],
          'TARIFE': row[9],
          'TELEFON': row[10],
        };
      }).toList();
    } finally {
      await conn.close();
    }
  }
}
