# RunPacer

RunPacer is a lightweight web app that helps you track your running sessions and monitor your pace. The entire application is contained in `index.html` along with a small service worker, so no build step is required.

## Usage

1. Clone or download this repository.
2. Open `index.html` in your web browser.
3. Allow the app to access your location if you want to record GPS tracks.

Your runs are stored locally in the browser. You can view statistics, generate training plans and share your progress. A Strava integration lets you connect your account and publish your activities automatically. The service worker enables offline access so the app can be installed as a Progressive Web App.

```
# Example
$ git clone <this repo>
$ cd running
$ xdg-open index.html  # or open the file in your browser of choice
```

That's it—RunPacer is ready to use.

To enable Strava uploads, set your Strava API client ID in `index.html` and click the link icon in the profile section to authorize the app. The Strava client secret is handled server-side, so you don't need to include it in the frontend.

## Confidentialite

Consultez [PRIVACY.md](PRIVACY.md) pour connaitre notre politique de confidentialite.
