import QtQuick
import Quickshell
import Quickshell.Services.Pam

// State shared by the lock surfaces of all monitors: the typed password,
// the PAM check and the unlock animation flag.
Scope {
    id: root

    signal unlocked()
    signal failed()

    property string currentText: ""
    property bool unlockInProgress: false
    property bool showFailure: false
    // True while the surfaces play their exit animation
    property bool unlocking: false

    // Typing after a failed attempt clears the error
    onCurrentTextChanged: showFailure = false

    function reset() {
        currentText = "";
        showFailure = false;
        unlockInProgress = false;
        unlocking = false;
    }

    function tryUnlock() {
        if (currentText === "" || unlockInProgress)
            return;
        unlockInProgress = true;
        pam.start();
    }

    PamContext {
        id: pam

        // Own PAM config next to this file: password only, no fingerprint prompts
        configDirectory: Qt.resolvedUrl("pam").toString().replace("file://", "")
        config: "password.conf"

        onPamMessage: {
            if (this.responseRequired)
                this.respond(root.currentText);
        }

        onCompleted: result => {
            if (result === PamResult.Success) {
                root.unlocked();
            } else {
                root.currentText = "";
                root.showFailure = true;
                root.failed();
            }
            root.unlockInProgress = false;
        }
    }
}
