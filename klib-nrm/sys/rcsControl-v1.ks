{
	local rcsPulseAccumulator is list(0,0,0).
	local rcsPulseControl is{
		parameter requestedControl,axis.
		if not rcs{
			set rcsPulseAccumulator to list(0,0,0).
			return 0.
		}
		if abs(requestedControl)<1e-9{
			set rcsPulseAccumulator[axis]to 0.
			return 0.
		}
		if abs(requestedControl)>=.05{
			set rcsPulseAccumulator[axis]to 0.
			return requestedControl.
		}
		set rcsPulseAccumulator[axis]to rcsPulseAccumulator[axis]+requestedControl/.05.
		if rcsPulseAccumulator[axis]>=1{
			set rcsPulseAccumulator[axis]to rcsPulseAccumulator[axis]-1.
			return .05.
		}
		if rcsPulseAccumulator[axis]<=-1{
			set rcsPulseAccumulator[axis]to rcsPulseAccumulator[axis]+1.
			return-.05.
		}
		return 0.
	}.
	local rcsTranslateOff is{
		set rcsPulseAccumulator to list(0,0,0).
		set ship:control:translation to V(0,0,0).
	}.
	local rcsVectorTranslate is{
		parameter vecTranslation,rcsThrottle is 1.
		if vecTranslation:mag<1e-9{
			rcsTranslateOff().
			return.
		}
		local vecTranslationControl is max(0,min(1,rcsThrottle))*vecTranslation:normalized.
		local rawControl is V(vecTranslationControl*facing:starvector,vecTranslationControl*facing:upvector,vecTranslationControl*facing:vector).
		set ship:control:translation to V(rcsPulseControl(rawControl:x,0),rcsPulseControl(rawControl:y,1),rcsPulseControl(rawControl:z,2)).
	}.
	export(lex(
		"translate",rcsVectorTranslate,
		"zero",{
			parameter targetVesselOrPart.
			local targetVessel is targetVesselOrPart.
			if targetVesselOrPart:hassuffix("ship")set targetVessel to targetVesselOrPart:ship.
			local vecVelocityError is targetVessel:velocity:orbit-ship:velocity:orbit.
			until vecVelocityError:mag<.05{
				rcsVectorTranslate(vecVelocityError,vecVelocityError:mag/.5).
				wait 0.
				set vecVelocityError to targetVessel:velocity:orbit-ship:velocity:orbit.
			}
			rcsTranslateOff().
		},
		"off",rcsTranslateOff
	)).
}