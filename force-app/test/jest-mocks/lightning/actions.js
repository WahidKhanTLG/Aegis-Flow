export class CloseActionScreenEvent extends Event {
    constructor() {
        super('closeactionscreen');
    }

    static get CLOSE_ACTION_SCREEN() {
        return 'closeactionscreen';
    }
}
