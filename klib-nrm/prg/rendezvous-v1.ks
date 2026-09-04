{
	local OrbitalMechanics is import("mech/orbitalMechanics-v1"),
		OrbitalParameters is import("mech/orbitalParameters-v1"),
		solveLambert is import("mech/solveLambert-v1"),
		altitudeSafety is import("tlm/altitudeSafety-v1"),
		velocityChangeToNode is import("mnv/velocityChangeToNode-v1"),
		createConfig is import("util/createConfig-v1"),
		PHASE_TIME_BISECTION_ITERATIONS is 40,
		LAMBERT_DIRECTIONS is list("short", "long"),
		LAMBERT_BRANCHES is list("left", "right"),
		DEFAULT_CONFIG is lex(
			"burnEta", 60,
			"depOffset", 900,
			"depPeriodFactor", 0.1,
			"patchMargin", 60,
			"depOrbits", 2,
			"tofMin", 60,
			"tofMinFactor", 0.5,
			"tofWindowFactor", 1.5,
			"maxRevs", 2,
			"phaseSizes", list(15, 3, 0.5, 0.1, 0.01),
			"phaseSamples", 100,
			"retainMax", 40,
			"retainFraction", 0.25,
			"retainFamily", 4,
			"peClearance", 1e3,
			"soiClearance", 1e3,
			"porkchop", false,
			"progressEvery", 1000,
			"chaseDegrees", 5,
			"progressStart", {parameter phaseSize. print "Evaluating initial phase grid at " + phaseSize + "°".},
			"progressLevel", {parameter level, phaseSize. print "Evaluating phase grid level " + level + " at " + phaseSize + "°". },
			"progressCell", {parameter level, evaluated. print "Level " + level + ": " + evaluated + " evaluated". },
			"progressChase", {parameter phaseCellSize, maxIterations. print "Chasing final refinement boundary".}
		).
	function trueAnomalyOfState {
		parameter positionVector, eccentricityVector, eccentricity, angularMomentumVector, signed is false.
		if eccentricity < 1e-12 return 0.
		local trueAnomaly is arccos(max(-1, min(1, vdot(eccentricityVector, positionVector) / (eccentricity * positionVector:mag)))).
		if vdot(-vcrs(eccentricityVector, positionVector), angularMomentumVector) < 0 {
			if signed return -trueAnomaly.
			return 360 - trueAnomaly.
		}
		return trueAnomaly.
	}
	function getArcRadii {
		parameter departurePosition, arrivalPosition, transferDepartureVelocity, tof, targetBody.
		local angularMomentumVector is -vcrs(departurePosition, transferDepartureVelocity),
			eccentricityVector is (-vcrs(transferDepartureVelocity, angularMomentumVector) / targetBody:mu) - departurePosition:normalized,
			transferEccentricity is eccentricityVector:mag,
			semilatusRectum is angularMomentumVector:mag^2 / targetBody:mu,
			periapsisRadius is semilatusRectum / (1 + transferEccentricity),
			minimumArcRadius is min(departurePosition:mag, arrivalPosition:mag),
			maximumArcRadius is max(departurePosition:mag, arrivalPosition:mag),
			departureTrueAnomaly is trueAnomalyOfState(
				departurePosition,
				eccentricityVector,
				transferEccentricity,
				angularMomentumVector,
				transferEccentricity >= 1
			).
		if transferEccentricity < 1 {
			local transferSemimajorAxis is semilatusRectum / (1 - transferEccentricity^2),
				transferPeriod is OrbitalMechanics:P(
					transferSemimajorAxis,
					targetBody
				),
				apoapsisRadius is semilatusRectum / (1 - transferEccentricity).
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
					),
					etaApoapsis is mod(
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
			"n", minimumArcRadius,
			"x", maximumArcRadius
		).
	}
	function transferInvalid {
		parameter cell, reason, departureUT, arrivalUT, tof.
		return lex(
			"v", false,
			"c", cell,
			"r", reason,
			"d", departureUT,
			"a", arrivalUT,
			"t", tof
		).
	}
	function createSearchCandidate {
		parameter cell, departureUT, arrivalUT, shipState, targetState, transferResult.
		local dvDeparture is (transferResult:departureVelocity - shipState:v):mag,
			dvArrival is (targetState:v - transferResult:arrivalVelocity):mag.
		return lex(
			"v", true,
			"c", cell,
			"d", departureUT,
			"a", arrivalUT,
			"t", arrivalUT - departureUT,
			"x", dvDeparture,
			"y", dvArrival,
			"z", dvDeparture + dvArrival
		).
	}
	function createTransferCandidate {
		parameter cell, departureUT, arrivalUT, shipState, targetState, transferResult.
		local candidate is createSearchCandidate(cell, departureUT, arrivalUT, shipState, targetState, transferResult).
		set candidate["s"] to shipState.
		set candidate["g"] to targetState.
		set candidate["f"] to transferResult.
		return candidate.
	}
	function createOrbitSnapshotFromState {
		parameter targetOrbit, referenceUT, positionVector, velocityVector, transitionUT is false.
		local targetBody is targetOrbit:body,
			angularMomentumVector is -vcrs(positionVector, velocityVector),
			angularMomentumMag is angularMomentumVector:mag,
			eccentricityVector is (-vcrs(velocityVector, angularMomentumVector) / targetBody:mu) - positionVector:normalized,
			eccentricity is eccentricityVector:mag,
			trueAnomaly is trueAnomalyOfState(
				positionVector,
				eccentricityVector,
				eccentricity,
				angularMomentumVector,
				eccentricity >= 1
			),
			radialVector is positionVector:normalized,
			transverseVector is (velocityVector - radialVector * vdot(velocityVector, radialVector)):normalized.
		return lex(
			"t", referenceUT,
			"b", targetBody,
			"v", trueAnomaly,
			"p", choose targetOrbit:period if eccentricity < 1 else false,
			"e", eccentricity,
			"a", targetOrbit:semimajoraxis,
			"m", choose targetOrbit:apoapsis if eccentricity < 1 else false,
			"n", targetOrbit:periapsis,
			"x", radialVector,
			"y", transverseVector,
			"l", angularMomentumMag^2 / targetBody:mu,
			"s", targetBody:mu / angularMomentumMag,
			"z", angularMomentumVector:normalized,
			"u", transitionUT
		).
	}
	function createOrbitableSnapshot {
		parameter targetOrbitable, referenceUT.
		local targetOrbit is targetOrbitable:orbit,
			targetBody is targetOrbit:body,
			transitionUT is false.
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
	function createOrbitSnapshot {
		parameter targetOrbit.
		local targetBody is targetOrbit:body,
			sampleUTBefore is time:seconds,
			positionVector is targetOrbit:position - targetBody:position,
			velocityVector is targetOrbit:velocity:orbit,
			sampleUTAfter is time:seconds,
			referenceUT is (sampleUTBefore + sampleUTAfter) / 2,
			transitionUT is false.
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
	function phaseToUT {
		parameter orbitSnapshot, phaseDegrees.
		if orbitSnapshot:e < 1 return orbitSnapshot:t + OrbitalMechanics:dtV(
				phaseDegrees,
				orbitSnapshot:p,
				orbitSnapshot:v,
				orbitSnapshot:e
			).
		return orbitSnapshot:t + OrbitalMechanics:etaVh(
			orbitSnapshot:v + phaseDegrees,
			orbitSnapshot:v,
			orbitSnapshot:a,
			orbitSnapshot:e,
			orbitSnapshot:b
		).
	}
	function phaseAtUT {
		parameter orbitSnapshot, ut.
		if ut <= orbitSnapshot:t return 0.
		local phaseLow is 0,
			phaseHigh is 0.
		if orbitSnapshot:e < 1 {
			local elapsedTime is ut - orbitSnapshot:t,
				upperOrbitCount is ceiling(elapsedTime / orbitSnapshot:p) + 1.
			set phaseHigh to upperOrbitCount * 360.
		}
		else {
			set phaseHigh to  OrbitalParameters:Vlim(orbitSnapshot:e) - orbitSnapshot:v - 1e-6.
		}
		from { local iteration is 0. }
		until iteration >= PHASE_TIME_BISECTION_ITERATIONS
		step { set iteration to iteration + 1. }
		do {
			local phaseMid is (phaseLow + phaseHigh) / 2,
				phaseUT is phaseToUT(orbitSnapshot, phaseMid).
			if phaseUT < ut set phaseLow to phaseMid.
			else set phaseHigh to phaseMid.
		}
		return (phaseLow + phaseHigh) / 2.
	}
	function calculateDepartureWindow {
		parameter shipSnapshot, cfg.
		local departureSearchOffset is cfg:depOffset.
		if shipSnapshot:e < 1 {
			set departureSearchOffset to max(
				departureSearchOffset,
				shipSnapshot:p * cfg:depPeriodFactor
			).
		}
		local earliestDepartureUT is shipSnapshot:t + departureSearchOffset,
			latestDepartureUT is 0.
		if shipSnapshot:e < 1 {
			set latestDepartureUT to earliestDepartureUT + cfg:depOrbits * shipSnapshot:p.
			if not shipSnapshot:u:istype("Boolean") {
				set latestDepartureUT to min(
					latestDepartureUT,
					shipSnapshot:u - cfg:patchMargin
				).
			}
		}
		else {
			if shipSnapshot:u:istype("Boolean") {
				return ApiFail("Hyperbolic departure trajectory has no finite patch transition").
			}
			set latestDepartureUT to shipSnapshot:u - cfg:patchMargin.
		}
		if latestDepartureUT <= earliestDepartureUT return ApiFail("Orbit will transition and the departure window is too small").
		return ApiOK(lex(
			"n", earliestDepartureUT,
			"x", latestDepartureUT
		)).
	}
	function calculateTOFWindow {
		parameter shipSnapshot, targetSnapshot, departureWindow, cfg.
		local minAltitude is 0,
			maxAltitude is 0.
		if shipSnapshot:e < 1 {
			set minAltitude to min(shipSnapshot:n, targetSnapshot:n).
			set maxAltitude to max(shipSnapshot:m, targetSnapshot:m).
		}
		else {
			local departureMinAltitude is (positionAt(ship, departureWindow:n) - body:position):mag - body:radius,
				departureMaxAltitude is (positionAt(ship, departureWindow:x) - body:position):mag - body:radius.
			set minAltitude to min(min(min(shipSnapshot:n, targetSnapshot:n), departureMinAltitude), departureMaxAltitude).
			set maxAltitude to max(max(targetSnapshot:m, departureMinAltitude), departureMaxAltitude).
		}
		local refPeriod is OrbitalMechanics:Ph(minAltitude, maxAltitude, body),
			refHalfPeriod is refPeriod / 2,
			minTof is max(cfg:tofMin, refHalfPeriod * cfg:tofMinFactor),
			maxTof is refHalfPeriod * cfg:tofWindowFactor + cfg:maxRevs * refPeriod.
		if not targetSnapshot:u:istype("Boolean") {
			set maxTof to min(maxTof, targetSnapshot:u - departureWindow:n).
		}
		if maxTof <= minTof return ApiFail("No useful time-of-flight window exists").
		return ApiOK(lex(
			"n", minTof,
			"x", maxTof
		)).
	}
	function getStateAt {
		parameter targetOrbitable, ut.
		return lex(
			"p", positionAt(targetOrbitable, ut) - body:position,
			"v", velocityAt(targetOrbitable, ut):orbit
		).
	}
	function getOrbitStateAtPhaseOffset {
		parameter orbitSnapshot, phaseDegrees.
		local phaseCos is cos(phaseDegrees),
			phaseSin is sin(phaseDegrees),
			radialVector is orbitSnapshot:x * phaseCos + orbitSnapshot:y * phaseSin,
			transverseVector is orbitSnapshot:y * phaseCos - orbitSnapshot:x * phaseSin,
			trueAnomaly is orbitSnapshot:v + phaseDegrees,
			trueAnomalyCos is cos(trueAnomaly),
			trueAnomalySin is sin(trueAnomaly),
			radius is orbitSnapshot:l / (1 + orbitSnapshot:e * trueAnomalyCos),
			radialVelocity is orbitSnapshot:s * orbitSnapshot:e * trueAnomalySin,
			transverseVelocity is orbitSnapshot:s * (1 + orbitSnapshot:e * trueAnomalyCos).
		return lex(
			"p", radialVector * radius,
			"v", radialVector * radialVelocity + transverseVector * transverseVelocity
		).
	}
	function evaluateTransfer {
		parameter cell, shipSnapshot, targetSnapshot,
			departureWindow, tofWindow, targetPhaseOffset,
			transferSafetyBounds.
		local departurePhase is (cell:d:n + cell:d:x) / 2,
			arrivalPhase is (cell:a:n + cell:a:x) / 2,
			departureUT is phaseToUT(shipSnapshot, departurePhase),
			arrivalUT is phaseToUT(targetSnapshot, arrivalPhase),
			tof is arrivalUT - departureUT.
		if departureUT < departureWindow:n or departureUT > departureWindow:x {
			return transferInvalid(
				cell, "Departure is outside the departure window",
				departureUT, arrivalUT, tof
			).
		}
		if tof < tofWindow:n or tof > tofWindow:x {
			return transferInvalid(
				cell, "Time of flight is outside the search window",
				departureUT, arrivalUT, tof
			).
		}
		if not targetSnapshot:u:istype("Boolean")
			and arrivalUT >= targetSnapshot:u {
			return transferInvalid(
				cell, "Target leaves current SOI before arrival",
				departureUT, arrivalUT, tof
			).
		}
		local shipState is getStateAt(ship, departureUT),
			targetState is getOrbitStateAtPhaseOffset(targetSnapshot, arrivalPhase + targetPhaseOffset),
			departurePosition is shipState:p,
			arrivalPosition is targetState:p,
			transferResult is solveLambert(
				departurePosition,
				arrivalPosition,
				tof,
				body:mu,
				cell:r,
				cell:v,
				cell:b,
				shipSnapshot:z
			).
		if not transferResult:valid {
			return transferInvalid(
				cell, transferResult:reason,
				departureUT, arrivalUT, tof
			).
		}
		local arcRadii is getArcRadii(departurePosition, arrivalPosition, transferResult:departureVelocity, tof, body).
		if arcRadii:n < transferSafetyBounds:n {
			return transferInvalid(
				cell, "Transfer arc goes below safe altitude",
				departureUT, arrivalUT, tof
			).
		}
		if arcRadii:x >= transferSafetyBounds:x {
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
	function familyKey {
		parameter candidate.
		if candidate:c:v = 0 {
			return candidate:c:v + ":" + candidate:c:r.
		}
		return candidate:c:v + ":" + candidate:c:r + ":" + candidate:c:b.
	}
	function insertBestCandidate {
		parameter candidates, candidate, limit.
		if limit <= 0 return.
		if limit = 1 {
			if candidates:length = 0 candidates:add(candidate).
			else if candidate:z < candidates[0]:z set candidates[0] to candidate.
			return.
		}
		local insertIndex is candidates:length.
		from { local candidateIndex is 0. }
		until candidateIndex >= candidates:length
		step { set candidateIndex to candidateIndex + 1. }
		do {
			if candidate:z < candidates[candidateIndex]:z {
				set insertIndex to candidateIndex.
				break.
			}
		}
		candidates:insert(insertIndex, candidate).
		if candidates:length > limit candidates:remove(candidates:length - 1).
	}
	function retainCandidate {
		parameter retentionState, candidate, cfg.
		set retentionState["c"] to retentionState:c + 1.
		insertBestCandidate(retentionState:g, candidate, cfg:retainMax).
		if cfg:retainFamily <= 0 return.
		local candidateFamily is familyKey(candidate).
		if not retentionState:f:haskey(candidateFamily) {
			retentionState:f:add(candidateFamily, list()).
		}
		insertBestCandidate(
			retentionState:f[candidateFamily],
			candidate,
			cfg:retainFamily
		).
	}
	function candidateAlreadyRetained {
		parameter candidates, candidateId.
		for retainedCandidate in candidates {
			if retainedCandidate:c:id = candidateId return true.
		}
		return false.
	}
	function finalizeRetention {
		parameter retentionState, cfg.
		if retentionState:c = 0 return list().
		local topCount is max(1, min(cfg:retainMax, floor(retentionState:c * cfg:retainFraction))),
			retained is list(),
			globalCount is min(topCount, retentionState:g:length).
		from { local globalIndex is 0. }
		until globalIndex >= globalCount
		step { set globalIndex to globalIndex + 1. }
		do {
			retained:add(retentionState:g[globalIndex]).
		}
		if cfg:retainFamily > 0 {
			for candidateFamily in retentionState:f:keys {
				for familyCandidate in retentionState:f[candidateFamily] {
					if not candidateAlreadyRetained(retained, familyCandidate:c:id) {
						retained:add(familyCandidate).
					}
				}
			}
		}
		return retained.
	}
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
			"l", level,
			"n", 0,
			"p", porkchopLog,
			"r", lex(
				"c", 0,
				"g", list(),
				"f", lex()
			)
		).
	}
	function logPorkchopResult {
		parameter evaluationState, result.
		local cell is result:c.
		if result:v {
			log
				cell:d:n + ","
				+ cell:d:x + ","
				+ cell:a:n + ","
				+ cell:a:x + ","
				+ result:d + ","
				+ result:a + ","
				+ result:t + ","
				+ cell:v + ","
				+ cell:r + ","
				+ cell:b + ","
				+ result:x + ","
				+ result:y + ","
				+ result:z + ","
			to evaluationState:p.
		}
		else {
			log
				cell:d:n + ","
				+ cell:d:x + ","
				+ cell:a:n + ","
				+ cell:a:x + ","
				+ result:d + ","
				+ result:a + ","
				+ result:t + ","
				+ cell:v + ","
				+ cell:r + ","
				+ cell:b + ",,,,"
				+ result:r
			to evaluationState:p.
		}
	}
	function processCell {
		parameter cell, evaluationState,
			shipSnapshot, targetSnapshot, departureWindow, tofWindow,
			targetPhaseOffset, transferSafetyBounds, cfg, retain is true.
		cell:add("id", evaluationState:n).
		set evaluationState["n"] to evaluationState:n + 1.
		local result is evaluateTransfer(
			cell,
			shipSnapshot,
			targetSnapshot,
			departureWindow,
			tofWindow,
			targetPhaseOffset,
			transferSafetyBounds
		).
		if result:v and retain {
			retainCandidate(evaluationState:r, result, cfg).
		}
		if cfg:porkchop logPorkchopResult(evaluationState, result).
		if cfg:progressEvery > 0 and mod(evaluationState:n, cfg:progressEvery) = 0 {
			cfg:progressCell(evaluationState:l, evaluationState:n).
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
			"d", lex(
				"n", departurePhaseMin,
				"x", departurePhaseMax
			),
			"a", lex(
				"n", arrivalPhaseMin,
				"x", arrivalPhaseMax
			),
			"v", revolutions,
			"r", direction,
			"b", branch,
			"m", expandDepartureMin,
			"n", expandDepartureMax,
			"o", expandArrivalMin,
			"p", expandArrivalMax
		).
	}
	function cellCanExpand {
		parameter cell.
		return cell:m or cell:n or cell:o or cell:p.
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
					if revolutionCount = 0 break.
				}
			}
		}
	}
	function cellCount {
		parameter width, resolution.
		local countExact is width / resolution,
			countNearest is round(countExact).
		if abs(countExact - countNearest) < 1e-9 {
			return max(1, countNearest).
		}
		return max(1, ceiling(countExact)).
	}
	function evaluateInitialPhaseGrid {
		parameter shipSnapshot, targetSnapshot,
			departureWindow, tofWindow, targetPhaseOffset,
			transferSafetyBounds, cfg.
		local evaluationState is createEvaluationState(0, cfg),
			departurePhaseMin is phaseAtUT(shipSnapshot, departureWindow:n),
			departurePhaseMax is phaseAtUT(shipSnapshot, departureWindow:x),
			departurePhaseWidth is departurePhaseMax - departurePhaseMin,
			departurePhaseResolution is max(cfg:phaseSizes[0], departurePhaseWidth / cfg:phaseSamples),
			departureCount is cellCount(departurePhaseWidth, departurePhaseResolution).
		set departurePhaseResolution to departurePhaseWidth / departureCount.
		from { local departureIndex is 0. }
		until departureIndex >= departureCount
		step { set departureIndex to departureIndex + 1. }
		do {
			local phaseDepartureMin is departurePhaseMin + departureIndex * departurePhaseResolution,
				phaseDepartureMax is min(phaseDepartureMin + departurePhaseResolution, departurePhaseMax),
				phaseDepartureMid is (phaseDepartureMin + phaseDepartureMax) / 2,
				departureUT is phaseToUT(shipSnapshot, phaseDepartureMid),
				arrivalUTMin is departureUT + tofWindow:n,
				arrivalUTMax is departureUT + tofWindow:x.
			if not targetSnapshot:u:istype("Boolean") {
				set arrivalUTMax to min(arrivalUTMax, targetSnapshot:u).
			}
			if arrivalUTMax > arrivalUTMin {
				local arrivalPhaseMin is phaseAtUT(targetSnapshot, arrivalUTMin),
					arrivalPhaseMax is phaseAtUT(targetSnapshot, arrivalUTMax),
					arrivalPhaseWidth is arrivalPhaseMax - arrivalPhaseMin,
					arrivalPhaseResolution is max(cfg:phaseSizes[0], arrivalPhaseWidth / cfg:phaseSamples),
					arrivalCount is cellCount(arrivalPhaseWidth, arrivalPhaseResolution).
				set arrivalPhaseResolution to arrivalPhaseWidth / arrivalCount.
				from { local arrivalIndex is 0. }
				until arrivalIndex >= arrivalCount
				step { set arrivalIndex to arrivalIndex + 1. }
				do {
					local phaseArrivalMin is arrivalPhaseMin + arrivalIndex * arrivalPhaseResolution,
						phaseArrivalMax is min(phaseArrivalMin + arrivalPhaseResolution, arrivalPhaseMax),
						expandDepartureMin is departureIndex > 0,
						expandDepartureMax is departureIndex < departureCount - 1,
						expandArrivalMin is true,
						expandArrivalMax is true.
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
		return finalizeRetention(evaluationState:r, cfg).
	}
	function evaluateRefinedPhaseGrid {
		parameter parentCandidates, phaseCellSize, level,
			shipSnapshot, targetSnapshot, departureWindow, tofWindow,
			targetPhaseOffset, transferSafetyBounds, cfg.
		local evaluationState is createEvaluationState(level, cfg).
		for parentCandidate in parentCandidates {
			local parentCell is parentCandidate:c,
				refineDepartureMin is parentCell:d:n,
				refineDepartureMax is parentCell:d:x,
				refineArrivalMin is parentCell:a:n,
				refineArrivalMax is parentCell:a:x.
			if level > 1 {
				if parentCell:m {
					set refineDepartureMin to refineDepartureMin - phaseCellSize.
				}
				if parentCell:n {
					set refineDepartureMax to refineDepartureMax + phaseCellSize.
				}
				if parentCell:o {
					set refineArrivalMin to refineArrivalMin - phaseCellSize.
				}
				if parentCell:p {
					set refineArrivalMax to refineArrivalMax + phaseCellSize.
				}
			}
			local departurePhaseWidth is refineDepartureMax - refineDepartureMin,
				arrivalPhaseWidth is refineArrivalMax - refineArrivalMin,
				departureCount is cellCount(departurePhaseWidth, phaseCellSize),
				arrivalCount is cellCount(arrivalPhaseWidth, phaseCellSize),
				departureResolution is departurePhaseWidth / departureCount,
				arrivalResolution is arrivalPhaseWidth / arrivalCount.
			from { local departureIndex is 0. }
			until departureIndex >= departureCount
			step { set departureIndex to departureIndex + 1. }
			do {
				local childDepartureMin is refineDepartureMin + departureIndex * departureResolution,
					childDepartureMax is min(childDepartureMin + departureResolution, refineDepartureMax).
				from { local arrivalIndex is 0. }
				until arrivalIndex >= arrivalCount
				step { set arrivalIndex to arrivalIndex + 1. }
				do {
					local childArrivalMin is refineArrivalMin + arrivalIndex * arrivalResolution,
						childArrivalMax is min(childArrivalMin + arrivalResolution, refineArrivalMax),
						expandDepartureMin is parentCell:m and departureIndex = 0,
						expandDepartureMax is parentCell:n and departureIndex = departureCount - 1,
						expandArrivalMin is parentCell:o and arrivalIndex = 0,
						expandArrivalMax is parentCell:p and arrivalIndex = arrivalCount - 1,
						childCell is createCell(
							childDepartureMin,
							childDepartureMax,
							childArrivalMin,
							childArrivalMax,
							parentCell:v,
							parentCell:r,
							parentCell:b,
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
		return finalizeRetention(evaluationState:r, cfg).
	}
	function chaseBoundary {
		parameter candidate, phaseCellSize,
			shipSnapshot, targetSnapshot, departureWindow, tofWindow,
			targetPhaseOffset, transferSafetyBounds, cfg.
		local maxIterations is floor(cfg:chaseDegrees / phaseCellSize).
		if maxIterations <= 0 or not cellCanExpand(candidate:c) {
			return candidate.
		}
		
		cfg:progressChase(phaseCellSize, maxIterations).
		local evaluationState is createEvaluationState("boundary", cfg),
			best is candidate,
			iterations is 0.
		until iterations >= maxIterations or not cellCanExpand(best:c) {
			local cell is best:c,
				departureWidth is cell:d:x - cell:d:n,
				arrivalWidth is cell:a:x - cell:a:n,
				departureOffsets is list(0).
			if cell:m departureOffsets:add(-1).
			if cell:n departureOffsets:add(1).
			local arrivalOffsets is list(0).
			if cell:o arrivalOffsets:add(-1).
			if cell:p arrivalOffsets:add(1).
			local nextBest is best,
				improved is false.
			for departureOffset in departureOffsets {
				for arrivalOffset in arrivalOffsets {
					if departureOffset <> 0 or arrivalOffset <> 0 {
						local departureShift is departureOffset * departureWidth,
							arrivalShift is arrivalOffset * arrivalWidth,
							adjacentCell is createCell(
								cell:d:n + departureShift,
								cell:d:x + departureShift,
								cell:a:n + arrivalShift,
								cell:a:x + arrivalShift,
								cell:v,
								cell:r,
								cell:b,
								cell:m and departureOffset <= 0,
								cell:n and departureOffset >= 0,
								cell:o and arrivalOffset <= 0,
								cell:p and arrivalOffset >= 0
							),
							result is processCell(
								adjacentCell,
								evaluationState,
								shipSnapshot,
								targetSnapshot,
								departureWindow,
								tofWindow,
								targetPhaseOffset,
								transferSafetyBounds,
								cfg,
								false
							).
						if result:v and result:z < nextBest:z {
							set nextBest to result.
							set improved to true.
						}
					}
				}
			}
			set iterations to iterations + 1.
			if not improved break.
			set best to nextBest.
		}
		return best.
	}
	function adaptiveSearch {
		parameter shipSnapshot, targetSnapshot,
			departureWindow, tofWindow, targetPhaseOffset,
			transferSafetyBounds, cfg.
		cfg:progressStart(cfg:phaseSizes[0]).
		local promising is evaluateInitialPhaseGrid(
			shipSnapshot,
			targetSnapshot,
			departureWindow,
			tofWindow,
			targetPhaseOffset,
			transferSafetyBounds,
			cfg
		).
		if promising:length = 0 return false.
		local best is promising[0].
		from { local level is 1. }
		until level >= cfg:phaseSizes:length
		step { set level to level + 1. }
		do {
			cfg:progressLevel(level, cfg:phaseSizes[level]).
			set promising to evaluateRefinedPhaseGrid(
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
			if promising:length = 0 break.
			if promising[0]:z < best:z set best to promising[0].
		}
		local chaseCandidate is false.
		for candidate in promising {
			if cellCanExpand(candidate:c) {
				if chaseCandidate:istype("Boolean") {
					set chaseCandidate to candidate.
				}
				else if candidate:z < chaseCandidate:z {
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
			if chased:z < best:z set best to chased.
		}
		return best.
	}
	function refreshTransfer {
		parameter candidate, targetSnapshot, targetPhaseOffset, transferSafetyBounds.
		local departureUT is candidate:d,
			tof is candidate:t,
			arrivalUT is departureUT + tof,
			shipState is getStateAt(ship, departureUT),
			arrivalPhase is phaseAtUT(targetSnapshot, arrivalUT),
			targetState is getOrbitStateAtPhaseOffset(targetSnapshot, arrivalPhase + targetPhaseOffset),
			departurePosition is shipState:p,
			arrivalPosition is targetState:p,
			transferResult is solveLambert(
			departurePosition,
			arrivalPosition,
			tof,
			body:mu,
			candidate:c:r,
			candidate:c:v,
			candidate:c:b,
			(-vcrs(departurePosition, shipState:v)):normalized
		).
		if not transferResult:valid {
			return transferInvalid(
				candidate:c, transferResult:reason,
				departureUT, arrivalUT, tof
			).
		}
		local arcRadii is getArcRadii(departurePosition, arrivalPosition, transferResult:departureVelocity, tof, body).
		if arcRadii:n < transferSafetyBounds:n {
			return transferInvalid(
				candidate:c, "Transfer arc goes below safe altitude",
				departureUT, arrivalUT, tof
			).
		}
		if arcRadii:x >= transferSafetyBounds:x {
			return transferInvalid(
				candidate:c, "Transfer arc leaves current SOI",
				departureUT, arrivalUT, tof
			).
		}
		return createTransferCandidate(
			candidate:c, departureUT, arrivalUT,
			shipState, targetState, transferResult
		).
	}
	function transferToNodes {
		parameter candidate.
		local mnvDeparture is velocityChangeToNode(candidate:d, candidate:s:p, candidate:s:v, candidate:f:departureVelocity),
			mnvArrival is velocityChangeToNode(candidate:a, candidate:g:p, candidate:f:arrivalVelocity, candidate:g:v).
		return lex(
			"departure", mnvDeparture,
			"arrival", mnvArrival
		).
	}
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
		local cfg is configResult:val,
			referenceUT is time:seconds,
			shipSnapshot is createOrbitableSnapshot(ship, referenceUT),
			targetSnapshot is createOrbitSnapshot(targetOrbit),
			departureWindowResult is calculateDepartureWindow(shipSnapshot, cfg).
		if not departureWindowResult:ok return ApiFail(departureWindowResult:msg).
		local departureWindow is departureWindowResult:val,
			tofWindowResult is calculateTOFWindow(shipSnapshot, targetSnapshot, departureWindow, cfg).
		if not tofWindowResult:ok return ApiFail(tofWindowResult:msg).
		local tofWindow is tofWindowResult:val,
			safeRadiusResult is altitudeSafety:radius(body).
		if not safeRadiusResult:ok return safeRadiusResult.
		local transferSafetyBounds is lex("n", safeRadiusResult:val + cfg:peClearance, "x", body:soiradius - cfg:soiClearance),
			oldIpu is config:ipu.
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
		local refreshed is refreshTransfer(
			best,
			targetSnapshot,
			atPhaseOffset,
			transferSafetyBounds
		).
		if not refreshed:v {
			return ApiFail("Unable to refresh final transfer: " + refreshed:r).
		}
		local departureBurnEta is refreshed:d - time:seconds.
		if departureBurnEta < cfg:burnEta {
			return ApiFail("Transfer departure is too soon; only " + round(departureBurnEta) + " seconds remain").
		}
		return ApiOK(transferToNodes(refreshed)).
	}
	export(rendezvous@).
}