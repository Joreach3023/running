#!/usr/bin/env bash
set -euo pipefail

WEB_DIR="www"
OPEN_XCODE=true

echo "📥 Pull Git..."
git pull --rebase --autostash || true

# (Optionnel) Build web si script disponible
if npm run -s build; then
  echo "✅ Build web terminé."
else
  echo "ℹ️ Pas de script build, utilisation de ${WEB_DIR} tel quel."
fi

# Vérifs
if [[ ! -d "$WEB_DIR" ]]; then
  echo "❌ Dossier WEB_DIR '$WEB_DIR' introuvable"; exit 1
fi

echo "🧹 Nettoyage ios/App/public ..."
rm -rf ios/App/public/*
mkdir -p ios/App/public

echo "⚡ Capacitor copy/sync..."
npx --yes @capacitor/cli@7.4.2 copy ios
npx --yes @capacitor/cli@7.4.2 sync ios

if [ "${OPEN_XCODE}" = true ]; then
  echo "📂 Ouverture dans Xcode..."
  npx --yes @capacitor/cli@7.4.2 open ios
fi

echo "✅ Terminé."
