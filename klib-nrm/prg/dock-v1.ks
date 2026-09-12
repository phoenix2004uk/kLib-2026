{
	local rcsControl is import("sys/rcsControl-v1").
	local createConfig is import("util/createConfig-v1").
	local steeringControl is import("sys/steering-v1").
	local calculateCorridorOffset is{
		parameter targetPort,corridorLength.
		return targetPort:nodePosition-targetPort:ship:position+targetPort:portFacing:vector*corridorLength.
	}.
	local approachDockingRange is{
		parameter sourcePort,targetPort,distance,speed,trackCorridor.
		notify("Docking approach: "+round(distance,1)+"m").
		dmsg("[Dock] Approach: "+round(distance,1)+"m @ "+round(speed,1)+"m/s",true).
		local lock approachVector to calculateCorridorOffset(targetPort,distance)+targetPort:ship:position-sourcePort:nodeposition.
		local lock lateralVector to vxcl(targetPort:portFacing:vector,approachVector).
		local lock axialVector to approachVector-lateralVector.
		local lock approachVelocity to (choose axialVector*min(1,speed/max(axialVector:mag,1e-6))+lateralVector*min(1,speed/max(lateralVector:mag,1e-6)) if trackCorridor else approachVector:normalized*min(speed,approachVector:mag/2))-velocity:orbit+targetPort:ship:velocity:orbit.
		until(distance>0 and approachVector:mag<.25)or sourcePort:state<>"Ready"{
			rcsControl:translate(approachVelocity,approachVelocity:mag/.5).
			wait 0.
		}
	}.
	export({
		parameter sourcePort,targetPort,options is lex().
		if not sourcePort:istype("DockingPort")or not targetPort:istype("DockingPort")return ApiFail("Docking requires docking ports").
		if sourcePort:ship<>ship return ApiFail("Source docking port must belong to the active vessel").
		if targetPort:ship=ship return ApiFail("Target docking port must belong to another vessel").
		if sourcePort:state<>"Ready"or targetPort:state<>"Ready"return ApiFail("Docking port is not ready").
		if sourcePort:nodetype<>targetPort:nodetype return ApiFail("Docking ports are incompatible").
		local configResult is createConfig(lex("routeSpeed",2,"rollOffset",0,"dockSpeed",.1,"dockApproach",list(list(20,2),list(5,.5),list(2,.2))),options).
		if not configResult:ok return configResult.
		local cfg is configResult:val.
		local targetVessel is targetPort:ship.
		clearScreen.
		notify("Begin docking procedure with "+targetVessel:name).
		dmsg("[Dock] Begin docking procedure",true).
		dmsg("[Dock]   Target/Port:  "+targetVessel:name+" / "+targetPort:getModule("ModuleDockingNodeNamed"):getField("port name"),true).
		dmsg("[Dock]   Control port: "+sourcePort:getModule("ModuleDockingNodeNamed"):getField("port name"),true).
		dmsg("[Dock]   Roll offset:  "+cfg:rollOffset+"°",true).
		sourcePort:controlFrom().
		local targetBounds is targetVessel:bounds.
		local shipBounds is ship:bounds.
		local targetRadius is(targetBounds:abscenter-targetVessel:position):mag+targetBounds:size:mag/2.
		local shipRadius is shipBounds:abscenter:mag+shipBounds:size:mag/2.
		local routingRadius is (targetRadius+shipRadius+10)*sqrt(2).
		dmsg("[Dock] Projecting a "+round(routingRadius,1)+"m routing sphere",true).
		dmsg("[Dock]   target = "+round(targetRadius,1)+"m",true).
		dmsg("[Dock]   ship   = "+round(shipRadius,1)+"m",true).
		local approachProfile is list(list(routingRadius,cfg:routeSpeed)).
		for entry in cfg:dockApproach if entry[0]<routingRadius approachProfile:add(entry).
		local holdFacing is ship:facing.
		lock steering to holdFacing.
		sas off.
		rcs on.
		notify("Establishing safe distance").
		dmsg("[Dock] Establish safe distance of "+round(routingRadius,1)+"m",true).
		local lock relativePosition to-targetVessel:position.
		if relativePosition:mag<routingRadius{
			local lock departVector to(relativePosition:normalized*routingRadius)-relativePosition.
			local lock departVelocity to departVector:normalized*min(cfg:routeSpeed,departVector:mag/2)-velocity:orbit+targetVessel:velocity:orbit.
			until departVector:mag<.25{
				rcsControl:translate(departVelocity,departVelocity:mag/.5).
				wait 0.
			}
		}
		notify("Aligning docking ports").
		dmsg("[Dock] Align for docking",true).
		local lock approachAxis to-targetPort:portFacing:vector.
		lock steering to lookDirUp(approachAxis,angleAxis(-cfg:rollOffset,approachAxis)*targetPort:portFacing:upvector).
		local noSideswipe is false.
		until noSideswipe{
			wait 0.
			set noSideswipe to true.
			local startVector is-targetPort:ship:position.
			local destinationVector is calculateCorridorOffset(targetPort,routingRadius).
			if vdot(startVector,destinationVector)<startVector:mag*destinationVector:mag*cos(90){
				notify("Routing around target").
				dmsg("[Dock] Sideswipe target by "+90+"° at "+round(cfg:routeSpeed,1)+"m/s",true).
				set noSideswipe to false.
				local routeNormal is vcrs(destinationVector:normalized,startVector:normalized).
				if routeNormal:mag<1e-6{
					set routeNormal to vcrs(startVector:normalized,targetPort:portFacing:upvector).
					if routeNormal:mag<1e-6 set routeNormal to vcrs(startVector:normalized,targetPort:portFacing:starvector).
				}
				local sideVector is(angleAxis(-90,routeNormal)*startVector):normalized*routingRadius.
				local otherSideVector is(angleAxis(90,routeNormal)*startVector):normalized*routingRadius.
				if vdot(otherSideVector,destinationVector)>vdot(sideVector,destinationVector)set sideVector to otherSideVector.
				local lock sidePosition to targetPort:ship:position+sideVector.
				local lock sideVelocity to sidePosition:normalized*min(cfg:routeSpeed,sidePosition:mag/2)-velocity:orbit+targetPort:ship:velocity:orbit.
				until sidePosition:mag<.25{
					rcsControl:translate(sideVelocity,sideVelocity:mag/.5).
					wait 0.
				}
			}
		}
		local trackCorridor is false.
		for entry in approachProfile{
			approachDockingRange(sourcePort,targetPort,entry[0],entry[1],trackCorridor).
			if not trackCorridor and not steeringControl:isSettled(){
				notify("Awaiting docking port alignment").
				dmsg("[Dock] Awaiting docking port alignment to complete",true).
				rcsControl:zero(targetPort:ship).
				steeringControl:awaitSteering().
			}
			set trackCorridor to true.
		}
		approachDockingRange(sourcePort,targetPort,0,cfg:dockSpeed,true).
		dmsg("[Dock] Within magnetic docking range",true).
		rcsControl:off().
		wait until sourcePort:hasPartner or sourcePort:state="Ready".
		rcs off.
		unlock steering.
		if sourcePort:hasPartner{
			notify("Docking success").
			dmsg("[Dock] Docking success",true).
			return ApiOK().
		}
		notify("Docking failed").
		dmsg("[Dock] Docking failed",true).
		return ApiFail("Docking capture failed").
	}).
}