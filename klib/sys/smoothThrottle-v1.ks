{
	local SLEW_RATE is 0.3.
	export({
		local targetThrottle is throttle.
		local currentThrottle is targetThrottle.
		local lastUpdate is time:seconds.

		return lex(
			"current", {
				local sampleTime is time:seconds.
				local maxChange is SLEW_RATE * (sampleTime - lastUpdate).
				set lastUpdate to sampleTime.
				set currentThrottle to max(
					currentThrottle - maxChange,
					min(currentThrottle + maxChange, targetThrottle)
				).
				return currentThrottle.
			},
			"setTarget", {
				parameter newTarget.
				set targetThrottle to max(0, min(1, newTarget)).
			},
			"target", {
				return targetThrottle.
			},
			"reset", {
				parameter newThrottle is throttle.
				set targetThrottle to max(0, min(1, newThrottle)).
				set currentThrottle to targetThrottle.
				set lastUpdate to time:seconds.
			}
		).
	}).
}