import { App } from '@capacitor/app';
import { Browser } from '@capacitor/browser';

App.addListener('appUrlOpen', async ({ url }) => {
  if (url?.startsWith('runpacer://')) {
    try {
      await Browser.close();
    } catch (_) {}
    const code = new URL(url).searchParams.get('code');
    if (code && window.exchangeCodeOnServer && window.saveTokens) {
      const tokens = await window.exchangeCodeOnServer(code);
      window.saveTokens(tokens);
    }
  }
});
