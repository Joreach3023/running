const App = window.Capacitor?.Plugins?.App;
const Browser = window.Capacitor?.Plugins?.Browser;

if (App && Browser) {
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
}
