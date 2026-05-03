// Bridge the HTML5 Geolocation API to CoreLocation via a script message handler.
// This lets map ZIM files use navigator.geolocation; The native side prompts the user for CoreLocation
// permission on first use. Supports both getCurrentPosition (one-shot) and
// watchPosition (continuous).
(function () {
    const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.geolocation;
    if (!handler) {
        // Surface installation state explicitly so the Web Inspector can tell
        // "not installed" apart from "script never ran".
        window.__kiwixGeolocationShimInstalled = false;
        return;
    }

    let pending = new Array();
    let nextId = 1;

    function deliverSuccess(success, payload) {
        if (typeof success !== "function") {
            return;
        }
        success({
            coords: {
                latitude: payload.coords.latitude,
                longitude: payload.coords.longitude,
                accuracy: payload.coords.accuracy,
                altitude: payload.coords.altitude ?? null,
                altitudeAccuracy: payload.coords.altitudeAccuracy ?? null,
                heading: payload.coords.heading ?? null,
                speed: payload.coords.speed ?? null,
            },
            timestamp: payload.timestamp,
        });
    }

    function deliverError(error, err) {
        if (typeof error !== "function") {
            return;
        }
        error({
            code: err.code,
            message: err.message,
            PERMISSION_DENIED: 1,
            POSITION_UNAVAILABLE: 2,
            TIMEOUT: 3,
        });
    }

    window.__kiwixGeolocationResolve = function (payload) {
        if (payload && payload.coords) {
            pending.forEach((entry) => {
                deliverSuccess(entry.success, payload);
            });
        } else if (payload && payload.error) {
            pending.forEach((entry) => {
                deliverError(entry.error, payload.error);
            });
            if (payload.error.code === 1) {
                // on permission denied, clear out all pending
                pending = new Array();
                return;
            }
        }
        // remove all one-shot requests, they have been served
        pending = pending.filter((entry) => entry.isWatch == true);
    };

    function getCurrentPosition(success, error, options) {
        const id = nextId++;
        const entry = { id: id, success: success, error: error, isWatch: false };
        pending.push(entry);
        handler.postMessage({
            type: "getCurrentPosition",
            id: id,
            highAccuracy: !!(options && options.enableHighAccuracy),
        });
    }

    function watchPosition(success, error, options) {
        const id = nextId++;
        const entry = { id: id, success: success, error: error, isWatch: true };
        pending.push(entry);
        handler.postMessage({
            type: "watchPosition",
            id: id,
            highAccuracy: !!(options && options.enableHighAccuracy),
        });
        return id;
    }

    function clearWatch(id) {
        pending = pending.filter((entry) => { entry.id !== id });
        handler.postMessage({ type: "clearWatch", id: id });
    }

    const shim = {
        getCurrentPosition: getCurrentPosition,
        watchPosition: watchPosition,
        clearWatch: clearWatch,
    };
    let installed = false;
    try {
        Object.defineProperty(navigator, "geolocation", {
            configurable: true,
            value: shim,
        });
        installed = true;
    } catch (_) {
        try {
            // Some hardened runtimes mark navigator.geolocation non-configurable
            // on the instance; the prototype property is still replaceable.
            Object.defineProperty(Object.getPrototypeOf(navigator), "geolocation", {
                configurable: true,
                value: shim,
            });
            installed = true;
        } catch (_) {
            // Native navigator.geolocation stays in place.
        }
    }
    window.__kiwixGeolocationShimInstalled = installed;
})();
