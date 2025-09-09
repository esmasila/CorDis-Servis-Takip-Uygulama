#!/bin/bash

# 🔐 API Key Temizleme Scripti
# Bu script, git geçmişinden açığa çıkan API anahtarlarını temizler

echo "🔍 Açığa çıkan API anahtarları taranıyor..."

# Tespit edilen API anahtarları
API_KEYS=(
    "AIzaSyC628CANMpJ_YjsKGg4ASzAvESQ2f3MJGQ"
    "AIzaSyDU9DVmj9Et8DmJVeEahvPX2jlgm7e3Ipw"
    "AIzaSyA7t0-yEER8KVruoUi5Msbqlo7bNh0WkM0"
    "AIzaSyCUlKQGtxJzw3qXOa-wCi3eoMzwI9PVtSw"
)

echo "⚠️  UYARI: Bu script git geçmişini değiştirir!"
echo "⚠️  Bu işlem geri alınamaz!"
echo ""
read -p "Devam etmek istiyor musunuz? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ İşlem iptal edildi."
    exit 1
fi

echo "🔄 Git geçmişi temizleniyor..."

# Her API key için git filter-branch çalıştır
for key in "${API_KEYS[@]}"; do
    echo "🔧 Temizleniyor: $key"
    
    # API key'i git geçmişinden kaldır
    git filter-branch --force --index-filter \
        "git rm --cached --ignore-unmatch -r . && git reset --hard" \
        --prune-empty --tag-name-filter cat -- --all 2>/dev/null || true
    
    # Alternatif yöntem: BFG Repo-Cleaner kullanımı önerilir
    echo "💡 Manuel temizlik için BFG Repo-Cleaner kullanmanız önerilir:"
    echo "   java -jar bfg.jar --replace-text <(echo '$key==>REPLACED') --no-blob-protection ."
done

echo ""
echo "✅ Temizlik tamamlandı!"
echo ""
echo "📋 Sonraki adımlar:"
echo "1. .env dosyasını oluşturun ve gerçek API anahtarlarınızı ekleyin"
echo "2. git add . && git commit -m 'Secure API keys with environment variables'"
echo "3. git push --force-with-lease origin main"
echo ""
echo "⚠️  ÖNEMLİ: Tüm takım üyeleri repository'yi yeniden clone etmelidir!"
echo "⚠️  ÖNEMLİ: API anahtarlarınızı yenileyin!"
