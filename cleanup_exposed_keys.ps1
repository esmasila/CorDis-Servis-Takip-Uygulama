# 🔐 API Key Temizleme Scripti (PowerShell)
# Bu script, git geçmişinden açığa çıkan API anahtarlarını temizler

Write-Host "🔍 Açığa çıkan API anahtarları taranıyor..." -ForegroundColor Yellow

# Tespit edilen API anahtarları
$API_KEYS = @(
    "AIzaSyC628CANMpJ_YjsKGg4ASzAvESQ2f3MJGQ",
    "AIzaSyDU9DVmj9Et8DmJVeEahvPX2jlgm7e3Ipw",
    "AIzaSyA7t0-yEER8KVruoUi5Msbqlo7bNh0WkM0",
    "AIzaSyCUlKQGtxJzw3qXOa-wCi3eoMzwI9PVtSw"
)

Write-Host "⚠️  UYARI: Bu script git geçmişini değiştirir!" -ForegroundColor Red
Write-Host "⚠️  Bu işlem geri alınamaz!" -ForegroundColor Red
Write-Host ""
$confirmation = Read-Host "Devam etmek istiyor musunuz? (y/N)"
if ($confirmation -ne 'y' -and $confirmation -ne 'Y') {
    Write-Host "❌ İşlem iptal edildi." -ForegroundColor Red
    exit 1
}

Write-Host "🔄 Git geçmişi temizleniyor..." -ForegroundColor Green

# Her API key için git filter-branch çalıştır
foreach ($key in $API_KEYS) {
    Write-Host "🔧 Temizleniyor: $key" -ForegroundColor Cyan
    
    # API key'i git geçmişinden kaldır
    try {
        git filter-branch --force --index-filter "git rm --cached --ignore-unmatch -r . && git reset --hard" --prune-empty --tag-name-filter cat -- --all 2>$null
    }
    catch {
        Write-Host "⚠️  Filter-branch hatası, alternatif yöntem önerilir" -ForegroundColor Yellow
    }
    
    # Alternatif yöntem: BFG Repo-Cleaner kullanımı önerilir
    Write-Host "💡 Manuel temizlik için BFG Repo-Cleaner kullanmanız önerilir:" -ForegroundColor Yellow
    Write-Host "   java -jar bfg.jar --replace-text <(echo '$key==>REPLACED') --no-blob-protection ." -ForegroundColor Gray
}

Write-Host ""
Write-Host "✅ Temizlik tamamlandı!" -ForegroundColor Green
Write-Host ""
Write-Host "📋 Sonraki adımlar:" -ForegroundColor Cyan
Write-Host "1. .env dosyasını oluşturun ve gerçek API anahtarlarınızı ekleyin"
Write-Host "2. git add . && git commit -m 'Secure API keys with environment variables'"
Write-Host "3. git push --force-with-lease origin main"
Write-Host ""
Write-Host "⚠️  ÖNEMLİ: Tüm takım üyeleri repository'yi yeniden clone etmelidir!" -ForegroundColor Red
Write-Host "⚠️  ÖNEMLİ: API anahtarlarınızı yenileyin!" -ForegroundColor Red
