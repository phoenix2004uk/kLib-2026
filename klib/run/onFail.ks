{
	local NOTIFY_FAILED is " failed - ".
	local DMSG_FAILED is " failed: ".
	export(lex(
		"shutdown", {
			parameter planResult, notifyType, logType is notifyType + " planning".
			if not planResult:ok {
				notify(notifyType + NOTIFY_FAILED + "shutting down").
				dmsg(logType + DMSG_FAILED + planResult:msg, true).
				shutdown.
			}
		},
		"reboot", {
			parameter rebootDelay, failureMessage, notifyType, logType is notifyType + " planning".
			notify(notifyType + NOTIFY_FAILED + "rebooting in " + rebootDelay + " seconds").
			dmsg(logType + DMSG_FAILED + failureMessage, true).
			wait rebootDelay.
			reboot.
		}
	)).
}