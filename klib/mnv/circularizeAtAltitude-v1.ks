{
	local orbitalParameters is import("mech/orbitalParameters-v1").
	local orbitalMechanics is import("mech/orbitalMechanics-v1").
	local circularizeAtUT is import("mnv/circularizeAtUT-v1").

	// Unlike other maneuver planners, `circularizeAtAltitude` will return a list of 0->2 possible results
	// Valid results (if any) will appear first in the list
	function circularizeAtAltitude {
		parameter targetAltitude.

		if obt:eccentricity = 1 {
			return ApiFail("Parabolic trajectories are not supported").
		}

		local targetTrueAnomalies is orbitalParameters:hV(targetAltitude).
		if targetTrueAnomalies:length = 0 {
			return ApiFail("Targeted burn altitude does not exist on the current orbit").
		}

		local elliptical is obt:eccentricity < 1.
		local results is list().
		local numOK is 0.
		local resultsFailed is list().
		for anomaly in targetTrueAnomalies {
			local anomalyUT is time:seconds.
			if elliptical {
				set anomalyUT to anomalyUT + orbitalMechanics:etaV(anomaly).
			}
			else {
				set anomalyUT to anomalyUT + orbitalMechanics:etaVh(anomaly).
			}
			local result is circularizeAtUT(anomalyUT).
			if result:ok results:add(result).
			else resultsFailed:add(result).
		}
		set numOK to results:length.
		for result in resultsFailed {
			results:add(result).
		}
		if numOK > 0 return ApiOK(results).
		return ApiFail("Unable to plot any valid maneuvers for the targeted burn altitude", results).
	}

	export(circularizeAtAltitude@).
}