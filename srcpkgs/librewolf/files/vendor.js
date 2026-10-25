// Use LANG environment variable to choose locale
pref("intl.locale.requested", "");

// Disable default browser checking.
pref("browser.shell.checkDefaultBrowser", false);

// Don't disable bundled extensions in the application directory.
pref("extensions.autoDisableScopes", 11);

// Linux low-memory watcher can unload inactive tabs before memory pressure becomes fatal.
pref("browser.tabs.unloadOnLowMemory", true);

// Halve periodic session-store writes on the HDD while retaining recovery.
pref("browser.sessionstore.interval", 30000);

// Avoid preloading a new-tab document before it is needed.
pref("browser.newtab.preload", false);

// Bound pending disk-cache writes while retaining enough buffering for a slow HDD.
// These limits are KiB per cache class (normal and priority).
pref("browser.cache.disk.max_chunks_memory_usage", 24576);
pref("browser.cache.disk.max_priority_chunks_memory_usage", 24576);

// Keep Fission site isolation while avoiding a second isolated process per site.
// A single prelaunch is retained for startup responsiveness; Firefox also caps
// preallocation to one process on systems with 4 GiB RAM or less.
pref("dom.ipc.processCount", 4);
pref("dom.ipc.processCount.webIsolated", 1);
pref("dom.ipc.processPrelaunch.fission.number", 1);

// The default is Google and we don't have API keys for it.
pref("geo.provider.network.url", "https://location.services.mozilla.com/v1/geolocate?key=%MOZILLA_API_KEY%");
