#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_REF="yibfsniqbivhahyjxcmk"
PUSH_PATCH="$ROOT_DIR/patch-social-push-hooks.command"
INDEX="$ROOT_DIR/ios/App/App/public/index.html"
PBXPROJ="$ROOT_DIR/ios/App/App.xcodeproj/project.pbxproj"

printf '\nRunPacer — configuration APNs\n\n'

if [ ! -f "$INDEX" ]; then
  echo "ERREUR: index.html introuvable: $INDEX"
  exit 1
fi

# 1) Installer les hooks sociaux push si nécessaire.
if grep -q 'RunPacer social push bridge' "$INDEX" 2>/dev/null; then
  echo "✓ Hooks push déjà installés."
else
  if [ ! -f "$PUSH_PATCH" ]; then
    echo "ERREUR: patch-social-push-hooks.command introuvable. Fais git pull."
    exit 1
  fi
  echo "Installation des hooks push…"
  bash "$PUSH_PATCH"
fi

# 2) Détecter Team ID et Bundle ID depuis le projet Xcode.
TEAM_ID=""
BUNDLE_ID=""
if [ -f "$PBXPROJ" ]; then
  TEAM_ID="$(sed -n 's/.*DEVELOPMENT_TEAM = \([A-Z0-9]*\);.*/\1/p' "$PBXPROJ" | head -n 1)"
  BUNDLE_ID="$(sed -n 's/.*PRODUCT_BUNDLE_IDENTIFIER = \([^;]*\);.*/\1/p' "$PBXPROJ" | grep -v '\$(' | head -n 1 | tr -d ' \"')"
fi

if [ -z "$BUNDLE_ID" ]; then
  BUNDLE_ID="com.runpacer.app"
fi

if [ -z "$TEAM_ID" ]; then
  printf 'Team ID Apple introuvable automatiquement. Entre ton Team ID: '
  read -r TEAM_ID
fi

if [ -z "$TEAM_ID" ]; then
  echo "ERREUR: Team ID vide."
  exit 1
fi

echo "✓ Team ID détecté: $TEAM_ID"
echo "✓ Bundle ID: $BUNDLE_ID"

# 3) Trouver la clé APNs .p8 sans jamais l'afficher.
P8_PATH=""
CANDIDATES=()
for dir in "$HOME/Downloads" "$HOME/Desktop" "$HOME/Documents"; do
  if [ -d "$dir" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] && CANDIDATES+=("$f")
    done < <(find "$dir" -maxdepth 2 -type f -name 'AuthKey_*.p8' 2>/dev/null | head -n 20)
  fi
done

if [ "${#CANDIDATES[@]}" -eq 1 ]; then
  P8_PATH="${CANDIDATES[0]}"
  echo "✓ Une clé APNs .p8 a été trouvée automatiquement."
elif [ "${#CANDIDATES[@]}" -gt 1 ]; then
  echo "Plusieurs clés .p8 ont été trouvées:"
  i=1
  for f in "${CANDIDATES[@]}"; do
    echo "  $i) $f"
    i=$((i+1))
  done
  printf 'Choisis le numéro de la clé APNs: '
  read -r PICK
  if ! [[ "$PICK" =~ ^[0-9]+$ ]] || [ "$PICK" -lt 1 ] || [ "$PICK" -gt "${#CANDIDATES[@]}" ]; then
    echo "ERREUR: choix invalide."
    exit 1
  fi
  P8_PATH="${CANDIDATES[$((PICK-1))]}"
else
  echo "Aucune clé AuthKey_*.p8 trouvée dans Downloads/Desktop/Documents."
  echo "Télécharge d'abord une APNs Auth Key depuis Apple Developer, puis relance ce script."
  exit 2
fi

BASENAME="$(basename "$P8_PATH")"
KEY_ID="${BASENAME#AuthKey_}"
KEY_ID="${KEY_ID%.p8}"
if [ -z "$KEY_ID" ] || [ "$KEY_ID" = "$BASENAME" ]; then
  printf 'Key ID Apple introuvable depuis le nom du fichier. Entre le Key ID: '
  read -r KEY_ID
fi

if [ -z "$KEY_ID" ]; then
  echo "ERREUR: Key ID vide."
  exit 1
fi

echo "✓ Key ID détecté: $KEY_ID"

# 4) Encoder la clé localement. La valeur n'est jamais imprimée.
PRIVATE_KEY_B64="$(base64 < "$P8_PATH" | tr -d '\r\n')"
if [ -z "$PRIVATE_KEY_B64" ]; then
  echo "ERREUR: impossible de lire la clé .p8."
  exit 1
fi

# 5) Choisir Supabase CLI sans stocker de secret dans le repo.
if command -v supabase >/dev/null 2>&1; then
  SB=(supabase)
elif command -v npx >/dev/null 2>&1; then
  SB=(npx --yes supabase@latest)
else
  echo "ERREUR: Supabase CLI et npx sont introuvables."
  unset PRIVATE_KEY_B64
  exit 1
fi

echo "Envoi sécurisé des secrets à Supabase…"
set +e
"${SB[@]}" secrets set \
  --project-ref "$PROJECT_REF" \
  "APPLE_APNS_KEY_ID=$KEY_ID" \
  "APPLE_APNS_TEAM_ID=$TEAM_ID" \
  "APPLE_APNS_PRIVATE_KEY_B64=$PRIVATE_KEY_B64" \
  "APPLE_APNS_BUNDLE_ID=$BUNDLE_ID" \
  "APPLE_APNS_ENVIRONMENT=production"
STATUS=$?
set -e
unset PRIVATE_KEY_B64

if [ "$STATUS" -ne 0 ]; then
  echo
  echo "ERREUR: Supabase n'a pas accepté les secrets."
  echo "Si le CLI demande une connexion, exécute 'supabase login' puis relance ce script."
  exit "$STATUS"
fi

echo
echo "✓ Configuration APNs envoyée à Supabase."
echo "✓ La clé privée n'a pas été copiée dans GitHub."
echo "✓ Les hooks Boss Run / Like / Commentaire sont installés."
echo
echo "Rebuild RunPacer sur les deux iPhone, puis envoie une nouvelle invitation Boss Run pour tester la notification."
