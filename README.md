# RunPacer

RunPacer is a lightweight web app that helps you track your running sessions and monitor your pace. The entire application is contained in `index.html` along with a small service worker, so no build step is required.

## Usage

1. Clone or download this repository.
2. Open `index.html` in your web browser.
3. Allow the app to access your location if you want to record GPS tracks.

Your runs are stored locally in the browser. You can view statistics, generate training plans and share your progress. A Strava integration lets you publish your activities directly if you provide a personal access token. The service worker enables offline access so the app can be installed as a Progressive Web App. Background data saving keeps a run active even when you switch pages or open other apps.

```
# Example
$ git clone <this repo>
$ cd running
$ xdg-open index.html  # or open the file in your browser of choice
```

That's it—RunPacer is ready to use.


## Confidentialite

Consultez [PRIVACY.md](PRIVACY.md) pour connaitre notre politique de confidentialite.
