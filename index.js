import { App } from '@capacitor/app';

App.addListener('appUrlOpen', (event) => {
  if (event.url && event.url.startsWith('runpacer://')) {
    const code = new URL(event.url).searchParams.get('code');
    if (code) {
      console.log('Strava code reçu:', code);
      if (window.exchangeStravaCode) {
        window.exchangeStravaCode(code).catch(err => console.error('Erreur Strava: ' + err.message));
      }
    }
  }
});
