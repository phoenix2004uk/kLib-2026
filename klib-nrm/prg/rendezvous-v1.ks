{
	local OrbitalMechanics is import("mech/orbitalMechanics-v1").
	local OrbitalParameters is import("mech/orbitalParameters-v1").
	local solveLambert is import("mech/solveLambert-v1").
	local altitudeSafety is import("tlm/altitudeSafety-v1").
	local velocityChangeToNode is import("mnv/velocityChangeToNode-v1").
	local createConfig is import("util/createConfig-v1").
	local trueAnomalyOfState is {
		parameter positionVector, eccentricityVector, eccentricity, angularMomentumVector, signed is false.
		if eccentricity < 1e-12 return 0.
		local trueAnomaly is arccos(max(-1, min(1, (eccentricityVector * positionVector) / (eccentricity * positionVector:mag)))).
		if -vcrs(eccentricityVector, positionVector) * angularMomentumVector < 0 {
			if signed return -trueAnomaly.
			return 360 - trueAnomaly.
		}
		return trueAnomaly.
	}.
	local getArcRadii is {
		parameter departurePosition, arrivalPosition, transferDepartureVelocity, tof, targetBody.
		local angularMomentumVector is -vcrs(departurePosition, transferDepartureVelocity).
		local eccentricityVector is (-vcrs(transferDepartureVelocity, angularMomentumVector) / targetBody:mu) - departurePosition:normalized.
		local transferEccentricity is eccentricityVector:mag.
		local semilatusRectum is angularMomentumVector:sqrmagnitude / targetBody:mu.
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
			local transferPeriod is OrbitalMechanics:P(
				semilatusRectum / (1 - transferEccentricity^2),
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
				if etaPeriapsis <= tof {
					set minimumArcRadius to min(minimumArcRadius, periapsisRadius).
				}
				if mod(etaPeriapsis + transferPeriod / 2, transferPeriod) <= tof {
					set maximumArcRadius to max(maximumArcRadius, apoapsisRadius).
				}
			}
		}
		else if departureTrueAnomaly <= 0 and trueAnomalyOfState(arrivalPosition, eccentricityVector, transferEccentricity, angularMomentumVector, true) >= 0 {
			set minimumArcRadius to min(minimumArcRadius, periapsisRadius).
		}
		return lex(
			"min", minimumArcRadius,
			"max", maximumArcRadius
		).
	}.
	local transferInvalid is {
		parameter cell, reason, departureUT, arrivalUT, tof.
		return lex(
			"valid", false,
			"cell", cell,
			"reason", reason,
			"departureUT", departureUT,
			"arrivalUT", arrivalUT,
			"tof", tof
		).
	}.
	local createOrbitSnapshotFromState is {
		parameter targetOrbit, referenceUT, positionVector, velocityVector, transitionUT is false.
		local targetBody is targetOrbit:body.
		local angularMomentumVector is -vcrs(positionVector, velocityVector).
		local angularMomentumMag is angularMomentumVector:mag.
		local eccentricityVector is (-vcrs(velocityVector, angularMomentumVector) / targetBody:mu) - positionVector:normalized.
		local eccentricity is eccentricityVector:mag.
		local radialVector is positionVector:normalized.
		return lex(
			"referenceUT", referenceUT,
			"body", targetBody,
			"trueAnomaly", trueAnomalyOfState(positionVector, eccentricityVector, eccentricity, angularMomentumVector, eccentricity >= 1),
			"period", choose targetOrbit:period if eccentricity < 1 else false,
			"eccentricity", eccentricity,
			"semimajorAxis", targetOrbit:semimajoraxis,
			"apoapsis", choose targetOrbit:apoapsis if eccentricity < 1 else false,
			"periapsis", targetOrbit:periapsis,
			"radialVector", radialVector,
			"transverseVector", (velocityVector - radialVector * (velocityVector * radialVector)):normalized,
			"semilatusRectum", angularMomentumVector:sqrmagnitude / targetBody:mu,
			"velocityFactor", targetBody:mu / angularMomentumMag,
			"planeNormal", angularMomentumVector / angularMomentumMag,
			"transitionUT", transitionUT
		).
	}.
	local phaseToUT is {
		parameter orbitSnapshot, phaseDegrees.
		if orbitSnapshot:eccentricity < 1 return orbitSnapshot:referenceUT + OrbitalMechanics:dtV(
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
	}.
	local phaseAtUT is {
		parameter orbitSnapshot, ut.
		if ut <= orbitSnapshot:referenceUT return 0.
		local phaseLow is 0.
		local phaseHigh is 0.
		if orbitSnapshot:eccentricity < 1 {
			set phaseHigh to (ceiling((ut - orbitSnapshot:referenceUT) / orbitSnapshot:period) + 1) * 360.
		}
		else {
			set phaseHigh to  OrbitalParameters:Vlim(orbitSnapshot:eccentricity) - orbitSnapshot:trueAnomaly - 1e-6.
		}
		from { local iteration is 0. }
		until iteration >= 40
		step { set iteration to iteration + 1. }
		do {
			local phaseMid is (phaseLow + phaseHigh) / 2.
			if phaseToUT(orbitSnapshot, phaseMid) < ut set phaseLow to phaseMid.
			else set phaseHigh to phaseMid.
		}
		return (phaseLow + phaseHigh) / 2.
	}.
	local getShipStateAt is {
		parameter ut.
		return lex(
			"position", positionAt(ship, ut) - body:position,
			"velocity", velocityAt(ship, ut):orbit
		).
	}.
	local getOrbitStateAtPhaseOffset is {
		parameter orbitSnapshot, phaseDegrees.
		local phaseCos is cos(phaseDegrees).
		local phaseSin is sin(phaseDegrees).
		local radialVector is orbitSnapshot:radialVector * phaseCos + orbitSnapshot:transverseVector * phaseSin.
		local trueAnomaly is orbitSnapshot:trueAnomaly + phaseDegrees.
		local trueAnomalyCos is cos(trueAnomaly).
		return lex(
			"position", radialVector * orbitSnapshot:semilatusRectum / (1 + orbitSnapshot:eccentricity * trueAnomalyCos),
			"velocity", radialVector * orbitSnapshot:velocityFactor * orbitSnapshot:eccentricity * sin(trueAnomaly) + (orbitSnapshot:transverseVector * phaseCos - orbitSnapshot:radialVector * phaseSin) * orbitSnapshot:velocityFactor * (1 + orbitSnapshot:eccentricity * trueAnomalyCos)
		).
	}.
	local insertBestCandidate is {
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
	}.
	local createCell is {
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
	}.
	local cellCanExpand is {
		parameter cell.
		return cell:expandDepartureMin or cell:expandDepartureMax or cell:expandArrivalMin or cell:expandArrivalMax.
	}.
	local cellCount is {
		parameter width, resolution.
		local countExact is width / resolution.
		local countNearest is round(countExact).
		if abs(countExact - countNearest) < 1e-9 {
			return max(1, countNearest).
		}
		return max(1, ceiling(countExact)).
	}.
	export({
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
		local configResult is createConfig(lex(
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
		), options).
		if not configResult:ok return configResult.
		local cfg is configResult:val.

		local targetSnapshot is 0.
		local transferSafetyBounds is 0.
		local bestCandidate is false.
		{
			local shipSnapshot is 0.
			local departureWindow is 0.
			local tofWindow is 0.
			{
				local referenceUT is time:seconds.
				local transitionUT is false.
				if obt:hasnextpatch {
					set transitionUT to referenceUT + obt:nextpatcheta.
				}
				set shipSnapshot to createOrbitSnapshotFromState(
					obt,
					referenceUT,
					positionAt(ship, referenceUT) - body:position,
					velocityAt(ship, referenceUT):orbit,
					transitionUT
				).
				set referenceUT to time:seconds.
				local positionVector is targetOrbit:position - targetOrbit:body:position.
				local velocityVector is targetOrbit:velocity:orbit.
				set transitionUT to time:seconds.

				set referenceUT to (referenceUT + transitionUT) / 2.
				set transitionUT to false.
				if targetOrbit:hasnextpatch {
					set transitionUT to referenceUT + targetOrbit:nextpatcheta.
				}
				set targetSnapshot to createOrbitSnapshotFromState(
					targetOrbit,
					referenceUT,
					positionVector,
					velocityVector,
					transitionUT
				).


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
					set latestDepartureUT to earliestDepartureUT + cfg:depOrbits * shipSnapshot:period.
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
				set departureWindow to lex(
					"min", earliestDepartureUT,
					"max", latestDepartureUT
				).


				local minAltitude is 0.
				local maxAltitude is 0.
				if shipSnapshot:eccentricity < 1 {
					set minAltitude to min(shipSnapshot:periapsis, targetSnapshot:periapsis).
					set maxAltitude to max(shipSnapshot:apoapsis, targetSnapshot:apoapsis).
				}
				else {
					local departureMinAltitude is (positionAt(ship, departureWindow:min) - body:position):mag - body:radius.
					local departureMaxAltitude is (positionAt(ship, departureWindow:max) - body:position):mag - body:radius.
					set minAltitude to min(min(min(shipSnapshot:periapsis, targetSnapshot:periapsis), departureMinAltitude), departureMaxAltitude).
					set maxAltitude to max(max(targetSnapshot:apoapsis, departureMinAltitude), departureMaxAltitude).
				}
				local refPeriod is OrbitalMechanics:Ph(minAltitude, maxAltitude, body).
				local refHalfPeriod is refPeriod / 2.
				local minTof is max(cfg:tofMin, refHalfPeriod * cfg:tofMinFactor).
				local maxTof is refHalfPeriod * cfg:tofWindowFactor + cfg:maxRevs * refPeriod.
				if not targetSnapshot:transitionUT:istype("Boolean") {
					set maxTof to min(maxTof, targetSnapshot:transitionUT - departureWindow:min).
				}
				if maxTof <= minTof return ApiFail("No useful time-of-flight window exists").
				set tofWindow to lex("min", minTof, "max", maxTof).
			}

			local safeRadiusResult is altitudeSafety:radius(body).
			if not safeRadiusResult:ok return safeRadiusResult.
			set transferSafetyBounds to lex("min", safeRadiusResult:val + cfg:peClearance, "max", body:soiradius - cfg:soiClearance).

			local oldIpu is config:ipu.
			set config:ipu to 2000.
			{
				cfg:progressStart(cfg:phaseSizes[0]).

				local finalizeRetention is {
					parameter retentionState.
					if retentionState:validCount = 0 return list().
					local retained is list().
					local globalCount is min(max(1, min(cfg:retainMax, floor(retentionState:validCount * cfg:retainFraction))), retentionState:globalBest:length).
					from { local globalIndex is 0. }
					until globalIndex >= globalCount
					step { set globalIndex to globalIndex + 1. }
					do {
						retained:add(retentionState:globalBest[globalIndex]).
					}
					if cfg:retainFamily > 0 {
						for candidateFamily in retentionState:familyBest:keys {
							for familyCandidate in retentionState:familyBest[candidateFamily] {
								local shouldRetain is true.
								for retainedCandidate in retained {
									if retainedCandidate:cell:id = familyCandidate:cell:id {
										set shouldRetain to false.
										break.
									}
								}
								if shouldRetain {
									retained:add(familyCandidate).
								}
							}
						}
					}
					return retained.
				}.
				local createEvaluationState is {
					parameter level.
					local porkchopLog is "0:/porkchop." + level + ".txt".
					if cfg:porkchop {
						deletePath(porkchopLog).
						log "departurePhase:min,departurePhase:max,arrivalPhase:min,arrivalPhase:max,departureUT,arrivalUT,tof,revolutions,direction,branch,dvDeparture,dvArrival,dvTotal,invalidReason" to porkchopLog.
					}
					return lex(
						"level", level,
						"nextCellId", 0,
						"porkchopLog", porkchopLog,
						"retention", lex(
							"validCount", 0,
							"globalBest", list(),
							"familyBest", lex()
						)
					).
				}.
				local evaluateTransfer is {
					parameter cell.
					local arrivalPhase is (cell:arrivalPhase:min + cell:arrivalPhase:max) / 2.
					local departureUT is phaseToUT(shipSnapshot, (cell:departurePhase:min + cell:departurePhase:max) / 2).
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
					if not targetSnapshot:transitionUT:istype("Boolean") and arrivalUT >= targetSnapshot:transitionUT {
						return transferInvalid(
							cell, "Target leaves current SOI before arrival",
							departureUT, arrivalUT, tof
						).
					}
					local shipState is getShipStateAt(departureUT).
					local targetState is getOrbitStateAtPhaseOffset(targetSnapshot, arrivalPhase + atPhaseOffset).
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
					local dvDeparture is (transferResult:departureVelocity - shipState:velocity):mag.
					local dvArrival is (targetState:velocity - transferResult:arrivalVelocity):mag.
					return lex(
						"valid", true,
						"cell", cell,
						"departureUT", departureUT,
						"arrivalUT", arrivalUT,
						"tof", tof,
						"dvDeparture", dvDeparture,
						"dvArrival", dvArrival,
						"dvTotal", dvDeparture + dvArrival
					).
				}.
				local processCell is {
					parameter cell, evaluationState, retain is true.
					cell:add("id", evaluationState:nextCellId).
					set evaluationState["nextCellId"] to evaluationState:nextCellId + 1.
					local result is evaluateTransfer(cell).
					local resultCell is result:cell.
					if result:valid and retain {
						set evaluationState:retention["validCount"] to evaluationState:retention:validCount + 1.
						insertBestCandidate(evaluationState:retention:globalBest, result, cfg:retainMax).
						if cfg:retainFamily > 0 {
							local candidateFamily is resultCell:revolutions + ":" + resultCell:direction.
							if resultCell:revolutions <> 0 set candidateFamily to candidateFamily + ":" + resultCell:branch.
							if not evaluationState:retention:familyBest:haskey(candidateFamily) {
								evaluationState:retention:familyBest:add(candidateFamily, list()).
							}
							insertBestCandidate(
								evaluationState:retention:familyBest[candidateFamily],
								result,
								cfg:retainFamily
							).
						}
					}
					if cfg:porkchop {
						local values is list(
							resultCell:departurePhase:min,
							resultCell:departurePhase:max,
							resultCell:arrivalPhase:min,
							resultCell:arrivalPhase:max,
							result:departureUT,
							result:arrivalUT,
							result:tof,
							resultCell:revolutions,
							resultCell:direction,
							resultCell:branch
						).
						if result:valid values:add(list(result:dvDeparture,result:dvArrival,result:dvTotal,""):join(",")).
						else values:add(",,,"+result:reason).
						log values:join(",") to evaluationState:porkchopLog.
					}
					if cfg:progressEvery > 0 and mod(evaluationState:nextCellId, cfg:progressEvery) = 0 {
						cfg:progressCell(evaluationState:level, evaluationState:nextCellId).
					}
					return result.
				}.
				local evaluateRefinedPhaseGrid is {
					parameter parentCandidates, phaseCellSize, level.
					local evaluationState is createEvaluationState(level).
					for parentCandidate in parentCandidates {
						local parentCell is parentCandidate:cell.
						local refineDepartureMin is parentCell:departurePhase:min.
						local refineDepartureMax is parentCell:departurePhase:max.
						local refineArrivalMin is parentCell:arrivalPhase:min.
						local refineArrivalMax is parentCell:arrivalPhase:max.
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
						local departureResolution is refineDepartureMax - refineDepartureMin.
						local arrivalResolution is refineArrivalMax - refineArrivalMin.
						local departureCount is cellCount(departureResolution, phaseCellSize).
						local arrivalCount is cellCount(arrivalResolution, phaseCellSize).
						set departureResolution to departureResolution / departureCount.
						set arrivalResolution to arrivalResolution / arrivalCount.
						from { local departureIndex is 0. }
						until departureIndex >= departureCount
						step { set departureIndex to departureIndex + 1. }
						do {
							local childDepartureMin is refineDepartureMin + departureIndex * departureResolution.
							from { local arrivalIndex is 0. }
							until arrivalIndex >= arrivalCount
							step { set arrivalIndex to arrivalIndex + 1. }
							do {
								local childArrivalMin is refineArrivalMin + arrivalIndex * arrivalResolution.
								processCell(
									createCell(
										childDepartureMin,
										min(childDepartureMin + departureResolution, refineDepartureMax),
										childArrivalMin,
										min(childArrivalMin + arrivalResolution, refineArrivalMax),
										parentCell:revolutions,
										parentCell:direction,
										parentCell:branch,
										parentCell:expandDepartureMin and departureIndex = 0,
										parentCell:expandDepartureMax and departureIndex = departureCount - 1,
										parentCell:expandArrivalMin and arrivalIndex = 0,
										parentCell:expandArrivalMax and arrivalIndex = arrivalCount - 1
									),
									evaluationState
								).
							}
						}
					}
					return finalizeRetention(evaluationState:retention).
				}.

				local LAMBERT_DIRECTIONS is list("short", "long").
				local LAMBERT_BRANCHES is list("left", "right").
				local evaluationState is createEvaluationState(0).
				local departurePhaseMin is phaseAtUT(shipSnapshot, departureWindow:min).
				local departurePhaseMax is phaseAtUT(shipSnapshot, departureWindow:max).
				local departurePhaseWidth is departurePhaseMax - departurePhaseMin.
				local departurePhaseResolution is max(cfg:phaseSizes[0], departurePhaseWidth / cfg:phaseSamples).
				local departureCount is cellCount(departurePhaseWidth, departurePhaseResolution).
				set departurePhaseResolution to departurePhaseWidth / departureCount.
				from { local departureIndex is 0. }
				until departureIndex >= departureCount
				step { set departureIndex to departureIndex + 1. }
				do {
					local phaseDepartureMin is departurePhaseMin + departureIndex * departurePhaseResolution.
					local phaseDepartureMax is min(phaseDepartureMin + departurePhaseResolution, departurePhaseMax).
					local departureUT is phaseToUT(shipSnapshot, (phaseDepartureMin + phaseDepartureMax) / 2).
					local arrivalUTMin is departureUT + tofWindow:min.
					local arrivalUTMax is departureUT + tofWindow:max.
					if not targetSnapshot:transitionUT:istype("Boolean") {
						set arrivalUTMax to min(arrivalUTMax, targetSnapshot:transitionUT).
					}
					if arrivalUTMax > arrivalUTMin {
						local arrivalPhaseMin is phaseAtUT(targetSnapshot, arrivalUTMin).
						local arrivalPhaseMax is phaseAtUT(targetSnapshot, arrivalUTMax).
						local arrivalPhaseWidth is arrivalPhaseMax - arrivalPhaseMin.
						local arrivalPhaseResolution is max(cfg:phaseSizes[0], arrivalPhaseWidth / cfg:phaseSamples).
						local arrivalCount is cellCount(arrivalPhaseWidth, arrivalPhaseResolution).
						set arrivalPhaseResolution to arrivalPhaseWidth / arrivalCount.
						from { local arrivalIndex is 0. }
						until arrivalIndex >= arrivalCount
						step { set arrivalIndex to arrivalIndex + 1. }
						do {
							local phaseArrivalMin is arrivalPhaseMin + arrivalIndex * arrivalPhaseResolution.
							for direction in LAMBERT_DIRECTIONS {
								from { local revolutionCount is 0. }
								until revolutionCount > cfg:maxRevs
								step { set revolutionCount to revolutionCount + 1. }
								do {
									for branch in LAMBERT_BRANCHES {
										processCell(
											createCell(
												phaseDepartureMin,
												phaseDepartureMax,
												phaseArrivalMin,
												min(phaseArrivalMin + arrivalPhaseResolution, arrivalPhaseMax),
												revolutionCount,
												direction,
												branch,
												departureIndex > 0,
												departureIndex < departureCount - 1,
												true,
												true
											),
											evaluationState
										).
										if revolutionCount = 0 break.
									}
								}
							}
						}
					}
				}
				local promising is finalizeRetention(evaluationState:retention).
				if promising:length > 0 {
					set bestCandidate to promising[0].
					local chaseCandidate is false.
					from { local level is 1. }
					until level >= cfg:phaseSizes:length
					step { set level to level + 1. }
					do {
						cfg:progressLevel(level, cfg:phaseSizes[level]).
						set promising to evaluateRefinedPhaseGrid(
							promising,
							cfg:phaseSizes[level],
							level
						).
						if promising:length = 0 break.
						if promising[0]:dvTotal < bestCandidate:dvTotal set bestCandidate to promising[0].
					}
					for candidate in promising {
						if cellCanExpand(candidate:cell) and (chaseCandidate:istype("Boolean") or candidate:dvTotal < chaseCandidate:dvTotal) {
							set chaseCandidate to candidate.
						}
					}
					if not chaseCandidate:istype("Boolean") {
						local phaseCellSize is cfg:phaseSizes[cfg:phaseSizes:length - 1].
						local maxIterations is floor(cfg:chaseDegrees / phaseCellSize).
						local iterations is 0.
						if maxIterations > 0 and cellCanExpand(chaseCandidate:cell) {
							cfg:progressChase(phaseCellSize, maxIterations).
							set evaluationState to createEvaluationState("boundary").
							until iterations >= maxIterations or not cellCanExpand(chaseCandidate:cell) {
								local cell is chaseCandidate:cell.
								local departureWidth is cell:departurePhase:max - cell:departurePhase:min.
								local arrivalWidth is cell:arrivalPhase:max - cell:arrivalPhase:min.
								local departureOffsets is list(0).
								local arrivalOffsets is list(0).
								local nextBest is chaseCandidate.
								local improved is false.
								if cell:expandDepartureMin departureOffsets:add(-1).
								if cell:expandDepartureMax departureOffsets:add(1).
								if cell:expandArrivalMin arrivalOffsets:add(-1).
								if cell:expandArrivalMax arrivalOffsets:add(1).
								for departureOffset in departureOffsets {
									for arrivalOffset in arrivalOffsets {
										if departureOffset <> 0 or arrivalOffset <> 0 {
											local departureShift is departureOffset * departureWidth.
											local arrivalShift is arrivalOffset * arrivalWidth.
											local result is processCell(
												createCell(
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
												),
												evaluationState,
												false
											).
											if result:valid and result:dvTotal < nextBest:dvTotal {
												set nextBest to result.
												set improved to true.
											}
										}
									}
								}
								set iterations to iterations + 1.
								if not improved break.
								set chaseCandidate to nextBest.
							}
						}
						if chaseCandidate:dvTotal < bestCandidate:dvTotal set bestCandidate to chaseCandidate.
					}
				}
			}
			set config:ipu to oldIpu.
		}

		if bestCandidate:istype("Boolean") return ApiFail("No valid transfer was found").

		local departureUT is bestCandidate:departureUT.
		local tof is bestCandidate:tof.
		local arrivalUT is departureUT + tof.
		local shipState is getShipStateAt(departureUT).
		local targetState is getOrbitStateAtPhaseOffset(targetSnapshot, phaseAtUT(targetSnapshot, arrivalUT) + atPhaseOffset).
		local transferResult is solveLambert(
			shipState:position,
			targetState:position,
			tof,
			body:mu,
			bestCandidate:cell:direction,
			bestCandidate:cell:revolutions,
			bestCandidate:cell:branch,
			(-vcrs(shipState:position, shipState:velocity)):normalized
		).
		local errorMessage is "Unable to refresh final transfer: ".
		if not transferResult:valid {
			return ApiFail(errorMessage + transferResult:reason).
		}
		local arcRadii is getArcRadii(shipState:position, targetState:position, transferResult:departureVelocity, tof, body).
		if arcRadii:min < transferSafetyBounds:min {
			return ApiFail(errorMessage + "Transfer arc goes below safe altitude").
		}
		if arcRadii:max >= transferSafetyBounds:max {
			return ApiFail(errorMessage + "Transfer arc leaves current SOI").
		}

		set tof to departureUT - time:seconds.
		if tof < cfg:burnEta {
			return ApiFail("Transfer departure is too soon; only " + round(tof) + " seconds remain").
		}

		return ApiOK(lex(
			"departure", velocityChangeToNode(departureUT, shipState:position, shipState:velocity, transferResult:departureVelocity),
			"arrival", velocityChangeToNode(arrivalUT, targetState:position, transferResult:arrivalVelocity, targetState:velocity)
		)).
	}).
}