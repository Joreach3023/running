import { App } from '@capacitor/app';

App.addListener('appUrlOpen', async ({ url }) => {
  if (url?.startsWith('runpacer://')) {
    const code = new URL(url).searchParams.get('code');
    if (code && window.exchangeCodeOnServer && window.saveTokens) {
      const tokens = await window.exchangeCodeOnServer(code);
      window.saveTokens(tokens);
    }
  }
});
