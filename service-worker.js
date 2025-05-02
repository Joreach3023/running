// Nom du cache
const CACHE_NAME = 'runpacer-cache-v3';

// Fichiers à mettre en cache
const urlsToCache = [
  '/',
  '/index.html',
  '/manifest.json',
  '/css/styles.css',
  '/js/app.js',
  'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.2.0/css/all.min.css',
  'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.2.0/webfonts/fa-solid-900.woff2',
  'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.css',
  'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.js',
  'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-icon.png',
  'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-shadow.png'
];

// Installation du service worker
self.addEventListener('install', function(event) {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(function(cache) {
        console.log('Cache ouvert');
        return cache.addAll(urlsToCache);
      })
  );
});

// Récupération des ressources
self.addEventListener('fetch', function(event) {
  event.respondWith(
    caches.match(event.request)
      .then(function(response) {
        // Cache trouvé - retourner la réponse
        if (response) {
          return response;
        }
        
        // Pour les requêtes de tuiles de carte (OpenStreetMap), essayer de récupérer en ligne
        // mais ne pas mettre en cache (pour éviter de remplir le stockage)
        if (event.request.url.includes('tile.openstreetmap.org')) {
          return fetch(event.request);
        }
        
        return fetch(event.request).then(
          function(response) {
            // Vérifier si nous avons reçu une réponse valide
            if(!response || response.status !== 200 || response.type !== 'basic') {
              return response;
            }

            // Clone de la réponse
            var responseToCache = response.clone();

            caches.open(CACHE_NAME)
              .then(function(cache) {
                cache.put(event.request, responseToCache);
              });

            return response;
          }
        );
      })
    );
});

// Mise à jour du service worker
self.addEventListener('activate', function(event) {
  var cacheWhitelist = [CACHE_NAME];
  event.waitUntil(
    caches.keys().then(function(cacheNames) {
      return Promise.all(
        cacheNames.map(function(cacheName) {
          if (cacheWhitelist.indexOf(cacheName) === -1) {
            console.log('Suppression de l\'ancien cache:', cacheName);
            return caches.delete(cacheName);
          }
        })
      );
    })
  );
});

// Gestion des synchronisations en arrière-plan
self.addEventListener('sync', function(event) {
  if (event.tag === 'sync-run-data') {
    event.waitUntil(syncRunData());
  }
});

// Stockage des données de course en arrière-plan
let backgroundRunData = null;

// Dans service-worker.js
self.addEventListener('message', (event) => {
  if (event.data.type === 'SET_BACKGROUND_RUN') {
    backgroundRunData = event.data.runData;
    console.log('Données de course stockées pour arrière-plan');
  }
  else if (event.data.type === 'UPDATE_BACKGROUND_RUN') {
    // Fusionner les nouvelles données avec les existantes
    if (backgroundRunData) {
      backgroundRunData = {
        ...backgroundRunData,
        ...event.data.runData,
        locations: [...backgroundRunData.locations, ...event.data.runData.locations]
      };
    } else {
      backgroundRunData = event.data.runData;
    }
    console.log('Données de course mises à jour');
  }
  else if (event.data.type === 'GET_BACKGROUND_RUN') {
    event.ports[0].postMessage({
      type: 'BACKGROUND_RUN_DATA',
      runData: backgroundRunData
    });
    backgroundRunData = null; // Nettoyer après envoi
  }
});

// Fonction pour synchroniser les données de course
function syncRunData() {
  if (!backgroundRunData) {
    return Promise.resolve();
  }

  return new Promise((resolve) => {
    // Simuler l'envoi des données au serveur
    console.log('Synchronisation des données de course en arrière-plan:', backgroundRunData);
    
    // Envoyer les données à la page lorsque l'application est rouverte
    self.clients.matchAll().then(clients => {
      clients.forEach(client => {
        client.postMessage({
          type: 'BACKGROUND_RUN_DATA',
          runData: backgroundRunData
        });
      });
    });
    
    resolve();
  });
}
