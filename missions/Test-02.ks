// #include "../lib-v1/kldr-stub.ks"

local awaitSteering is import("steering-v1"):awaitSteering.
local stageUntil is import("staging-v1"):stageUntil.
local printLn is import("printLn-v1"):printLn.
local ascent is import("ascent-v2").
local circularizeAtAp is import("mnv/circularizeAtAp-v1").
local matchInclination is import("mnv/matchInclination-v1").
local execute is import("mnv/executeNode-v1").
clearScreen.

local parkingAltitude is 100e3.
local targetInclination is 0.
local orbitalStage is 2.

if status = "PRELAUNCH" {
	ascent:executeAscent(parkingAltitude, targetInclination).
	panels on.
	lights on.
	ascent:orbitalInsertion(parkingAltitude).
	printLn("Dropping Ascent Stage").
	stageUntil(orbitalStage).
	printLn("Circularizing at Apoapsis").
	circularizeAtAp().
	execute:warpToNode(10).
	execute:executeNode(10).
	printLn("Orbit achieved").
}

wait until hasTarget.
printLn("Matching planes").
matchInclination().
// execute:warpToNode(10).
// execute:executeNode(10).

on abort {
	lock steering to retrograde.
	awaitSteering().
	lock throttle to 1.
	wait until periapsis < 35e3.
	lock throttle to 0.
	lock steering to srfRetrograde.
	wait 1.
	stageUntil(0).
	wait until status = "LANDED" or status = "SPLASHED".
	unlock steering.
	wait 5.
	sas on.
}

wait until 0.