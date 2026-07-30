// Test double for lightning/empApi. Tracks a callback per channel, because the monitor
// subscribes to both the Aegis alert channel and the Flow error stream.
const callbacks = {};

export const subscribe = jest.fn((channel, replayId, callback) => {
    callbacks[channel] = callback;
    return Promise.resolve({ id: `sub-${channel}`, channel });
});
export const unsubscribe = jest.fn((sub, callback) => {
    if (callback) callback({});
    return Promise.resolve();
});
export const onError = jest.fn();
export const setDebugFlag = jest.fn();
export const isEmpEnabled = jest.fn(() => Promise.resolve(true));

/** Deliver a payload to a specific channel's subscriber. */
export function __emitOn(channel, payload) {
    if (callbacks[channel]) callbacks[channel]({ data: { payload } });
}
/** Convenience for the Aegis alert channel, which most tests use. */
export function __emit(payload) {
    __emitOn('/event/Aegis_User_Alert__e', payload);
}
export function __reset() {
    Object.keys(callbacks).forEach((k) => delete callbacks[k]);
    subscribe.mockClear();
    unsubscribe.mockClear();
    onError.mockClear();
}
