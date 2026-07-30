export const ShowToastEvent = class extends CustomEvent {
    constructor(detail) {
        super('lightning__showtoast', { detail, bubbles: true, composed: true });
    }
};
