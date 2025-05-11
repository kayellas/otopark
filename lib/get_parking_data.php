<?php
// CORS başlıklarını ayarla (geliştirme aşamasında)
header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");

// Veritabanı bağlantı bilgileri
$servername = "localhost";
$username = "root";  // phpMyAdmin kullanıcı adınız
$password = "";      // phpMyAdmin şifreniz
$dbname = "otopark_db"; // Veritabanı adınız

// Veritabanı bağlantısını oluştur
$conn = new mysqli($servername, $username, $password, $dbname);

// Bağlantıyı kontrol et
if ($conn->connect_error) {
    die(json_encode(["error" => "Veritabanı bağlantı hatası: " . $conn->connect_error]));
}

// Türkçe karakter desteği
$conn->set_charset("utf8");

// Otoparkları getiren sorgu
$sql = "SELECT * FROM otoparklar";
$result = $conn->query($sql);

if ($result->num_rows > 0) {
    $parkingData = [];
    
    // Tüm verileri diziye ekle
    while($row = $result->fetch_assoc()) {
        $parkingData[] = $row;
    }
    
    // JSON olarak döndür
    echo json_encode(["success" => true, "data" => $parkingData]);
} else {
    echo json_encode(["success" => false, "message" => "Otopark verisi bulunamadı"]);
}

$conn->close();
?>
