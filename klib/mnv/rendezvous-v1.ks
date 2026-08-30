{
	local OrbitalMechanics is import("orbitalMechanics-v1").
	local OrbitalParameters is import("orbitalParameters-v1").
	local solveLambert is import("mnv/solveLambert-v1").
	local altitudeSafety is import("altitudeSafety-v1").
	local velocityChangeToNode is import("mnv/velocityChangeToNode-v1").
	local createConfig is import("util/createConfig-v1").

	// Number of bisection iterations used when converting UT back to orbital phase.
	local PHASE_TIME_BISECTION_ITERATIONS is 40.
	local LAMBERT_DIRECTIONS is list("short", "long").
	local LAMBERT_BRANCHES is list("left", "right").
	local VERBOSE_DEBUG_LOG is false.

	local DEFAULT_CONFIG is lex(
		// Minimum time that must remain before the final selected departure.
		"burnEta", 60,
		// Minimum time after search start before departures are considered.
		"depOffset", 900,
		// Minimum departure-search offset as a fraction of the ship's orbital period.
		"depPeriodFactor", 0.1,
		// Safety margin before the ship's current orbit patch ends.
		"patchMargin", 60,
		// Maximum number of current-orbit periods searched for departure opportunities.
		"depOrbits", 2,
		// Hard lower limit for transfer time of flight, in seconds.
		"tofMin", 60,
		// Minimum TOF as a fraction of the reference transfer half-period.
		"tofMinFactor", 0.5,
		// Maximum zero-revolution TOF as a fraction of the reference transfer half-period.
		"tofWindowFactor", 1.5,
		// Maximum complete revolutions allowed in a Lambert transfer.
		"maxRevs", 2,
		// Orbital-phase resolutions, in degrees, used by successive search levels.
		"phaseSizes", list(15, 3, 0.5, 0.1, 0.01),
		// Maximum number of phase samples in either dimension of the initial grid.
		"phaseSamples", 100,
		// Maximum number of globally best candidates retained between search levels.
		"retainMax", 40,
		// Fraction of valid candidates eligible for global retention, subject to retainMax.
		"retainFraction", 0.25,
		// Minimum number of candidates preserved from each Lambert solution family.
		"retainFamily", 4,
		// Additional safe altitude required above the atmosphere/terrain, in metres.
		"peClearance", 1e3,
		// Additional safe distance required inside the current SOI radius, in metres.
		"soiClearance", 1e3,
		// Whether each evaluated search cell is written to a porkchop data file.
		"porkchop", true,
		// Number of evaluated cells between console progress updates; 0 disables updates.
		"progressEvery", 1000,
		// Maximum phase distance, per axis, that the final refinement may continue beyond a retained-cell boundary while dV keeps improving.
		"chaseDegrees", 5,
		"progressStart", {parameter phaseSize. print "Evaluating initial phase grid at " + phaseSize + "°".},
		"progressLevel", {parameter level, phaseSize. print "Evaluating phase grid level " + level + " at " + phaseSize + "°". },
		"progressCell", {parameter level, evaluated. print "Level " + level + ": " + evaluated + " evaluated". },
		"progressChase", {parameter phaseCellSize, maxIterations. print "Chasing final refinement boundary".}
	).

	function dPrint {
		parameter message.
		if homeConnection:isconnected log message to "0:/debug.txt".
		if VERBOSE_DEBUG_LOG print message.
	}

	function trueAnomalyOfState {
		parameter positionVector, eccentricityVector, eccentricity, angularMomentumVector, signed is false.

		if eccentricity < 1e-12 return 0.

		local trueAnomaly is arccos(max(
			-1,
			min(1, vdot(eccentricityVector, positionVector) / (eccentricity * positionVector:mag))
		)).
		if vdot(-vcrs(eccentricityVector, positionVector), angularMomentumVector) < 0 {
			if signed return -trueAnomaly.
			return 360 - trueAnomaly.
		}
		return trueAnomaly.
	}

	function getArcRadii {
		parameter departurePosition, arrivalPosition, transferDepartureVelocity, tof, targetBody.

		local angularMomentumVector is -vcrs(departurePosition, transferDepartureVelocity).
		local eccentricityVector is (
			-vcrs(transferDepartureVelocity, angularMomentumVector) / targetBody:mu
		) - departurePosition:normalized.

		local transferEccentricity is eccentricityVector:mag.
		local semilatusRectum is angularMomentumVector:mag^2 / targetBody:mu.
		local periapsisRadius is semilatusRectum / (1 + transferEccentricity).

		local minimumArcRadius is min(departurePosition:mag, arrivalPosition:mag).
		local maximumArcRadius is max(departurePosition:mag, arrivalPosition:mag).

		local departureTrueAnomaly is trueAnomalyOfState(
			departurePosition,
			eccentricityVector,
			transferEccentricity,
			angularMomentumVector,
			transferEccentricity >= 1
		).

		if transferEccentricity < 1 {
			// For an ellipse, either apsis may lie inside the travelled arc.
			// Determine this from the time required to reach the next occurrence
			// of each apsis rather than from wrapped anomaly differences.
			// If tof is at least 1 revolution, then both apsides are inside the travelled arc.
			local transferSemimajorAxis is semilatusRectum / (1 - transferEccentricity^2).
			local transferPeriod is OrbitalMechanics:P(
				transferSemimajorAxis,
				targetBody
			).
			local apoapsisRadius is semilatusRectum / (1 - transferEccentricity).

			if tof >= transferPeriod {
				set minimumArcRadius to min(minimumArcRadius, periapsisRadius).
				set maximumArcRadius to max(maximumArcRadius, apoapsisRadius).
			}
			else {
				local etaPeriapsis is OrbitalMechanics:etaV(
					0,
					transferPeriod,
					departureTrueAnomaly,
					transferEccentricity
				).
				local etaApoapsis is mod(
					etaPeriapsis + transferPeriod / 2,
					transferPeriod
				).

				if etaPeriapsis <= tof {
					set minimumArcRadius to min(minimumArcRadius, periapsisRadius).
				}
				if etaApoapsis <= tof {
					set maximumArcRadius to max(maximumArcRadius, apoapsisRadius).
				}
			}
		}
		else {
			// A hyperbola has no apoapsis, so its maximum radius over a finite
			// transfer segment must be one of the endpoints. Periapsis can still
			// lie between them.
			local arrivalTrueAnomaly is trueAnomalyOfState(
				arrivalPosition,
				eccentricityVector,
				transferEccentricity,
				angularMomentumVector,
				true
			).

			if departureTrueAnomaly <= 0 and arrivalTrueAnomaly >= 0 {
				set minimumArcRadius to min(
					minimumArcRadius,
					periapsisRadius
				).
			}
		}

		return lex(
			"min", minimumArcRadius,
			"max", maximumArcRadius
		).
	}

	function transferInvalid {
		parameter cell, reason, departureUT, arrivalUT, tof.
		return lex(
			"valid", false,
			"cell", cell,
			"reason", reason,
			"departureUT", departureUT,
			"arrivalUT", arrivalUT,
			"tof", tof
		).
	}

	function createSearchCandidate {
		parameter cell, departureUT, arrivalUT, shipState, targetState, transferResult.

		local dvDeparture is (transferResult:departureVelocity - shipState:velocity):mag.
		local dvArrival is (targetState:velocity - transferResult:arrivalVelocity):mag.
		return lex(
			"valid", true,
			"cell", cell,
			"departureUT", departureUT,
			"arrivalUT", arrivalUT,
			"tof", arrivalUT - departureUT,
			"dvDeparture", dvDeparture,
			"dvArrival", dvArrival,
			"dvTotal", dvDeparture + dvArrival
		).
	}

	function createTransferCandidate {
		parameter cell, departureUT, arrivalUT, shipState, targetState, transferResult.

		local candidate is createSearchCandidate(cell, departureUT, arrivalUT, shipState, targetState, transferResult).
		set candidate["shipState"] to shipState.
		set candidate["targetState"] to targetState.
		set candidate["transfer"] to transferResult.
		return candidate.
	}

	// Orbit phase mapping
	// ----------------------------------------------------------------

	// Freeze the orbital values used to map true-anomaly phase to UT.
	// Calculate true anomaly from the state, as a CREATEORBIT() Orbit can report trueanomaly=0 regardless of its current state.
	function createOrbitSnapshotFromState {
		parameter targetOrbit, referenceUT, positionVector, velocityVector, transitionUT is false.

		local targetBody is targetOrbit:body.
		local angularMomentumVector is -vcrs(positionVector, velocityVector).
		local angularMomentumMag is angularMomentumVector:mag.

		local eccentricityVector is (
			-vcrs(velocityVector, angularMomentumVector) / targetBody:mu
		) - positionVector:normalized.
		local eccentricity is eccentricityVector:mag.

		local trueAnomaly is trueAnomalyOfState(
			positionVector,
			eccentricityVector,
			eccentricity,
			angularMomentumVector,
			eccentricity >= 1
		).

		local radialVector is positionVector:normalized.
		local transverseVector is (
			velocityVector
			- radialVector * vdot(velocityVector, radialVector)
		):normalized.

		return lex(
			"referenceUT", referenceUT,
			"body", targetBody,
			"trueAnomaly", trueAnomaly,
			"period", choose targetOrbit:period if eccentricity < 1 else false,
			"eccentricity", eccentricity,
			"semimajorAxis", targetOrbit:semimajoraxis,
			"apoapsis", choose targetOrbit:apoapsis if eccentricity < 1 else false,
			"periapsis", targetOrbit:periapsis,
			"radialVector", radialVector,
			"transverseVector", transverseVector,
			"semilatusRectum", angularMomentumMag^2 / targetBody:mu,
			"velocityFactor", targetBody:mu / angularMomentumMag,
			"planeNormal", angularMomentumVector:normalized,
			"transitionUT", transitionUT
		).
	}

	// Snapshot a real Orbitable at an exact specified UT.
	// Used for the ship so POSITIONAT/VELOCITYAT retain normal flight prediction.
	function createOrbitableSnapshot {
		parameter targetOrbitable, referenceUT.

		local targetOrbit is targetOrbitable:orbit.
		local targetBody is targetOrbit:body.
		local transitionUT is false.

		if targetOrbit:hasnextpatch {
			set transitionUT to referenceUT + targetOrbit:nextpatcheta.
		}

		return createOrbitSnapshotFromState(
			targetOrbit,
			referenceUT,
			positionAt(targetOrbitable, referenceUT) - targetBody:position,
			velocityAt(targetOrbitable, referenceUT):orbit,
			transitionUT
		).
	}

	// Snapshot an arbitrary Orbit.
	// Orbit:POSITION/VELOCITY are evaluated at the current UT, so timestamp the state using the midpoint of those reads.
	function createOrbitSnapshot {
		parameter targetOrbit.

		local targetBody is targetOrbit:body.
		local sampleUTBefore is time:seconds.
		local positionVector is targetOrbit:position - targetBody:position.
		local velocityVector is targetOrbit:velocity:orbit.
		local sampleUTAfter is time:seconds.
		local referenceUT is (sampleUTBefore + sampleUTAfter) / 2.

		local transitionUT is false.
		if targetOrbit:hasnextpatch {
			set transitionUT to referenceUT + targetOrbit:nextpatcheta.
		}

		return createOrbitSnapshotFromState(
			targetOrbit,
			referenceUT,
			positionVector,
			velocityVector,
			transitionUT
		).
	}

	// Convert true-anomaly phase advance to absolute UT.
	// For elliptical orbits, the true-anomaly is unwrapped so 360 = one orbit later
	function phaseToUT {
		parameter orbitSnapshot, phaseDegrees.

		if orbitSnapshot:eccentricity < 1 return orbitSnapshot:referenceUT
			+ OrbitalMechanics:dtV(
				phaseDegrees,
				orbitSnapshot:period,
				orbitSnapshot:trueAnomaly,
				orbitSnapshot:eccentricity
			).

		return orbitSnapshot:referenceUT + OrbitalMechanics:etaVh(
			orbitSnapshot:trueAnomaly + phaseDegrees,
			orbitSnapshot:trueAnomaly,
			orbitSnapshot:semimajorAxis,
			orbitSnapshot:eccentricity,
			orbitSnapshot:body
		).
	}

	// Converts absolute UT to unwrapped true-anomaly phase
	function phaseAtUT {
		parameter orbitSnapshot, ut.

		if ut <= orbitSnapshot:referenceUT return 0.
		local phaseLow is 0.
		local phaseHigh is 0.

		if orbitSnapshot:eccentricity < 1 {
			local elapsedTime is ut - orbitSnapshot:referenceUT.
			local upperOrbitCount is ceiling(elapsedTime / orbitSnapshot:period) + 1.
			set phaseHigh to upperOrbitCount * 360.
		}
		else {
			// Stay slightly inside the asymptotic true-anomaly limit.
			set phaseHigh to  OrbitalParameters:Vlim(orbitSnapshot:eccentricity) - orbitSnapshot:trueAnomaly - 1e-6.
		}

		from { local iteration is 0. }
		until iteration >= PHASE_TIME_BISECTION_ITERATIONS
		step { set iteration to iteration + 1. }
		do {
			local phaseMid is (phaseLow + phaseHigh) / 2.
			local phaseUT is phaseToUT(orbitSnapshot, phaseMid).

			if phaseUT < ut set phaseLow to phaseMid.
			else set phaseHigh to phaseMid.
		}

		return (phaseLow + phaseHigh) / 2.
	}

	// Search windows
	// ----------------------------------------------------------------

	function calculateDepartureWindow {
		parameter shipSnapshot, cfg.

		local departureSearchOffset is cfg:depOffset.

		if shipSnapshot:eccentricity < 1 {
			set departureSearchOffset to max(
				departureSearchOffset,
				shipSnapshot:period * cfg:depPeriodFactor
			).
		}

		local earliestDepartureUT is shipSnapshot:referenceUT + departureSearchOffset.
		local latestDepartureUT is 0.

		if shipSnapshot:eccentricity < 1 {
			set latestDepartureUT to earliestDepartureUT
				+ cfg:depOrbits * shipSnapshot:period.

			if not shipSnapshot:transitionUT:istype("Boolean") {
				set latestDepartureUT to min(
					latestDepartureUT,
					shipSnapshot:transitionUT - cfg:patchMargin
				).
			}
		}
		else {
			if shipSnapshot:transitionUT:istype("Boolean") {
				return ApiFail("Hyperbolic departure trajectory has no finite patch transition").
			}
			set latestDepartureUT to shipSnapshot:transitionUT - cfg:patchMargin.
		}

		if latestDepartureUT <= earliestDepartureUT return ApiFail("Orbit will transition and the departure window is too small").

		return ApiOK(lex(
			"min", earliestDepartureUT,
			"max", latestDepartureUT
		)).
	}

	function calculateTOFWindow {
		parameter shipSnapshot, targetSnapshot, departureWindow, cfg.

		local minAltitude is 0.
		local maxAltitude is 0.

		if shipSnapshot:eccentricity < 1 {
			set minAltitude to min(shipSnapshot:periapsis, targetSnapshot:periapsis).
			set maxAltitude to max(shipSnapshot:apoapsis, targetSnapshot:apoapsis).
		}
		else {
			local departureMinAltitude is (positionAt(ship, departureWindow:min) - body:position):mag - body:radius.
			local departureMaxAltitude is (positionAt(ship, departureWindow:max) - body:position):mag - body:radius.

			set minAltitude to min(
				min(
					min(
						shipSnapshot:periapsis,
						targetSnapshot:periapsis
					),
					departureMinAltitude
				),
				departureMaxAltitude
			).

			set maxAltitude to max(
				max(
					targetSnapshot:apoapsis,
					departureMinAltitude
				),
				departureMaxAltitude
			).
		}

		local refPeriod is OrbitalMechanics:Ph(minAltitude, maxAltitude, body).
		local refHalfPeriod is refPeriod / 2.

		local minTof is max(cfg:tofMin, refHalfPeriod * cfg:tofMinFactor).
		local maxTof is refHalfPeriod * cfg:tofWindowFactor
			+ cfg:maxRevs * refPeriod.

		if not targetSnapshot:transitionUT:istype("Boolean") {
			set maxTof to min(
				maxTof,
				targetSnapshot:transitionUT - departureWindow:min
			).
		}

		if maxTof <= minTof return ApiFail("No useful time-of-flight window exists").

		return ApiOK(lex(
			"min", minTof,
			"max", maxTof
		)).
	}

	// Vessel state
	// ----------------------------------------------------------------

	function getStateAt {
		parameter targetOrbitable, ut.

		return lex(
			"position", positionAt(targetOrbitable, ut) - body:position,
			"velocity", velocityAt(targetOrbitable, ut):orbit
		).
	}

	// Get the state of an orbit at a true-anomaly offset
	function getOrbitStateAtPhaseOffset {
		parameter orbitSnapshot, phaseDegrees.

		local phaseCos is cos(phaseDegrees).
		local phaseSin is sin(phaseDegrees).

		local radialVector is
			orbitSnapshot:radialVector * phaseCos
			+ orbitSnapshot:transverseVector * phaseSin.

		local transverseVector is
			orbitSnapshot:transverseVector * phaseCos
			- orbitSnapshot:radialVector * phaseSin.

		local trueAnomaly is orbitSnapshot:trueAnomaly + phaseDegrees.
		local trueAnomalyCos is cos(trueAnomaly).
		local trueAnomalySin is sin(trueAnomaly).

		local radius is orbitSnapshot:semilatusRectum
			/ (
				1
				+ orbitSnapshot:eccentricity * trueAnomalyCos
			).

		local radialVelocity is orbitSnapshot:velocityFactor
			* orbitSnapshot:eccentricity
			* trueAnomalySin.

		local transverseVelocity is orbitSnapshot:velocityFactor
			* (
				1
				+ orbitSnapshot:eccentricity * trueAnomalyCos
			).

		return lex(
			"position", radialVector * radius,
			"velocity",
				radialVector * radialVelocity
				+ transverseVector * transverseVelocity
		).
	}

	// Transfer evaluation
	// ----------------------------------------------------------------

	function evaluateTransfer {
		parameter cell, shipSnapshot, targetSnapshot,
			departureWindow, tofWindow, targetPhaseOffset,
			transferSafetyBounds.

		local departurePhase is (cell:departurePhase:min + cell:departurePhase:max) / 2.
		local arrivalPhase is (cell:arrivalPhase:min + cell:arrivalPhase:max) / 2.
		local departureUT is phaseToUT(shipSnapshot, departurePhase).
		local arrivalUT is phaseToUT(targetSnapshot, arrivalPhase).
		local tof is arrivalUT - departureUT.

		if departureUT < departureWindow:min or departureUT > departureWindow:max {
			return transferInvalid(
				cell, "Departure is outside the departure window",
				departureUT, arrivalUT, tof
			).
		}

		if tof < tofWindow:min or tof > tofWindow:max {
			return transferInvalid(
				cell, "Time of flight is outside the search window",
				departureUT, arrivalUT, tof
			).
		}

		if not targetSnapshot:transitionUT:istype("Boolean")
			and arrivalUT >= targetSnapshot:transitionUT {
			return transferInvalid(
				cell, "Target leaves current SOI before arrival",
				departureUT, arrivalUT, tof
			).
		}

		local shipState is getStateAt(ship, departureUT).
		local targetState is getOrbitStateAtPhaseOffset(
			targetSnapshot,
			arrivalPhase + targetPhaseOffset
		).
		local departurePosition is shipState:position.
		local arrivalPosition is targetState:position.

		local transferResult is solveLambert(
			departurePosition,
			arrivalPosition,
			tof,
			body:mu,
			cell:direction,
			cell:revolutions,
			cell:branch,
			shipSnapshot:planeNormal
		).

		if not transferResult:valid {
			return transferInvalid(
				cell, transferResult:reason,
				departureUT, arrivalUT, tof
			).
		}

		// Transfer arc safety.
		local arcRadii is getArcRadii(departurePosition, arrivalPosition, transferResult:departureVelocity, tof, body).
		if arcRadii:min < transferSafetyBounds:min {
			return transferInvalid(
				cell, "Transfer arc goes below safe altitude",
				departureUT, arrivalUT, tof
			).
		}
		if arcRadii:max >= transferSafetyBounds:max {
			return transferInvalid(
				cell, "Transfer arc leaves current SOI",
				departureUT, arrivalUT, tof
			).
		}

		return createSearchCandidate(
			cell, departureUT, arrivalUT,
			shipState, targetState, transferResult
		).
	}

	// Streaming retention
	// ----------------------------------------------------------------

	function familyKey {
		parameter candidate.

		if candidate:cell:revolutions = 0 {
			return candidate:cell:revolutions + ":" + candidate:cell:direction.
		}

		return candidate:cell:revolutions
			+ ":" + candidate:cell:direction
			+ ":" + candidate:cell:branch.
	}

	// Keep a small list sorted by increasing total dV.
	function insertBestCandidate {
		parameter candidates, candidate, limit.

		if limit <= 0 return.
		if limit = 1 {
			if candidates:length = 0 candidates:add(candidate).
			else if candidate:dvTotal < candidates[0]:dvTotal set candidates[0] to candidate.
			return.
		}

		local insertIndex is candidates:length.
		from { local candidateIndex is 0. }
		until candidateIndex >= candidates:length
		step { set candidateIndex to candidateIndex + 1. }
		do {
			if candidate:dvTotal < candidates[candidateIndex]:dvTotal {
				set insertIndex to candidateIndex.
				break.
			}
		}

		candidates:insert(insertIndex, candidate).
		if candidates:length > limit candidates:remove(candidates:length - 1).
	}

	function retainCandidate {
		parameter retentionState, candidate, cfg.

		set retentionState["validCount"] to retentionState:validCount + 1.
		insertBestCandidate(retentionState:globalBest, candidate, cfg:retainMax).

		if cfg:retainFamily <= 0 return.

		local candidateFamily is familyKey(candidate).
		if not retentionState:familyBest:haskey(candidateFamily) {
			retentionState:familyBest:add(candidateFamily, list()).
		}

		insertBestCandidate(
			retentionState:familyBest[candidateFamily],
			candidate,
			cfg:retainFamily
		).
	}

	function candidateAlreadyRetained {
		parameter candidates, candidateId.

		for retainedCandidate in candidates {
			if retainedCandidate:cell:id = candidateId return true.
		}

		return false.
	}

	function finalizeRetention {
		parameter retentionState, cfg.

		if retentionState:validCount = 0 return list().

		local topCount is max(
			1,
			min(
				cfg:retainMax,
				floor(retentionState:validCount * cfg:retainFraction)
			)
		).

		local retained is list().
		local globalCount is min(topCount, retentionState:globalBest:length).

		from { local globalIndex is 0. }
		until globalIndex >= globalCount
		step { set globalIndex to globalIndex + 1. }
		do {
			retained:add(retentionState:globalBest[globalIndex]).
		}

		if cfg:retainFamily > 0 {
			for candidateFamily in retentionState:familyBest:keys {
				for familyCandidate in retentionState:familyBest[candidateFamily] {
					if not candidateAlreadyRetained(retained, familyCandidate:cell:id) {
						retained:add(familyCandidate).
					}
				}
			}
		}

		return retained.
	}

	// Streaming evaluation state / porkchop logging
	// ----------------------------------------------------------------

	function createEvaluationState {
		parameter level, cfg.

		local porkchopLog is "0:/porkchop." + level + ".txt".

		if cfg:porkchop {
			deletePath(porkchopLog).
			log
				"departurePhase:min,departurePhase:max,"
				+ "arrivalPhase:min,arrivalPhase:max,"
				+ "departureUT,arrivalUT,tof,"
				+ "revolutions,direction,branch,"
				+ "dvDeparture,dvArrival,dvTotal,invalidReason"
			to porkchopLog.
		}

		return lex(
			"level", level,
			"invalid", 0,
			"failureReasons", lex(),
			"nextCellId", 0,
			"porkchopLog", porkchopLog,
			"retention", lex(
				"validCount", 0,
				"globalBest", list(),
				"familyBest", lex()
			)
		).
	}

	function logPorkchopResult {
		parameter evaluationState, result.

		local cell is result:cell.

		if result:valid {
			log
				cell:departurePhase:min + ","
				+ cell:departurePhase:max + ","
				+ cell:arrivalPhase:min + ","
				+ cell:arrivalPhase:max + ","
				+ result:departureUT + ","
				+ result:arrivalUT + ","
				+ result:tof + ","
				+ cell:revolutions + ","
				+ cell:direction + ","
				+ cell:branch + ","
				+ result:dvDeparture + ","
				+ result:dvArrival + ","
				+ result:dvTotal + ","
			to evaluationState:porkchopLog.
		}
		else {
			log
				cell:departurePhase:min + ","
				+ cell:departurePhase:max + ","
				+ cell:arrivalPhase:min + ","
				+ cell:arrivalPhase:max + ","
				+ result:departureUT + ","
				+ result:arrivalUT + ","
				+ result:tof + ","
				+ cell:revolutions + ","
				+ cell:direction + ","
				+ cell:branch + ",,,,"
				+ result:reason
			to evaluationState:porkchopLog.
		}
	}

	function processCell {
		parameter cell, evaluationState,
			shipSnapshot, targetSnapshot, departureWindow, tofWindow,
			targetPhaseOffset, transferSafetyBounds, cfg, retain is true.

		cell:add("id", evaluationState:nextCellId).
		set evaluationState["nextCellId"] to evaluationState:nextCellId + 1.

		local result is evaluateTransfer(
			cell,
			shipSnapshot,
			targetSnapshot,
			departureWindow,
			tofWindow,
			targetPhaseOffset,
			transferSafetyBounds
		).

		if result:valid {
			if retain retainCandidate(evaluationState:retention, result, cfg). // allows chaseBoundary() as caller, to not retain candidates as finalizeRetention() is not called
		}
		else {
			set evaluationState["invalid"] to evaluationState:invalid + 1.

			if not evaluationState:failureReasons:haskey(result:reason) {
				evaluationState:failureReasons:add(result:reason, 0).
			}
			local failureReasons is evaluationState:failureReasons.
			set failureReasons[result:reason] to failureReasons[result:reason] + 1.
		}

		if cfg:porkchop logPorkchopResult(evaluationState, result).

		if cfg:progressEvery > 0 and mod(evaluationState:nextCellId, cfg:progressEvery) = 0 {
			cfg:progressCell(evaluationState:level, evaluationState:nextCellId).
		}

		return result.
	}

	function createCell {
		parameter departurePhaseMin, departurePhaseMax,
			arrivalPhaseMin, arrivalPhaseMax,
			revolutions, direction, branch,
			expandDepartureMin,
			expandDepartureMax,
			expandArrivalMin,
			expandArrivalMax.

		return lex(
			"departurePhase", lex(
				"min", departurePhaseMin,
				"max", departurePhaseMax
			),
			"arrivalPhase", lex(
				"min", arrivalPhaseMin,
				"max", arrivalPhaseMax
			),
			"revolutions", revolutions,
			"direction", direction,
			"branch", branch,
			"expandDepartureMin", expandDepartureMin,
			"expandDepartureMax", expandDepartureMax,
			"expandArrivalMin", expandArrivalMin,
			"expandArrivalMax", expandArrivalMax
		).
	}

	function cellCanExpand {
		parameter cell.

		return cell:expandDepartureMin
			or cell:expandDepartureMax
			or cell:expandArrivalMin
			or cell:expandArrivalMax.
	}

	function processLambertFamilies {
		parameter
			departurePhaseMin, departurePhaseMax,
			arrivalPhaseMin, arrivalPhaseMax,
			evaluationState, shipSnapshot, targetSnapshot,
			departureWindow, tofWindow, targetPhaseOffset,
			expandDepartureMin, expandDepartureMax,
			expandArrivalMin, expandArrivalMax,
			transferSafetyBounds, cfg.

		for direction in LAMBERT_DIRECTIONS {
			from { local revolutionCount is 0. }
			until revolutionCount > cfg:maxRevs
			step { set revolutionCount to revolutionCount + 1. }
			do {
				for branch in LAMBERT_BRANCHES {
					local cell is createCell(
						departurePhaseMin, departurePhaseMax,
						arrivalPhaseMin, arrivalPhaseMax,
						revolutionCount, direction, branch,
						expandDepartureMin, expandDepartureMax,
						expandArrivalMin, expandArrivalMax
					).

					processCell(
						cell,
						evaluationState,
						shipSnapshot,
						targetSnapshot,
						departureWindow,
						tofWindow,
						targetPhaseOffset,
						transferSafetyBounds,
						cfg
					).

					// Zero-revolution has only one x solution.
					if revolutionCount = 0 break.
				}
			}
		}
	}

	// Initial phase grid
	// ----------------------------------------------------------------
	function cellCount {
		parameter width, resolution.

		local countExact is width / resolution.
		local countNearest is round(countExact).

		if abs(countExact - countNearest) < 1e-9 {
			return max(1, countNearest).
		}

		return max(1, ceiling(countExact)).
	}

	function evaluateInitialPhaseGrid {
		parameter shipSnapshot, targetSnapshot,
			departureWindow, tofWindow, targetPhaseOffset,
			transferSafetyBounds, cfg.

		local evaluationState is createEvaluationState(0, cfg).
		local departurePhaseMin is phaseAtUT(shipSnapshot, departureWindow:min).
		local departurePhaseMax is phaseAtUT(shipSnapshot, departureWindow:max).
		local departurePhaseWidth is departurePhaseMax - departurePhaseMin.

		local departurePhaseResolution is max(
			cfg:phaseSizes[0],
			departurePhaseWidth / cfg:phaseSamples
		).
		local departureCount is cellCount(departurePhaseWidth, departurePhaseResolution).

		// Cover the departure phase window exactly.
		set departurePhaseResolution to departurePhaseWidth / departureCount.

		{
			// DEBUG
			dPrint("--------------------------------").
			dPrint("INITIAL PHASE GRID").
			dPrint("departure phase min = " + departurePhaseMin).
			dPrint("departure phase max = " + departurePhaseMax).
			dPrint("departure phase count = " + departureCount).
			dPrint("departure phase resolution = " + departurePhaseResolution).
		}

		from { local departureIndex is 0. }
		until departureIndex >= departureCount
		step { set departureIndex to departureIndex + 1. }
		do {
			local phaseDepartureMin is
				departurePhaseMin + departureIndex * departurePhaseResolution.
			local phaseDepartureMax is min(
				phaseDepartureMin + departurePhaseResolution,
				departurePhaseMax
			).
			local phaseDepartureMid is (phaseDepartureMin + phaseDepartureMax) / 2.
			local departureUT is phaseToUT(shipSnapshot, phaseDepartureMid).

			// Only generate target phases for TOFs useful at this departure.
			local arrivalUTMin is departureUT + tofWindow:min.
			local arrivalUTMax is departureUT + tofWindow:max.

			if not targetSnapshot:transitionUT:istype("Boolean") {
				set arrivalUTMax to min(arrivalUTMax, targetSnapshot:transitionUT).
			}

			if arrivalUTMax > arrivalUTMin {
				local arrivalPhaseMin is phaseAtUT(targetSnapshot, arrivalUTMin).
				local arrivalPhaseMax is phaseAtUT(targetSnapshot, arrivalUTMax).
				local arrivalPhaseWidth is arrivalPhaseMax - arrivalPhaseMin.

				local arrivalPhaseResolution is max(
					cfg:phaseSizes[0],
					arrivalPhaseWidth / cfg:phaseSamples
				).
				local arrivalCount is cellCount(arrivalPhaseWidth, arrivalPhaseResolution).
				set arrivalPhaseResolution to arrivalPhaseWidth / arrivalCount.

				from { local arrivalIndex is 0. }
				until arrivalIndex >= arrivalCount
				step { set arrivalIndex to arrivalIndex + 1. }
				do {
					local phaseArrivalMin is
						arrivalPhaseMin + arrivalIndex * arrivalPhaseResolution.
					local phaseArrivalMax is min(
						phaseArrivalMin + arrivalPhaseResolution,
						arrivalPhaseMax
					).

					local expandDepartureMin is departureIndex > 0.
					local expandDepartureMax is departureIndex < departureCount - 1.
					local expandArrivalMin is true.
					local expandArrivalMax is true.

					processLambertFamilies(
						phaseDepartureMin,
						phaseDepartureMax,
						phaseArrivalMin,
						phaseArrivalMax,
						evaluationState,
						shipSnapshot,
						targetSnapshot,
						departureWindow,
						tofWindow,
						targetPhaseOffset,
						expandDepartureMin,
						expandDepartureMax,
						expandArrivalMin,
						expandArrivalMax,
						transferSafetyBounds,
						cfg
					).
				}
			}
		}

		return lex(
			"promising", finalizeRetention(evaluationState:retention, cfg),
			"evaluated", evaluationState:nextCellId,
			"valid", evaluationState:retention:validCount,
			"invalid", evaluationState:invalid,
			"reasons", evaluationState:failureReasons
		).
	}

	// Refined phase grid
	// ----------------------------------------------------------------

	function evaluateRefinedPhaseGrid {
		parameter parentCandidates, phaseCellSize, level,
			shipSnapshot, targetSnapshot, departureWindow, tofWindow,
			targetPhaseOffset, transferSafetyBounds, cfg.

		local evaluationState is createEvaluationState(level, cfg).

		for parentCandidate in parentCandidates {
			local parentCell is parentCandidate:cell.

			local refineDepartureMin is parentCell:departurePhase:min.
			local refineDepartureMax is parentCell:departurePhase:max.
			local refineArrivalMin is parentCell:arrivalPhase:min.
			local refineArrivalMax is parentCell:arrivalPhase:max.

			// Level 1 first determines whether a promising child actually lies
			// against an initial-cell boundary. Later levels may then walk
			// beyond that boundary.
			if level > 1 {
				if parentCell:expandDepartureMin {
					set refineDepartureMin to refineDepartureMin - phaseCellSize.
				}
				if parentCell:expandDepartureMax {
					set refineDepartureMax to refineDepartureMax + phaseCellSize.
				}
				if parentCell:expandArrivalMin {
					set refineArrivalMin to refineArrivalMin - phaseCellSize.
				}
				if parentCell:expandArrivalMax {
					set refineArrivalMax to refineArrivalMax + phaseCellSize.
				}
			}

			local departurePhaseWidth is refineDepartureMax - refineDepartureMin.
			local arrivalPhaseWidth is refineArrivalMax - refineArrivalMin.

			local departureCount is cellCount(departurePhaseWidth, phaseCellSize).
			local arrivalCount is cellCount(arrivalPhaseWidth, phaseCellSize).
			local departureResolution is departurePhaseWidth / departureCount.
			local arrivalResolution is arrivalPhaseWidth / arrivalCount.

			from { local departureIndex is 0. }
			until departureIndex >= departureCount
			step { set departureIndex to departureIndex + 1. }
			do {
				local childDepartureMin is refineDepartureMin + departureIndex * departureResolution.
				local childDepartureMax is min(
					childDepartureMin + departureResolution,
					refineDepartureMax
				).

				from { local arrivalIndex is 0. }
				until arrivalIndex >= arrivalCount
				step { set arrivalIndex to arrivalIndex + 1. }
				do {
					local childArrivalMin is refineArrivalMin + arrivalIndex * arrivalResolution.
					local childArrivalMax is min(
						childArrivalMin + arrivalResolution,
						refineArrivalMax
					).

					local expandDepartureMin is parentCell:expandDepartureMin and departureIndex = 0.
					local expandDepartureMax is parentCell:expandDepartureMax and departureIndex = departureCount - 1.
					local expandArrivalMin is parentCell:expandArrivalMin and arrivalIndex = 0.
					local expandArrivalMax is parentCell:expandArrivalMax and arrivalIndex = arrivalCount - 1.

					local childCell is createCell(
						childDepartureMin,
						childDepartureMax,
						childArrivalMin,
						childArrivalMax,
						parentCell:revolutions,
						parentCell:direction,
						parentCell:branch,
						expandDepartureMin,
						expandDepartureMax,
						expandArrivalMin,
						expandArrivalMax
					).

					processCell(
						childCell,
						evaluationState,
						shipSnapshot,
						targetSnapshot,
						departureWindow,
						tofWindow,
						targetPhaseOffset,
						transferSafetyBounds,
						cfg
					).
				}
			}
		}

		return lex(
			"promising", finalizeRetention(evaluationState:retention, cfg),
			"evaluated", evaluationState:nextCellId,
			"valid", evaluationState:retention:validCount,
			"invalid", evaluationState:invalid,
			"reasons", evaluationState:failureReasons
		).
	}

	// Continue the finest refinement across an inherited cell boundary
	// while an adjacent cell continues to improve the solution.
	function chaseBoundary {
		parameter candidate, phaseCellSize,
			shipSnapshot, targetSnapshot, departureWindow, tofWindow,
			targetPhaseOffset, transferSafetyBounds, cfg.

		local maxIterations is floor(cfg:chaseDegrees / phaseCellSize).

		if maxIterations <= 0 or not cellCanExpand(candidate:cell) {
			return candidate.
		}

		cfg:progressChase(phaseCellSize, maxIterations).

		local evaluationState is createEvaluationState("boundary", cfg).
		local initialCandidate is candidate.
		local best is candidate.
		local iterations is 0.

		until iterations >= maxIterations or not cellCanExpand(best:cell) {
			local cell is best:cell.

			local departureWidth is cell:departurePhase:max - cell:departurePhase:min.
			local arrivalWidth is cell:arrivalPhase:max - cell:arrivalPhase:min.

			// Zero means keep this dimension unchanged. Add only directions
			// in which this cell is allowed to continue expanding.
			local departureOffsets is list(0).
			if cell:expandDepartureMin departureOffsets:add(-1).
			if cell:expandDepartureMax departureOffsets:add(1).

			local arrivalOffsets is list(0).
			if cell:expandArrivalMin arrivalOffsets:add(-1).
			if cell:expandArrivalMax arrivalOffsets:add(1).

			local nextBest is best.
			local improved is false.

			for departureOffset in departureOffsets {
				for arrivalOffset in arrivalOffsets {

					// Do not re-evaluate the current cell.
					if departureOffset <> 0 or arrivalOffset <> 0 {
						local departureShift is departureOffset * departureWidth.
						local arrivalShift is arrivalOffset * arrivalWidth.

						local adjacentCell is createCell(
							cell:departurePhase:min + departureShift,
							cell:departurePhase:max + departureShift,
							cell:arrivalPhase:min + arrivalShift,
							cell:arrivalPhase:max + arrivalShift,
							cell:revolutions,
							cell:direction,
							cell:branch,
							cell:expandDepartureMin and departureOffset <= 0,
							cell:expandDepartureMax and departureOffset >= 0,
							cell:expandArrivalMin and arrivalOffset <= 0,
							cell:expandArrivalMax and arrivalOffset >= 0
						).

						local result is processCell(
							adjacentCell,
							evaluationState,
							shipSnapshot,
							targetSnapshot,
							departureWindow,
							tofWindow,
							targetPhaseOffset,
							transferSafetyBounds,
							cfg, false
						).

						if result:valid and result:dvTotal < nextBest:dvTotal {
							set nextBest to result.
							set improved to true.
						}
					}
				}
			}

			set iterations to iterations + 1.

			// We have crossed the boundary far enough to bracket the minimum:
			// none of the immediately adjacent cells is cheaper.
			if not improved break.

			set best to nextBest.
		}

		{
			// DEBUG
			dPrint("--------------------------------").
			dPrint("BOUNDARY CHASE").
			dPrint("phase resolution = " + phaseCellSize).
			dPrint("maximum distance = " + cfg:chaseDegrees).
			dPrint("iterations = " + iterations).
			dPrint("evaluated = " + evaluationState:nextCellId).
			dPrint("valid = " + (evaluationState:nextCellId - evaluationState:invalid)).
			dPrint("invalid = " + evaluationState:invalid).
			dPrint("initial total dV = " + initialCandidate:dvTotal).
			dPrint("final total dV = " + best:dvTotal).
			dPrint("total dV improvement = " + (initialCandidate:dvTotal - best:dvTotal)).
			dPrint(
				"final departure phase cell = "
				+ best:cell:departurePhase:min
				+ " .. "
				+ best:cell:departurePhase:max
			).
			dPrint(
				"final arrival phase cell = "
				+ best:cell:arrivalPhase:min
				+ " .. "
				+ best:cell:arrivalPhase:max
			).
		}

		return best.
	}

	// Search logging
	// ----------------------------------------------------------------

	function logEvaluation {
		parameter evaluation, level, promising.

		dPrint("--------------------------------").
		dPrint("GRID LEVEL " + level).
		dPrint("evaluated = " + evaluation:evaluated).
		dPrint("valid = " + evaluation:valid).
		dPrint("invalid = " + evaluation:invalid).

		for reason in evaluation:reasons:keys {
			dPrint("  failure: " + reason + " = " + evaluation:reasons[reason]).
		}

		local familiesRetained is lex().
		for candidate in promising {
			local candidateFamily is familyKey(candidate).

			if not familiesRetained:haskey(candidateFamily) {
				familiesRetained:add(candidateFamily, 0).
			}
			set familiesRetained[candidateFamily]
				to familiesRetained[candidateFamily] + 1.
		}

		dPrint("Retention Families:").
		for candidateFamily in familiesRetained:keys {
			dPrint("  " + candidateFamily + " = " + familiesRetained[candidateFamily]).
		}

		if promising:length > 0 {
			// Global retained candidates are sorted, so the first is the level best.
			local levelBest is promising[0].

			dPrint("best depart = " + levelBest:departureUT).
			dPrint("best arrival = " + levelBest:arrivalUT).
			dPrint("best tof = " + levelBest:tof).
			dPrint("best departure dV = " + levelBest:dvDeparture).
			dPrint("best arrival dV = " + levelBest:dvArrival).
			dPrint("best total dV = " + levelBest:dvTotal).
			dPrint("best revolutions = " + levelBest:cell:revolutions).
			dPrint("best direction = " + levelBest:cell:direction).
			dPrint("best branch = " + levelBest:cell:branch).
			dPrint("retained cells = " + promising:length).
			dPrint(
				"best departure phase cell = "
				+ levelBest:cell:departurePhase:min
				+ " .. "
				+ levelBest:cell:departurePhase:max
			).
			dPrint(
				"best arrival phase cell = "
				+ levelBest:cell:arrivalPhase:min
				+ " .. "
				+ levelBest:cell:arrivalPhase:max
			).
		}
	}

	// Adaptive search
	// ----------------------------------------------------------------

	function adaptiveSearch {
		parameter shipSnapshot, targetSnapshot,
			departureWindow, tofWindow, targetPhaseOffset,
			transferSafetyBounds, cfg.

		cfg:progressStart(cfg:phaseSizes[0]).

		local evaluation is evaluateInitialPhaseGrid(
			shipSnapshot,
			targetSnapshot,
			departureWindow,
			tofWindow,
			targetPhaseOffset,
			transferSafetyBounds,
			cfg
		).
		local promising is evaluation:promising.

		logEvaluation(evaluation, 0, promising).
		if promising:length = 0 return false.

		local best is promising[0].

		from { local level is 1. }
		until level >= cfg:phaseSizes:length
		step { set level to level + 1. }
		do {
			cfg:progressLevel(level, cfg:phaseSizes[level]).

			set evaluation to evaluateRefinedPhaseGrid(
				promising,
				cfg:phaseSizes[level],
				level,
				shipSnapshot,
				targetSnapshot,
				departureWindow,
				tofWindow,
				targetPhaseOffset,
				transferSafetyBounds,
				cfg
			).
			set promising to evaluation:promising.

			logEvaluation(evaluation, level, promising).
			if promising:length = 0 break.

			if promising[0]:dvTotal < best:dvTotal set best to promising[0].
		}

		local chaseCandidate is false.
		for candidate in promising {
			if cellCanExpand(candidate:cell) {
				if chaseCandidate:istype("Boolean") {
					set chaseCandidate to candidate.
				}
				else if candidate:dvTotal < chaseCandidate:dvTotal {
					set chaseCandidate to candidate.
				}
			}
		}

		if not chaseCandidate:istype("Boolean") {
			local chased is chaseBoundary(
				chaseCandidate,
				cfg:phaseSizes[cfg:phaseSizes:length - 1],
				shipSnapshot,
				targetSnapshot,
				departureWindow,
				tofWindow,
				targetPhaseOffset,
				transferSafetyBounds,
				cfg
			).

			if chased:dvTotal < best:dvTotal set best to chased.
		}

		return best.
	}

	// Final live refresh
	// ----------------------------------------------------------------

	function refreshTransfer {
		parameter candidate, targetSnapshot, targetPhaseOffset, transferSafetyBounds.

		local departureUT is candidate:departureUT.
		local tof is candidate:tof.
		local arrivalUT is departureUT + tof.
		local shipState is getStateAt(ship, departureUT).
		local arrivalPhase is phaseAtUT(targetSnapshot, arrivalUT).
		local targetState is getOrbitStateAtPhaseOffset(
			targetSnapshot,
			arrivalPhase + targetPhaseOffset
		).
		local departurePosition is shipState:position.
		local arrivalPosition is targetState:position.

		local transferResult is solveLambert(
			departurePosition,
			arrivalPosition,
			tof,
			body:mu,
			candidate:cell:direction,
			candidate:cell:revolutions,
			candidate:cell:branch,
			(-vcrs(departurePosition, shipState:velocity)):normalized
		).

		if not transferResult:valid {
			return transferInvalid(
				candidate:cell, transferResult:reason,
				departureUT, arrivalUT, tof
			).
		}

		// Transfer arc safety.
		local arcRadii is getArcRadii(departurePosition, arrivalPosition, transferResult:departureVelocity, tof, body).
		if arcRadii:min < transferSafetyBounds:min {
			return transferInvalid(
				candidate:cell, "Transfer arc goes below safe altitude",
				departureUT, arrivalUT, tof
			).
		}
		if arcRadii:max >= transferSafetyBounds:max {
			return transferInvalid(
				candidate:cell, "Transfer arc leaves current SOI",
				departureUT, arrivalUT, tof
			).
		}

		return createTransferCandidate(
			candidate:cell, departureUT, arrivalUT,
			shipState, targetState, transferResult
		).
	}

	// Maneuver node
	// ----------------------------------------------------------------

	function transferToNodes {
		parameter candidate.

		local mnvDeparture is velocityChangeToNode(
			candidate:departureUT,
			candidate:shipState:position,
			candidate:shipState:velocity,
			candidate:transfer:departureVelocity
		).
		local mnvArrival is velocityChangeToNode(
			candidate:arrivalUT,
			candidate:targetState:position,
			candidate:transfer:arrivalVelocity,
			candidate:targetState:velocity
		).

		{
			// DEBUG
			dPrint("================================").
			dPrint("FINAL TRANSFER").
			dPrint("departure UT = " + candidate:departureUT).
			dPrint("arrival UT = " + candidate:arrivalUT).
			dPrint("tof = " + candidate:tof).
			dPrint("departure dV = " + candidate:dvDeparture).
			dPrint("arrival dV = " + candidate:dvArrival).
			dPrint("total dV = " + candidate:dvTotal).
			dPrint("departure radial = " + mnvDeparture:radialout).
			dPrint("departure normal = " + mnvDeparture:normal).
			dPrint("departure prograde = " + mnvDeparture:prograde).
			dPrint("arrival radial = " + mnvArrival:radialout).
			dPrint("arrival normal = " + mnvArrival:normal).
			dPrint("arrival prograde = " + mnvArrival:prograde).
		}

		return lex(
			"departure", mnvDeparture,
			"arrival", mnvArrival
		).
	}

	// Public rendezvous API
	// ----------------------------------------------------------------

	function rendezvous {
		parameter withTarget, atPhaseOffset is 0, options is lex().

		local targetOrbit is withTarget.
		if withTarget:istype("Vessel") or withTarget:istype("Body") {
			set targetOrbit to withTarget:orbit.
		}
		else if not withTarget:istype("Orbit") {
			return ApiFail("Rendezvous target must be a Vessel, Body, or Orbit").
		}

		if body <> targetOrbit:body {
			return ApiFail("Targeted orbit must be in the same SOI").
		}

		if targetOrbit:eccentricity >= 1 {
			return ApiFail("Orbital-phase rendezvous search does not safely support targeting a hyperbolic trajectory").
		}

		local configResult is createConfig(DEFAULT_CONFIG, options).
		if not configResult:ok return configResult.
		local cfg is configResult:val.

		// Freeze the ship at an exact search reference UT. The target Orbit snapshots itself at the time its current state is sampled.
		local referenceUT is time:seconds.
		local shipSnapshot is createOrbitableSnapshot(ship, referenceUT).
		local targetSnapshot is createOrbitSnapshot(targetOrbit).

		local departureWindowResult is calculateDepartureWindow(shipSnapshot, cfg).
		if not departureWindowResult:ok return ApiFail(departureWindowResult:msg).
		local departureWindow is departureWindowResult:val.

		local tofWindowResult is calculateTOFWindow(shipSnapshot, targetSnapshot, departureWindow, cfg).
		if not tofWindowResult:ok return ApiFail(tofWindowResult:msg).
		local tofWindow is tofWindowResult:val.

		// Calculate the min/max safe radius for a transfer
		local safeRadiusResult is altitudeSafety:radius(body).
		if not safeRadiusResult:ok return safeRadiusResult.
		local transferSafetyBounds is lex(
			"min", safeRadiusResult:val + cfg:peClearance,
			"max", body:soiradius - cfg:soiClearance
		).

		{
			// DEBUG
			dPrint("================================").
			dPrint("RENDEZVOUS SEARCH").
			dPrint("================================").
			dPrint("UT now = " + referenceUT).
			dPrint("ship = " + ship:name).
			dPrint("target = " + withTarget:tostring).
			dPrint("target reference UT = " + targetSnapshot:referenceUT).
			dPrint("target phase offset = " + atPhaseOffset).
			dPrint("body = " + body:name).
			dPrint("ship a = " + shipSnapshot:semimajorAxis).
			dPrint("ship e = " + shipSnapshot:eccentricity).
			dPrint("ship V0 = " + shipSnapshot:trueAnomaly).
			dPrint("target a = " + targetSnapshot:semimajorAxis).
			dPrint("target e = " + targetSnapshot:eccentricity).
			dPrint("target V0 = " + targetSnapshot:trueAnomaly).

			dPrint("--------------------------------").
			dPrint("SEARCH CONFIGURATION").
			dPrint("minimum departure burn eta = " + cfg:burnEta).
			dPrint("minimum departure search offset = " + cfg:depOffset).
			dPrint("minimum departure search period factor = " + cfg:depPeriodFactor).
			dPrint("minimum patch transition margin = " + cfg:patchMargin).
			dPrint("maximum orbit count = " + cfg:depOrbits).
			dPrint("minimum tof = " + cfg:tofMin).
			dPrint("minimum tof factor = " + cfg:tofMinFactor).
			dPrint("tof window factor = " + cfg:tofWindowFactor).
			dPrint("maximum revolutions = " + cfg:maxRevs).
			dPrint("phase cell sizes = " + cfg:phaseSizes:join(", ")).
			dPrint("maximum initial phase samples/dimension = " + cfg:phaseSamples).
			dPrint("retention limit = " + cfg:retainMax).
			dPrint("retention fraction = " + cfg:retainFraction).
			dPrint("retention per Lambert family = " + cfg:retainFamily).
			dPrint("minimum periapsis clearance = " + cfg:peClearance).
			dPrint("minimum soi radius clearance = " + cfg:soiClearance).
			dPrint("output porkchop log = " + cfg:porkchop).
			dPrint("stream progress interval = " + cfg:progressEvery).
			dPrint("maximum boundary chase degrees = " + cfg:chaseDegrees).

			dPrint("--------------------------------").
			dPrint("SEARCH WINDOWS").
			dPrint("departure min = " + departureWindow:min).
			dPrint("departure max = " + departureWindow:max).
			dPrint("tof min = " + tofWindow:min).
			dPrint("tof max = " + tofWindow:max).
		}

		local oldIpu is config:ipu.
		set config:ipu to 2000.

		local best is adaptiveSearch(
			shipSnapshot,
			targetSnapshot,
			departureWindow,
			tofWindow,
			atPhaseOffset,
			transferSafetyBounds,
			cfg
		).
		set config:ipu to oldIpu.

		if best:istype("Boolean") return ApiFail("No valid transfer was found").

		{
			// DEBUG
			dPrint("================================").
			dPrint("REFRESHING FINAL TRANSFER").
			dPrint("search finished UT = " + time:seconds).
			dPrint("original departure dV = " + best:dvDeparture).
			dPrint("original arrival dV = " + best:dvArrival).
			dPrint("original total dV = " + best:dvTotal).
		}

		local refreshed is refreshTransfer(
			best,
			targetSnapshot,
			atPhaseOffset,
			transferSafetyBounds
		).
		if not refreshed:valid {
			return ApiFail("Unable to refresh final transfer: " + refreshed:reason).
		}

		local departureBurnEta is refreshed:departureUT - time:seconds.
		{
			// DEBUG
			dPrint("departure burn eta = " + departureBurnEta).
		}
		if departureBurnEta < cfg:burnEta {
			return ApiFail("Transfer departure is too soon; only " + round(departureBurnEta) + " seconds remain").
		}
		{
			// DEBUG
			dPrint("refreshed departure dV = " + refreshed:dvDeparture).
			dPrint("refreshed arrival dV = " + refreshed:dvArrival).
			dPrint("refreshed total dV = " + refreshed:dvTotal).
			dPrint("departure dV change = " + (refreshed:dvDeparture - best:dvDeparture)).
			dPrint("arrival dV change = " + (refreshed:dvArrival - best:dvArrival)).
			dPrint("total dV change = " + (refreshed:dvTotal - best:dvTotal)).
		}

		return ApiOK(transferToNodes(refreshed)).
	}

	export(rendezvous@).
}