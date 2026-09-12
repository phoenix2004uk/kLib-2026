{
	local RCS_VELOCITY_THRESHOLD is 0.05.
	local RCS_VELOCITY_TAPER is 0.5.
	local FLOATING_POINT_NOISE is 1e-9.

	local RCS_DEADBAND is 0.05.
	local rcsPulseAccumulator is list(0, 0, 0).

	function rcsPulseControl {
		parameter requestedControl, axis.

		if not rcs {
			set rcsPulseAccumulator to list(0, 0, 0).
			return 0.
		}

		if abs(requestedControl) < FLOATING_POINT_NOISE {
			set rcsPulseAccumulator[axis] to 0.
			return 0.
		}

		// Above the deadband, use the requested value directly.
		if abs(requestedControl) >= RCS_DEADBAND {
			set rcsPulseAccumulator[axis] to 0.
			return requestedControl.
		}

		// Accumulate the fractional pulse requirement.
		set rcsPulseAccumulator[axis] to
			rcsPulseAccumulator[axis]
			+ requestedControl / RCS_DEADBAND.

		if rcsPulseAccumulator[axis] >= 1 {
			set rcsPulseAccumulator[axis] to
				rcsPulseAccumulator[axis] - 1.
			return RCS_DEADBAND.
		}

		if rcsPulseAccumulator[axis] <= -1 {
			set rcsPulseAccumulator[axis] to
				rcsPulseAccumulator[axis] + 1.
			return -RCS_DEADBAND.
		}

		return 0.
	}

	function rcsTranslateOff {
		set rcsPulseAccumulator to list(0, 0, 0).
		set ship:control:translation to V(0, 0, 0).
	}

	function rcsVectorTranslate {
		parameter vecTranslation, rcsThrottle is 1.

		if vecTranslation:mag < FLOATING_POINT_NOISE {
			rcsTranslateOff().
			return.
		}

		local vecTranslationControl is max(0, min(1, rcsThrottle)) * vecTranslation:normalized.

		local rawControl is V(
			vecTranslationControl * facing:starvector,
			vecTranslationControl * facing:upvector,
			vecTranslationControl * facing:vector
		).

		set ship:control:translation to V(
			rcsPulseControl(rawControl:x, 0),
			rcsPulseControl(rawControl:y, 1),
			rcsPulseControl(rawControl:z, 2)
		).
	}

	function getTargetVessel {
		parameter targetVesselOrPart.
		
		local targetVessel is targetVesselOrPart.
		if targetVesselOrPart:hassuffix("ship") {
			set targetVessel to targetVesselOrPart:ship.
		}

		return targetVessel.
	}

	function rcsKillRelativeVelocity {
		parameter targetVesselOrPart.

		local targetVessel is getTargetVessel(targetVesselOrPart).
		local vecVelocityError is targetVessel:velocity:orbit - ship:velocity:orbit.

		until vecVelocityError:mag < RCS_VELOCITY_THRESHOLD {
			rcsVectorTranslate(
				vecVelocityError,
				vecVelocityError:mag / RCS_VELOCITY_TAPER
			).
			wait 0.
			set vecVelocityError to targetVessel:velocity:orbit - ship:velocity:orbit.
		}

		rcsTranslateOff().
	}

	export(lex(
		"translate", rcsVectorTranslate@,
		"zero", rcsKillRelativeVelocity@,
		"off", rcsTranslateOff@
	)).
}