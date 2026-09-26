// ============================================================================
// Telemetry Processor controller
//
// Runs on the dedicated telemetry kOS processor.
// Owns the refresh loop and CORE:MESSAGES queue, loads local screen-definition
// modules, and drives telemetryViewer-v1 one tick at a time.
//
// Mission-processor message contract:
//   list("load",   "moon-descent")
//   list("remove", "moon-descent")
//   list("show",   "moon-descent")
// ============================================================================
export({
	parameter screenRegistry, defaultScreens is list(), defaultActiveScreen is "".

	local REFRESH_RATE is 100.
	local REFRESH_WAIT is 1 / REFRESH_RATE.

	function telemetryLog {
		parameter message.
		// Log only. Never print directly to the telemetry terminal.
		dmsg("[Telemetry] " + message).
	}

	function loadTelemetryScreen {
		parameter viewer, screenName.

		if viewer:has(screenName) return ApiOK(false).
		if not screenRegistry:hasKey(screenName) {
			return ApiFail("Unknown telemetry screen: " + screenName).
		}

		return viewer:screen(
			screenName,
			import(screenRegistry[screenName])
		).
	}

	function removeTelemetryScreen {
		parameter viewer, screenName.

		if not viewer:has(screenName) return ApiOK(false).
		return viewer:remove(screenName).
	}

	function showTelemetryScreen {
		parameter viewer, screenName.
		return viewer:show(screenName).
	}

	function reportTelemetryResult {
		parameter actionName, screenName, apiResult.

		if not apiResult:ok {
			telemetryLog(actionName + " '" + screenName + "' failed: " + apiResult:msg).
		}
		return apiResult:ok.
	}

	function handleTelemetryMessage {
		parameter viewer, messageContent.

		if not messageContent:isType("List") or messageContent:length < 2 {
			telemetryLog("Ignoring malformed processor message").
			return.
		}

		local actionName is messageContent[0]:toString.
		local screenName is messageContent[1]:toString.
		local apiResult is ApiFail("Unknown telemetry action: " + actionName).

		if actionName = "load" {
			set apiResult to loadTelemetryScreen(viewer, screenName).
		}
		else if actionName = "remove" {
			set apiResult to removeTelemetryScreen(viewer, screenName).
		}
		else if actionName = "show" {
			set apiResult to showTelemetryScreen(viewer, screenName).
		}

		reportTelemetryResult(actionName, screenName, apiResult).
	}

	function processTelemetryMessages {
		parameter viewer.

		until core:messages:empty {
			handleTelemetryMessage(viewer, core:messages:pop:content).
		}
	}

	local viewer is import("telemetryViewer-v1"):create().

	for screenName in defaultScreens {
		reportTelemetryResult(
			"load",
			screenName,
			loadTelemetryScreen(viewer, screenName)
		).
	}

	if defaultActiveScreen <> "" {
		reportTelemetryResult(
			"show",
			defaultActiveScreen,
			showTelemetryScreen(viewer, defaultActiveScreen)
		).
	}

	terminal:input:clear().

	until false {
		processTelemetryMessages(viewer).
		viewer:tick().
		wait REFRESH_WAIT.
	}
}).