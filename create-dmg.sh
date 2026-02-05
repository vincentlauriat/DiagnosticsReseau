#!/bin/bash
# Script de création de DMG pour NetDisco
# Usage: ./create-dmg.sh

set -e

APP_NAME="NetDisco"
DMG_NAME="NetDisco-Installer"
BUILD_DIR="build"
DMG_DIR="$BUILD_DIR/dmg"
VOLUME_NAME="NetDisco"

echo "🔨 Compilation de $APP_NAME en mode Release..."
xcodebuild -project NetDisco.xcodeproj \
    -scheme NetDisco \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    clean build

# Trouver l'application compilée
APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Erreur: Application non trouvée à $APP_PATH"
    exit 1
fi

echo "✅ Application compilée: $APP_PATH"

# Obtenir la version de l'application
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "1.0")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "1")
DMG_FINAL_NAME="${DMG_NAME}-${VERSION}.dmg"

echo "📦 Version: $VERSION (build $BUILD)"

# Nettoyer et créer le dossier DMG
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"

# Copier l'application
echo "📁 Copie de l'application..."
cp -R "$APP_PATH" "$DMG_DIR/"

# Créer le lien symbolique vers Applications
ln -s /Applications "$DMG_DIR/Applications"

# Supprimer l'ancien DMG s'il existe
rm -f "$BUILD_DIR/$DMG_FINAL_NAME"

echo "💿 Création du DMG..."

# Créer un DMG temporaire
hdiutil create -srcfolder "$DMG_DIR" \
    -volname "$VOLUME_NAME" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" \
    -format UDRW \
    -size 200m \
    "$BUILD_DIR/temp.dmg"

# Monter le DMG pour le personnaliser
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "$BUILD_DIR/temp.dmg" | grep -E '^/dev/' | head -1 | awk '{print $1}')
MOUNT_POINT="/Volumes/$VOLUME_NAME"

echo "🎨 Personnalisation du DMG..."

# Attendre que le volume soit monté
sleep 2

# Configurer l'apparence du DMG avec AppleScript
osascript << EOF
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {400, 100, 900, 450}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 80

        -- Positionner les icônes
        set position of item "$APP_NAME.app" of container window to {125, 170}
        set position of item "Applications" of container window to {375, 170}

        update without registering applications
        close
    end tell
end tell
EOF

# Synchroniser et démonter
sync
hdiutil detach "$DEVICE" -quiet

# Convertir en DMG compressé final
echo "🗜️  Compression du DMG..."
hdiutil convert "$BUILD_DIR/temp.dmg" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$BUILD_DIR/$DMG_FINAL_NAME"

# Nettoyer
rm -f "$BUILD_DIR/temp.dmg"
rm -rf "$DMG_DIR"

# Afficher le résultat
DMG_SIZE=$(du -h "$BUILD_DIR/$DMG_FINAL_NAME" | cut -f1)
echo ""
echo "✅ DMG créé avec succès!"
echo "📍 Emplacement: $BUILD_DIR/$DMG_FINAL_NAME"
echo "📏 Taille: $DMG_SIZE"
echo ""
echo "Pour installer:"
echo "  1. Double-cliquez sur le fichier DMG"
echo "  2. Glissez $APP_NAME vers Applications"
