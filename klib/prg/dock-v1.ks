{
	local rcsControl is import("sys/rcsControl-v1").
	local createConfig is import("util/createConfig-v1").
	local steeringControl is import("sys/steering-v1").

	local SWIPE_ANGLE is 90.
	local ROUTE_FACTOR is 1 / cos(SWIPE_ANGLE / 2).
	local SAFETY_DISTANCE_MARGIN is 10.
	local POSITION_TOLERANCE is 0.25.
	local VECTOR_EPSILON is 1e-6.
	local RCS_VELOCITY_TAPER is 0.5.
	// Tapers the route speed when approaching a point; Increase to brake earlier and more smoothly
	local ROUTE_SPEED_TAPER is 2.
	local PORT_NAME_FIELD is "port name".

	local DOCKING_DEFAULTS is lex(
		"routeSpeed", 2,
		"rollOffset", 0,
		"dockSpeed", 0.1,
		"dockApproach", list(
			list(20, 2),
			list(5, 0.5),
			list(2, 0.2)
		)
	).

	function validateDockingPorts {
		parameter sourcePort, targetPort.
		if not sourcePort:istype("DockingPort")
			or not targetPort:istype("DockingPort") {
			return ApiFail("Docking requires docking ports").
		}

		if sourcePort:ship <> ship {
			return ApiFail("Source docking port must belong to the active vessel").
		}

		if targetPort:ship = ship {
			return ApiFail("Target docking port must belong to another vessel").
		}

		if sourcePort:state <> "Ready" or targetPort:state <> "Ready" {
			return ApiFail("Docking port is not ready").
		}

		if sourcePort:nodetype <> targetPort:nodetype {
			return ApiFail("Docking ports are incompatible").
		}
		return ApiOK().
	}

	function calculateRoutingRadius {
		parameter targetVessel.

		local targetBounds is targetVessel:bounds.
		local shipBounds is ship:bounds.

		local targetRadius is
			(targetBounds:abscenter - targetVessel:position):mag
			+ targetBounds:size:mag / 2.

		local shipRadius is
			shipBounds:abscenter:mag
			+ shipBounds:size:mag / 2.

		local safeRadius is targetRadius + shipRadius + SAFETY_DISTANCE_MARGIN.
		local routingRadius is safeRadius * ROUTE_FACTOR.

		dmsg("[Dock] Projecting a " + round(routingRadius, 1) + "m routing sphere", true).
		dmsg("[Dock]   target = " + round(targetRadius, 1) + "m", true).
		dmsg("[Dock]   ship   = " + round(shipRadius, 1) + "m", true).

		return routingRadius.
	}

	function calculateApproachProfile {
		parameter routingRadius, dockApproachProfile, routeSpeed.

		local approachProfile is list(
			list(routingRadius, routeSpeed)
		).

		for entry in dockApproachProfile {
			if entry[0] < routingRadius {
				approachProfile:add(entry).
			}
		}

		return approachProfile.
	}

	function calculateCorridorOffset {
		parameter targetPort, corridorLength.

		return targetPort:nodePosition
			- targetPort:ship:position
			+ targetPort:portFacing:vector * corridorLength.
	}

	function establishSafeDistance {
		parameter targetVessel, routingRadius, routeSpeed.

		notify("Establishing safe distance").
		dmsg("[Dock] Establish safe distance of " + round(routingRadius, 1) + "m", true).

		local lock relativePosition to -targetVessel:position.
		if relativePosition:mag < routingRadius {
			local lock departVector to (relativePosition:normalized * routingRadius) - relativePosition.
			local lock relativeVelocity to velocity:orbit - targetVessel:velocity:orbit.
			local lock desiredSpeed to min(routeSpeed, departVector:mag / ROUTE_SPEED_TAPER).
			local lock departVelocity to departVector:normalized * desiredSpeed - relativeVelocity.

			until departVector:mag < POSITION_TOLERANCE {
				rcsControl:translate(departVelocity, departVelocity:mag / RCS_VELOCITY_TAPER).
				wait 0.
			}
		}
	}

	function alignForDocking {
		parameter targetPort, rollOffset.

		notify("Aligning docking ports").
		dmsg("[Dock] Align for docking", true).

		local lock approachAxis to -targetPort:portFacing:vector.
		lock steering to lookDirUp(
			approachAxis,
			angleAxis(
				-rollOffset, // negative so that roll will be clockwise relative to target port
				approachAxis
			) * targetPort:portFacing:upvector
		).
	}

	function sideswipeTarget {
		parameter targetPort, routingRadius, routeSpeed.

		local targetVessel is targetPort:ship.
		local startVector is -targetVessel:position.
		local destinationVector is calculateCorridorOffset(targetPort, routingRadius).
		local performedSideswipe is false.

		// Check if angular separation > `SWIPE_ANGLE` degrees
		if vdot(startVector, destinationVector) < startVector:mag * destinationVector:mag * cos(SWIPE_ANGLE) {
			notify("Routing around target").
			dmsg("[Dock] Sideswipe target by " + SWIPE_ANGLE + "° at " + round(routeSpeed, 1) + "m/s", true).
			set performedSideswipe to true.

			local routeNormal is vcrs(destinationVector:normalized, startVector:normalized).

			if routeNormal:mag < VECTOR_EPSILON {
				// Vectors are almost opposite, so the route plane is undefined.
				// Pick a plane normal that is perpendicular to startVector.
				set routeNormal to vcrs(startVector:normalized, targetPort:portFacing:upvector).

				if routeNormal:mag < VECTOR_EPSILON {
					set routeNormal to vcrs(startVector:normalized, targetPort:portFacing:starvector).
				}
			}

			// Rotate the startVector `SWIPE_ANGLE` degrees around the routeNormal
			local sideVector is (angleAxis(-SWIPE_ANGLE, routeNormal) * startVector):normalized * routingRadius.
			local otherSideVector is (angleAxis(SWIPE_ANGLE, routeNormal) * startVector):normalized * routingRadius.

			// Check which side vector is the correct direction; Fallback plane may have selected the opposite direction
			if vdot(otherSideVector, destinationVector) > vdot(sideVector, destinationVector) {
				set sideVector to otherSideVector.
			}

			local lock relativeVelocity to velocity:orbit - targetVessel:velocity:orbit.
			local lock sidePosition to targetVessel:position + sideVector.
			local lock desiredSpeed to min(routeSpeed, sidePosition:mag / ROUTE_SPEED_TAPER).
			local lock sideVelocity to sidePosition:normalized * desiredSpeed - relativeVelocity.

			until sidePosition:mag < POSITION_TOLERANCE {
				rcsControl:translate(sideVelocity, sideVelocity:mag / RCS_VELOCITY_TAPER).
				wait 0.
			}
		}

		return performedSideswipe.
	}

	function approachDockingRange {
		parameter sourcePort, targetPort, distance, speed, trackCorridor.

		notify("Docking approach: " + round(distance,1) + "m").
		dmsg("[Dock] Approach: " + round(distance,1) + "m @ " + round(speed,1) + "m/s", true).

		local targetVessel is targetPort:ship.
		local lock relativeVelocity to velocity:orbit - targetVessel:velocity:orbit.
		local lock destinationVector to calculateCorridorOffset(targetPort, distance).
		local lock approachVector to destinationVector
			+ targetPort:ship:position
			- sourcePort:nodeposition.

		local lock approachAxis to targetPort:portFacing:vector.
		local lock lateralVector to vxcl(approachAxis, approachVector).
		local lock axialVector to approachVector - lateralVector.

		local lock directVelocity to
			approachVector:normalized * min(speed, approachVector:mag / ROUTE_SPEED_TAPER).

		local lock axialVelocity to axialVector
			* min(1, speed / max(axialVector:mag, VECTOR_EPSILON)).
		local lock lateralVelocity to lateralVector
			* min(1, speed / max(lateralVector:mag, VECTOR_EPSILON)).

		local lock desiredVelocity to choose
			axialVelocity + lateralVelocity
			if trackCorridor
			else directVelocity.

		local lock approachVelocity to desiredVelocity - relativeVelocity.

		until (distance > 0 and approachVector:mag < POSITION_TOLERANCE)
		or sourcePort:state <> "Ready" {
			rcsControl:translate(approachVelocity, approachVelocity:mag / RCS_VELOCITY_TAPER).
			wait 0.
		}
	}

	function approachPort {
		parameter sourcePort, targetPort, approachProfile, dockingSpeed.

		local trackCorridor is false.
		for entry in approachProfile {
			approachDockingRange(sourcePort, targetPort, entry[0], entry[1], trackCorridor).

			if not trackCorridor and not steeringControl:isSettled(true) {
				notify("Awaiting docking port alignment").
				dmsg("[Dock] Awaiting docking port alignment to complete", true).
				rcsControl:zero(targetPort:ship).
				steeringControl:awaitSteering(true).
			}

			set trackCorridor to true.
		}
		approachDockingRange(sourcePort, targetPort, 0, dockingSpeed, true).

		dmsg("[Dock] Within magnetic docking range", true).
	}

	function completeDocking {
		parameter sourcePort.

		// Stop RCS translation, but retain RCS attitude authority for steering
		rcsControl:off().

		wait until sourcePort:hasPartner or sourcePort:state = "Ready".

		rcs off.
		unlock steering.

		return sourcePort:hasPartner.
	}

	function dock {
		parameter sourcePort, targetPort, options is lex().

		local portValidation is validateDockingPorts(sourcePort, targetPort).
		if not portValidation:ok return portValidation.

		local configResult is createConfig(DOCKING_DEFAULTS, options).
		if not configResult:ok return configResult.
		local cfg is configResult:val.
		local targetVessel is targetPort:ship.

		clearScreen.
		local targetPortNameModule is targetPort:getModule("ModuleDockingNodeNamed").
		local targetPortName is targetPortNameModule:getField(PORT_NAME_FIELD).
		local sourcePortNameModule is sourcePort:getModule("ModuleDockingNodeNamed").
		local sourcePortName is sourcePortNameModule:getField(PORT_NAME_FIELD).
		notify("Begin docking procedure with " + targetVessel:name).
		dmsg("[Dock] Begin docking procedure", true).
		dmsg("[Dock]   Target/Port:  " + targetVessel:name + " / " + targetPortName, true).
		dmsg("[Dock]   Control port: " + sourcePortName, true).
		dmsg("[Dock]   Roll offset:  " + cfg:rollOffset + "°", true).
		sourcePort:controlFrom().

		local routingRadius is calculateRoutingRadius(targetVessel).
		local approachProfile is calculateApproachProfile(routingRadius, cfg:dockApproach, cfg:routeSpeed).

		local holdFacing is ship:facing.
		lock steering to holdFacing.
		sas off.
		rcs on.

		establishSafeDistance(targetVessel, routingRadius, cfg:routeSpeed).
		alignForDocking(targetPort, cfg:rollOffset).
		wait until not sideswipeTarget(targetPort, routingRadius, cfg:routeSpeed).
		approachPort(sourcePort, targetPort, approachProfile, cfg:dockSpeed).

		if completeDocking(sourcePort) {
			notify("Docking success").
			dmsg("[Dock] Docking success", true).
			return ApiOK().
		}
		notify("Docking failed").
		dmsg("[Dock] Docking failed", true).
		return ApiFail("Docking capture failed").
	}

	export(dock@).
}