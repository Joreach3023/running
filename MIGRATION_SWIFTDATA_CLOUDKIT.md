# RunPacer — Migration SwiftData + CloudKit

Cette branche prépare le stockage personnel de RunPacer pour iOS 17+.

## Architecture cible

- **SwiftData (local)** : source de vérité pour les données personnelles de l'utilisateur.
- **CloudKit privé** : synchronisation iCloud de ces données personnelles quand la capability iCloud est activée.
- **Supabase** : conservé pour Boss Run, amis, invitations et push.
- **Strava** : conservé séparément; les jetons doivent rester dans un stockage sécurisé.

## Données à migrer depuis Supabase

### Vers SwiftData / CloudKit
- `runs`
- `user_backups.user_data`
- `user_backups.training_plan`
- partie personnelle de `profiles` (avatar, badges, XP, total_km, recent_runs)

### À garder dans Supabase
- `boss_runs`
- `br_members`
- `br_activities`
- `friendships`
- `rp_invites`
- `push_tokens`

## Ordre de migration

1. Ajouter la couche native SwiftData et le bridge Capacitor.
2. Garder le stockage SwiftData local tant que la capability CloudKit n'est pas activée.
3. Retrouver/remettre sous contrôle de version la source web courante utilisée dans `ios/App/App/public`.
4. Brancher le JavaScript RunPacer sur le bridge natif.
5. Migrer les courses Supabase vers SwiftData.
6. Migrer les backups/plans d'entraînement.
7. Activer iCloud + CloudKit + Background Modes/Remote notifications lorsque la signature Apple Developer le permet.
8. Valider la synchronisation multi-appareils avant de retirer les anciennes écritures Supabase personnelles.

## Important

`ios/.gitignore` ignore actuellement `App/App/public`, donc le contenu web embarqué dans l'app iOS n'est pas suivi dans Git. Il faut régler ce point avant de modifier les appels JavaScript de production.
